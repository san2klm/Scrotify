/// Modelo de datos de waveform para una pista.
///
/// Las amplitudes SIEMPRE provienen del análisis del audio real (PCM):
/// nunca de `Random`, `hashCode`, `trackId`, `sin`/`cos` ni curvas inventadas.
/// El `trackId` solo se usa como parte de la clave de caché.
class WaveformData {
  final String trackId;
  final Duration duration;
  final List<double> amplitudes; // Valores normalizados entre 0.0 y 1.0

  const WaveformData({
    required this.trackId,
    required this.duration,
    required this.amplitudes,
  });

  /// Crea una copia con las amplitudes downsampled a [targetLength].
  ///
  /// Usa el máximo (peak) de cada ventana para preservar visualmente los
  /// picos en lugar de aplanarlos con un promedio.
  WaveformData downsample(int targetLength) {
    if (amplitudes.length <= targetLength || targetLength <= 0) {
      return this;
    }
    final downsampled = <double>[];
    final step = amplitudes.length / targetLength;
    for (var i = 0; i < targetLength; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(0, amplitudes.length);
      if (end <= start) {
        downsampled.add(amplitudes[start.clamp(0, amplitudes.length - 1)]);
        continue;
      }
      final range = amplitudes.sublist(start, end);
      var peak = range[0];
      for (var j = 1; j < range.length; j++) {
        if (range[j] > peak) peak = range[j];
      }
      downsampled.add(peak);
    }
    return WaveformData(
      trackId: trackId,
      duration: duration,
      amplitudes: downsampled,
    );
  }
}

/// Causa de un [WaveformDecodeException], para explicarla sin filtrar detalles.
enum WaveformFailure {
  unsupported,
  tooLarge,
  network,
  timeout,
  cancelled,
  unknown,
}

/// Error lanzado cuando la waveform no puede extraerse del audio real.
///
/// Nunca se debe "resolver" este error generando datos sintéticos en
/// producción: la UI debe mostrar un estado neutro/cargando en su lugar.
class WaveformDecodeException implements Exception {
  final String message;
  final WaveformFailure kind;
  const WaveformDecodeException(this.message,
      {this.kind = WaveformFailure.unknown});

  /// Motivo seguro para mostrar al usuario: nunca incluye URLs ni credenciales.
  String get userMessage => switch (kind) {
        WaveformFailure.unsupported =>
          'este dispositivo no puede decodificar este formato',
        WaveformFailure.tooLarge => 'el archivo es demasiado grande',
        WaveformFailure.network => 'no se pudo descargar el audio',
        WaveformFailure.timeout => 'se agotó el tiempo de espera',
        WaveformFailure.cancelled => 'se canceló el análisis del audio',
        WaveformFailure.unknown => 'no se pudo analizar el audio',
      };

  @override
  String toString() => 'WaveformDecodeException: $message';
}

/// Servicio abstracto para obtener datos de waveform de una pista.
///
/// Contrato REAL:
/// - [trackId] solo es clave de caché, NUNCA fuente de la forma.
/// - [streamUrl] es el audio real a analizar (stream Navidrome o file://).
/// - [duration] es la duración esperada, usada para dimensionar los bins.
abstract class WaveformService {
  /// Obtiene los datos de waveform para la pista dada.
  /// Si los datos están en caché y son válidos, los devuelve inmediatamente.
  /// Si no, descarga/decodifica el audio REAL, lo analiza y lo guarda en caché.
  Future<WaveformData> getWaveform(
      String trackId, String streamUrl, Duration duration);
}

/// Extensión opcional de [WaveformService] para cancelar trabajo en curso
/// cuando deja de ser necesario (cambio de pista, vaciado de cola o `dispose`).
///
/// Separada de [WaveformService] para no romper dobles de prueba existentes.
abstract class CancelableWaveformService implements WaveformService {
  /// Cancela el análisis en curso para [trackId] (o todos si [trackId] es null).
  Future<void> cancelWaveform([String? trackId]);
}
