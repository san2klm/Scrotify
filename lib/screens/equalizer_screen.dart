// Pantalla del ecualizador de tres niveles.
//
//   Simple        → presets por situación + 3 sliders grandes + "Modo noche".
//   Intermedio    → 10 bandas verticales ISO + preamp auto/manual + presets.
//   Profesional   → lista de filtros paramétricos editables, curva con banda
//                   resaltada, importación/exportación AutoEQ (EqualizerAPO).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/eq_models.dart';
import '../services/equalizer_service.dart';
import '../widgets/eq_response_curve.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerService>();
    final caps = eq.capabilities;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ecualizador'),
        actions: [
          if (eq.mode != EqMode.simple)
            IconButton(
              tooltip: 'Restablecer',
              icon: const Icon(Icons.restart_alt),
              onPressed: eq.reset,
            ),
          Switch(value: eq.enabled, onChanged: eq.setEnabled),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<EqMode>(
            segments: const [
              ButtonSegment(
                  value: EqMode.simple,
                  label: Text('Simple'),
                  icon: Icon(Icons.tune)),
              ButtonSegment(
                  value: EqMode.intermediate,
                  label: Text('10 bandas'),
                  icon: Icon(Icons.equalizer)),
              ButtonSegment(
                  value: EqMode.professional,
                  label: Text('Pro'),
                  icon: Icon(Icons.science_outlined)),
            ],
            selected: {eq.mode},
            onSelectionChanged: (s) => eq.setMode(s.first),
          ),
          const SizedBox(height: 12),
          if (eq.blockedByHifi)
            const _Banner(
              icon: Icons.high_quality,
              text:
                  'En pausa: el modo Bit-perfect envía el audio sin modificar. '
                  'Cambiá a "Alta fidelidad" en Ajustes > Audio para ecualizar.',
            )
          else if (caps?.note != null)
            _Banner(icon: Icons.info_outline, text: caps!.note!),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: eq.enabled && !eq.blockedByHifi ? 1 : 0.45,
            child: switch (eq.mode) {
              EqMode.simple => const _SimpleView(),
              EqMode.intermediate => const _GraphicView(),
              EqMode.professional => const _ProView(),
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ Simple ═══════════════════════════════

class _SimpleView extends StatelessWidget {
  const _SimpleView();

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerService>();
    final p = eq.active;
    final bands = p.bands.length == 3 ? p.bands : const <EqBand>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Cómo querés que suene?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in eq.presetsForMode)
              ChoiceChip(
                label: Text(preset.name),
                selected: preset.id == p.id,
                onSelected: (_) => eq.selectProfile(preset),
              ),
          ],
        ),
        const SizedBox(height: 20),
        EqResponseCurve(
            bands: p.effectiveBands, preampDb: 0, rangeDb: 8, height: 110),
        const SizedBox(height: 12),
        if (bands.isNotEmpty) ...[
          _BigSlider(
            label: 'Graves',
            hint: 'Bombo, bajo, "punch"',
            value: bands[0].gainDb,
            onChanged: (v) => eq.setSimple(bass: v, dragging: true),
            onChangeEnd: (v) => eq.setSimple(bass: v),
          ),
          _BigSlider(
            label: 'Medios',
            hint: 'Voces, guitarras, presencia',
            value: bands[1].gainDb,
            onChanged: (v) => eq.setSimple(mid: v, dragging: true),
            onChangeEnd: (v) => eq.setSimple(mid: v),
          ),
          _BigSlider(
            label: 'Agudos',
            hint: 'Platillos, brillo, detalle',
            value: bands[2].gainDb,
            onChanged: (v) => eq.setSimple(treble: v, dragging: true),
            onChangeEnd: (v) => eq.setSimple(treble: v),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Modo noche'),
          subtitle: const Text(
              'Mantiene graves y brillo cuando escuchás a volumen bajo'),
          value: p.loudness,
          onChanged: eq.setLoudness,
        ),
      ],
    );
  }
}

class _BigSlider extends StatelessWidget {
  final String label, hint;
  final double value;
  final ValueChanged<double> onChanged, onChangeEnd;
  const _BigSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  String get _word {
    if (value.abs() < 0.5) return 'Normal';
    final mag = value.abs() >= 4 ? 'Mucho ' : '';
    return value > 0 ? '${mag}más' : '${mag}menos';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: t.titleSmall),
            const SizedBox(width: 8),
            Expanded(
                child: Text(hint,
                    style: t.bodySmall, overflow: TextOverflow.ellipsis)),
            Text(_word, style: t.labelLarge),
          ]),
          Slider(
            value: value.clamp(
                EqLimits.simple.minGainDb, EqLimits.simple.maxGainDb),
            min: EqLimits.simple.minGainDb,
            max: EqLimits.simple.maxGainDb,
            divisions: 24,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ Intermedio ═══════════════════════════════

class _GraphicView extends StatelessWidget {
  const _GraphicView();

  static String _fmtHz(double f) =>
      f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}';

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerService>();
    final p = eq.active;
    final lim = eq.limits;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetDropdown(eq: eq),
        const SizedBox(height: 12),
        EqResponseCurve(
            bands: p.effectiveBands,
            preampDb: eq.effectivePreampDb,
            rangeDb: 12),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: Row(
            children: [
              for (var i = 0; i < p.bands.length; i++)
                Expanded(
                  child: Column(children: [
                    Text(p.bands[i].gainDb.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.labelSmall),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: p.bands[i].gainDb
                              .clamp(lim.minGainDb, lim.maxGainDb),
                          min: lim.minGainDb,
                          max: lim.maxGainDb,
                          divisions: 48, // pasos de 0.5 dB
                          onChanged: (v) => eq.updateBand(
                              i, p.bands[i].copyWith(gainDb: v),
                              dragging: true),
                          onChangeEnd: (v) =>
                              eq.updateBand(i, p.bands[i].copyWith(gainDb: v)),
                        ),
                      ),
                    ),
                    Text(_fmtHz(p.bands[i].frequency),
                        style: Theme.of(context).textTheme.labelSmall),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _PreampControl(eq: eq),
        _SaveRow(eq: eq),
      ],
    );
  }
}

// ═══════════════════════════════ Profesional ═══════════════════════════════

class _ProView extends StatefulWidget {
  const _ProView();
  @override
  State<_ProView> createState() => _ProViewState();
}

class _ProViewState extends State<_ProView> {
  int? _selected;

  Future<void> _import(EqualizerService eq) async {
    final ctrl = TextEditingController();
    final nameCtrl = TextEditingController(text: 'AutoEQ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar ParametricEQ.txt'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText:
                    'Preamp: -6.2 dB\nFilter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70\n…',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final warnings = await eq.importApo(ctrl.text, nameCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(warnings.isEmpty
          ? 'Importado: ${eq.active.bands.length} filtros'
          : 'Importado con ${warnings.length} advertencias: ${warnings.first}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerService>();
    final p = eq.active;
    final sel =
        (_selected != null && _selected! < p.bands.length) ? _selected : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: _PresetDropdown(eq: eq)),
          IconButton(
            tooltip: 'Importar AutoEQ / EqualizerAPO',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _import(eq),
          ),
          IconButton(
            tooltip: 'Copiar como EqualizerAPO',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: eq.exportApo()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copiado al portapapeles')));
              }
            },
          ),
        ]),
        const SizedBox(height: 8),
        EqResponseCurve(
          bands: p.effectiveBands,
          preampDb: eq.effectivePreampDb,
          rangeDb: 15,
          highlightedBand: sel,
          height: 200,
        ),
        const SizedBox(height: 8),
        _PreampControl(eq: eq),
        const Divider(),
        for (var i = 0; i < p.bands.length; i++)
          _ProBandTile(
            index: i,
            band: p.bands[i],
            selected: i == sel,
            onTap: () => setState(() => _selected = i == sel ? null : i),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              p.bands.length < eq.limits.maxBands ? () => eq.addBand() : null,
          icon: const Icon(Icons.add),
          label:
              Text('Agregar filtro (${p.bands.length}/${eq.limits.maxBands})'),
        ),
        _SaveRow(eq: eq),
      ],
    );
  }
}

class _ProBandTile extends StatelessWidget {
  final int index;
  final EqBand band;
  final bool selected;
  final VoidCallback onTap;
  const _ProBandTile({
    required this.index,
    required this.band,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eq = context.read<EqualizerService>();
    final lim = eq.limits;
    void setBand(EqBand b, {bool drag = false}) =>
        eq.updateBand(index, b, dragging: drag);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        ListTile(
          dense: true,
          onTap: onTap,
          leading: Checkbox(
              value: band.enabled,
              onChanged: (v) => setBand(band.copyWith(enabled: v))),
          title: Text('${band.type.label} · ${band.frequency.round()} Hz'
              '${band.type.usesGain ? ' · ${band.gainDb.toStringAsFixed(1)} dB' : ''}'
              ' · Q ${band.q.toStringAsFixed(2)}'),
          trailing: IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => eq.removeBand(index),
          ),
        ),
        if (selected)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              DropdownButton<EqFilterType>(
                isExpanded: true,
                value: band.type,
                items: [
                  for (final t in EqFilterType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) {
                  if (t != null) setBand(band.copyWith(type: t));
                },
              ),
              _LabeledSlider(
                label: 'Frecuencia',
                // Slider logarítmico: 0..1 → 20 Hz..20 kHz
                value: _toLog(band.frequency),
                display: '${band.frequency.round()} Hz',
                onChanged: (v) =>
                    setBand(band.copyWith(frequency: _fromLog(v)), drag: true),
                onChangeEnd: (v) =>
                    setBand(band.copyWith(frequency: _fromLog(v))),
              ),
              if (band.type.usesGain)
                _LabeledSlider(
                  label: 'Ganancia',
                  value: (band.gainDb - lim.minGainDb) /
                      (lim.maxGainDb - lim.minGainDb),
                  display: '${band.gainDb.toStringAsFixed(1)} dB',
                  onChanged: (v) => setBand(
                      band.copyWith(
                          gainDb: _round(
                              lim.minGainDb +
                                  v * (lim.maxGainDb - lim.minGainDb),
                              0.1)),
                      drag: true),
                  onChangeEnd: (v) => setBand(band.copyWith(
                      gainDb: _round(
                          lim.minGainDb + v * (lim.maxGainDb - lim.minGainDb),
                          0.1))),
                ),
              _LabeledSlider(
                label: 'Q (ancho)',
                // 0.1..10 en escala logarítmica
                value: (_ln(band.q) - _ln(0.1)) / (_ln(10) - _ln(0.1)),
                display: band.q.toStringAsFixed(2),
                onChanged: (v) =>
                    setBand(band.copyWith(q: _qFrom(v)), drag: true),
                onChangeEnd: (v) => setBand(band.copyWith(q: _qFrom(v))),
              ),
            ]),
          ),
      ]),
    );
  }

  static double _ln(double v) => math.log(v);

  static double _toLog(double f) =>
      ((_ln(f) - _ln(20)) / (_ln(20000) - _ln(20))).clamp(0.0, 1.0);
  static double _fromLog(double v) =>
      _round(math.exp(_ln(20) + v * (_ln(20000) - _ln(20))), 1);
  static double _qFrom(double v) =>
      _round(math.exp(_ln(0.1) + v * (_ln(10) - _ln(0.1))), 0.01);
  static double _round(double v, double step) =>
      (v / step).roundToDouble() * step;
}

class _LabeledSlider extends StatelessWidget {
  final String label, display;
  final double value;
  final ValueChanged<double> onChanged, onChangeEnd;
  const _LabeledSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(width: 72, child: Text(display, textAlign: TextAlign.end)),
      ]);
}

// ═══════════════════════════════ Compartidos ═══════════════════════════════

class _PresetDropdown extends StatelessWidget {
  final EqualizerService eq;
  const _PresetDropdown({required this.eq});

  @override
  Widget build(BuildContext context) {
    final presets = eq.presetsForMode;
    final current =
        presets.any((p) => p.id == eq.active.id) ? eq.active.id : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: const InputDecoration(
          labelText: 'Preset', border: OutlineInputBorder()),
      hint: Text(eq.active.name),
      items: [
        for (final p in presets)
          DropdownMenuItem(
              value: p.id, child: Text(p.isBuiltIn ? p.name : '★ ${p.name}')),
      ],
      onChanged: (id) {
        final p = presets.where((e) => e.id == id).firstOrNull;
        if (p != null) eq.selectProfile(p);
      },
    );
  }
}

class _PreampControl extends StatelessWidget {
  final EqualizerService eq;
  const _PreampControl({required this.eq});

  @override
  Widget build(BuildContext context) {
    final p = eq.active;
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Preamp automático'),
        subtitle: Text(p.autoPreamp
            ? 'Evita la saturación: ${eq.effectivePreampDb.toStringAsFixed(1)} dB'
            : 'Manual — puede saturar si realzás mucho'),
        value: p.autoPreamp,
        onChanged: (v) => eq.setPreamp(auto: v),
      ),
      if (!p.autoPreamp)
        Row(children: [
          const SizedBox(width: 84, child: Text('Preamp')),
          Expanded(
            child: Slider(
              value: p.preampDb.clamp(-24.0, 6.0),
              min: -24,
              max: 6,
              divisions: 60,
              onChanged: (v) => eq.setPreamp(manualDb: v),
            ),
          ),
          SizedBox(
              width: 72,
              child: Text('${p.preampDb.toStringAsFixed(1)} dB',
                  textAlign: TextAlign.end)),
        ]),
    ]);
  }
}

class _SaveRow extends StatelessWidget {
  final EqualizerService eq;
  const _SaveRow({required this.eq});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Guardar como preset'),
          onPressed: () async {
            final ctrl = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Nombre del preset'),
                content:
                    TextField(controller: ctrl, autofocus: true, maxLength: 40),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text),
                      child: const Text('Guardar')),
                ],
              ),
            );
            if (name != null) await eq.saveCurrentAs(name);
          },
        ),
      );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Banner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: cs.onSecondaryContainer),
        const SizedBox(width: 12),
        Expanded(
            child:
                Text(text, style: TextStyle(color: cs.onSecondaryContainer))),
      ]),
    );
  }
}
