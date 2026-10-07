// Scrotify — Modelos del Ecualizador de tres niveles.
//
// Un único modelo de datos (lista de filtros biquad + preamp) sirve a los tres
// modos de la UI. Lo que cambia entre modos es CUÁNTO del modelo se expone:
//
//   * Simple        → 3 controles (Graves / Medios / Agudos) + presets por "vibra".
//   * Intermedio    → Ecualizador gráfico ISO de 10 bandas (Q fija de 1 octava).
//   * Profesional   → Paramétrico completo: tipo, frecuencia, ganancia y Q por
//                     filtro, hasta 16 filtros, importación AutoEQ/EqualizerAPO.
//
// Los backends de cada plataforma (mpv, Android, etc.) sólo ven `EqProfile`.

import 'dart:convert';

/// Nivel de complejidad de la interfaz del ecualizador.
enum EqMode { simple, intermediate, professional }

/// Tipos de filtro soportados (fórmulas del RBJ Audio EQ Cookbook).
enum EqFilterType { peaking, lowShelf, highShelf, lowPass, highPass, notch }

extension EqFilterTypeX on EqFilterType {
  /// Si el tipo admite ganancia (los pasa-altos/bajos y notch no la usan).
  bool get usesGain =>
      this == EqFilterType.peaking ||
      this == EqFilterType.lowShelf ||
      this == EqFilterType.highShelf;

  String get label => switch (this) {
        EqFilterType.peaking => 'Campana',
        EqFilterType.lowShelf => 'Estante graves',
        EqFilterType.highShelf => 'Estante agudos',
        EqFilterType.lowPass => 'Pasa bajos',
        EqFilterType.highPass => 'Pasa altos',
        EqFilterType.notch => 'Notch',
      };
}

/// Límites de cada modo. El modo simple es deliberadamente conservador para que
/// un usuario sin experiencia no pueda "romper" el sonido.
class EqLimits {
  final double minGainDb;
  final double maxGainDb;
  final int maxBands;
  const EqLimits(this.minGainDb, this.maxGainDb, this.maxBands);

  static const simple = EqLimits(-6, 6, 3);
  static const intermediate = EqLimits(-12, 12, 10);
  static const professional = EqLimits(-15, 15, 16);

  static EqLimits forMode(EqMode m) => switch (m) {
        EqMode.simple => simple,
        EqMode.intermediate => intermediate,
        EqMode.professional => professional,
      };
}

/// Frecuencias centrales ISO 266 por octava para el modo intermedio.
const List<double> kIsoGraphicFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Q de un filtro de 1 octava de ancho (≈ √2). Es el estándar de los
/// ecualizadores gráficos de 10 bandas.
const double kOneOctaveQ = 1.41;

/// Q "musical" y suave para estantes y el modo simple (Butterworth).
const double kGentleQ = 0.707;

/// Frecuencias fijas de los tres controles del modo simple.
const double kSimpleBassHz = 105;
const double kSimpleMidHz = 1000;
const double kSimpleTrebleHz = 8000;

class EqBand {
  final EqFilterType type;
  final double frequency; // Hz
  final double gainDb;
  final double q;
  final bool enabled;

  const EqBand({
    required this.type,
    required this.frequency,
    this.gainDb = 0,
    this.q = kOneOctaveQ,
    this.enabled = true,
  });

  const EqBand.peaking(double f, double g, {double q = kOneOctaveQ})
      : this(type: EqFilterType.peaking, frequency: f, gainDb: g, q: q);

  EqBand copyWith({
    EqFilterType? type,
    double? frequency,
    double? gainDb,
    double? q,
    bool? enabled,
  }) =>
      EqBand(
        type: type ?? this.type,
        frequency: frequency ?? this.frequency,
        gainDb: gainDb ?? this.gainDb,
        q: q ?? this.q,
        enabled: enabled ?? this.enabled,
      );

  /// Un filtro que no modifica la señal y puede omitirse del pipeline.
  bool get isNeutral => enabled && type.usesGain && gainDb.abs() < 0.05;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'f': frequency,
        'g': gainDb,
        'q': q,
        'on': enabled,
      };

  factory EqBand.fromJson(Map<String, dynamic> j) => EqBand(
        type: EqFilterType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => EqFilterType.peaking,
        ),
        frequency: (j['f'] as num).toDouble(),
        gainDb: (j['g'] as num? ?? 0).toDouble(),
        q: (j['q'] as num? ?? kOneOctaveQ).toDouble(),
        enabled: j['on'] as bool? ?? true,
      );

  /// Saneado defensivo: evita valores que hagan inestable un biquad o que
  /// lleguen de un archivo importado malformado.
  EqBand sanitized(EqLimits limits) => copyWith(
        frequency: frequency.clamp(10.0, 22000.0),
        gainDb: gainDb.clamp(limits.minGainDb, limits.maxGainDb),
        q: q.clamp(0.1, 18.0),
      );

  @override
  bool operator ==(Object other) =>
      other is EqBand &&
      other.type == type &&
      other.frequency == frequency &&
      other.gainDb == gainDb &&
      other.q == q &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(type, frequency, gainDb, q, enabled);
}

/// Configuración completa de ecualización (lo que se guarda y se aplica).
class EqProfile {
  final String id;
  final String name;
  final EqMode mode;
  final List<EqBand> bands;

  /// Preamp manual en dB (sólo se usa si [autoPreamp] es false).
  final double preampDb;

  /// Si es true, el servicio calcula el preamp necesario para que la curva
  /// nunca supere 0 dB y no haya recorte digital (clipping).
  final bool autoPreamp;

  /// Compensación de sonoridad a bajo volumen (curva Fletcher–Munson
  /// simplificada). Sólo se expone en el modo simple ("Modo noche").
  final bool loudness;

  final bool isBuiltIn;

  const EqProfile({
    required this.id,
    required this.name,
    required this.mode,
    required this.bands,
    this.preampDb = 0,
    this.autoPreamp = true,
    this.loudness = false,
    this.isBuiltIn = false,
  });

  EqProfile copyWith({
    String? id,
    String? name,
    EqMode? mode,
    List<EqBand>? bands,
    double? preampDb,
    bool? autoPreamp,
    bool? loudness,
    bool? isBuiltIn,
  }) =>
      EqProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        bands: bands ?? this.bands,
        preampDb: preampDb ?? this.preampDb,
        autoPreamp: autoPreamp ?? this.autoPreamp,
        loudness: loudness ?? this.loudness,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      );

  /// Filtros que realmente hay que aplicar (activos y no neutros), incluyendo
  /// los de compensación de sonoridad si están activados.
  List<EqBand> get effectiveBands => [
        ...bands.where((b) => b.enabled && !b.isNeutral),
        if (loudness) ...kLoudnessBands,
      ];

  bool get isFlat => effectiveBands.isEmpty && preampDb.abs() < 0.05;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode.name,
        'bands': bands.map((b) => b.toJson()).toList(),
        'preamp': preampDb,
        'autoPreamp': autoPreamp,
        'loudness': loudness,
      };

  factory EqProfile.fromJson(Map<String, dynamic> j) {
    final mode = EqMode.values.firstWhere(
      (m) => m.name == j['mode'],
      orElse: () => EqMode.intermediate,
    );
    final limits = EqLimits.forMode(mode);
    final rawBands = (j['bands'] as List? ?? const [])
        .whereType<Map>()
        .map(
            (m) => EqBand.fromJson(m.cast<String, dynamic>()).sanitized(limits))
        .take(limits.maxBands)
        .toList();
    return EqProfile(
      id: j['id'] as String,
      name: (j['name'] as String? ?? 'Sin nombre').trim(),
      mode: mode,
      bands: rawBands,
      preampDb: ((j['preamp'] as num?) ?? 0).toDouble().clamp(-24.0, 6.0),
      autoPreamp: j['autoPreamp'] as bool? ?? true,
      loudness: j['loudness'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());
}

/// Curva de sonoridad para escuchar a volumen bajo (modo noche). Valores
/// moderados para no desbalancear la mezcla.
const List<EqBand> kLoudnessBands = [
  EqBand(type: EqFilterType.lowShelf, frequency: 90, gainDb: 4, q: kGentleQ),
  EqBand(
      type: EqFilterType.highShelf, frequency: 11000, gainDb: 2, q: kGentleQ),
];
