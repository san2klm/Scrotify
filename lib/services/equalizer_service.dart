// EqualizerService — reemplaza al servicio de 10 bandas actual.
//
// Responsabilidades:
//  * Guardar el modo elegido (simple / intermedio / profesional) y el perfil
//    activo de cada modo, más los perfiles propios del usuario.
//  * Convertir la curva al cambiar de modo sin que el sonido "salte".
//  * Calcular el preamp anti-clipping y entregar la cadena al backend.
//  * Respetar el plan Hi-Fi (en Bit-perfect el EQ se pone en pausa).
//
// Persistencia: `equalizer_v2.json` en el directorio de soporte de la app.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../models/eq_models.dart';
import '../utils/app_data_dir.dart';
import 'eq/eq_backends.dart';
import 'eq/eq_import_export.dart';
import 'eq/eq_math.dart';
import 'eq/eq_presets.dart';

class EqualizerService extends ChangeNotifier {
  EqualizerService({EqBackend? backend, Directory? storageDir})
      : _backend = backend,
        _storageDirOverride = storageDir;

  EqBackend? _backend;
  final Directory? _storageDirOverride;

  bool _enabled = false;
  bool _blockedByHifi = false;
  EqMode _mode = EqMode.simple;
  final Map<EqMode, EqProfile> _active = {
    for (final m in EqMode.values) m: EqPresets.defaultFor(m),
  };
  final List<EqProfile> _userProfiles = [];

  Timer? _applyDebounce;
  Timer? _saveDebounce;

  // ───────────── Getters para la UI ─────────────
  bool get enabled => _enabled;
  bool get blockedByHifi => _blockedByHifi;
  EqMode get mode => _mode;
  EqProfile get active => _active[_mode]!;
  EqLimits get limits => EqLimits.forMode(_mode);
  EqCapabilities? get capabilities => _backend?.capabilities;
  double get effectivePreampDb => EqMath.effectivePreampDb(active);

  List<EqProfile> get presetsForMode => [
        ...EqPresets.forMode(_mode),
        ..._userProfiles.where((p) => p.mode == _mode),
      ];

  // ───────────── Ciclo de vida ─────────────

  Future<void> attachBackend(EqBackend backend) async {
    await _backend?.dispose();
    _backend = backend;
    await _applyNow();
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _enabled = j['enabled'] as bool? ?? false;
        _mode = EqMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => EqMode.simple,
        );
        final actives =
            (j['active'] as Map?)?.cast<String, dynamic>() ?? const {};
        for (final m in EqMode.values) {
          final raw = actives[m.name];
          if (raw is Map) {
            _active[m] = EqProfile.fromJson(raw.cast<String, dynamic>())
                .copyWith(mode: m);
          }
        }
        _userProfiles
          ..clear()
          ..addAll((j['user'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => EqProfile.fromJson(e.cast<String, dynamic>())));
      }
    } catch (e) {
      // Archivo corrupto: se arranca plano en vez de crashear.
      debugPrint('EqualizerService: no se pudo leer la configuración ($e)');
    }
    await _applyNow();
    notifyListeners();
  }

  // ───────────── Acciones comunes ─────────────

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _commit(immediate: true);
  }

  /// Cambia de modo convirtiendo la curva actual para que el sonido no cambie.
  Future<void> setMode(EqMode next) async {
    if (next == _mode) return;
    final current = active;
    final converted = _convert(current, next);
    _mode = next;
    if (converted != null) _active[next] = converted;
    await _commit(immediate: true);
  }

  /// Devuelve null cuando la conversión no tiene sentido (p. ej. desde
  /// "Natural" plano): en ese caso se conserva lo último que había en el modo.
  EqProfile? _convert(EqProfile from, EqMode to) {
    if (from.isFlat) return null;
    final curve = from.effectiveBands;
    switch (to) {
      case EqMode.professional:
        // Sin pérdida: el paramétrico puede representar cualquier curva.
        return EqProfile(
          id: 'converted.pro',
          name: '${from.name} (editable)',
          mode: to,
          bands: from.loudness ? curve : from.bands,
          autoPreamp: true,
        );
      case EqMode.intermediate:
        return EqProfile(
          id: 'converted.graphic',
          name: '${from.name} (10 bandas)',
          mode: to,
          bands: EqMath.fitToGraphic(curve, kIsoGraphicFrequencies),
        );
      case EqMode.simple:
        // Lectura aproximada de graves/medios/agudos de la curva.
        double at(double f) => EqMath.responseDb(curve, f)
            .clamp(EqLimits.simple.minGainDb, EqLimits.simple.maxGainDb);
        return EqProfile(
          id: 'converted.simple',
          name: 'Personalizado',
          mode: to,
          loudness: false,
          bands: simpleBands(
              bass: _r(at(60)), mid: _r(at(1000)), treble: _r(at(12000))),
        );
    }
  }

  static double _r(double v) => (v * 2).roundToDouble() / 2;

  Future<void> selectProfile(EqProfile p) async {
    _active[_mode] = p.copyWith(mode: _mode);
    if (!_enabled) _enabled = true;
    await _commit(immediate: true);
  }

  // ───────────── Edición (todos los modos) ─────────────

  /// Mientras el usuario arrastra un slider se llama con [dragging]=true: se
  /// aplica con debounce para no reinicializar el filtro de mpv 60 veces/s,
  /// lo que provoca chasquidos audibles.
  Future<void> updateBand(int index, EqBand band,
      {bool dragging = false}) async {
    final bands = [...active.bands];
    if (index < 0 || index >= bands.length) return;
    bands[index] = band.sanitized(limits);
    _active[_mode] = active.copyWith(
      bands: bands,
      id: active.isBuiltIn ? 'custom.${_mode.name}' : active.id,
      name: active.isBuiltIn ? 'Personalizado' : active.name,
      isBuiltIn: false,
    );
    await _commit(immediate: !dragging);
  }

  // Modo simple
  Future<void> setSimple(
      {double? bass,
      double? mid,
      double? treble,
      bool dragging = false}) async {
    final b = active.bands.length == 3 ? active.bands : simpleBands();
    final next = simpleBands(
      bass: (bass ?? b[0].gainDb)
          .clamp(EqLimits.simple.minGainDb, EqLimits.simple.maxGainDb),
      mid: (mid ?? b[1].gainDb)
          .clamp(EqLimits.simple.minGainDb, EqLimits.simple.maxGainDb),
      treble: (treble ?? b[2].gainDb)
          .clamp(EqLimits.simple.minGainDb, EqLimits.simple.maxGainDb),
    );
    _active[EqMode.simple] = active.copyWith(
      bands: next,
      id: 'custom.simple',
      name: 'Personalizado',
      isBuiltIn: false,
    );
    await _commit(immediate: !dragging);
  }

  Future<void> setLoudness(bool v) async {
    _active[_mode] = active.copyWith(loudness: v);
    await _commit(immediate: true);
  }

  // Preamp (intermedio y profesional)
  Future<void> setPreamp({bool? auto, double? manualDb}) async {
    _active[_mode] = active.copyWith(
      autoPreamp: auto ?? active.autoPreamp,
      preampDb: (manualDb ?? active.preampDb).clamp(-24.0, 6.0),
    );
    await _commit(immediate: true);
  }

  // Modo profesional
  Future<void> addBand([EqBand? band]) async {
    if (_mode != EqMode.professional ||
        active.bands.length >= limits.maxBands) {
      return;
    }
    _active[_mode] = active.copyWith(
      bands: [...active.bands, band ?? const EqBand.peaking(1000, 0)],
      isBuiltIn: false,
    );
    await _commit(immediate: true);
  }

  Future<void> removeBand(int index) async {
    if (_mode != EqMode.professional) return;
    final bands = [...active.bands]..removeAt(index);
    _active[_mode] = active.copyWith(bands: bands);
    await _commit(immediate: true);
  }

  Future<List<String>> importApo(String text, String name) async {
    final r = EqImportExport.parseApo(
      text,
      id: 'user.${DateTime.now().millisecondsSinceEpoch}',
      name: name,
    );
    _mode = EqMode.professional;
    _active[EqMode.professional] = r.profile;
    _userProfiles.add(r.profile);
    _enabled = true;
    await _commit(immediate: true);
    return r.warnings;
  }

  String exportApo() =>
      EqImportExport.toApo(active, preampDb: effectivePreampDb);

  Future<void> saveCurrentAs(String name) async {
    final p = active.copyWith(
      id: 'user.${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Mi ecualización' : name.trim(),
      isBuiltIn: false,
    );
    _userProfiles.add(p);
    _active[_mode] = p;
    await _commit(immediate: true);
  }

  Future<void> deleteUserProfile(String id) async {
    _userProfiles.removeWhere((p) => p.id == id);
    await _commit(immediate: true);
  }

  Future<void> reset() => selectProfile(EqPresets.defaultFor(_mode));

  /// Vuelve a aplicar la curva actual. Se usa cuando aparece un reproductor
  /// nuevo (just_audio crea el motor al cargar la primera pista).
  Future<void> reapply() => _applyNow();

  // ───────────── Hi-Fi ─────────────

  /// Llamado por PlayerController cuando cambia el plan de fidelidad.
  Future<void> setHifiAllowsEq(bool allows) async {
    _blockedByHifi = !allows;
    await _applyNow();
    notifyListeners();
  }

  // ───────────── Internos ─────────────

  Future<void> _commit({required bool immediate}) async {
    notifyListeners();
    _applyDebounce?.cancel();
    if (immediate) {
      await _applyNow();
    } else {
      _applyDebounce = Timer(const Duration(milliseconds: 90), _applyNow);
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _applyNow() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      if (!_enabled || _blockedByHifi || active.isFlat) {
        await backend.bypass();
      } else {
        await backend.apply(active.effectiveBands, effectivePreampDb);
      }
    } catch (e) {
      debugPrint('EqualizerService: el backend rechazó la configuración ($e)');
    }
  }

  Future<File> _file() async {
    final dir = _storageDirOverride ?? await getAppDataDirectory();
    return File('${dir.path}${Platform.pathSeparator}equalizer_v2.json');
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'version': 2,
        'enabled': _enabled,
        'mode': _mode.name,
        'active': {
          for (final e in _active.entries) e.key.name: e.value.toJson()
        },
        'user': _userProfiles.map((p) => p.toJson()).toList(),
      }));
      await tmp.rename(f.path); // escritura atómica
    } catch (e) {
      debugPrint('EqualizerService: no se pudo guardar ($e)');
    }
  }

  @override
  void dispose() {
    _applyDebounce?.cancel();
    _saveDebounce?.cancel();
    _backend?.dispose();
    super.dispose();
  }
}
