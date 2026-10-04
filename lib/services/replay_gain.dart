import 'dart:math' as math;

/// Modo de funcionamiento de ReplayGain.
enum ReplayGainMode {
  off,
  track,
  album;

  String get label => switch (this) {
        ReplayGainMode.off => 'Desactivado',
        ReplayGainMode.track => 'Pista (Track)',
        ReplayGainMode.album => 'Álbum (Album)',
      };

  String get subtitle => switch (this) {
        ReplayGainMode.off => 'Sin normalización de volumen',
        ReplayGainMode.track => 'Normaliza cada canción individualmente',
        ReplayGainMode.album =>
          'Preserva la diferencia relativa de volumen del álbum',
      };

  static ReplayGainMode fromString(String? name) => switch (name) {
        'track' => ReplayGainMode.track,
        'album' => ReplayGainMode.album,
        _ => ReplayGainMode.off,
      };
}

/// Metadatos canónicos de ReplayGain según el estándar OpenSubsonic / Navidrome.
///
/// Soporta valores en dB para ganancias (`trackGain`, `albumGain`, `baseGain`,
/// `fallbackGain`) y factores lineales para picos (`trackPeak`, `albumPeak`).
/// El valor 0.0 es explícitamente válido y no se confunde con ausencia de etiqueta.
class ReplayGainMetadata {
  /// Ganancia de pista en dB (ej. -7.5 dB o 0.0 dB).
  final double? trackGain;

  /// Ganancia de álbum en dB (ej. -6.2 dB o 0.0 dB).
  final double? albumGain;

  /// Pico de amplitud de pista (lineal >= 0.0, ej. 0.988 o 0.0).
  final double? trackPeak;

  /// Pico de amplitud de álbum (lineal >= 0.0, ej. 1.02 o 0.0).
  final double? albumPeak;

  /// Ganancia base opcional en dB (default 0.0 en OpenSubsonic).
  final double? baseGain;

  /// Ganancia de reserva opcional en dB cuando falta la solicitada.
  final double? fallbackGain;

  const ReplayGainMetadata({
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
    this.baseGain,
    this.fallbackGain,
  });

  /// Parsea defensivamente un mapa JSON proveniente de Navidrome/OpenSubsonic.
  /// Acepta formatos numéricos (int, double) o cadenas con sufijo 'dB'/'db'.
  /// No descarta 0 ni 0.0 (son valores válidos). Descarta NaN, infinitos y valores corruptos.
  factory ReplayGainMetadata.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReplayGainMetadata();

    // Soporte para mapas que anidan 'replayGain' directamente
    final target = (json['replayGain'] is Map)
        ? (json['replayGain'] as Map).cast<String, dynamic>()
        : json;

    return ReplayGainMetadata(
      trackGain: _parseGain(target['trackGain']),
      albumGain: _parseGain(target['albumGain']),
      trackPeak: _parsePeak(target['trackPeak']),
      albumPeak: _parsePeak(target['albumPeak']),
      baseGain: _parseGain(target['baseGain']),
      fallbackGain: _parseGain(target['fallbackGain']),
    );
  }

  static double? _parseGain(dynamic val) {
    if (val == null) return null;
    if (val is num) {
      if (val.isNaN || val.isInfinite) return null;
      return val.toDouble();
    }
    if (val is String) {
      final cleaned = val.replaceAll(RegExp(r'[dD][bB]'), '').trim();
      final parsed = double.tryParse(cleaned);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  static double? _parsePeak(dynamic val) {
    final d = _parseGain(val);
    if (d != null && d >= 0.0) return d;
    return null;
  }

  Map<String, dynamic> toJson() => {
        if (trackGain != null) 'trackGain': trackGain,
        if (albumGain != null) 'albumGain': albumGain,
        if (trackPeak != null) 'trackPeak': trackPeak,
        if (albumPeak != null) 'albumPeak': albumPeak,
        if (baseGain != null) 'baseGain': baseGain,
        if (fallbackGain != null) 'fallbackGain': fallbackGain,
      };

  bool get isEmpty =>
      trackGain == null &&
      albumGain == null &&
      trackPeak == null &&
      albumPeak == null &&
      baseGain == null &&
      fallbackGain == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayGainMetadata &&
          runtimeType == other.runtimeType &&
          trackGain == other.trackGain &&
          albumGain == other.albumGain &&
          trackPeak == other.trackPeak &&
          albumPeak == other.albumPeak &&
          baseGain == other.baseGain &&
          fallbackGain == other.fallbackGain;

  @override
  int get hashCode => Object.hash(
        trackGain,
        albumGain,
        trackPeak,
        albumPeak,
        baseGain,
        fallbackGain,
      );

  @override
  String toString() =>
      'ReplayGainMetadata(trackGain: $trackGain, albumGain: $albumGain, '
      'trackPeak: $trackPeak, albumPeak: $albumPeak, '
      'baseGain: $baseGain, fallbackGain: $fallbackGain)';
}

/// Alias para mantener retrocompatibilidad con código existente.
typedef ReplayGainData = ReplayGainMetadata;

/// Resultado del cálculo puro de ReplayGain para una pista específica.
class ReplayGainResult {
  /// Ganancia teórica calculada en dB tras aplicar preamp, baseGain y límites/clipping.
  final double gainDb;

  /// Ganancia en dB efectivamente aplicable al backend de audio.
  ///
  /// IMPORTANTE: Dado que el backend `just_audio` tiene un rango de volumen acotado
  /// a [0.0, 1.0] sin booster nativo multiplataforma, cualquier ganancia positiva (> 0 dB)
  /// no se puede amplificar sin distorsión o platform channel dedicado. Por lo tanto,
  /// en este backend ReplayGain funciona en modo atenuación-única (attenuation-only),
  /// aplicando siempre valores <= 0.0 dB y exponiendo [hasPositiveBoost] de forma veraz.
  final double appliedGainDb;

  /// Factor multiplicador lineal para el volumen del reproductor, acotado estrictamente a [0.0, 1.0].
  /// Formula: 10^(appliedGainDb / 20).
  final double multiplier;

  /// True si se está aplicando alguna modificación (atenuación al volumen).
  final bool isApplied;

  /// True si no existían datos de ReplayGain para el modo solicitado.
  final bool isMissingData;

  /// True si la ganancia tuvo que ser limitada para evitar clipping.
  final bool isClipped;

  /// True si la ganancia calculada superaba 0 dB (requería boost positivo no soportado).
  final bool hasPositiveBoost;

  const ReplayGainResult({
    required this.gainDb,
    required this.appliedGainDb,
    required this.multiplier,
    required this.isApplied,
    required this.isMissingData,
    required this.isClipped,
    required this.hasPositiveBoost,
  });

  /// Compatibilidad con interfaces previas que usaban `playerVolumeScale`.
  double get playerVolumeScale => multiplier;

  /// Compatibilidad: siempre 0.0 dB ya que no se utiliza boost nativo.
  double get androidBoostDb => 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayGainResult &&
          runtimeType == other.runtimeType &&
          gainDb == other.gainDb &&
          appliedGainDb == other.appliedGainDb &&
          multiplier == other.multiplier &&
          isApplied == other.isApplied &&
          isMissingData == other.isMissingData &&
          isClipped == other.isClipped &&
          hasPositiveBoost == other.hasPositiveBoost;

  @override
  int get hashCode => Object.hash(
        gainDb,
        appliedGainDb,
        multiplier,
        isApplied,
        isMissingData,
        isClipped,
        hasPositiveBoost,
      );

  @override
  String toString() =>
      'ReplayGainResult(gainDb: $gainDb, appliedGainDb: $appliedGainDb, '
      'multiplier: $multiplier, applied: $isApplied, missing: $isMissingData, '
      'clipped: $isClipped, positiveBoost: $hasPositiveBoost)';
}

/// Función pura que calcula la ganancia y escalado de volumen a partir de los
/// metadatos de ReplayGain, modo y configuración del usuario.
///
/// Reglas:
/// 1. Modo off o metadata nula -> sin modificación (gain=0 dB, mult=1.0).
/// 2. Selección de ganancia solicitada según modo (track -> trackGain; album -> albumGain).
///    Si falta la solicitada, se utiliza fallbackGain.
/// 3. Se añade baseGain + preamp del usuario (acotado a [minPreampDb, maxPreampDb]).
/// 4. Se rechazan dobles inválidos (NaN, Infinito).
/// 5. Prevención de clipping:
///    - Si peak > 0.0, cap = -20 * log10(peak). Si gain > cap, se limita a cap.
///    - Si peak está ausente (null o <= 0.0), se prohíbe el boost positivo (gain <= 0.0).
/// 6. Backend just_audio (0.0 a 1.0):
///    - Solo se aplica dB no positivo (attenuation-only). Ganancia positiva expone
///      [hasPositiveBoost]=true pero aplica multiplier=1.0 (0 dB).
ReplayGainResult computeReplayGain({
  required ReplayGainMetadata? replayGain,
  required ReplayGainMode mode,
  double preampDb = 0.0,
  bool preventClipping = true,
  double maxPreampDb = 12.0,
  double minPreampDb = -12.0,
  double maxGainDb = 12.0,
  double minGainDb = -30.0,
}) {
  if (mode == ReplayGainMode.off || replayGain == null) {
    return const ReplayGainResult(
      gainDb: 0.0,
      appliedGainDb: 0.0,
      multiplier: 1.0,
      isApplied: false,
      isMissingData: false,
      isClipped: false,
      hasPositiveBoost: false,
    );
  }

  // 1. Selección de ganancia solicitada o fallbackGain
  double? rawGain;
  double? peak;

  switch (mode) {
    case ReplayGainMode.track:
      rawGain = replayGain.trackGain ?? replayGain.fallbackGain;
      peak = replayGain.trackPeak ?? replayGain.albumPeak;
    case ReplayGainMode.album:
      rawGain = replayGain.albumGain ?? replayGain.fallbackGain;
      peak = replayGain.albumPeak ?? replayGain.trackPeak;
    case ReplayGainMode.off:
      break;
  }

  // Rechazo de dobles inválidos en rawGain
  if (rawGain == null || !rawGain.isFinite) {
    return const ReplayGainResult(
      gainDb: 0.0,
      appliedGainDb: 0.0,
      multiplier: 1.0,
      isApplied: false,
      isMissingData: true,
      isClipped: false,
      hasPositiveBoost: false,
    );
  }

  // 2. Preamp y ganancia base (OpenSubsonic)
  final validPreamp = preampDb.isFinite ? preampDb : 0.0;
  final boundedPreamp = validPreamp.clamp(minPreampDb, maxPreampDb);

  final base = (replayGain.baseGain != null && replayGain.baseGain!.isFinite)
      ? replayGain.baseGain!
      : 0.0;

  var calculatedDb = rawGain + base + boundedPreamp;
  if (!calculatedDb.isFinite) {
    calculatedDb = 0.0;
  }
  calculatedDb = calculatedDb.clamp(minGainDb, maxGainDb);

  // 3. Prevención de clipping
  var wasClipped = false;
  if (preventClipping) {
    final validPeak =
        (peak != null && peak.isFinite && peak > 0.0) ? peak : null;
    if (validPeak != null) {
      // cap = -20 * log10(peak)
      final cap = -20.0 * (math.log(validPeak) / math.ln10);
      if (cap.isFinite && calculatedDb > cap) {
        calculatedDb = cap;
        wasClipped = true;
      }
    } else {
      // Pico ausente o inválido: prohibir cualquier boost positivo
      if (calculatedDb > 0.0) {
        calculatedDb = 0.0;
        wasClipped = true;
      }
    }
  }

  // 4. Atenuación estricta para el backend just_audio (volumen 0.0 a 1.0)
  // Cualquier boost positivo (> 0 dB) se expone de forma veraz como hasPositiveBoost=true,
  // pero el backend solo puede aplicar dB <= 0.0 para no sobrepasar el volumen máximo 1.0.
  final hasPositiveBoost = calculatedDb > 0.0;
  final appliedDb = math.min(0.0, calculatedDb);

  // Multiplicador lineal acotado en [0.0, 1.0]
  final multiplier =
      math.pow(10.0, appliedDb / 20.0).toDouble().clamp(0.0, 1.0);

  final isApplied = appliedDb < -0.001 || appliedDb > 0.001;

  return ReplayGainResult(
    gainDb: calculatedDb,
    appliedGainDb: appliedDb,
    multiplier: multiplier,
    isApplied: isApplied,
    isMissingData: false,
    isClipped: wasClipped,
    hasPositiveBoost: hasPositiveBoost,
  );
}
