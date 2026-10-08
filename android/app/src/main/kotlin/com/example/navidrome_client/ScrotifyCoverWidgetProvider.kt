package com.example.navidrome_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.widget.RemoteViews

/** Diseño "Carátula": la portada ocupa todo el widget con el texto encima. */
class ScrotifyCoverWidgetProvider : ScrotifyBaseWidget() {
    override fun build(
        context: Context, mgr: AppWidgetManager, id: Int, state: WidgetState, withCover: Boolean,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.scrotify_widget_cover)
        WidgetSupport.bindCommon(
            context, views, state,
            R.id.widget_root, R.id.widget_prev, R.id.widget_play, R.id.widget_next,
            R.id.widget_title, R.id.widget_artist)
        val (w, h) = WidgetSupport.sizePx(context, mgr, id, 160f, 160f)
        val cover = if (withCover) WidgetSupport.loadCover(state.coverPath, 640) else null
        if (cover != null) {
            views.setImageViewBitmap(
                R.id.widget_bg, WidgetSupport.coverCard(cover, w, h, minOf(w, h) * 0.12f))
            views.setInt(R.id.widget_bg, "setColorFilter", 0)
        } else {
            views.setImageViewResource(R.id.widget_bg, R.drawable.widget_bg_round)
            views.setInt(R.id.widget_bg, "setColorFilter", WidgetSupport.accentColor(null))
        }
        return views
    }
}
