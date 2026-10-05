package com.example.navidrome_client

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Widget de pantalla de inicio: carátula, título, artista y controles.
 *
 * Los datos los escribe la app Flutter (HomeWidgetService) en las
 * SharedPreferences de home_widget. Los botones envían eventos de medios al
 * MediaButtonReceiver de audio_service, así que funcionan con la misma
 * lógica que los botones de la notificación.
 */
class ScrotifyWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString(KEY_TITLE, null)
        val artist = widgetData.getString(KEY_ARTIST, null)
        val playing = widgetData.getBoolean(KEY_PLAYING, false)
        val coverPath = widgetData.getString(KEY_COVER_PATH, null)
        // La carátula es opcional: si falla la decodificación (archivo corrupto,
        // sin memoria…) el widget se dibuja igual, sin imagen.
        val cover = try {
            loadCover(coverPath)
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo cargar la carátula del widget", e)
            null
        }

        for (id in appWidgetIds) {
            try {
                appWidgetManager.updateAppWidget(
                    id, buildViews(context, title, artist, playing, cover))
            } catch (e: Throwable) {
                // Un RemoteViews inválido deja el widget en negro: se reintenta
                // sin carátula, que es lo único que puede exceder los límites.
                Log.e(TAG, "Fallo al dibujar el widget; reintentando sin carátula", e)
                try {
                    appWidgetManager.updateAppWidget(
                        id, buildViews(context, title, artist, playing, null))
                } catch (e2: Throwable) {
                    Log.e(TAG, "Fallo definitivo al dibujar el widget", e2)
                }
            }
        }
    }

    private fun buildViews(
        context: Context,
        title: String?,
        artist: String?,
        playing: Boolean,
        cover: Bitmap?,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.scrotify_widget)

        views.setTextViewText(
            R.id.widget_title,
            title ?: context.getString(R.string.widget_nothing_playing),
        )
        views.setTextViewText(
            R.id.widget_artist,
            artist ?: context.getString(R.string.widget_open_app),
        )
        views.setImageViewResource(
            R.id.widget_play,
            if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
        )
        if (cover != null) {
            views.setImageViewBitmap(R.id.widget_cover, cover)
        } else {
            views.setImageViewResource(R.id.widget_cover, android.R.color.transparent)
        }

        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
        views.setOnClickPendingIntent(
            R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        views.setOnClickPendingIntent(
            R.id.widget_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        views.setOnClickPendingIntent(
            R.id.widget_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))

        return views
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent()
        return PendingIntent.getActivity(
            context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Evento de medios dirigido al receptor de audio_service. */
    private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context, keyCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /**
     * Decodifica la carátula reducida: un RemoteViews con un bitmap enorme
     * falla (límite de memoria del binder), así que se limita a ~256 px.
     */
    private fun loadCover(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = File(path)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MAX_COVER_PX) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeFile(path, opts)
    }

    companion object {
        const val KEY_TITLE = "widget_title"
        const val KEY_ARTIST = "widget_artist"
        const val KEY_PLAYING = "widget_playing"
        const val KEY_COVER_PATH = "widget_cover_path"
        private const val MAX_COVER_PX = 256
        private const val TAG = "ScrotifyWidget"
    }
}
