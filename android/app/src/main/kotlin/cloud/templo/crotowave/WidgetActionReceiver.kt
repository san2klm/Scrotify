package cloud.templo.crotowave

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.browse.MediaBrowser
import android.media.session.MediaController
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Botón de favorito del widget: se conecta a la sesión de medios de
 * audio_service y le envía la acción personalizada "toggleLike", que la app
 * Flutter resuelve (marca/desmarca la pista actual en el servidor).
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE_LIKE) return
        val pending = goAsync()
        val main = Handler(Looper.getMainLooper())
        var browser: MediaBrowser? = null
        var finished = false
        fun finish() {
            if (finished) return
            finished = true
            try { browser?.disconnect() } catch (_: Throwable) {}
            pending.finish()
        }
        try {
            browser = MediaBrowser(
                context,
                ComponentName(context, "com.ryanheise.audioservice.AudioService"),
                object : MediaBrowser.ConnectionCallback() {
                    override fun onConnected() {
                        try {
                            MediaController(context, browser!!.sessionToken)
                                .transportControls.sendCustomAction(CUSTOM_ACTION, null)
                        } catch (e: Throwable) {
                            Log.w(WidgetSupport.TAG, "No se pudo enviar el favorito", e)
                        }
                        finish()
                    }

                    override fun onConnectionFailed() = finish()
                    override fun onConnectionSuspended() = finish()
                },
                null,
            )
            browser.connect()
            main.postDelayed({ finish() }, 8000)
        } catch (e: Throwable) {
            Log.w(WidgetSupport.TAG, "Fallo al conectar con la sesión de medios", e)
            finish()
        }
    }

    companion object {
        const val ACTION_TOGGLE_LIKE = "cloud.templo.crotowave.WIDGET_TOGGLE_LIKE"
        private const val CUSTOM_ACTION = "toggleLike"

        fun likeIntent(context: Context): PendingIntent {
            val intent = Intent(ACTION_TOGGLE_LIKE).apply {
                component = ComponentName(context, WidgetActionReceiver::class.java)
            }
            return PendingIntent.getBroadcast(
                context, 7001, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
    }
}
