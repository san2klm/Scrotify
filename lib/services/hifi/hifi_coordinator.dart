// Une el modo de fidelidad elegido en Ajustes con el reproductor.
//
//   Ajustes (modo, "sin pérdida con datos móviles") + red + plataforma
//        └─► HifiPlanner.plan() ─► HifiPlan
//              ├─► PlayerController.applyHifi   (stream, volumen, crossfade, ReplayGain)
//              ├─► EqualizerService.setHifiAllowsEq (Bit-perfect pone el EQ en pausa)
//              └─► propiedades de mpv (escritorio)
//
// En modo Estándar no se toca mpv ni el reproductor más allá de lo que ya
// hacía la app: el comportamiento de siempre se conserva.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../settings_controller.dart';
import 'hifi_profiles.dart';

typedef HifiMpvSetter = Future<void> Function(String name, String value);

class HifiCoordinator extends ChangeNotifier {
  HifiCoordinator({
    required SettingsController settings,
    required Future<void> Function(HifiPlan plan) applyToPlayer,
    required Future<void> Function(bool allowed) setEqAllowed,
    HifiMpvSetter? setMpvProperty,
    HifiPlatform? platform,
    bool? mpvEngine,
  })  : _settings = settings,
        _applyToPlayer = applyToPlayer,
        _setEqAllowed = setEqAllowed,
        _setMpv = setMpvProperty,
        platform = platform ?? currentPlatform(),
        mpvEngine = mpvEngine ?? isDesktop;

  final SettingsController _settings;
  final Future<void> Function(HifiPlan plan) _applyToPlayer;
  final Future<void> Function(bool allowed) _setEqAllowed;
  final HifiMpvSetter? _setMpv;
  final HifiPlatform platform;

  /// `true` donde el audio lo reproduce mpv (escritorio).
  final bool mpvEngine;

  HifiPlan? _plan;
  Object? _lastKey;
  bool _mpvTouched = false;
  bool _started = false;

  /// Plan vigente (para mostrar sus notas en Ajustes).
  HifiPlan? get plan => _plan;

  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  static HifiPlatform currentPlatform() {
    if (Platform.isAndroid) return HifiPlatform.android;
    if (Platform.isIOS) return HifiPlatform.ios;
    if (Platform.isWindows) return HifiPlatform.windows;
    if (Platform.isMacOS) return HifiPlatform.macos;
    return HifiPlatform.linux;
  }

  /// Valores por defecto de mpv para todas las propiedades que un plan puede
  /// cambiar; sirven para volver al modo Estándar sin reiniciar. No incluye
  /// `af` (lo gestiona el ecualizador).
  static const Map<String, String> mpvDefaults = {
    'audio-swresample-o': '',
    'audio-pitch-correction': 'yes',
    'audio-buffer': '0.2',
    'audio-normalize-downmix': 'no',
    'audio-samplerate': '0',
    'audio-exclusive': 'no',
    'coreaudio-change-physical-format': 'no',
  };

  void start() {
    if (_started) return;
    _started = true;
    _settings.addListener(_onSettingsChanged);
    // start() se llama al crear el proveedor, en plena construcción de widgets:
    // aplicar el plan notifica al reproductor y no debe hacerlo durante el build.
    scheduleMicrotask(refresh);
  }

  @override
  void dispose() {
    if (_started) _settings.removeListener(_onSettingsChanged);
    _started = false;
    super.dispose();
  }

  void _onSettingsChanged() => unawaited(refresh());

  HifiPlan computePlan() => HifiPlanner.plan(
        mode: _settings.fidelityMode,
        platform: platform,
        network: _settings.isMobileData
            ? NetworkKind.mobile
            : NetworkKind.wifiOrEthernet,
        mpvEngine: mpvEngine,
        allowLosslessOnMobileData: _settings.losslessOnMobileData,
      );

  /// Recalcula y aplica el plan si algo relevante cambió.
  Future<void> refresh({bool force = false}) async {
    final key = (
      _settings.fidelityMode,
      _settings.losslessOnMobileData,
      _settings.isMobileData,
    );
    if (!force && key == _lastKey) return;
    _lastKey = key;

    final plan = computePlan();
    _plan = plan;
    try {
      await _applyToPlayer(plan);
      await _setEqAllowed(plan.allowEq);
      await reapplyMpv();
    } catch (e) {
      debugPrint('HifiCoordinator: no se pudo aplicar el plan ($e)');
    }
    notifyListeners();
  }

  /// Fija las propiedades de mpv del plan (también al crearse un reproductor nuevo).
  Future<void> reapplyMpv() async {
    final set = _setMpv;
    final plan = _plan;
    if (set == null || plan == null || !mpvEngine) return;

    if (plan.mode == AudioFidelityMode.standard) {
      // Estándar no toca mpv, salvo para deshacer un modo anterior.
      if (!_mpvTouched) return;
      for (final e in mpvDefaults.entries) {
        await set(e.key, e.value);
      }
      _mpvTouched = false;
      return;
    }
    _mpvTouched = true;
    final props = {
      ...mpvDefaults,
      for (final e in plan.mpvProperties.entries)
        if (!plan.mpvInitOnly.contains(e.key)) e.key: e.value,
    };
    for (final e in props.entries) {
      await set(e.key, e.value);
    }
  }
}
