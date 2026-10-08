// Presets de fábrica para cada nivel del ecualizador.
//
// Criterios de diseño:
//  * Ningún preset de fábrica realza más de +6 dB: con preamp automático eso
//    significa como mucho ~6 dB de pérdida de volumen, aceptable en móviles.
//  * Los presets del modo simple usan nombres por "situación" (lo que el
//    usuario quiere), no por género o frecuencia.

import '../../models/eq_models.dart';

EqProfile _simple(
        String id, String name, double bass, double mid, double treble,
        {bool loudness = false}) =>
    EqProfile(
      id: 'builtin.simple.$id',
      name: name,
      mode: EqMode.simple,
      isBuiltIn: true,
      loudness: loudness,
      bands: simpleBands(bass: bass, mid: mid, treble: treble),
    );

/// Los tres filtros del modo simple: estante de graves, campana ancha de
/// medios y estante de agudos. Q suaves para que suene natural en cualquier
/// posición del control.
List<EqBand> simpleBands(
        {double bass = 0, double mid = 0, double treble = 0}) =>
    [
      EqBand(
          type: EqFilterType.lowShelf,
          frequency: kSimpleBassHz,
          gainDb: bass,
          q: kGentleQ),
      EqBand(
          type: EqFilterType.peaking,
          frequency: kSimpleMidHz,
          gainDb: mid,
          q: 0.5),
      EqBand(
          type: EqFilterType.highShelf,
          frequency: kSimpleTrebleHz,
          gainDb: treble,
          q: kGentleQ),
    ];

EqProfile _graphic(String id, String name, List<double> gains) {
  assert(gains.length == kIsoGraphicFrequencies.length);
  return EqProfile(
    id: 'builtin.graphic.$id',
    name: name,
    mode: EqMode.intermediate,
    isBuiltIn: true,
    bands: [
      for (var i = 0; i < gains.length; i++)
        EqBand.peaking(kIsoGraphicFrequencies[i], gains[i]),
    ],
  );
}

class EqPresets {
  // ───────────── Modo simple ─────────────
  static final List<EqProfile> simple = [
    _simple('natural', 'Natural', 0, 0, 0),
    _simple('bass', 'Más graves', 5, 0, 0),
    _simple('voices', 'Voces claras', -1.5, 3, 1),
    _simple('bright', 'Más brillo', 0, 0, 4),
    _simple('warm', 'Cálido', 2.5, 0, -2.5),
    _simple('night', 'Modo noche', 0, 0, 0, loudness: true),
    // Parlantes chicos (celular, notebook): no pueden reproducir sub-graves;
    // realzarlos sólo distorsiona. Se recortan y se realzan los medios.
    _simple('small', 'Parlante chico', -4, 2.5, 1.5),
    _simple('car', 'Auto', 3, -1.5, 2),
  ];

  // ───────────── Modo intermedio (10 bandas ISO) ─────────────
  //                31   62  125  250  500   1k   2k   4k   8k  16k
  static final List<EqProfile> graphic = [
    _graphic('flat', 'Plano', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    _graphic('bass', 'Bass Boost', [5, 5, 3, 1, 0, 0, 0, 0, 0, 0]),
    _graphic('vocal', 'Vocal', [-2, -1, 0, 1, 2, 3, 3, 2, 0, -1]),
    _graphic('treble', 'Treble Boost', [0, 0, 0, 0, 0, 0, 1, 3, 4, 4]),
    _graphic('rock', 'Rock', [4, 3, 1, -1, -1, 0, 1, 3, 4, 4]),
    _graphic('electronic', 'Electrónica', [5, 4, 1, 0, -1, 1, 0, 1, 3, 4]),
    _graphic('acoustic', 'Acústico', [2, 2, 1, 1, 1, 1, 2, 2, 2, 1]),
    _graphic('classical', 'Clásica', [3, 2, 1, 0, 0, 0, -1, -1, 1, 2]),
    _graphic(
        'podcast', 'Podcast / Hablado', [-6, -4, -1, 1, 2, 3, 3, 1, -1, -3]),
    _graphic('harman', 'Auriculares (Harman aprox.)',
        [4, 4, 3, 1, 0, 0, 1, 2, 0, -1]),
  ];

  static List<EqProfile> forMode(EqMode m) => switch (m) {
        EqMode.simple => simple,
        EqMode.intermediate => graphic,
        EqMode.professional => const [],
      };

  static EqProfile defaultFor(EqMode m) => switch (m) {
        EqMode.simple => simple.first,
        EqMode.intermediate => graphic.first,
        EqMode.professional => const EqProfile(
            id: 'builtin.pro.empty',
            name: 'Paramétrico vacío',
            mode: EqMode.professional,
            bands: [],
            isBuiltIn: true,
          ),
      };
}
