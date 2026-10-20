package cloud.templo.crotowave

import android.media.MediaMetadataRetriever
import android.Manifest
import android.content.Intent
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.view.KeyEvent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    private val storageRequest = 30174
    private val notificationRequest = 30175
    private var pendingStorage: MethodChannel.Result? = null
    private var volumeChannel: MethodChannel? = null
    private var volumeKeysEnabled = false

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        if (volumeKeysEnabled &&
            (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                volumeChannel?.invokeMethod("volumeKey", code == KeyEvent.KEYCODE_VOLUME_UP)
            }
            return true // consumida: no aparece el panel del sistema
        }
        return super.dispatchKeyEvent(event)
    }

    private fun hasStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+: la notificación de reproducción necesita este permiso.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationRequest
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Salida bit-perfect por USB (Android 14+) para los modos de alta fidelidad.
        HifiAudioPlugin(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        // Waveform real (MediaExtractor/MediaCodec). El plugin pertenece al
        // FlutterEngine (compartido con audio_service), no a la Activity: una sola
        // instancia, liberada al desregistrar/destruir el engine.
        if (!flutterEngine.plugins.has(AndroidWaveformPlugin::class.java)) {
            AndroidWaveformPlugin().register(flutterEngine)
        }
        // Botones físicos de volumen → volumen interno de la app (ver
        // dispatchKeyEvent y lib/widgets/android_volume_keys.dart).
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crotowave/volume_keys").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeysEnabled = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    // Fallback (p. ej. bit-perfect): mover el volumen del sistema.
                    "adjustSystem" -> {
                        val up = call.arguments as? Boolean ?: true
                        (getSystemService(AUDIO_SERVICE) as AudioManager).adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // ¿Corre en un Android TV? La UI usa navegación con control remoto.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crotowave/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> {
                        val modes = getSystemService(UI_MODE_SERVICE) as? UiModeManager
                        result.success(
                            modes?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                                packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crotowave/music_storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readAudioMetadata" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(null)
                        } else {
                            Thread {
                                val reader = MediaMetadataRetriever()
                                val tags = try {
                                    reader.setDataSource(path)
                                    mapOf(
                                        "title" to reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                                        "artist" to reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                                        "album" to reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                                        "duration" to reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                                            ?.toDoubleOrNull()?.div(1000.0)
                                    )
                                } catch (_: Exception) {
                                    null
                                } finally {
                                    runCatching { reader.release() }
                                }
                                runOnUiThread { result.success(tags) }
                            }.start()
                        }
                    }
                    "hasAccess" -> result.success(hasStorageAccess())
                    "requestAccess" -> {
                        if (hasStorageAccess()) {
                            result.success(true)
                        } else if (pendingStorage != null) {
                            result.error("busy", "Ya hay una solicitud de permiso abierta.", null)
                        } else {
                            pendingStorage = result
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                    val intent = Intent(
                                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                        Uri.parse("package:$packageName")
                                    )
                                    startActivityForResult(intent, storageRequest)
                                } else {
                                    requestPermissions(
                                        arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,
                                            Manifest.permission.WRITE_EXTERNAL_STORAGE),
                                        storageRequest
                                    )
                                }
                            } catch (error: Exception) {
                                pendingStorage = null
                                result.error("storage_permission", "No se pudo abrir el permiso de almacenamiento.", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == storageRequest) finishStorageRequest()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == storageRequest) finishStorageRequest()
    }

    private fun finishStorageRequest() {
        val result = pendingStorage
        pendingStorage = null
        result?.success(hasStorageAccess())
    }
}
