import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/jam_models.dart';
import 'replay_gain.dart';

/// Calidad de streaming. `lossless` transmite el archivo original (sin
/// transcode, FLAC si el servidor lo tiene); el resto pide a Navidrome que
/// transcodifique a MP3 con el bitrate indicado (`kbps`).
enum AudioQuality {
  lossless,
  high320,
  high192,
  medium128,
  low96;

  /// Bitrate en kbps para el parámetro `maxBitRate` de Subsonic; `null` sin
  /// pérdida (sin transcode).
  int? get kbps => switch (this) {
        AudioQuality.lossless => null,
        AudioQuality.high320 => 320,
        AudioQuality.high192 => 192,
        AudioQuality.medium128 => 128,
        AudioQuality.low96 => 96,
      };

  String get label => switch (this) {
        AudioQuality.lossless => 'Sin pérdida',
        AudioQuality.high320 => 'Muy alta',
        AudioQuality.high192 => 'Alta',
        AudioQuality.medium128 => 'Media',
        AudioQuality.low96 => 'Baja',
      };

  String get subtitle => switch (this) {
        AudioQuality.lossless => 'Archivo original (FLAC)',
        AudioQuality.high320 => 'MP3 · 320 kbps',
        AudioQuality.high192 => 'MP3 · 192 kbps',
        AudioQuality.medium128 => 'MP3 · 128 kbps',
        AudioQuality.low96 => 'MP3 · 96 kbps',
      };

  static AudioQuality fromName(String? name) => AudioQuality.values.firstWhere(
        (q) => q.name == name,
        orElse: () => AudioQuality.lossless,
      );
}

/// Configuración global de la app (calidad de audio, portadas, volumen…).
/// Persiste en `settings.json` en el directorio de documentos, siguiendo el
/// mismo patrón que el historial y las playlists fijadas.
///
/// También escucha a `connectivity_plus` para saber si la red actual es datos
/// móviles o una conexión de "casa" (WiFi/ethernet) y así elegir la calidad.
class SettingsController extends ChangeNotifier {
  AudioQuality _wifiQuality = AudioQuality.lossless;
  AudioQuality _mobileQuality = AudioQuality.low96;
  bool _autoSwitch = true;
  int _coverArtSize = 600;
  double _initialVolume = 0.7;
  bool _gapless = false;
  Duration _crossfade = Duration.zero;
  bool _silenceRemovalEnabled = false;
  bool _isSmartMixEnabled = true;
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  double _replayGainPreamp = 0.0;
  bool _replayGainPreventClipping = true;
  String _jamServerUrl = kDefaultRemoteJamEndpoint;

  // Red actual detectada. Si no se puede saber (sin NetworkManager, etc.) se
  // asume "casa" para no degradar la calidad sin motivo.
  ConnectivityResult _network = ConnectivityResult.wifi;
  // Para detectar transiciones WiFi ↔ móvil y notificar solo cuando cambia.
  bool? _wasMobile;

  SettingsController() {
    _load();
    _listenConnectivity();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  AudioQuality get wifiQuality => _wifiQuality;
  AudioQuality get mobileQuality => _mobileQuality;
  bool get autoSwitch => _autoSwitch;
  int get coverArtSize => _coverArtSize;
  double get initialVolume => _initialVolume;
  bool get gapless => _gapless;
  Duration get crossfade => _crossfade;
  bool get isMobileData => _network == ConnectivityResult.mobile;
  String get networkLabel =>
      isMobileData ? 'Datos móviles' : 'WiFi / conexión fija';

  /// Calidad efectiva según el contexto de red.
  AudioQuality get effectiveQuality => _autoSwitch
      ? (isMobileData ? _mobileQuality : _wifiQuality)
      : _wifiQuality;

  /// Estado de la eliminación de silencios.
  bool get silenceRemovalEnabled => _silenceRemovalEnabled;

  /// Estado del modo Smart Mix.
  bool get isSmartMixEnabled => _isSmartMixEnabled;

  /// Modo actual de normalización ReplayGain (off, track, album).
  ReplayGainMode get replayGainMode => _replayGainMode;

  /// Nivel de preamplificador (preamp) en decibelios [-12.0, +12.0].
  double get replayGainPreamp => _replayGainPreamp;

  /// Si está activa la prevención de clipping mediante el pico de amplitud.
  bool get replayGainPreventClipping => _replayGainPreventClipping;

  /// URL (normalizada) del servidor Jam usado para salas remotas y el radar.
  String get jamServerUrl => _jamServerUrl;

  /// Valida y guarda la URL del servidor Jam. Devuelve el resultado de la
  /// validación; solo persiste si es válida.
  JamServerEndpoint setJamServerUrl(String input) {
    final parsed = JamServerEndpoint.parse(input);
    if (parsed.isValid && parsed.url != _jamServerUrl) {
      _jamServerUrl = parsed.url!;
      _save();
      notifyListeners();
    }
    return parsed;
  }

  void resetJamServerUrl() => setJamServerUrl(kDefaultRemoteJamEndpoint);

  /// Activa o desactiva la eliminación de silencios.
  void setSilenceRemovalEnabled(bool enabled) {
    if (_silenceRemovalEnabled == enabled) return;
    _silenceRemovalEnabled = enabled;
    _save();
    notifyListeners();
  }

  void setSmartMixEnabled(bool enabled) {
    if (_isSmartMixEnabled == enabled) return;
    _isSmartMixEnabled = enabled;
    _save();
    notifyListeners();
  }

  void setReplayGainMode(ReplayGainMode mode) {
    if (mode == _replayGainMode) return;
    _replayGainMode = mode;
    _save();
    notifyListeners();
  }

  void setReplayGainPreamp(double preampDb) {
    final clamped = preampDb.clamp(-12.0, 12.0);
    if (clamped == _replayGainPreamp) return;
    _replayGainPreamp = clamped;
    _save();
    notifyListeners();
  }

  void setReplayGainPreventClipping(bool prevent) {
    if (prevent == _replayGainPreventClipping) return;
    _replayGainPreventClipping = prevent;
    _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Setters (persisten y notifican)
  // ---------------------------------------------------------------------------

  void setWifiQuality(AudioQuality q) {
    if (q == _wifiQuality) return;
    _wifiQuality = q;
    _save();
    notifyListeners();
  }

  void setMobileQuality(AudioQuality q) {
    if (q == _mobileQuality) return;
    _mobileQuality = q;
    _save();
    notifyListeners();
  }

  void setAutoSwitch(bool value) {
    if (value == _autoSwitch) return;
    _autoSwitch = value;
    _save();
    notifyListeners();
  }

  void setCoverArtSize(int size) {
    if (size == _coverArtSize) return;
    _coverArtSize = size;
    _save();
    notifyListeners();
  }

  void setInitialVolume(double volume) {
    final v = volume.clamp(0.0, 1.0).toDouble();
    if (v == _initialVolume) return;
    _initialVolume = v;
    _save();
    notifyListeners();
  }

  void setGapless(bool value) {
    if (value == _gapless) return;
    _gapless = value;
    _save();
    notifyListeners();
  }

  /// Crossfade entre canciones. `Duration.zero` = desactivado. Al activarlo en
  /// Ajustes se usa el valor predeterminado de 5 s (ver `settings_screen.dart`).
  void setCrossfade(Duration d) {
    final clamped = Duration(milliseconds: d.inMilliseconds.clamp(0, 10000));
    if (clamped == _crossfade) return;
    _crossfade = clamped;
    _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Red
  // ---------------------------------------------------------------------------

  void _listenConnectivity() {
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen(
      (results) {
        _updateNetwork(
            results.isEmpty ? ConnectivityResult.none : results.first);
      },
      onError:
          (_) {}, // Sin red disponible para consultar; mantener último valor.
    );
    // Valor inicial (fire-and-forget; si falla queda "casa").
    connectivity
        .checkConnectivity()
        .catchError(
          (_) => const <ConnectivityResult>[],
        )
        .then(
          (results) => _updateNetwork(
              results.isEmpty ? ConnectivityResult.wifi : results.first),
        );
  }

  void _updateNetwork(ConnectivityResult result) {
    // `none`/`bluetooth`/`other` → mantener la última clasificación conocida.
    final known = result != ConnectivityResult.none &&
        result != ConnectivityResult.bluetooth &&
        result != ConnectivityResult.other;
    if (known) _network = result;
    final isMobile = _network == ConnectivityResult.mobile;
    if (_wasMobile == null || _wasMobile != isMobile) {
      _wasMobile = isMobile;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Persistencia
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/settings.json');
      if (!await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _wifiQuality = AudioQuality.fromName(data['wifiQuality'] as String?);
      _mobileQuality = AudioQuality.fromName(data['mobileQuality'] as String?);
      _autoSwitch = data['autoSwitch'] as bool? ?? true;
      _coverArtSize = (data['coverArtSize'] as num?)?.toInt() ?? 600;
      final rawVol = (data['initialVolume'] as num?)?.toDouble();
      _initialVolume = rawVol == null ? 0.7 : rawVol.clamp(0.0, 1.0).toDouble();
      _gapless = data['gapless'] as bool? ?? false;
      final rawCf = (data['crossfade'] as num?)?.toInt() ?? 0;
      _crossfade = Duration(milliseconds: rawCf.clamp(0, 10000));
      _silenceRemovalEnabled = data['silenceRemovalEnabled'] as bool? ?? false;
      _isSmartMixEnabled = data['smartMixEnabled'] as bool? ?? true;
      _replayGainMode =
          ReplayGainMode.fromString(data['replayGainMode'] as String?);
      final rawPreamp = (data['replayGainPreamp'] as num?)?.toDouble();
      _replayGainPreamp =
          rawPreamp == null ? 0.0 : rawPreamp.clamp(-12.0, 12.0);
      _replayGainPreventClipping =
          data['replayGainPreventClipping'] as bool? ?? true;
      final jamUrl =
          JamServerEndpoint.parse(data['jamServerUrl'] as String? ?? '');
      _jamServerUrl = jamUrl.url ?? kDefaultRemoteJamEndpoint;
      notifyListeners();
    } catch (_) {
      // Silently ignore — los ajustes no son críticos.
    }
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/settings.json');
      await file.writeAsString(jsonEncode({
        'wifiQuality': _wifiQuality.name,
        'mobileQuality': _mobileQuality.name,
        'autoSwitch': _autoSwitch,
        'coverArtSize': _coverArtSize,
        'initialVolume': _initialVolume,
        'gapless': _gapless,
        'crossfade': _crossfade.inMilliseconds,
        'silenceRemovalEnabled': _silenceRemovalEnabled,
        'smartMixEnabled': _isSmartMixEnabled,
        'replayGainMode': _replayGainMode.name,
        'replayGainPreamp': _replayGainPreamp,
        'replayGainPreventClipping': _replayGainPreventClipping,
        'jamServerUrl': _jamServerUrl,
      }));
    } catch (err) {
      debugPrint('settings_controller:304 ignorado: $err');
    }
  }
}
