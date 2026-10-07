package com.example.navidrome_client

import android.content.Context

/** Personalización de un widget "Personalizable" (una por widget colocado). */
data class WidgetConfig(
    val background: Int = DEFAULT_BACKGROUND,
    val primary: Int = DEFAULT_PRIMARY,
    val secondary: Int = DEFAULT_SECONDARY,
    val hideCover: Boolean = false,
    val autoColors: Boolean = false,
    /** Tamaño general de textos y botones, en %. */
    val scale: Int = 100,
    /** Tamaño máximo de la portada, en %. */
    val coverScale: Int = 100,
    /** Opacidad del fondo, en %. */
    val bgAlpha: Int = 100,
    /** Redondeo de esquinas: índice en [RADIUS_DP]. */
    val radiusStep: Int = 2,
    val showHeart: Boolean = true,
    val showSettings: Boolean = true,
    val showAlbum: Boolean = true,
    val showText: Boolean = true,
    /** Ancho y alto del widget dentro de su celda, en % (reduce el recuadro visible). */
    val widthPct: Int = 100,
    val heightPct: Int = 100,
) {
    companion object {
        const val DEFAULT_BACKGROUND = 0xFF121212.toInt()
        const val DEFAULT_PRIMARY = 0xFFFFFFFF.toInt()
        const val DEFAULT_SECONDARY = 0xFFB3B3B3.toInt()
        const val MIN_SCALE = 40
        const val MAX_SCALE = 180
        /** Radios disponibles (dp); el último es una "píldora". */
        val RADIUS_DP = intArrayOf(0, 12, 24, 36, 100)
        private const val PREFS = "scrotify_widget_config"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun load(context: Context, id: Int): WidgetConfig {
            val p = prefs(context)
            val d = WidgetConfig()
            return WidgetConfig(
                background = p.getInt("bg_$id", d.background),
                primary = p.getInt("primary_$id", d.primary),
                secondary = p.getInt("secondary_$id", d.secondary),
                hideCover = p.getBoolean("hideCover_$id", d.hideCover),
                autoColors = p.getBoolean("auto_$id", d.autoColors),
                scale = p.getInt("scale_$id", d.scale).coerceIn(MIN_SCALE, MAX_SCALE),
                coverScale = p.getInt("coverScale_$id", d.coverScale).coerceIn(MIN_SCALE, MAX_SCALE),
                bgAlpha = p.getInt("bgAlpha_$id", d.bgAlpha).coerceIn(10, 100),
                radiusStep = p.getInt("radius_$id", d.radiusStep).coerceIn(0, RADIUS_DP.size - 1),
                showHeart = p.getBoolean("heart_$id", d.showHeart),
                showSettings = p.getBoolean("gear_$id", d.showSettings),
                showAlbum = p.getBoolean("album_$id", d.showAlbum),
                showText = p.getBoolean("text_$id", d.showText),
                widthPct = p.getInt("widthPct_$id", d.widthPct).coerceIn(30, 100),
                heightPct = p.getInt("heightPct_$id", d.heightPct).coerceIn(40, 100),
            )
        }

        fun save(context: Context, id: Int, c: WidgetConfig) {
            prefs(context).edit()
                .putInt("bg_$id", c.background)
                .putInt("primary_$id", c.primary)
                .putInt("secondary_$id", c.secondary)
                .putBoolean("hideCover_$id", c.hideCover)
                .putBoolean("auto_$id", c.autoColors)
                .putInt("scale_$id", c.scale)
                .putInt("coverScale_$id", c.coverScale)
                .putInt("bgAlpha_$id", c.bgAlpha)
                .putInt("radius_$id", c.radiusStep)
                .putBoolean("heart_$id", c.showHeart)
                .putBoolean("gear_$id", c.showSettings)
                .putBoolean("album_$id", c.showAlbum)
                .putBoolean("text_$id", c.showText)
                .putInt("widthPct_$id", c.widthPct)
                .putInt("heightPct_$id", c.heightPct)
                .apply()
        }

        fun delete(context: Context, id: Int) {
            val e = prefs(context).edit()
            for (k in listOf("bg", "primary", "secondary", "hideCover", "auto", "scale",
                "coverScale", "bgAlpha", "radius", "heart", "gear", "album", "text", "widthPct", "heightPct")) e.remove("${k}_$id")
            e.apply()
        }
    }
}
