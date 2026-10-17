import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/wait_for.dart';
import 'package:crotowave/models/eq_models.dart';
import 'package:crotowave/services/eq/eq_backends.dart';
import 'package:crotowave/services/eq/eq_math.dart';
import 'package:crotowave/services/eq/eq_presets.dart';
import 'package:crotowave/services/equalizer_service.dart';

class _FakeBackend extends EqBackend {
  final applied = <(List<EqBand>, double)>[];
  int bypasses = 0;

  @override
  EqCapabilities get capabilities =>
      const EqCapabilities(exact: true, maxBands: 16, engineLabel: 'fake');

  @override
  Future<void> apply(List<EqBand> bands, double preampDb) async =>
      applied.add((bands, preampDb));

  @override
  Future<void> bypass() async => bypasses++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late _FakeBackend backend;
  late EqualizerService eq;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crotowave-eq-');
    backend = _FakeBackend();
    eq = EqualizerService(backend: backend, storageDir: dir);
    await eq.initialize();
  });

  tearDown(() async {
    eq.dispose();
    await dir.delete(recursive: true);
  });

  test('arranca plano, desactivado y en modo simple', () {
    expect(eq.enabled, isFalse);
    expect(eq.mode, EqMode.simple);
    expect(eq.active.isFlat, isTrue);
  });

  test('desactivado no aplica nada: pasa por el bypass', () async {
    await eq.selectProfile(EqPresets.simple[1]); // «Más graves» activa el EQ
    expect(eq.enabled, isTrue);
    expect(backend.applied, isNotEmpty);
    final applied = backend.applied.length;

    await eq.setEnabled(false);
    expect(backend.bypasses, greaterThan(0));
    expect(backend.applied.length, applied);
  });

  test('el preamp automático compensa el realce que recibe el backend',
      () async {
    await eq.setMode(EqMode.intermediate);
    final bass = EqPresets.graphic.firstWhere((p) => p.name == 'Bass Boost');
    await eq.selectProfile(bass);
    final (bands, preamp) = backend.applied.last;
    expect(bands, isNotEmpty);
    expect(preamp, lessThan(-6));
    expect(preamp, EqMath.autoPreampDb(bands));
  });

  test('cambiar de modo conserva la curva (simple → 10 bandas)', () async {
    await eq.selectProfile(EqPresets.simple[1]); // graves +5 dB
    final before = EqMath.responseDb(eq.active.effectiveBands, 80);
    await eq.setMode(EqMode.intermediate);
    expect(eq.mode, EqMode.intermediate);
    expect(eq.active.bands, hasLength(10));
    final after = EqMath.responseDb(eq.active.effectiveBands, 80);
    expect(after, closeTo(before, 0.8));
  });

  test('de cualquier modo al profesional no pierde filtros', () async {
    await eq.setMode(EqMode.intermediate);
    await eq
        .selectProfile(EqPresets.graphic.firstWhere((p) => p.name == 'Rock'));
    final bands = eq.active.bands;
    await eq.setMode(EqMode.professional);
    expect(eq.active.bands, bands);
  });

  test('el modo Bit-perfect pone el ecualizador en pausa', () async {
    await eq.selectProfile(EqPresets.simple[1]);
    final bypasses = backend.bypasses;
    await eq.setHifiAllowsEq(false);
    expect(eq.blockedByHifi, isTrue);
    expect(backend.bypasses, bypasses + 1);

    await eq.setHifiAllowsEq(true);
    expect(eq.blockedByHifi, isFalse);
    expect(backend.applied.last.$1, isNotEmpty);
  });

  test('importa AutoEQ y lo deja activo en modo profesional', () async {
    final warnings = await eq.importApo(
        'Preamp: -4.0 dB\nFilter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1.41\nruido',
        'HD 600');
    expect(warnings, hasLength(1));
    expect(eq.mode, EqMode.professional);
    expect(eq.enabled, isTrue);
    expect(eq.active.bands, hasLength(1));
    expect(eq.effectivePreampDb, -4.0);
  });

  test('persiste modo, perfiles y presets propios entre ejecuciones', () async {
    await eq.setMode(EqMode.intermediate);
    await eq
        .selectProfile(EqPresets.graphic.firstWhere((p) => p.name == 'Vocal'));
    await eq.saveCurrentAs('Mi vocal');
    // La escritura tiene un debounce de 600 ms: esperar a que aparezca.
    final file = File('${dir.path}/equalizer_v2.json');
    await waitFor(
        () => file.existsSync() && !File('${file.path}.tmp').existsSync(),
        reason: 'el ecualizador no persistió a tiempo');
    expect(file.existsSync(), isTrue);
    expect(File('${file.path}.tmp').existsSync(), isFalse);

    final again = EqualizerService(backend: _FakeBackend(), storageDir: dir);
    addTearDown(again.dispose);
    await again.initialize();
    expect(again.mode, EqMode.intermediate);
    expect(again.enabled, isTrue);
    expect(again.presetsForMode.any((p) => p.name == 'Mi vocal'), isTrue);
  });

  test('un archivo corrupto arranca plano sin lanzar', () async {
    await File('${dir.path}/equalizer_v2.json').writeAsString('{ no es json');
    final broken = EqualizerService(backend: _FakeBackend(), storageDir: dir);
    addTearDown(broken.dispose);
    await broken.initialize();
    expect(broken.enabled, isFalse);
    expect(broken.active.isFlat, isTrue);
  });
}
