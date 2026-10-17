import '../utils/app_data_dir.dart';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/crotolink_models.dart';
import 'hifi/audio_output_devices.dart' show isValidDirectDevice;
import 'hifi/hifi_profiles.dart' show AudioFidelityMode;
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
  bool _thirdPartyArtistImages = false;
  bool _syncQueueToServer = false;
  bool _discordPresence = false;
  String _discordClientId = '';
  bool _isSmartMixEnabled = true;
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  double _replayGainPreamp = 0.0;
  bool _replayGainPreventClipping = true;
  String _crotoLinkServerUrl = kDefaultRemoteCrotoLinkEndpoint;
  AudioFidelityMode _fidelityMode = AudioFidelityMode.standard;
  bool _losslessOnMobileData = false;
  String? _connectDeviceName;
  String? _audioOutputDevice;

  // Red actual detectada. Si no se puede saber (sin NetworkManager, etc.) se
  // asume "casa" para no degradar la calidad sin motivo.
  ConnectivityResult _network = ConnectivityResult.wifi;
  // Para detectar transiciones WiFi ↔ móvil y notificar solo cuando cambia.
  bool? _wasMobile;

  /// Termina cuando los ajustes guardados ya se leyeron del disco.
  late final Future<void> ready;

  SettingsController() {
    ready = _load();
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

  /// Modo de fidelidad: Estándar (el comportamiento de siempre), Alta
  /// fidelidad o Bit-perfect.
  AudioFidelityMode get fidelityMode => _fidelityMode;

  /// En Alta fidelidad/Bit-perfect, pedir el archivo original también con datos móviles.
  bool get losslessOnMobileData => _losslessOnMobileData;
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

  /// Permite buscar fotos de artista en TheAudioDB y Deezer (reciben el nombre
  /// del artista). Desactivado por defecto.
  bool get thirdPartyArtistImages => _thirdPartyArtistImages;

  /// Guarda la cola en el servidor (`savePlayQueue`) para continuar en otro
  /// dispositivo. Desactivado por defecto: sobrescribe la cola guardada.
  bool get syncQueueToServer => _syncQueueToServer;

  /// Discord Rich Presence (escritorio). Necesita el Application ID propio.
  bool get discordPresence => _discordPresence;
  String get discordClientId => _discordClientId;

  void setDiscordPresence(bool enabled) {
    if (_discordPresence == enabled) return;
    _discordPresence = enabled;
    _save();
    notifyListeners();
  }

  void setDiscordClientId(String id) {
    final clean = id.trim();
    if (_discordClientId == clean) return;
    _discordClientId = clean;
    _save();
    notifyListeners();
  }

  void setSyncQueueToServer(bool enabled) {
    if (_syncQueueToServer == enabled) return;
    _syncQueueToServer = enabled;
    _save();
    notifyListeners();
  }

  void setThirdPartyArtistImages(bool enabled) {
    if (_thirdPartyArtistImages == enabled) return;
    _thirdPartyArtistImages = enabled;
    _save();
    notifyListeners();
  }

  /// Estado del modo Smart Mix.
  bool get isSmartMixEnabled => _isSmartMixEnabled;

  /// Modo actual de normalización ReplayGain (off, track, album).
  ReplayGainMode get replayGainMode => _replayGainMode;

  /// Nivel de preamplificador (preamp) en decibelios [-12.0, +12.0].
  double get replayGainPreamp => _replayGainPreamp;

  /// Si está activa la prevención de clipping mediante el pico de amplitud.
  bool get replayGainPreventClipping => _replayGainPreventClipping;

  /// URL (normalizada) del servidor CrotoLink usado para salas remotas y el radar.
  String get crotoLinkServerUrl => _crotoLinkServerUrl;

  /// Valida y guarda la URL del servidor CrotoLink. Devuelve el resultado de la
  /// validación; solo persiste si es válida.
  CrotoLinkServerEndpoint setCrotoLinkServerUrl(String input) {
    final parsed = CrotoLinkServerEndpoint.parse(input);
    if (parsed.isValid && parsed.url != _crotoLinkServerUrl) {
      _crotoLinkServerUrl = parsed.url!;
      _save();
      notifyListeners();
    }
    return parsed;
  }

  /// Nombre elegido por el usuario para este dispositivo en Connect, o `null`
  /// para usar el del sistema.
  String? get connectDeviceName => _connectDeviceName;

  static const maxDeviceNameLength = 40;

  /// Limpia un nombre de dispositivo: sin caracteres de control, espacios
  /// colapsados y como mucho [maxDeviceNameLength]. `null` si queda vacío.
  static String? normalizeDeviceName(String input) {
    final clean = input
        .replaceAll(RegExp(r'[\u0000-\u0008\u000b-\u001f\u007f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    return clean.length <= maxDeviceNameLength
        ? clean
        : clean.substring(0, maxDeviceNameLength).trimRight();
  }

  /// Salida ALSA `hw:` elegida para Bit-perfect en Linux, o `null` para usar
  /// la del sistema.
  String? get audioOutputDevice => _audioOutputDevice;

  void setAudioOutputDevice(String? device) {
    final value = isValidDirectDevice(device) ? device : null;
    if (value == _audioOutputDevice) return;
    _audioOutputDevice = value;
    _save();
    notifyListeners();
  }

  void setConnectDeviceName(String? name) {
    final value = name == null ? null : normalizeDeviceName(name);
    if (value == _connectDeviceName) return;
    _connectDeviceName = value;
    _save();
    notifyListeners();
  }

  /// Quita el servidor CrotoLink (vuelve al valor por defecto: ninguno).
  void resetCrotoLinkServerUrl() {
    if (_crotoLinkServerUrl == kDefaultRemoteCrotoLinkEndpoint) return;
    _crotoLinkServerUrl = kDefaultRemoteCrotoLinkEndpoint;
    _save();
    notifyListeners();
  }

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

  void setFidelityMode(AudioFidelityMode mode) {
    if (mode == _fidelityMode) return;
    _fidelityMode = mode;
    _save();
    notifyListeners();
  }

  void setLosslessOnMobileData(bool value) {
    if (value == _losslessOnMobileData) return;
    _losslessOnMobileData = value;
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

  /// Vuelve a leer `settings.json` (p. ej. tras recibirlo de otro dispositivo).
  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final dir = await getAppDataDirectory();
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
      _thirdPartyArtistImages =
          data['thirdPartyArtistImages'] as bool? ?? false;
      _syncQueueToServer = data['syncQueueToServer'] as bool? ?? false;
      _discordPresence = data['discordPresence'] as bool? ?? false;
      _discordClientId = data['discordClientId'] as String? ?? '';
      _isSmartMixEnabled = data['smartMixEnabled'] as bool? ?? true;
      _replayGainMode =
          ReplayGainMode.fromString(data['replayGainMode'] as String?);
      final rawPreamp = (data['replayGainPreamp'] as num?)?.toDouble();
      _replayGainPreamp =
          rawPreamp == null ? 0.0 : rawPreamp.clamp(-12.0, 12.0);
      _replayGainPreventClipping =
          data['replayGainPreventClipping'] as bool? ?? true;
      _fidelityMode = AudioFidelityMode.values.firstWhere(
        (m) => m.name == data['fidelityMode'],
        orElse: () => AudioFidelityMode.standard,
      );
      _losslessOnMobileData = data['losslessOnMobileData'] as bool? ?? false;
      final crotoLinkUrl = CrotoLinkServerEndpoint.parse(
          data['crotoLinkServerUrl'] as String? ?? '');
      _crotoLinkServerUrl = crotoLinkUrl.url ?? kDefaultRemoteCrotoLinkEndpoint;
      final savedDevice = data['audioOutputDevice'];
      _audioOutputDevice =
          savedDevice is String && isValidDirectDevice(savedDevice)
              ? savedDevice
              : null;
      final savedName = data['connectDeviceName'];
      _connectDeviceName =
          savedName is String ? normalizeDeviceName(savedName) : null;
      notifyListeners();
    } catch (_) {
      // Silently ignore — los ajustes no son críticos.
    }
  }

  Future<void> _save() async {
    try {
      final dir = await getAppDataDirectory();
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
        'thirdPartyArtistImages': _thirdPartyArtistImages,
        'syncQueueToServer': _syncQueueToServer,
        'discordPresence': _discordPresence,
        'discordClientId': _discordClientId,
        'smartMixEnabled': _isSmartMixEnabled,
        'replayGainMode': _replayGainMode.name,
        'replayGainPreamp': _replayGainPreamp,
        'replayGainPreventClipping': _replayGainPreventClipping,
        'crotoLinkServerUrl': _crotoLinkServerUrl,
        'fidelityMode': _fidelityMode.name,
        'losslessOnMobileData': _losslessOnMobileData,
        'connectDeviceName': _connectDeviceName,
        'audioOutputDevice': _audioOutputDevice,
      }));
    } catch (err) {
      debugPrint('settings_controller:304 ignorado: $err');
    }
  }
}
