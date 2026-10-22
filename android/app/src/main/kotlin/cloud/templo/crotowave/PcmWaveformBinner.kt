// CrotoWave — acumulador PCM por ventanas para la waveform nativa.
//
// Consume bloques de PCM (nunca la canción entera) y conserva solo, por ventana:
// suma de cuadrados, pico y número de muestras. Mismo algoritmo que
// `PcmWaveformAnalyzer` (Dart): mono = promedio de canales,
// amplitud = RMS * 0.75 + pico * 0.25, normalizada por el máximo global;
// el silencio real queda en 0.

package cloud.templo.crotowave

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Error con código estable del canal (unsupported, timeout, cancelled, decode_failed...). */
internal class WaveformException(val code: String, message: String) : Exception(message)

/** Valores de android.media.AudioFormat.ENCODING_PCM_*, fijos para evitar dependencias de API. */
internal object PcmEncoding {
    const val PCM_16BIT = 2
    const val PCM_8BIT = 3
    const val PCM_FLOAT = 4
    const val PCM_24BIT_PACKED = 21 // API 31+
    const val PCM_32BIT = 22 // API 31+

    fun bytesPerSample(encoding: Int): Int = when (encoding) {
        PCM_8BIT -> 1
        PCM_16BIT -> 2
        PCM_24BIT_PACKED -> 3
        PCM_32BIT, PCM_FLOAT -> 4
        else -> throw WaveformException("unsupported", "PCM encoding $encoding not supported")
    }
}

internal class PcmWaveformBinner(private val bins: Int, private val durationUs: Long) {
    private val sumSq = DoubleArray(bins)
    private val peak = DoubleArray(bins)
    private val count = LongArray(bins)

    /** Instante (µs) de la próxima trama, medido desde el PTS inicial del decoder. */
    private var timelineUs = 0.0
    private val binUs = durationUs.toDouble() / bins

    /** Pasada la duración esperada (+margen) ya no hace falta seguir decodificando. */
    val pastEnd: Boolean
        get() = timelineUs >= durationUs + END_MARGIN_US

    fun setStartUs(startUs: Long) {
        timelineUs = max(0L, startUs).toDouble()
    }

    /**
     * Procesa las tramas completas de [buffer] entre su `position` y `limit`
     * (el llamador fija ambos con offset/size del BufferInfo). Un resto parcial
     * de trama se descarta.
     */
    fun consume(buffer: ByteBuffer, encoding: Int, channels: Int, sampleRate: Int) {
        if (channels <= 0 || sampleRate <= 0) {
            throw WaveformException("decode_failed", "Invalid PCM format")
        }
        val bytesPerSample = PcmEncoding.bytesPerSample(encoding)
        val frameBytes = bytesPerSample * channels
        val frames = buffer.remaining() / frameBytes
        // slice() comparte contenido pero reinicia el orden: se fija el nativo.
        val data = buffer.slice().order(ByteOrder.nativeOrder())
        val stepUs = 1_000_000.0 / sampleRate
        var pos = 0
        for (f in 0 until frames) {
            var sum = 0.0
            for (c in 0 until channels) {
                sum += sampleAt(data, pos, encoding)
                pos += bytesPerSample
            }
            addFrame(sum / channels)
            timelineUs += stepUs
        }
    }

    private fun addFrame(mono: Double) {
        if (timelineUs >= durationUs) return
        val index = min((timelineUs / binUs).toInt(), bins - 1)
        if (index < 0) return
        val s = if (mono.isNaN() || mono.isInfinite()) 0.0 else mono.coerceIn(-1.0, 1.0)
        val a = abs(s)
        sumSq[index] += s * s
        if (a > peak[index]) peak[index] = a
        count[index]++
    }

    private fun sampleAt(b: ByteBuffer, pos: Int, encoding: Int): Double = when (encoding) {
        PcmEncoding.PCM_16BIT -> b.getShort(pos) / 32768.0
        PcmEncoding.PCM_FLOAT -> b.getFloat(pos).toDouble()
        PcmEncoding.PCM_8BIT -> ((b.get(pos).toInt() and 0xFF) - 128) / 128.0
        PcmEncoding.PCM_32BIT -> b.getInt(pos) / 2147483648.0
        PcmEncoding.PCM_24BIT_PACKED -> {
            // Little-endian empaquetado (todas las ABIs de Android son LE).
            val v = (b.get(pos).toInt() and 0xFF) or
                ((b.get(pos + 1).toInt() and 0xFF) shl 8) or
                (b.get(pos + 2).toInt() shl 16)
            v / 8388608.0
        }
        else -> throw WaveformException("unsupported", "PCM encoding $encoding not supported")
    }

    /** Exactamente [bins] amplitudes finitas en 0..1. Ventana sin muestras = 0. */
    fun finish(): DoubleArray {
        val out = DoubleArray(bins)
        var maxValue = 0.0
        for (i in 0 until bins) {
            if (count[i] == 0L) continue
            val rms = sqrt(sumSq[i] / count[i])
            val v = (rms * RMS_WEIGHT + peak[i] * PEAK_WEIGHT).coerceIn(0.0, 1.0)
            out[i] = v
            if (v > maxValue) maxValue = v
        }
        // Silencio digital: no amplificar ruido residual (igual que el analizador Dart).
        if (maxValue < 1e-6) return DoubleArray(bins)
        for (i in 0 until bins) out[i] = (out[i] / maxValue).coerceIn(0.0, 1.0)
        return out
    }

    companion object {
        const val RMS_WEIGHT = 0.75
        const val PEAK_WEIGHT = 0.25
        const val END_MARGIN_US = 2_000_000.0
    }
}
