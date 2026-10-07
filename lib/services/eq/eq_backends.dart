// Backends de ecualización por plataforma.
//
// ┌──────────────────────┬──────────────────────────┬────────────────────────────┐
// │ Plataforma / motor   │ Backend                   │ Capacidad                   │
// ├──────────────────────┼──────────────────────────┼────────────────────────────┤
// │ Linux/Win/macOS mpv  │ MpvEqBackend (lavfi)      │ Paramétrico real, 16 filt.  │
// │ Android just_audio   │ AndroidEqBackend          │ Bandas fijas del sistema    │
// │                      │ (android.media.Equalizer) │ (5 típicamente) → ajuste    │
// │ iOS just_audio       │ UnsupportedEqBackend      │ AVPlayer no admite DSP      │
// │ iOS/Android media_kit│ MpvEqBackend              │ Paramétrico real            │
// └──────────────────────┴──────────────────────────┴────────────────────────────┘
//
// La UI consulta `capabilities` para avisar al usuario cuando su curva se
// aproxima (Android) en vez de aplicarse exacta.

import 'package:just_audio/just_audio.dart';

import '../../models/eq_models.dart';
import 'eq_math.dart';

class EqCapabilities {
  final bool exact; // la curva se aplica tal cual (paramétrico real)
  final int maxBands;
  final String engineLabel;
  final String? note;
  const EqCapabilities({
    required this.exact,
    required this.maxBands,
    required this.engineLabel,
    this.note,
  });
}

abstract class EqBackend {
  EqCapabilities get capabilities;

  /// Aplica la cadena. [preampDb] ya viene calculado (auto o manual).
  Future<void> apply(List<EqBand> bands, double preampDb);

  /// Quita todo procesamiento (necesario para el modo Bit-Perfect).
  Future<void> bypass();

  Future<void> dispose() async {}
}

// ═══════════════════════════════ mpv / media_kit ═══════════════════════════════

/// Función que fija una propiedad de mpv. Se inyecta desde PlayerController,
/// que la aplica sobre AMBOS reproductores (A y B) para que el crossfade no
/// mezcle una pista ecualizada con una sin ecualizar.
///
/// Ejemplo con media_kit:
///   (p) async { await (player.platform as NativePlayer).setProperty(k, v); }
typedef MpvPropertySetter = Future<void> Function(String name, String value);

class MpvEqBackend extends EqBackend {
  final List<MpvPropertySetter> players;

  /// Limitador final de seguridad. Con preamp automático casi nunca actúa,
  /// pero protege si el usuario fija un preamp manual demasiado alto.
  final bool safetyLimiter;

  /// Si otro subsistema (p. ej. el karaoke) necesita filtros propios, se
  /// concatenan aquí para no pisarlos.
  String extraFilters;

  MpvEqBackend(this.players,
      {this.safetyLimiter = true, this.extraFilters = ''});

  @override
  EqCapabilities get capabilities => const EqCapabilities(
        exact: true,
        maxBands: 16,
        engineLabel: 'mpv / FFmpeg (paramétrico de 64 bits)',
      );

  @override
  Future<void> apply(List<EqBand> bands, double preampDb) =>
      _setAll(buildAfChain(bands, preampDb,
          safetyLimiter: safetyLimiter, extraFilters: extraFilters));

  @override
  Future<void> bypass() =>
      _setAll(extraFilters.isEmpty ? '' : 'lavfi=[$extraFilters]');

  Future<void> _setAll(String af) async {
    for (final set in players) {
      await set('af', af);
    }
  }

  static String _n(double v, [int d = 2]) => v.toStringAsFixed(d);

  /// Traduce un filtro a la sintaxis de FFmpeg. Se usan `bass`/`treble` (y no
  /// `lowshelf`/`highshelf`) porque existen en cualquier FFmpeg ≥ 3.x que
  /// traigan las builds de libmpv de Linux, Windows y macOS.
  static String ffmpegFilter(EqBand b) {
    final f = _n(b.frequency, 1);
    final q = _n(b.q, 3);
    final g = _n(b.gainDb);
    return switch (b.type) {
      EqFilterType.peaking => 'equalizer=f=$f:t=q:w=$q:g=$g',
      EqFilterType.lowShelf => 'bass=f=$f:t=q:w=$q:g=$g',
      EqFilterType.highShelf => 'treble=f=$f:t=q:w=$q:g=$g',
      EqFilterType.lowPass => 'lowpass=f=$f:t=q:w=$q',
      EqFilterType.highPass => 'highpass=f=$f:t=q:w=$q',
      EqFilterType.notch => 'bandreject=f=$f:t=q:w=$q',
    };
  }

  /// Construye el valor de la propiedad `af` de mpv.
  ///
  /// Orden: [conversión a float] → preamp → filtros → limitador.
  /// Procesar en float (`aformat=sample_fmts=fltp|dblp`) evita que la cadena
  /// trabaje en enteros de 16 bits y añada ruido de cuantización.
  static String buildAfChain(
    List<EqBand> bands,
    double preampDb, {
    bool safetyLimiter = true,
    String extraFilters = '',
  }) {
    final active = bands.where((b) => b.enabled && !b.isNeutral).toList();
    if (active.isEmpty && preampDb.abs() < 0.05 && extraFilters.isEmpty) {
      return '';
    }

    final chain = <String>[
      'aformat=sample_fmts=fltp|dblp',
      if (preampDb.abs() >= 0.05) 'volume=${_n(preampDb)}dB',
      ...active.map(ffmpegFilter),
      if (extraFilters.isNotEmpty) extraFilters,
      if (safetyLimiter && active.isNotEmpty)
        'alimiter=limit=0.977:attack=5:release=50:level=0',
    ];
    return 'lavfi=[${chain.join(',')}]';
  }
}

// ═══════════════════════════════ Android ═══════════════════════════════

/// Usa `android.media.audiofx.Equalizer` vía just_audio. Ese ecualizador tiene
/// un número FIJO de bandas que decide el fabricante (casi siempre 5, a veces
/// 10). La curva del usuario se ajusta por mínimos cuadrados iterativos a
/// esas bandas con [EqMath.fitToGraphic].
///
/// IMPORTANTE: cada AudioPlayer necesita su propio AndroidEqualizer creado en
/// su AudioPipeline (A y B del crossfade):
///
///   final eqA = AndroidEqualizer();
///   final playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [eqA]));
class AndroidEqBackend extends EqBackend {
  final List<AndroidEqualizer> equalizers;
  EqCapabilities _caps = const EqCapabilities(
    exact: false,
    maxBands: 5,
    engineLabel: 'Ecualizador del sistema Android',
  );

  AndroidEqBackend(this.equalizers);

  @override
  EqCapabilities get capabilities => _caps;

  @override
  Future<void> apply(List<EqBand> bands, double preampDb) async {
    for (final eq in equalizers) {
      final params = await eq.parameters;
      final centers = [for (final b in params.bands) b.centerFrequency];
      _caps = EqCapabilities(
        exact: false,
        maxBands: centers.length,
        engineLabel:
            'Ecualizador del sistema Android (${centers.length} bandas)',
        note:
            'Tu dispositivo ofrece ${centers.length} bandas fijas: la curva se aproxima. '
            'Para un ecualizador paramétrico exacto activá el motor mpv en Ajustes > Audio.',
      );
      // Q menor que la ISO: las bandas de Android son anchas (~2 octavas).
      final fitted = EqMath.fitToGraphic(
        bands,
        centers,
        q: centers.length <= 5 ? 0.6 : kOneOctaveQ,
        minDb: params.minDecibels,
        maxDb: params.maxDecibels,
      );
      for (var i = 0; i < params.bands.length; i++) {
        // El preamp negativo se reparte en todas las bandas (Android no tiene
        // ganancia previa); así se evita el clipping igual que en desktop.
        final g = (fitted[i].gainDb + preampDb)
            .clamp(params.minDecibels, params.maxDecibels);
        await params.bands[i].setGain(g);
      }
      await eq.setEnabled(true);
    }
  }

  @override
  Future<void> bypass() async {
    for (final eq in equalizers) {
      await eq.setEnabled(false);
    }
  }
}

// ═══════════════════════════════ Sin soporte ═══════════════════════════════

/// just_audio en iOS usa AVPlayer, que no permite insertar DSP propio. En vez
/// de fingir que funciona, la UI muestra el motivo y la solución.
class UnsupportedEqBackend extends EqBackend {
  final String reason;
  UnsupportedEqBackend(this.reason);

  @override
  EqCapabilities get capabilities => EqCapabilities(
        exact: false,
        maxBands: 0,
        engineLabel: 'No disponible',
        note: reason,
      );

  @override
  Future<void> apply(List<EqBand> bands, double preampDb) async {}

  @override
  Future<void> bypass() async {}
}
