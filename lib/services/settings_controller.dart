import '../utils/app_data_dir.dart';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/crotolink_models.dart';
import 'hifi/audio_output_devices.dart' show isValidDirectDevice;
import 'hifi/hifi_profiles.dart' show AudioFidelityMode;
import 'replay_gain.dart';

/// Representa un atajo configurable (botón del mouse o tecla del teclado)
/// para acciones de reproducción como Reproducir/Pausar o Siguiente tema.
class ShortcutBinding {
  /// Código persistido, ej:
  /// - `mouse:xbutton1` (Botón lateral atrás / Mouse 4)
  /// - `mouse:xbutton2` (Botón lateral adelante / Mouse 5)
  /// - `mouse:middle`   (Clic de rueda / Botón central)
  /// - `key:<vk>:<keyId>:<label>` (Tecla del teclado)
  /// - `none`           (Desactivado)
  final String raw;

  const ShortcutBinding(this.raw);

  static const mouseXButton1 = ShortcutBinding('mouse:xbutton1');
  static const mouseXButton2 = ShortcutBinding('mouse:xbutton2');
  static const mouseMiddle = ShortcutBinding('mouse:middle');
  static const mouseRight = ShortcutBinding('mouse:right');
  static const none = ShortcutBinding('none');

  bool get isNone => raw == 'none' || raw.isEmpty;
  bool get isMouse => raw.startsWith('mouse:');
  bool get isKey => raw.startsWith('key:');

  /// Identificador para el canal nativo (`mouse_xb1`, `mouse_xb2`, `mouse_middle`, `mouse_right`, `key`, `none`).
  String get nativeType {
    if (raw == 'mouse:xbutton1') return 'mouse_xb1';
    if (raw == 'mouse:xbutton2') return 'mouse_xb2';
    if (raw == 'mouse:middle') return 'mouse_middle';
    if (raw == 'mouse:right') return 'mouse_right';
    if (isKey) return 'key';
    return 'none';
  }

  /// Código Virtual-Key de Windows (`VK_*`) si es una tecla, o `0` si no aplica.
  int get vkCode {
    if (!isKey) return 0;
    final parts = raw.split(':');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  /// `LogicalKeyboardKey.keyId` de Flutter si es una tecla, o `0` si no aplica.
  int get logicalKeyId {
    if (!isKey) return 0;
    final parts = raw.split(':');
    if (parts.length < 3) return 0;
    return int.tryParse(parts[2]) ?? 0;
  }

  /// Etiqueta legible para mostrar en la interfaz.
  String get label {
    switch (raw) {
      case 'mouse:xbutton1':
        return 'Botón lateral atrás (Mouse 4)';
      case 'mouse:xbutton2':
        return 'Botón lateral adelante (Mouse 5)';
      case 'mouse:middle':
        return 'Clic de rueda (Botón central)';
      case 'mouse:right':
        return 'Clic derecho (Botón secundario)';
      case 'none':
      case '':
        return 'Desactivado';
      default:
        if (isKey) {
          final parts = raw.split(':');
          if (parts.length >= 4) {
            return 'Tecla: ${parts.sublist(3).join(':')}';
          }
          return 'Tecla personalizada';
        }
        return raw;
    }
  }

  /// Subtítulo descriptivo para la lista de opciones.
  String get subtitle {
    switch (raw) {
      case 'mouse:xbutton1':
        return 'Botón lateral trasero del mouse (XButton 1)';
      case 'mouse:xbutton2':
        return 'Botón lateral delantero del mouse (XButton 2)';
      case 'mouse:middle':
        return 'Pulsar la rueda del mouse (Botón central)';
      case 'mouse:right':
        return 'Botón secundario del mouse';
      default:
        if (isKey) {
          return 'Atajo de teclado detectado y guardado';
        }
        return 'Botón personalizado guardado';
    }
  }

  /// Etiqueta corta para badges/botones.
  String get shortLabel {
    switch (raw) {
      case 'mouse:xbutton1':
        return 'Mouse 4 (Atrás)';
      case 'mouse:xbutton2':
        return 'Mouse 5 (Adelante)';
      case 'mouse:middle':
        return 'Clic de rueda';
      case 'mouse:right':
        return 'Clic derecho';
      case 'none':
      case '':
        return 'Desactivado';
      default:
        if (isKey) {
          final parts = raw.split(':');
          if (parts.length >= 4) {
            return 'Tecla ${parts.sublist(3).join(':')}';
          }
        }
        return label;
    }
  }

  /// Crea un `ShortcutBinding` a partir de un `LogicalKeyboardKey` de Flutter.
  static ShortcutBinding? fromLogicalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return null;
    }
    final info = _mapLogicalKeyToWindowsVk(key);
    return ShortcutBinding('key:${info.vk}:${key.keyId}:${info.label}');
  }

  static ({int vk, String label}) _mapLogicalKeyToWindowsVk(
      LogicalKeyboardKey key) {
    final id = key.keyId;
    if (id >= 0x61 && id <= 0x7A) {
      final char = String.fromCharCode(id - 32);
      return (vk: id - 32, label: char);
    }
    if (id >= 0x30 && id <= 0x39) {
      final char = String.fromCharCode(id);
      return (vk: id, label: char);
    }
    final fKeys = <LogicalKeyboardKey, (int, String)>{
      LogicalKeyboardKey.f1: (0x70, 'F1'),
      LogicalKeyboardKey.f2: (0x71, 'F2'),
      LogicalKeyboardKey.f3: (0x72, 'F3'),
      LogicalKeyboardKey.f4: (0x73, 'F4'),
      LogicalKeyboardKey.f5: (0x74, 'F5'),
      LogicalKeyboardKey.f6: (0x75, 'F6'),
      LogicalKeyboardKey.f7: (0x76, 'F7'),
      LogicalKeyboardKey.f8: (0x77, 'F8'),
      LogicalKeyboardKey.f9: (0x78, 'F9'),
      LogicalKeyboardKey.f10: (0x79, 'F10'),
      LogicalKeyboardKey.f11: (0x7A, 'F11'),
      LogicalKeyboardKey.f12: (0x7B, 'F12'),
      LogicalKeyboardKey.space: (0x20, 'Espacio'),
      LogicalKeyboardKey.enter: (0x0D, 'Enter'),
      LogicalKeyboardKey.numpadEnter: (0x0D, 'Intro Num'),
      LogicalKeyboardKey.tab: (0x09, 'Tab'),
      LogicalKeyboardKey.backspace: (0x08, 'Borrar'),
      LogicalKeyboardKey.capsLock: (0x14, 'Bloq Mayús'),
      LogicalKeyboardKey.shiftLeft: (0x10, 'Shift'),
      LogicalKeyboardKey.shiftRight: (0x10, 'Shift'),
      LogicalKeyboardKey.shift: (0x10, 'Shift'),
      LogicalKeyboardKey.controlLeft: (0x11, 'Ctrl'),
      LogicalKeyboardKey.controlRight: (0x11, 'Ctrl'),
      LogicalKeyboardKey.control: (0x11, 'Ctrl'),
      LogicalKeyboardKey.altLeft: (0x12, 'Alt'),
      LogicalKeyboardKey.altRight: (0x12, 'Alt'),
      LogicalKeyboardKey.alt: (0x12, 'Alt'),
      LogicalKeyboardKey.insert: (0x2D, 'Insert'),
      LogicalKeyboardKey.delete: (0x2E, 'Supr'),
      LogicalKeyboardKey.home: (0x24, 'Inicio'),
      LogicalKeyboardKey.end: (0x23, 'Fin'),
      LogicalKeyboardKey.pageUp: (0x21, 'Re Pág'),
      LogicalKeyboardKey.pageDown: (0x22, 'Av Pág'),
      LogicalKeyboardKey.arrowUp: (0x26, 'Flecha Arriba'),
      LogicalKeyboardKey.arrowDown: (0x28, 'Flecha Abajo'),
      LogicalKeyboardKey.arrowLeft: (0x25, 'Flecha Izquierda'),
      LogicalKeyboardKey.arrowRight: (0x27, 'Flecha Derecha'),
      LogicalKeyboardKey.numpad0: (0x60, 'Num 0'),
      LogicalKeyboardKey.numpad1: (0x61, 'Num 1'),
      LogicalKeyboardKey.numpad2: (0x62, 'Num 2'),
      LogicalKeyboardKey.numpad3: (0x63, 'Num 3'),
      LogicalKeyboardKey.numpad4: (0x64, 'Num 4'),
      LogicalKeyboardKey.numpad5: (0x65, 'Num 5'),
      LogicalKeyboardKey.numpad6: (0x66, 'Num 6'),
      LogicalKeyboardKey.numpad7: (0x67, 'Num 7'),
      LogicalKeyboardKey.numpad8: (0x68, 'Num 8'),
      LogicalKeyboardKey.numpad9: (0x69, 'Num 9'),
      LogicalKeyboardKey.numpadAdd: (0x6B, 'Num +'),
      LogicalKeyboardKey.numpadSubtract: (0x6D, 'Num -'),
      LogicalKeyboardKey.numpadMultiply: (0x6A, 'Num *'),
      LogicalKeyboardKey.numpadDivide: (0x6F, 'Num /'),
      LogicalKeyboardKey.numpadDecimal: (0x6E, 'Num .'),
      LogicalKeyboardKey.mediaPlayPause: (0xB3, 'Media Play/Pausa'),
      LogicalKeyboardKey.mediaTrackNext: (0xB0, 'Media Siguiente'),
      LogicalKeyboardKey.mediaTrackPrevious: (0xB1, 'Media Anterior'),
      LogicalKeyboardKey.mediaStop: (0xB2, 'Media Stop'),
      LogicalKeyboardKey.pause: (0x13, 'Pausa'),
      LogicalKeyboardKey.scrollLock: (0x91, 'Bloq Despl'),
      LogicalKeyboardKey.minus: (0xBD, '-'),
      LogicalKeyboardKey.equal: (0xBB, '='),
      LogicalKeyboardKey.comma: (0xBC, ','),
      LogicalKeyboardKey.period: (0xBE, '.'),
      LogicalKeyboardKey.slash: (0xBF, '/'),
      LogicalKeyboardKey.semicolon: (0xBA, ';'),
      LogicalKeyboardKey.quoteSingle: (0xDE, "'"),
      LogicalKeyboardKey.bracketLeft: (0xDB, '['),
      LogicalKeyboardKey.bracketRight: (0xDD, ']'),
      LogicalKeyboardKey.backslash: (0xDC, '\\'),
      LogicalKeyboardKey.backquote: (0xC0, '`'),
    };
    final match = fKeys[key];
    if (match != null) {
      return (vk: match.$1, label: match.$2);
    }
    final rawLabel = key.keyLabel.trim().isNotEmpty
        ? key.keyLabel.trim().toUpperCase()
        : (key.debugName ?? 'Tecla');
    return (vk: 0, label: rawLabel);
  }
}

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
  bool _mouseControlsEnabled = true;
  bool _mouseGlobalEnabled = true;
  bool _mouseMiddleClickEnabled = true;
  bool _closeToTray = true;
  static const List<String> defaultShortcutOptions = [
    'mouse:xbutton1',
    'mouse:xbutton2',
    'mouse:middle',
  ];

  String _playPauseShortcut = ShortcutBinding.mouseXButton1.raw;
  String _nextTrackShortcut = ShortcutBinding.mouseXButton2.raw;
  List<String> _shortcutSavedOptions = List<String>.of(defaultShortcutOptions);
  bool _isCapturingShortcut = false;
  void Function(String rawBinding)? _onShortcutCapturedCallback;

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
  // Atajos de reproducción (Escritorio / Windows)
  // ---------------------------------------------------------------------------

  bool get mouseControlsEnabled => _mouseControlsEnabled;
  bool get mouseGlobalEnabled => _mouseGlobalEnabled;
  bool get mouseMiddleClickEnabled => _mouseMiddleClickEnabled;
  bool get closeToTray => _closeToTray;
  String get playPauseShortcut => _playPauseShortcut;
  String get nextTrackShortcut => _nextTrackShortcut;
  ShortcutBinding get playPauseBinding => ShortcutBinding(_playPauseShortcut);
  ShortcutBinding get nextTrackBinding => ShortcutBinding(_nextTrackShortcut);
  bool get isCapturingShortcut => _isCapturingShortcut;

  /// Lista de opciones guardadas (máximo 3 opciones).
  List<ShortcutBinding> get shortcutSavedOptions => _shortcutSavedOptions
      .take(3)
      .map(ShortcutBinding.new)
      .toList(growable: false);

  void _registerShortcutInOptionsList(String rawBinding) {
    if (rawBinding.isEmpty || rawBinding == 'none') return;
    if (_shortcutSavedOptions.take(3).contains(rawBinding)) return;
    final nextList = <String>[rawBinding];
    for (final existing in _shortcutSavedOptions) {
      if (existing != rawBinding && existing.isNotEmpty && existing != 'none') {
        nextList.add(existing);
      }
    }
    for (final def in defaultShortcutOptions) {
      if (nextList.length >= 3) break;
      if (!nextList.contains(def)) {
        nextList.add(def);
      }
    }
    _shortcutSavedOptions = nextList.take(3).toList();
  }

  void setMouseControlsEnabled(bool value) {
    if (value == _mouseControlsEnabled) return;
    _mouseControlsEnabled = value;
    _save();
    notifyListeners();
  }

  void setMouseGlobalEnabled(bool value) {
    if (value == _mouseGlobalEnabled) return;
    _mouseGlobalEnabled = value;
    _save();
    notifyListeners();
  }

  void setMouseMiddleClickEnabled(bool value) {
    if (value == _mouseMiddleClickEnabled) return;
    _mouseMiddleClickEnabled = value;
    _save();
    notifyListeners();
  }

  void setCloseToTray(bool value) {
    if (value == _closeToTray) return;
    _closeToTray = value;
    _save();
    notifyListeners();
  }

  void setPlayPauseShortcut(String rawBinding) {
    if (rawBinding.isEmpty) return;
    final prev = _playPauseShortcut;
    _playPauseShortcut = rawBinding;
    if (rawBinding != 'none' && _nextTrackShortcut == rawBinding && prev != rawBinding) {
      _nextTrackShortcut = prev;
    }
    _registerShortcutInOptionsList(rawBinding);
    _save();
    notifyListeners();
  }

  void setNextTrackShortcut(String rawBinding) {
    if (rawBinding.isEmpty) return;
    final prev = _nextTrackShortcut;
    _nextTrackShortcut = rawBinding;
    if (rawBinding != 'none' && _playPauseShortcut == rawBinding && prev != rawBinding) {
      _playPauseShortcut = prev;
    }
    _registerShortcutInOptionsList(rawBinding);
    _save();
    notifyListeners();
  }

  void resetShortcutsToDefault() {
    _playPauseShortcut = ShortcutBinding.mouseXButton1.raw;
    _nextTrackShortcut = ShortcutBinding.mouseXButton2.raw;
    _shortcutSavedOptions = List<String>.of(defaultShortcutOptions);
    _save();
    notifyListeners();
  }

  void setCapturingShortcut(bool capturing) {
    if (_isCapturingShortcut == capturing) return;
    _isCapturingShortcut = capturing;
    if (!capturing) {
      _onShortcutCapturedCallback = null;
    }
    notifyListeners();
  }

  void startShortcutCapture(void Function(String rawBinding) onCaptured) {
    _onShortcutCapturedCallback = onCaptured;
    if (!_isCapturingShortcut) {
      _isCapturingShortcut = true;
    }
    notifyListeners();
  }

  void stopShortcutCapture() {
    _onShortcutCapturedCallback = null;
    if (_isCapturingShortcut) {
      _isCapturingShortcut = false;
      notifyListeners();
    }
  }

  void handleCapturedShortcut(String rawBinding) {
    final cb = _onShortcutCapturedCallback;
    stopShortcutCapture();
    if (cb != null && rawBinding.isNotEmpty && rawBinding != 'cancel') {
      cb(rawBinding);
    }
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
      _mouseControlsEnabled = data['mouseControlsEnabled'] as bool? ?? true;
      _mouseGlobalEnabled = data['mouseGlobalEnabled'] as bool? ?? true;
      _mouseMiddleClickEnabled =
          data['mouseMiddleClickEnabled'] as bool? ?? true;
      _closeToTray = data['closeToTray'] as bool? ?? true;
      final rawPlayPause = data['playPauseShortcut'] as String?;
      if (rawPlayPause != null && rawPlayPause.isNotEmpty) {
        _playPauseShortcut = rawPlayPause;
      }
      final rawNextTrack = data['nextTrackShortcut'] as String?;
      if (rawNextTrack != null && rawNextTrack.isNotEmpty) {
        _nextTrackShortcut = rawNextTrack;
      }
      final rawOptions = data['shortcutSavedOptions'];
      if (rawOptions is List) {
        final loaded = rawOptions
            .whereType<String>()
            .where((s) => s.isNotEmpty && s != 'none')
            .toSet()
            .toList();
        for (final def in defaultShortcutOptions) {
          if (loaded.length >= 3) break;
          if (!loaded.contains(def)) loaded.add(def);
        }
        _shortcutSavedOptions = loaded.take(3).toList();
      } else {
        _registerShortcutInOptionsList(_nextTrackShortcut);
        _registerShortcutInOptionsList(_playPauseShortcut);
      }
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
        'mouseControlsEnabled': _mouseControlsEnabled,
        'mouseGlobalEnabled': _mouseGlobalEnabled,
        'mouseMiddleClickEnabled': _mouseMiddleClickEnabled,
        'closeToTray': _closeToTray,
        'playPauseShortcut': _playPauseShortcut,
        'nextTrackShortcut': _nextTrackShortcut,
        'shortcutSavedOptions': _shortcutSavedOptions.take(3).toList(),
      }));
    } catch (err) {
      debugPrint('settings_controller:304 ignorado: $err');
    }
  }
}
