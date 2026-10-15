import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/settings_controller.dart';

import 'support/app_fakes.dart';
import 'support/fake_audio_player.dart';

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

  @override
  String? get serverUrl => url;
  @override
  String? get username => user;
  @override
  bool get connected => isConnected;

  @override
  String getPlaybackStreamUrl(String trackId, {AudioQuality? quality}) =>
      'https://a.example.invalid/stream/$trackId';

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
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await player.addNextInQueue(t('x'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await player.skipNext();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(player.currentTrack?.id, 'x');
    final loaded = [...a.loaded, ...b.loaded];
    expect(loaded.last, endsWith('/x'));
  });
}
