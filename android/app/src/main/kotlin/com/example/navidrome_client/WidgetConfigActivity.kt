package com.example.navidrome_client

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.Editable
import android.text.InputFilter
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Pantalla de personalización del widget (se abre al colocarlo y desde su
 * engranaje). Muestra una vista previa en vivo del widget real y permite
 * cambiar colores (paleta o código hexadecimal), tamaño general, tamaño de la
 * portada, transparencia, redondeo y qué elementos se muestran.
 */
class WidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var config = WidgetConfig()
    private lateinit var previewHolder: FrameLayout
    private lateinit var previewCaption: TextView
    private lateinit var previewHint: TextView
    private val swatchViews = mutableMapOf<String, List<Pair<Int, View>>>()
    private val hexFields = mutableMapOf<String, EditText>()
    private val checkBoxes = mutableMapOf<String, CheckBox>()
    private val sliders = mutableMapOf<String, Pair<SeekBar, TextView>>()
    private var updatingUi = false

    private val backgrounds = intArrayOf(
        0xFF000000.toInt(), 0xFF121212.toInt(), 0xFF1F2A44.toInt(), 0xFF3B1F2B.toInt(),
        0xFF1B3B2F.toInt(), 0xFF3A2A12.toInt(), 0xFF2D1B4E.toInt(), 0xFFF2F2F2.toInt())
    private val foregrounds = intArrayOf(
        0xFFFFFFFF.toInt(), 0xFFB3B3B3.toInt(), 0xFFFFD600.toInt(), 0xFFFF80AB.toInt(),
        0xFF80D8FF.toInt(), 0xFFA5D6A7.toInt(), 0xFFFFAB40.toInt(), 0xFF121212.toInt())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Si el usuario sale sin aceptar, el lanzador no debe colocar el widget.
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        config = WidgetConfig.load(this, widgetId)
        setContentView(buildUi())
        refreshPreview()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    // ---- UI --------------------------------------------------------------

    private fun buildUi(): View {
        // Cabecera fija: así la vista previa se ve siempre mientras ajustas.
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF0B0B10.toInt())
            setPadding(dp(20), dp(20), dp(20), dp(10))
        }
        header.addView(text(getString(R.string.widget_config_title), 20f, Color.WHITE, bold = true))
        previewCaption = text("", 12f, 0xFFB3B3B3.toInt()).apply { setPadding(0, dp(4), 0, dp(8)) }
        header.addView(previewCaption)
        previewHolder = object : FrameLayout(this) {
            // La vista previa es solo para mirar: no debe disparar los botones.
            override fun onInterceptTouchEvent(ev: MotionEvent?) = true
        }.apply {
            setBackgroundColor(0xFF2A2A33.toInt())
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }
        header.addView(previewHolder, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        previewHint = text(getString(R.string.widget_preview_hint), 11f, 0xFF8A8A94.toInt()).apply {
            setPadding(0, dp(6), 0, 0)
        }
        header.addView(previewHint)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(0), dp(20), dp(16))
        }

        root.addView(section(getString(R.string.widget_section_colors)))
        root.addView(colorRow("bg", getString(R.string.widget_color_background), backgrounds,
            { config.background }) { config = config.copy(background = it) })
        root.addView(colorRow("primary", getString(R.string.widget_color_primary), foregrounds,
            { config.primary }) { config = config.copy(primary = it) })
        root.addView(colorRow("secondary", getString(R.string.widget_color_secondary), foregrounds,
            { config.secondary }) { config = config.copy(secondary = it) })
        root.addView(check("auto", getString(R.string.widget_auto_colors)) {
            config = config.copy(autoColors = it)
        })

        root.addView(section(getString(R.string.widget_section_size)))
        root.addView(slider("scale", getString(R.string.widget_size_general),
            WidgetConfig.MIN_SCALE, WidgetConfig.MAX_SCALE, { config.scale }, { "$it %" }) {
            config = config.copy(scale = it)
        })
        root.addView(slider("coverScale", getString(R.string.widget_size_cover),
            WidgetConfig.MIN_SCALE, WidgetConfig.MAX_SCALE, { config.coverScale }, { "$it %" }) {
            config = config.copy(coverScale = it)
        })

        root.addView(section(getString(R.string.widget_section_style)))
        root.addView(slider("bgAlpha", getString(R.string.widget_opacity),
            10, 100, { config.bgAlpha }, { "$it %" }) { config = config.copy(bgAlpha = it) })
        root.addView(slider("radius", getString(R.string.widget_radius),
            0, WidgetConfig.RADIUS_DP.size - 1, { config.radiusStep }, { radiusLabel(it) }) {
            config = config.copy(radiusStep = it)
        })

        root.addView(section(getString(R.string.widget_section_show)))
        root.addView(check("hideCover", getString(R.string.widget_hide_cover)) {
            config = config.copy(hideCover = it)
        })
        root.addView(check("album", getString(R.string.widget_show_album)) {
            config = config.copy(showAlbum = it)
        })
        root.addView(check("heart", getString(R.string.widget_show_heart)) {
            config = config.copy(showHeart = it)
        })
        root.addView(check("gear", getString(R.string.widget_show_settings)) {
            config = config.copy(showSettings = it)
        })

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(0xFF0B0B10.toInt())
            setPadding(dp(20), dp(10), dp(20), dp(14))
        }
        buttons.addView(button(getString(R.string.widget_reset)) {
            config = WidgetConfig()
            syncControls()
            refreshPreview()
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(8) })
        buttons.addView(button(getString(R.string.widget_accept)) { accept() },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(8) })

        syncControls()
        val scroll = ScrollView(this).apply {
            setBackgroundColor(0xFF0B0B10.toInt())
            addView(root)
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF0B0B10.toInt())
            addView(header)
            addView(scroll, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
            addView(buttons)
        }
    }

    private fun radiusLabel(step: Int) =
        if (step == 0) getString(R.string.widget_radius_none)
        else if (step == WidgetConfig.RADIUS_DP.size - 1) getString(R.string.widget_radius_pill)
        else "${WidgetConfig.RADIUS_DP[step]} dp"

    private fun text(value: String, size: Float, color: Int, bold: Boolean = false) =
        TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            if (bold) setTypeface(typeface, Typeface.BOLD)
        }

    private fun section(label: String) = text(label.uppercase(), 12f, 0xFFFFD600.toInt(), bold = true).apply {
        setPadding(0, dp(22), 0, dp(4))
    }

    private fun check(key: String, label: String, onChange: (Boolean) -> Unit) = CheckBox(this).apply {
        text = label
        setTextColor(Color.WHITE)
        textSize = 15f
        setPadding(dp(4), dp(8), dp(4), dp(8))
        setOnCheckedChangeListener { _, checked ->
            if (updatingUi) return@setOnCheckedChangeListener
            onChange(checked)
            refreshPreview()
        }
        checkBoxes[key] = this
    }

    private fun button(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = true
        setTextColor(Color.WHITE)
        background = GradientDrawable().apply {
            cornerRadius = dp(10).toFloat()
            setColor(0xFF3A3A44.toInt())
        }
        setOnClickListener { onClick() }
    }

    private fun slider(
        key: String, label: String, min: Int, max: Int,
        value: () -> Int, format: (Int) -> String, onChange: (Int) -> Unit,
    ): View {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(6), 0, dp(6))
        }
        val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        header.addView(text(label, 14f, 0xFFD0D0D0.toInt()),
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val valueLabel = text(format(value()), 14f, Color.WHITE, bold = true)
        header.addView(valueLabel)
        column.addView(header)
        val bar = SeekBar(this).apply {
            this.max = max - min
            progress = value() - min
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(sb: SeekBar?, p: Int, fromUser: Boolean) {
                    val v = p + min
                    valueLabel.text = format(v)
                    if (!fromUser || updatingUi) return
                    onChange(v)
                    refreshPreview()
                }
                override fun onStartTrackingTouch(sb: SeekBar?) {}
                override fun onStopTrackingTouch(sb: SeekBar?) {}
            })
        }
        column.addView(bar)
        sliders[key] = bar to valueLabel
        sliderSpecs[key] = Triple(min, value, format)
        return column
    }

    private val sliderSpecs = mutableMapOf<String, Triple<Int, () -> Int, (Int) -> String>>()

    private fun colorRow(
        key: String, label: String, palette: IntArray, current: () -> Int, onPick: (Int) -> Unit,
    ): View {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(8), 0, dp(4))
        }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(text(label, 14f, 0xFFD0D0D0.toInt()),
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val hex = EditText(this).apply {
            setTextColor(Color.WHITE)
            textSize = 13f
            setSingleLine()
            filters = arrayOf(InputFilter.LengthFilter(7))
            hint = "#RRGGBB"
            setHintTextColor(0xFF777777.toInt())
            addTextChangedListener(object : TextWatcher {
                override fun afterTextChanged(s: Editable?) {
                    if (updatingUi) return
                    val parsed = parseHex(s?.toString().orEmpty()) ?: return
                    onPick(parsed)
                    paint(swatchViews[key].orEmpty(), parsed)
                    refreshPreview()
                }
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            })
        }
        hexFields[key] = hex
        header.addView(hex, LinearLayout.LayoutParams(dp(100), LinearLayout.LayoutParams.WRAP_CONTENT))
        column.addView(header)
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(6), 0, 0)
        }
        val items = palette.map { color ->
            val swatch = View(this).apply {
                setOnClickListener {
                    onPick(color)
                    syncControls()
                    refreshPreview()
                }
            }
            row.addView(swatch, LinearLayout.LayoutParams(0, dp(34), 1f).apply { marginEnd = dp(6) })
            color to swatch
        }
        swatchViews[key] = items
        column.addView(row)
        colorSources[key] = current
        return column
    }

    private val colorSources = mutableMapOf<String, () -> Int>()

    private fun parseHex(value: String): Int? {
        val v = value.trim().removePrefix("#")
        if (v.length != 6) return null
        return v.toIntOrNull(16)?.let { it or 0xFF000000.toInt() }
    }

    private fun paint(items: List<Pair<Int, View>>, selected: Int) {
        items.forEach { (color, view) ->
            view.background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(color)
                val isSelected = (color or 0xFF000000.toInt()) == (selected or 0xFF000000.toInt())
                setStroke(if (isSelected) dp(3) else dp(1),
                    if (isSelected) 0xFFFFD600.toInt() else 0x55FFFFFF)
            }
        }
    }

    /** Lleva el estado de [config] a todos los controles (sin disparar sus listeners). */
    private fun syncControls() {
        updatingUi = true
        try {
            colorSources.forEach { (key, source) ->
                val color = source()
                paint(swatchViews[key].orEmpty(), color)
                hexFields[key]?.let { field ->
                    val hex = String.format("#%06X", color and 0xFFFFFF)
                    if (field.text.toString().uppercase() != hex) field.setText(hex)
                }
            }
            sliderSpecs.forEach { (key, spec) ->
                val (min, value, format) = spec
                sliders[key]?.let { (bar, label) ->
                    bar.progress = value() - min
                    label.text = format(value())
                }
            }
            checkBoxes["auto"]?.isChecked = config.autoColors
            checkBoxes["hideCover"]?.isChecked = config.hideCover
            checkBoxes["album"]?.isChecked = config.showAlbum
            checkBoxes["heart"]?.isChecked = config.showHeart
            checkBoxes["gear"]?.isChecked = config.showSettings
        } finally {
            updatingUi = false
        }
    }

    // ---- Vista previa ----------------------------------------------------

    /** Tamaño real (dp) del widget colocado; si aún no existe, un 3x1 típico. */
    private fun widgetSizeDp(): Pair<Int, Int> {
        return try {
            val o = AppWidgetManager.getInstance(this).getAppWidgetOptions(widgetId)
            val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            if (w > 0 && h > 0) Pair(w, h) else Pair(DEFAULT_W_DP, DEFAULT_H_DP)
        } catch (e: Throwable) {
            Pair(DEFAULT_W_DP, DEFAULT_H_DP)
        }
    }

    private fun refreshPreview() {
        if (!::previewHolder.isInitialized) return
        try {
            val state = previewState(this)
            val views = ScrotifyWidgetProvider().buildWith(this, widgetId, config, state)
            val (wDp, hDp) = widgetSizeDp()
            val maxW = (resources.displayMetrics.widthPixels / resources.displayMetrics.density - 60).toInt()
            val widthDp = minOf(wDp, maxW)
            previewCaption.text = getString(R.string.widget_preview_caption, widthDp, hDp)
            // Alto aproximado que necesita el contenido con el tamaño elegido.
            val needed = (8 + 61.6f * config.scale / 100f).toInt()
            if (needed > hDp) {
                previewHint.text = getString(R.string.widget_preview_too_small, needed)
                previewHint.setTextColor(0xFFFFAB40.toInt())
            } else {
                previewHint.text = getString(R.string.widget_preview_hint)
                previewHint.setTextColor(0xFF8A8A94.toInt())
            }
            previewHolder.removeAllViews()
            previewHolder.addView(views.apply(this, previewHolder),
                FrameLayout.LayoutParams(dp(widthDp), dp(hDp), Gravity.CENTER_HORIZONTAL))
        } catch (e: Throwable) {
            android.util.Log.w(WidgetSupport.TAG, "No se pudo dibujar la vista previa", e)
        }
    }

    /** Estado real si hay música; si no, un ejemplo para poder ver el diseño. */
    private fun previewState(context: Context): WidgetState {
        val real = WidgetState.from(HomeWidgetPlugin.getData(context))
        return if (real.title != null) real else WidgetState(
            title = getString(R.string.widget_sample_title),
            artist = getString(R.string.widget_sample_artist),
            album = getString(R.string.widget_sample_album),
            playing = false, coverPath = null, liked = false)
    }

    private fun accept() {
        WidgetConfig.save(this, widgetId, config)
        // Redibuja con la configuración nueva.
        sendBroadcast(Intent(this, ScrotifyWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        })
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }

    private companion object {
        const val DEFAULT_W_DP = 250
        const val DEFAULT_H_DP = 72
    }
}
