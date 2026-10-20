import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/settings_controller.dart';

import 'support/app_fakes.dart';
import 'support/fake_audio_player.dart';
import 'support/wait_for.dart';

Track t(String id) => Track(
    id: id,
    title: 'T$id',
    artist: 'A',
    album: 'B',
    duration: '180',
    suffix: 'mp3');

/// Servicio falso con sesión controlable.
class SessionNavidrome extends FakeNavidrome {
  String? url = 'https://a.example.invalid';
  String? user = 'ana';
  bool isConnected = true;
  bool failStream = false;

  @override
  String? get serverUrl => url;
  @override
  String? get username => user;
  @override
  bool get connected => isConnected;

  @override
  String getPlaybackStreamUrl(String trackId, {AudioQuality? quality}) =>
      failStream
          ? throw StateError('sin red')
          : 'https://a.example.invalid/stream/$trackId';

  List<String>? savedIds;
  String? savedCurrent;
  int? savedPosition;
  SavedPlayQueue? toRestore;

  @override
  Future<bool> savePlayQueue(List<String> ids,
      {String? currentId, int positionMs = 0}) async {
    savedIds = ids;
    savedCurrent = currentId;
    savedPosition = positionMs;
    return true;
  }

  @override
  Future<SavedPlayQueue?> getSavedPlayQueue() async => toRestore;

  void changed() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionNavidrome service;
  late FakeAudioPlayer a, b;
  late PlayerController player;

  setUp(() {
    service = SessionNavidrome();
    a = FakeAudioPlayer('a');
    b = FakeAudioPlayer('b');
    player =
        PlayerController(service, SettingsController(), playerA: a, playerB: b);
  });

  tearDown(() {
    player.dispose();
  });

  test('un corte de red no vacía la cola ni la pista actual', () async {
    await player.playQueue([t('1'), t('2'), t('3')], startIndex: 1);
    expect(player.queue, hasLength(3));
    expect(player.currentTrack?.id, '2');

    service.isConnected = false;
    service.changed();
    service.isConnected = true;
    service.changed();

    expect(player.queue, hasLength(3));
    expect(player.currentTrack?.id, '2');
  });

  test('cambiar de usuario sí limpia la cola', () async {
    await player.playQueue([t('1'), t('2')]);
    service.user = 'otro';
    service.changed();
    expect(player.queue, isEmpty);
  });

  test('quitar pistas y alternar el aleatorio no las resucita', () async {
    await player.playQueue([t('1'), t('2'), t('3'), t('4'), t('5')]);
    player.removeFromQueue(3); // t4
    player.removeFromQueue(1); // t2
    expect(player.queue.map((e) => e.id), ['1', '3', '5']);

    await player.toggleShuffle();
    expect(player.currentTrack?.id, '1');
    expect(player.queue.map((e) => e.id).toSet(), {'1', '3', '5'});
    await player.toggleShuffle();
    expect(player.currentTrack?.id, '1');
    expect(player.queue.map((e) => e.id), ['1', '3', '5']);
  });

  test('insertar «a continuación» tras precargar suena la pista insertada',
      () async {
    await player.playQueue([t('1'), t('2'), t('3')]);
    // Esperar a que la siguiente esté precargada en el otro reproductor.
    await waitFor(() => a.loaded.isNotEmpty && b.loaded.isNotEmpty,
        reason: 'no se precargó la siguiente');
    await player.addNextInQueue(t('x'));
    await player.skipNext();
    await waitFor(() => player.currentTrack?.id == 'x');
    expect(player.currentTrack?.id, 'x');
    final loaded = [...a.loaded, ...b.loaded];
    expect(loaded.last, endsWith('/x'));
  });

  test('positionStream sigue al reproductor que conduce tras cambiar de pista',
      () async {
    await player.playQueue([t('1'), t('2'), t('3')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final received = <Duration>[];
    final sub = player.positionStream.listen(received.add);
    await player.skipNext();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final lead = a.playing ? a : b;
    final other = identical(lead, a) ? b : a;
    received.clear();
    other.emitPosition(const Duration(seconds: 1));
    lead.emitPosition(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received, [const Duration(seconds: 2)]);
    await sub.cancel();
  });

  test('playQueue sin red no lanza y deja la cola consistente', () async {
    service.failStream = true;
    await player.playQueue([t('1'), t('2')]);
    expect(player.queue, hasLength(2));
    // Dos toques rápidos tampoco rompen nada.
    await Future.wait([
      player.playQueue([t('3')]),
      player.addAllToQueue([t('4')]),
    ]);
  });

  test('cancelar el temporizador aborta el fundido y restaura el volumen',
      () async {
    await player.playQueue([t('1'), t('2')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final lead = a.playing ? a : b;
    final base = lead.volume;
    player.setSleepTimer(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(lead.volume, lessThan(base)); // el fundido empezó
    player.cancelSleepTimer();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(lead.playing, isTrue); // no se pausó
    expect(lead.volume, closeTo(base, 0.001)); // volumen restaurado
  });

  test('guardar y restaurar la cola en el servidor', () async {
    await player.playQueue([t('1'), t('2'), t('3')], startIndex: 1);
    expect(await player.saveQueueNow(), isTrue);
    expect(service.savedIds, ['1', '2', '3']);
    expect(service.savedCurrent, '2');

    service.toRestore = SavedPlayQueue(
        tracks: [t('x'), t('y')], currentId: 'y', positionMs: 5000);
    final restored = await player.restoreSavedQueue();
    expect(restored, isNotNull);
    expect(player.queue.map((e) => e.id), ['x', 'y']);
    expect(player.currentTrack?.id, 'y');

    service.toRestore = null;
    expect(await player.restoreSavedQueue(), isNull);
  });

  test('una radio de internet suena desde su URL directa', () async {
    await player.playInternetRadio(
        'r1', 'Radio Uno', 'https://radio.example.invalid/stream.mp3');
    expect(player.currentTrack?.title, 'Radio Uno');
    expect([...a.loaded, ...b.loaded],
        contains('https://radio.example.invalid/stream.mp3'));
  });

  test('removeDuplicatesFromQueue removes duplicated upcoming tracks', () async {
    final t1 = t('1');
    final t2 = t('2');
    final t1Dup = t('1');
    final t3 = t('3');
    final t2Dup = t('2');

    await player.playQueue([t1, t2, t1Dup, t3, t2Dup]);
    expect(player.orderedQueue.map((e) => e.id), ['1', '2', '1', '3', '2']);
    expect(player.currentTrack?.id, '1');

    final removed = player.removeDuplicatesFromQueue();
    expect(removed, 2);
    expect(player.orderedQueue.map((e) => e.id), ['1', '2', '3']);
    expect(player.currentTrack?.id, '1');
  });
}
