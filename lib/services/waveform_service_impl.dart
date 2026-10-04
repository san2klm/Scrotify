import 'audio_waveform_service.dart';

/// Implementación por defecto del [WaveformService] REAL.
///
/// Históricamente este archivo contenía un generador sintético por hash del
/// trackId. Ahora delega en [AudioWaveformService] (análisis de audio real).
/// Se conserva el nombre por compatibilidad.
class WaveformServiceImpl extends AudioWaveformService {
  WaveformServiceImpl({super.httpClient, super.cacheDirOverride});
}
