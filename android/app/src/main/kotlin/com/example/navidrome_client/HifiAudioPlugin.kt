// CrotoWave — salida bit-perfect por USB en Android 14+ (API 34).
//
// Registro en MainActivity.configureFlutterEngine():
//   HifiAudioPlugin(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
//
// Requisito: el AudioPlayer (ExoPlayer) debe usar AudioAttributes con
// USAGE_MEDIA, que es el default de just_audio.

package com.example.navidrome_client

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class HifiAudioPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mediaAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    private var activeDevice: AudioDeviceInfo? = null
    private var bitPerfectActive = false

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "scrotify/hifi").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableBitPerfect" -> result.success(
                enableBitPerfect(
                    call.argument<Int>("sampleRate") ?: 44100,
                    call.argument<Int>("bitDepth") ?: 16,
                )
            )
            "disableBitPerfect" -> { disableBitPerfect(); result.success(null) }
            "currentOutput" -> result.success(currentOutput())
            else -> result.notImplemented()
        }
    }

    private fun usbOutput(): AudioDeviceInfo? =
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }

    private fun encodingFor(bitDepth: Int): Int = when {
        bitDepth >= 32 -> AudioFormat.ENCODING_PCM_32BIT
        bitDepth >= 24 -> AudioFormat.ENCODING_PCM_24BIT_PACKED
        else -> AudioFormat.ENCODING_PCM_16BIT
    }

    private fun enableBitPerfect(sampleRate: Int, bitDepth: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        val device = usbOutput() ?: return false
        val candidates = audioManager.getSupportedMixerAttributes(device).filter {
            it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT
        }
        if (candidates.isEmpty()) return false

        val wantedEncoding = encodingFor(bitDepth)
        // 1º: misma frecuencia y profundidad. 2º: misma frecuencia (el DAC
        // acolchona 16→24 bits sin pérdida). Si no, no fingimos bit-perfect.
        val chosen = candidates.firstOrNull {
            it.format.sampleRate == sampleRate && it.format.encoding == wantedEncoding
        } ?: candidates.firstOrNull { it.format.sampleRate == sampleRate }
        ?: return false

        val ok = audioManager.setPreferredMixerAttributes(mediaAttributes, device, chosen)
        bitPerfectActive = ok
        activeDevice = if (ok) device else null
        return ok
    }

    private fun disableBitPerfect() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        activeDevice?.let { audioManager.clearPreferredMixerAttributes(mediaAttributes, it) }
        activeDevice = null
        bitPerfectActive = false
    }

    private fun currentOutput(): Map<String, Any?> {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val device = usbOutput()
            ?: outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }
            ?: outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES }
            ?: outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
        val type = when (device?.type) {
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            else -> "unknown"
        }
        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            device != null && type == "usb" &&
            audioManager.getSupportedMixerAttributes(device).any {
                it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT
            }
        return mapOf(
            "deviceName" to (device?.productName?.toString() ?: "Desconocido"),
            "deviceType" to type,
            "sampleRate" to audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull(),
            "bitPerfectActive" to bitPerfectActive,
            "bitPerfectSupported" to supported,
        )
    }
}
