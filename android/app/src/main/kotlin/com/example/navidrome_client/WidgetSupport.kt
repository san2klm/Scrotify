package com.example.navidrome_client

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.Log
import android.util.TypedValue
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/** Datos que la app Flutter (HomeWidgetService) deja en las SharedPreferences. */
data class WidgetState(
    val title: String?,
    val artist: String?,
    val album: String?,
    val playing: Boolean,
    val coverPath: String?,
    val liked: Boolean = false,
) {
    companion object {
        const val KEY_TITLE = "widget_title"
        const val KEY_ARTIST = "widget_artist"
        const val KEY_ALBUM = "widget_album"
        const val KEY_PLAYING = "widget_playing"
        const val KEY_COVER_PATH = "widget_cover_path"
        const val KEY_LIKED = "widget_liked"

        fun from(prefs: SharedPreferences) = WidgetState(
            title = prefs.getString(KEY_TITLE, null),
            artist = prefs.getString(KEY_ARTIST, null),
            album = prefs.getString(KEY_ALBUM, null),
            playing = prefs.getBoolean(KEY_PLAYING, false),
            coverPath = prefs.getString(KEY_COVER_PATH, null),
            liked = prefs.getBoolean(KEY_LIKED, false),
        )
    }
}

/** Utilidades compartidas por los distintos diseños del widget. */
object WidgetSupport {
    const val TAG = "ScrotifyWidget"
    private const val DEFAULT_BG = 0xFF1E1E1E.toInt()

    /**
     * Decodifica la carátula reducida: un RemoteViews con un bitmap enorme
     * falla (límite de memoria del binder), así que se limita su tamaño.
     */
    fun loadCover(path: String?, maxPx: Int): Bitmap? {
        if (path.isNullOrEmpty()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxPx) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (e: Throwable) {
            Log.w(TAG, "No se pudo cargar la carátula del widget", e)
            null
        }
    }

    /** Color oscuro derivado de la carátula (como los widgets con color de álbum). */
    fun accentColor(cover: Bitmap?): Int {
        if (cover == null) return DEFAULT_BG
        val tiny = Bitmap.createScaledBitmap(cover, 16, 16, true)
        var r = 0L; var g = 0L; var b = 0L
        for (x in 0 until 16) for (y in 0 until 16) {
            val p = tiny.getPixel(x, y)
            r += Color.red(p); g += Color.green(p); b += Color.blue(p)
        }
        val n = 256
        val hsv = FloatArray(3)
        Color.RGBToHSV((r / n).toInt(), (g / n).toInt(), (b / n).toInt(), hsv)
        hsv[1] = hsv[1].coerceIn(0f, 0.65f)
        hsv[2] = hsv[2].coerceIn(0.20f, 0.36f)
        return Color.HSVToColor(hsv)
    }

    /** Recorte cuadrado con esquinas redondeadas (carátula pequeña). */
    fun roundedSquare(src: Bitmap, sizePx: Int, radiusPx: Float): Bitmap =
        render(src, sizePx, sizePx, radiusPx, scrim = false)

    /** Carátula a todo el widget, con degradado inferior para leer el texto. */
    fun coverCard(src: Bitmap, widthPx: Int, heightPx: Int, radiusPx: Float): Bitmap =
        render(src, widthPx, heightPx, radiusPx, scrim = true)

    private fun render(src: Bitmap, w: Int, h: Int, radius: Float, scrim: Boolean): Bitmap {
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        // center-crop manual hacia (w, h)
        val scale = maxOf(w.toFloat() / src.width, h.toFloat() / src.height)
        val sw = src.width * scale
        val sh = src.height * scale
        val shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        shader.setLocalMatrix(android.graphics.Matrix().apply {
            setScale(scale, scale)
            postTranslate((w - sw) / 2f, (h - sh) / 2f)
        })
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader }
        val rect = RectF(0f, 0f, w.toFloat(), h.toFloat())
        canvas.drawRoundRect(rect, radius, radius, paint)
        if (scrim) {
            val grad = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.shader = LinearGradient(
                    0f, h * 0.30f, 0f, h.toFloat(),
                    Color.TRANSPARENT, 0xE6000000.toInt(), Shader.TileMode.CLAMP)
            }
            canvas.drawRoundRect(rect, radius, radius, grad)
        }
        return out
    }

    fun dp(context: Context, value: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics)

    /** Tamaño actual del widget en px (limitado para no exceder el límite del binder). */
    fun sizePx(context: Context, mgr: AppWidgetManager, id: Int, defW: Float, defH: Float): Pair<Int, Int> {
        val o = mgr.getAppWidgetOptions(id)
        val wDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0).takeIf { it > 0 }?.toFloat() ?: defW
        val hDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0).takeIf { it > 0 }?.toFloat() ?: defH
        var w = dp(context, wDp)
        var h = dp(context, hDp)
        val cap = 640f / maxOf(w, h)
        if (cap < 1f) { w *= cap; h *= cap }
        return Pair(w.toInt().coerceAtLeast(64), h.toInt().coerceAtLeast(64))
    }

    fun openAppIntent(context: Context): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        return PendingIntent.getActivity(
            context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Evento de medios dirigido al receptor de audio_service. */
    fun mediaButton(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context, keyCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Texto, botón play/pausa y los tres botones de control comunes. */
    fun bindCommon(
        context: Context,
        views: RemoteViews,
        state: WidgetState,
        rootId: Int, prevId: Int, playId: Int, nextId: Int,
        titleId: Int, artistId: Int,
    ) {
        views.setTextViewText(titleId, state.title ?: context.getString(R.string.widget_nothing_playing))
        views.setTextViewText(artistId, state.artist ?: context.getString(R.string.widget_open_app))
        views.setImageViewResource(
            playId, if (state.playing) R.drawable.ic_widget_pause_dark else R.drawable.ic_widget_play_dark)
        views.setOnClickPendingIntent(rootId, openAppIntent(context))
        bindControls(context, views, prevId, playId, nextId)
    }

    fun bindControls(context: Context, views: RemoteViews, prevId: Int, playId: Int, nextId: Int) {
        views.setOnClickPendingIntent(prevId, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        views.setOnClickPendingIntent(playId, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        views.setOnClickPendingIntent(nextId, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))
    }
}

/**
 * Base de los diseños: dibuja cada widget y, si el RemoteViews resulta
 * inválido (deja el widget en negro), reintenta sin carátula.
 */
abstract class ScrotifyBaseWidget : HomeWidgetProvider() {
    protected abstract fun build(
        context: Context, mgr: AppWidgetManager, id: Int, state: WidgetState, withCover: Boolean,
    ): RemoteViews

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val state = WidgetState.from(widgetData)
        for (id in appWidgetIds) {
            try {
                appWidgetManager.updateAppWidget(id, build(context, appWidgetManager, id, state, true))
            } catch (e: Throwable) {
                Log.e(WidgetSupport.TAG, "Fallo al dibujar el widget; reintentando sin carátula", e)
                try {
                    appWidgetManager.updateAppWidget(id, build(context, appWidgetManager, id, state, false))
                } catch (e2: Throwable) {
                    Log.e(WidgetSupport.TAG, "Fallo definitivo al dibujar el widget", e2)
                }
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach { WidgetConfig.delete(context, it) }
    }

    /** Al redimensionar hay que volver a renderizar con el tamaño nuevo. */
    override fun onAppWidgetOptionsChanged(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int,
        newOptions: android.os.Bundle?,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }
}
