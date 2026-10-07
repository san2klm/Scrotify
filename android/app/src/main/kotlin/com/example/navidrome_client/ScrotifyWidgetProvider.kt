package com.example.navidrome_client

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews

/**
 * Widget "Personalizable" (estilo AIMP, 3x1): portada a la izquierda, título,
 * «Artista - Álbum» y controles (anterior, play, siguiente, favorito), con
 * engranaje para personalizar colores, tamaño, transparencia y más.
 */
class ScrotifyWidgetProvider : ScrotifyBaseWidget() {
    override fun build(
        context: Context, mgr: AppWidgetManager, id: Int, state: WidgetState, withCover: Boolean,
    ): RemoteViews = buildWith(context, id, WidgetConfig.load(context, id), state, withCover)

    /** Dibuja el widget con [config]; también lo usa la vista previa de la configuración. */
    fun buildWith(
        context: Context, id: Int, config: WidgetConfig, state: WidgetState, withCover: Boolean = true,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.scrotify_widget)
        val s = config.scale / 100f

        val cover = if (withCover && !config.hideCover) WidgetSupport.loadCover(state.coverPath, 384) else null
        val background = if (config.autoColors) WidgetSupport.accentColor(cover) else config.background
        val primary = if (config.autoColors) Color.WHITE else config.primary
        val secondary = if (config.autoColors) 0xCCFFFFFF.toInt() else config.secondary

        // Textos
        views.setTextViewText(
            R.id.widget_title, state.title ?: context.getString(R.string.widget_nothing_playing))
        val subtitle = listOfNotNull(
            state.artist?.takeIf { it.isNotBlank() },
            state.album?.takeIf { it.isNotBlank() && config.showAlbum },
        ).joinToString(" - ")
        views.setTextViewText(
            R.id.widget_artist, subtitle.ifEmpty { context.getString(R.string.widget_open_app) })
        views.setTextColor(R.id.widget_title, primary)
        views.setTextColor(R.id.widget_artist, secondary)
        views.setTextViewTextSize(R.id.widget_title, TypedValue.COMPLEX_UNIT_SP, 12f * s)
        views.setTextViewTextSize(R.id.widget_artist, TypedValue.COMPLEX_UNIT_SP, 9.5f * s)

        // Fondo: color, opacidad y redondeo
        val radiusStep = config.radiusStep.coerceIn(0, WidgetConfig.RADIUS_DP.size - 1)
        views.setImageViewResource(R.id.widget_bg, BACKGROUNDS[radiusStep])
        views.setInt(R.id.widget_bg, "setColorFilter", background or 0xFF000000.toInt())
        views.setInt(R.id.widget_bg, "setImageAlpha", (config.bgAlpha * 255 / 100).coerceIn(25, 255))

        // Iconos: color y tamaño (el tamaño por código requiere Android 12+)
        for (button in intArrayOf(
            R.id.widget_prev, R.id.widget_play, R.id.widget_next, R.id.widget_like, R.id.widget_settings,
        )) views.setInt(button, "setColorFilter", primary)
        views.setImageViewResource(
            R.id.widget_play,
            if (state.playing) R.drawable.ic_widget_pause_ring else R.drawable.ic_widget_play_ring)
        views.setImageViewResource(
            R.id.widget_like,
            if (state.liked) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            fun size(viewId: Int, dp: Float) {
                views.setViewLayoutWidth(viewId, dp * s, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(viewId, dp * s, TypedValue.COMPLEX_UNIT_DIP)
            }
            size(R.id.widget_prev, 28f)
            size(R.id.widget_next, 28f)
            size(R.id.widget_like, 28f)
            size(R.id.widget_play, 32f)
        }
        views.setViewVisibility(R.id.widget_like, if (config.showHeart) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.widget_settings, if (config.showSettings) View.VISIBLE else View.GONE)

        // Portada: tamaño máximo y forma
        val coverPx = WidgetSupport.dp(context, 96f * config.coverScale / 100f).toInt()
        views.setInt(R.id.widget_cover, "setMaxHeight", coverPx)
        views.setInt(R.id.widget_cover, "setMaxWidth", coverPx)
        if (config.hideCover) {
            views.setViewVisibility(R.id.widget_cover, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_cover, View.VISIBLE)
            if (cover != null) {
                val ratio = floatArrayOf(0f, 0.08f, 0.16f, 0.24f, 0.5f)[radiusStep]
                views.setImageViewBitmap(
                    R.id.widget_cover, WidgetSupport.roundedSquare(cover, 384, 384 * ratio))
            } else {
                views.setImageViewResource(R.id.widget_cover, R.drawable.widget_cover_placeholder)
            }
        }

        // Acciones
        views.setOnClickPendingIntent(R.id.widget_root, WidgetSupport.openAppIntent(context))
        WidgetSupport.bindControls(context, views, R.id.widget_prev, R.id.widget_play, R.id.widget_next)
        views.setOnClickPendingIntent(R.id.widget_settings, settingsIntent(context, id))
        views.setOnClickPendingIntent(R.id.widget_like, WidgetActionReceiver.likeIntent(context))
        return views
    }

    private fun settingsIntent(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, WidgetConfigActivity::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            context, id, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private companion object {
        val BACKGROUNDS = intArrayOf(
            R.drawable.widget_bg_r0, R.drawable.widget_bg_r12, R.drawable.widget_bg_r24,
            R.drawable.widget_bg_r36, R.drawable.widget_bg_r100)
    }
}
