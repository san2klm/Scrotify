// CrotoWave — waveform real en Android con MediaExtractor + MediaCodec.
//
// Canal `crotowave/waveform`:
//   decode {jobId: String, path: String, bins: Int (16..2048), durationUs: Long > 0}
//          → DoubleArray con exactamente `bins` amplitudes finitas en 0..1.
//   cancel {jobId: String} → detiene el trabajo pendiente o en curso.
// Errores (PlatformException.code): unsupported, timeout, cancelled,
// decode_failed, invalid_arguments. Los mensajes nunca incluyen rutas.
//
// Es un FlutterPlugin: vive y muere con el FlutterEngine, no con la Activity
// (el engine se comparte con audio_service y sobrevive en segundo plano).
// Registro en MainActivity.configureFlutterEngine(), una sola instancia:
//   if (!flutterEngine.plugins.has(AndroidWaveformPlugin::class.java))
//       AndroidWaveformPlugin().register(flutterEngine)
//
// Notas de diseño:
// - IO, códec y análisis corren en un executor acotado (2 hilos, cola de 16),
//   nunca en el hilo de UI; las respuestas se publican en el hilo principal.
// - Solo rutas locales absolutas. No se crea AudioTrack ni se pide micrófono.
// - Se consume el PCM por bloques y solo se conservan los bins.
// - Cancelación cooperativa: un trabajo sin empezar se responde al instante;
//   uno en curso lo detecta el bucle del códec. Cancelar un jobId desconocido
//   no deja rastro (sin tombstones). Al destruir el motor se cancela todo.

package cloud.templo.crotowave

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class AndroidWaveformPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private class Job(val id: String, val result: MethodChannel.Result) {
        @Volatile var cancelled = false
        val started = AtomicBoolean(false)
        val replied = AtomicBoolean(false)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, Job>()
    private val executor = ThreadPoolExecutor(
        MAX_WORKERS, MAX_WORKERS, 30L, TimeUnit.SECONDS,
        LinkedBlockingQueue<Runnable>(QUEUE_CAPACITY),
        ThreadFactory { runnable ->
            Thread(runnable, "crotowave-waveform").apply { isDaemon = true }
        }
    ).apply { allowCoreThreadTimeOut(true) }

    @Volatile private var disposed = false
    private var channel: MethodChannel? = null
    private var engine: FlutterEngine? = null

    private val engineListener = object : FlutterEngine.EngineLifecycleListener {
        override fun onPreEngineRestart() = cancelAll()
        override fun onEngineWillDestroy() {
            // FlutterEngine itera sus listeners al destruirse: no mutar la colección
            // desde dentro (ConcurrentModificationException). Se suelta la referencia
            // antes para que dispose() no llame a removeEngineLifecycleListener.
            engine = null
            dispose()
        }
    }

    /** Añade el plugin al registro del engine y enlaza onPreEngineRestart. Una vez. */
    fun register(flutterEngine: FlutterEngine) {
        if (engine != null || disposed) return
        engine = flutterEngine
        flutterEngine.addEngineLifecycleListener(engineListener)
        flutterEngine.plugins.add(this) // dispara onAttachedToEngine
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (disposed || channel != null) return
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = dispose()

    /** Cancela todo, libera el executor y suelta el canal. Idempotente. */
    fun dispose() {
        if (disposed) return
        disposed = true
        cancelAll()
        executor.shutdownNow()
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.removeEngineLifecycleListener(engineListener)
        engine = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decode" -> decode(call, result)
            "cancel" -> cancel(call, result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Canal
    // -------------------------------------------------------------------------

    private fun decode(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("cancelled", "Waveform decoder is shut down", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val jobId = args?.get("jobId") as? String
        val path = args?.get("path") as? String
        // Number: el canal entrega Integer o Long según el valor.
        val bins = (args?.get("bins") as? Number)?.toInt()
        val durationUs = (args?.get("durationUs") as? Number)?.toLong()
        if (jobId.isNullOrEmpty() || jobId.length > MAX_JOB_ID ||
            path.isNullOrEmpty() || !path.startsWith("/") || path.contains("://") ||
            bins == null || bins < MIN_BINS || bins > MAX_BINS ||
            durationUs == null || durationUs <= 0L
        ) {
            result.error("invalid_arguments", "Invalid waveform arguments", null)
            return
        }
        val job = Job(jobId, result)
        if (jobs.putIfAbsent(jobId, job) != null) {
            result.error("invalid_arguments", "Duplicate job id", null)
            return
        }
        try {
            executor.execute { run(job, path, bins, durationUs) }
        } catch (_: RejectedExecutionException) {
            jobs.remove(jobId, job)
            result.error("decode_failed", "Waveform decoder is busy", null)
        }
    }

    private fun cancel(call: MethodCall, result: MethodChannel.Result) {
        val jobId = (call.arguments as? Map<*, *>)?.get("jobId") as? String
        if (jobId.isNullOrEmpty()) {
            result.error("invalid_arguments", "Missing job id", null)
            return
        }
        jobs[jobId]?.let { cancelJob(it) }
        result.success(null)
    }

    private fun cancelAll() {
        for (job in jobs.values.toList()) cancelJob(job)
    }

    private fun cancelJob(job: Job) {
        job.cancelled = true
        // Si aún no empezó, la tarea ya no correrá: se responde y se retira ahora.
        if (job.started.compareAndSet(false, true)) {
            jobs.remove(job.id, job)
            replyError(job, "cancelled", "Waveform analysis cancelled")
        }
    }

    // -------------------------------------------------------------------------
    // Trabajo en el executor
    // -------------------------------------------------------------------------

    private fun run(job: Job, path: String, bins: Int, durationUs: Long) {
        if (!job.started.compareAndSet(false, true)) return // ya cancelado y respondido
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            val amplitudes = WaveformDecoding.decode(path, bins, durationUs) {
                job.cancelled || disposed
            }
            replySuccess(job, amplitudes)
        } catch (e: WaveformException) {
            replyError(job, e.code, e.message ?: "Waveform decode failed")
        } catch (_: OutOfMemoryError) {
            replyError(job, "decode_failed", "Not enough memory to analyze the audio")
        } catch (_: Exception) {
            replyError(job, "decode_failed", "Waveform decode failed")
        } finally {
            jobs.remove(job.id, job)
        }
    }

    private fun replySuccess(job: Job, amplitudes: DoubleArray) {
        if (!job.replied.compareAndSet(false, true)) return
        mainHandler.post { runCatching { job.result.success(amplitudes) } }
    }

    private fun replyError(job: Job, code: String, message: String) {
        if (!job.replied.compareAndSet(false, true)) return
        mainHandler.post { runCatching { job.result.error(code, message, null) } }
    }

    companion object {
        const val CHANNEL = "crotowave/waveform"
        private const val MIN_BINS = 16
        private const val MAX_BINS = 2048
        private const val MAX_JOB_ID = 128
        private const val MAX_WORKERS = 2
        private const val QUEUE_CAPACITY = 16
    }
}

/** Decodificación MediaExtractor + MediaCodec en streaming → bins. */
internal object WaveformDecoding {
    private const val DEADLINE_MS = 120_000L
    private const val DEQUEUE_TIMEOUT_US = 10_000L

    fun decode(
        path: String,
        bins: Int,
        durationUs: Long,
        isCancelled: () -> Boolean,
    ): DoubleArray {
        val file = File(path)
        if (!file.isFile || !file.canRead() || file.length() <= 0L) {
            throw WaveformException("decode_failed", "Audio file is not readable")
        }
        val deadline = SystemClock.elapsedRealtime() + DEADLINE_MS
        fun checkAbort() {
            if (isCancelled()) throw WaveformException("cancelled", "Waveform analysis cancelled")
            if (SystemClock.elapsedRealtime() > deadline) {
                throw WaveformException("timeout", "Waveform analysis timed out")
            }
        }

        var input: FileInputStream? = null
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            val stream = FileInputStream(file)
            input = stream
            val source = MediaExtractor()
            extractor = source
            source.setDataSource(stream.fd)

            var selected = -1
            for (i in 0 until source.trackCount) {
                val m = source.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
                if (m != null && m.startsWith("audio/")) {
                    selected = i
                    break
                }
            }
            if (selected < 0) {
                throw WaveformException("unsupported", "No audio track found")
            }
            source.selectTrack(selected)
            val trackFormat = source.getTrackFormat(selected)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME)
                ?: throw WaveformException("unsupported", "No audio track found")

            val decoder = try {
                MediaCodec.createDecoderByType(mime).also { codec = it }
            } catch (e: Exception) {
                throw WaveformException("unsupported", "No decoder available for this audio format")
            }
            try {
                decoder.configure(trackFormat, null, null, 0)
                decoder.start()
            } catch (e: Exception) {
                throw WaveformException("unsupported", "Decoder cannot handle this audio format")
            }

            var channels = intOf(trackFormat, MediaFormat.KEY_CHANNEL_COUNT, 0)
            var sampleRate = intOf(trackFormat, MediaFormat.KEY_SAMPLE_RATE, 0)
            var encoding = pcmEncodingOf(trackFormat)

            val binner = PcmWaveformBinner(bins, durationUs)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var firstOutput = true

            while (!outputDone && !binner.pastEnd) {
                checkAbort()
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                    if (inIndex >= 0) {
                        val inBuffer = decoder.getInputBuffer(inIndex)
                            ?: throw WaveformException("decode_failed", "Codec input buffer unavailable")
                        val size = source.readSampleData(inBuffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, source.sampleTime, 0)
                            source.advance()
                        }
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)
                when {
                    outIndex >= 0 -> {
                        try {
                            if (info.size > 0) {
                                val out = decoder.getOutputBuffer(outIndex)
                                if (out != null) {
                                    if (firstOutput) {
                                        // Base temporal = PTS de la primera salida.
                                        binner.setStartUs(info.presentationTimeUs)
                                        firstOutput = false
                                    }
                                    // Respeta offset/size del BufferInfo (el búfer puede traer
                                    // position/limit de usos anteriores).
                                    out.clear()
                                    out.position(info.offset)
                                    out.limit(info.offset + info.size)
                                    binner.consume(out, encoding, channels, sampleRate)
                                }
                            }
                        } finally {
                            decoder.releaseOutputBuffer(outIndex, false)
                        }
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = decoder.outputFormat
                        channels = intOf(f, MediaFormat.KEY_CHANNEL_COUNT, channels)
                        sampleRate = intOf(f, MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                        encoding = pcmEncodingOf(f)
                    }
                    // INFO_TRY_AGAIN_LATER / INFO_OUTPUT_BUFFERS_CHANGED: seguir.
                }
            }
            checkAbort()
            if (firstOutput) {
                throw WaveformException("decode_failed", "Decoder produced no PCM audio")
            }
            return binner.finish()
        } catch (e: WaveformException) {
            throw e
        } catch (e: IOException) {
            throw WaveformException("decode_failed", "Audio could not be read")
        } catch (e: IllegalStateException) { // incluye MediaCodec.CodecException
            throw WaveformException("decode_failed", "Audio decoder failed")
        } catch (e: IllegalArgumentException) {
            throw WaveformException("decode_failed", "Audio could not be decoded")
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor?.release() }
            runCatching { input?.close() }
        }
    }


    private fun intOf(format: MediaFormat, key: String, fallback: Int): Int =
        if (format.containsKey(key)) format.getInteger(key) else fallback

    /** PCM de 16 bits si el formato no declara otra cosa (valor por defecto de Android). */
    private fun pcmEncodingOf(format: MediaFormat): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            format.containsKey(MediaFormat.KEY_PCM_ENCODING)
        ) {
            format.getInteger(MediaFormat.KEY_PCM_ENCODING)
        } else {
            PcmEncoding.PCM_16BIT
        }
}
