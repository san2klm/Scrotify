import 'package:http/http.dart' as http;
import 'dart:io';

import 'audio_waveform_service.dart';
import 'waveform_service.dart';

/// Servicio REAL de waveform para producción.
///
/// La forma deriva del audio REAL de cada pista (decodificación → PCM →
/// ventanas → RMS/peak → normalización). El `trackId` solo es clave de caché.
///
/// Implementación: [AudioWaveformService]. Esta clase existe por
/// compatibilidad con el nombre histórico.
class RealWaveformService extends AudioWaveformService {
  RealWaveformService({super.httpClient, super.cacheDirOverride});

  /// Análisis directo de bytes (tests A/B/C y archivos locales).
  Future<WaveformData> getWaveformForBytesCompat(
    String trackId,
    List<int> audioBytes, {
    required Duration duration,
    String? fileNameHint,
  }) =>
      getWaveformForBytes(trackId, audioBytes,
          duration: duration, fileNameHint: fileNameHint);
}

/// @nodoc
/// Alias histórico del constructor con cliente HTTP inyectable (tests).
class RealWaveformServiceWithClient extends RealWaveformService {
  RealWaveformServiceWithClient(http.Client client, {Directory? cacheDir})
      : super(httpClient: client, cacheDirOverride: cacheDir);
}
