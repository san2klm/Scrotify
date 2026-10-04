import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Servicio y modelo de configuración del ecualizador de 10 bandas (Fase 10).
///
/// Implementa un ecualizador estándar de 10 bandas convencionales (31 Hz a 16 kHz)
/// con ganancias acotadas entre -12.0 y +12.0 dB, presets estándar, bypass/reset
/// y persistencia en almacenamiento local.
///
/// IMPORTANTE (Auditoría de backend de audio):
/// El backend de audio actual de Scrotify (`just_audio` 0.9.44 + `just_audio_media_kit`
/// con mpv/media_kit) no expone un bus de efectos DSP en tiempo real en Dart sin
/// platform channels nativos específicos. Este servicio actúa como repositorio
/// persistente y reactivo para la configuración del ecualizador, reflejando
/// honestamente su disponibilidad sin introducir procesamiento DSP falso o
/// inestable en Dart.
class EqualizerService extends ChangeNotifier {
  static const double minGain = -12.0;
  static const double maxGain = 12.0;
  static const int bandCount = 10;

  /// Frecuencias centrales convencionales de las 10 bandas.
  static const List<int> bandFrequencies = [
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

  /// Etiquetas legibles de las frecuencias de las 10 bandas.
  static const List<String> bandLabels = [
    '31 Hz',
    '62 Hz',
    '125 Hz',
    '250 Hz',
    '500 Hz',
    '1 kHz',
    '2 kHz',
    '4 kHz',
    '8 kHz',
    '16 kHz',
  ];

  /// Ganancias predefinidas por preset (-12.0 a +12.0 dB).
  static const Map<String, List<double>> presets = {
    'Flat': [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    'Bass Boost': [6.0, 5.0, 4.0, 2.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    'Vocal': [-2.0, -1.0, 1.0, 3.0, 5.0, 4.0, 2.0, 0.0, -1.0, -2.0],
    'Treble Boost': [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.0, 4.0, 5.0, 6.0],
  };

  bool _enabled = false;
  List<double> _gains = List.filled(bandCount, 0.0);
  String _currentPreset = 'Flat';

  EqualizerService() {
    _load();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  bool get enabled => _enabled;
  List<double> get gains => List.unmodifiable(_gains);
  String get currentPreset => _currentPreset;

  /// Indica si el backend de audio actual soporta aplicación activa de DSP en tiempo real.
  /// En el stack actual (just_audio + just_audio_media_kit), es false.
  bool get isBackendSupported => false;

  /// Mensaje descriptivo sobre el estado del backend de audio.
  String get backendStatusMessage =>
      'El motor de audio actual (just_audio + media_kit) no expone un bus DSP '
      'en tiempo real en esta plataforma. Los ajustes se guardan localmente '
      'y estarán listos para aplicarse cuando esté disponible el soporte nativo.';

  // ---------------------------------------------------------------------------
  // Modificadores de estado
  // ---------------------------------------------------------------------------

  /// Activa o desactiva (bypass) el ecualizador.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _save();
    notifyListeners();
  }

  /// Alterna el estado activo / bypass.
  void toggleEnabled() => setEnabled(!_enabled);

  /// Desactiva el ecualizador (modo bypass).
  void bypass() => setEnabled(false);

  /// Establece la ganancia de una banda específica, acotándola entre -12 y +12 dB.
  void setBandGain(int index, double gain) {
    if (index < 0 || index >= bandCount) return;
    final clamped = gain.clamp(minGain, maxGain).toDouble();
    if (_gains[index] == clamped) return;

    _gains[index] = clamped;
    _currentPreset = _detectPreset();
    _save();
    notifyListeners();
  }

  /// Aplica un preset reconocido o ignora si no existe.
  void applyPreset(String presetName) {
    final presetGains = presets[presetName];
    if (presetGains == null) return;

    _gains =
        presetGains.map((g) => g.clamp(minGain, maxGain).toDouble()).toList();
    _currentPreset = presetName;
    _save();
    notifyListeners();
  }

  /// Restablece todas las bandas a 0.0 dB (Flat).
  void reset() {
    _gains = List.filled(bandCount, 0.0);
    _currentPreset = 'Flat';
    _save();
    notifyListeners();
  }

  String _detectPreset() {
    for (final entry in presets.entries) {
      if (listEquals(_gains, entry.value)) {
        return entry.key;
      }
    }
    return 'Personalizado';
  }

  // ---------------------------------------------------------------------------
  // Persistencia
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/equalizer.json');
      if (!await file.exists()) return;

      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _enabled = data['enabled'] as bool? ?? false;
      _currentPreset = data['currentPreset'] as String? ?? 'Flat';

      final rawGains = data['gains'] as List<dynamic>?;
      if (rawGains != null && rawGains.length == bandCount) {
        _gains = rawGains
            .map((e) =>
                ((e as num).toDouble()).clamp(minGain, maxGain).toDouble())
            .toList();
      }
      notifyListeners();
    } catch (_) {
      // Ajustes no críticos: se ignoran fallos de lectura para no impedir uso.
    }
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/equalizer.json');
      await file.writeAsString(jsonEncode({
        'enabled': _enabled,
        'currentPreset': _currentPreset,
        'gains': _gains,
      }));
    } catch (_) {}
  }
}
