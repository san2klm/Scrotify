package cloud.templo.crotowave

import android.appwidget.AppWidgetManager
import android.content.Context
import android.widget.RemoteViews

/** Diseño "Compacto": una fila con miniatura, título y controles. */
class CrotoWaveCompactWidgetProvider : CrotoWaveBaseWidget() {
    override fun build(
        context: Context, mgr: AppWidgetManager, id: Int, state: WidgetState, withCover: Boolean,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.crotowave_widget_compact)
        WidgetSupport.bindCommon(
            context, views, state,
            R.id.widget_root, R.id.widget_prev, R.id.widget_play, R.id.widget_next,
            R.id.widget_title, R.id.widget_artist)
        val cover = if (withCover) WidgetSupport.loadCover(state.coverPath, 256) else null
        views.setInt(R.id.widget_bg, "setColorFilter", WidgetSupport.accentColor(cover))
        if (cover != null) {
            views.setImageViewBitmap(
                R.id.widget_cover,
                WidgetSupport.roundedSquare(cover, 256, 256 * 10f / 56f))
        } else {
            views.setImageViewResource(R.id.widget_cover, R.drawable.widget_cover_placeholder)
        }
        return views
    }
}
