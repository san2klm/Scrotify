import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:crotowave/services/connect/connect_protocol.dart';
import 'package:crotowave/services/connect/player_connect_port.dart';
import 'package:crotowave/services/connect/track_codec.dart';
import 'package:crotowave/services/navidrome_service.dart';

import 'support/app_fakes.dart';

class _Nav extends FakeNavidrome {
  String? scopeValue = 'srv-1';
  @override
  String? get serverScope => scopeValue;
}

/// Reproductor que anota lo que le piden.
class _Player extends IdlePlayer {
  final calls = <String>[];
  List<Track> items = [];
  int pos = -1;
  Track? current;
  bool isPlaying = false;
  Duration at = Duration.zero;
  Duration? total;
  double vol = 0.7;
  bool shuffle = false;
  LoopMode repeat = LoopMode.off;
  List<Track> lastPlayed = [];
  int lastStart = -1;

  @override
  Track? get currentTrack => current;
  @override
  List<Track> get orderedQueue => items;
  @override
  int get currentOrderPos => pos;
  @override
  bool get playing => isPlaying;
  @override
  Duration get position => at;
  @override
  Duration? get duration => total;
  @override
  double get volume => vol;
  @override
  bool get shuffleEnabled => shuffle;
  @override
  LoopMode get repeatMode => repeat;

  @override
  Future<T> runLocally<T>(Future<T> Function() action) => action();
  @override
  T readLocally<T>(T Function() read) => read();

  @override
  Future<void> togglePlay() async => calls.add('togglePlay');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> skipNext() async => calls.add('skipNext');
  @override
  Future<void> skipPrevious() async => calls.add('skipPrevious');
  @override
  Future<void> seek(Duration target) async =>
      calls.add('seek:${target.inMilliseconds}');
  @override
  Future<void> setVolume(double v) async => calls.add('volume:$v');
  @override
  Future<void> toggleShuffle() async => calls.add('toggleShuffle');
  @override
  Future<void> toggleRepeat() async => calls.add('toggleRepeat');
  @override
  Future<void> playQueue(List<Track> tracks,
      {int startIndex = 0, Playlist? sourcePlaylist}) async {
    calls.add('playQueue');
    lastPlayed = tracks;
    lastStart = startIndex;
  }

  @override
  Future<void> playShuffledQueue(List<Track> tracks,
      {Playlist? sourcePlaylist}) async {
    calls.add('playShuffledQueue');
    lastPlayed = tracks;
  }

  @override
  Future<void> addAllToQueue(List<Track> tracks) async {
    calls.add('addAll:${tracks.map((t) => t.id).join(',')}');
  }

  @override
  Future<void> addToQueue(Track track) async => calls.add('add:${track.id}');
  @override
  Future<void> addNextInQueue(Track track) async =>
      calls.add('addNext:${track.id}');
  @override
  void removeFromQueue(int orderIndex) => calls.add('remove:$orderIndex');
  @override
  void reorderQueue(int oldIndex, int newIndex) =>
      calls.add('reorder:$oldIndex>$newIndex');
  @override
  void clearQueue() => calls.add('clear');
}

Track t(String id, {String duration = '200'}) =>
    Track(id: id, title: 'T$id', artist: 'A', album: 'B', duration: duration);

List<Track> tracks(int n) => [for (var i = 0; i < n; i++) t('$i')];

Map<String, dynamic> j(String id) => trackToConnectJson(t(id));

void main() {
  late _Player player;
  late _Nav nav;
  late PlayerConnectPort port;

  setUp(() {
    player = _Player();
    nav = _Nav();
    port = PlayerConnectPort(player, nav);
    addTearDown(port.dispose);
  });

  test('scope es el del servidor activo', () {
    expect(port.scope, 'srv-1');
    nav.scopeValue = null;
    expect(port.scope, isNull);
  });

  test('reenvía los cambios del reproductor a quien escuche', () {
    final own = PlayerConnectPort(player, nav);
    var n = 0;
    own.addListener(() => n++);
    player.notifyListeners();
    expect(n, 1);
    own.dispose();
    player.notifyListeners(); // ya no escucha
    expect(n, 1);
  });

  group('snapshot', () {
    test('es null si no hay nada cargado', () {
      expect(port.snapshot(), isNull);
    });

    test('describe la pista, el estado y una ventana de la cola', () {
      player
        ..items = tracks(100)
        ..pos = 50
        ..current = t('50')
        ..isPlaying = true
        ..at = const Duration(seconds: 12)
        ..total = const Duration(seconds: 180)
        ..vol = 0.5
        ..shuffle = true
        ..repeat = LoopMode.all;
      final s = port.snapshot()!;
      expect(s['scope'], 'srv-1');
      expect((s['track'] as Map)['id'], '50');
      expect(s['playing'], isTrue);
      expect(s['positionMs'], 12000);
      expect(s['durationMs'], 180000);
      expect(s['volume'], 0.5);
      expect(s['shuffle'], isTrue);
      expect(s['repeat'], 'all');
      final window = s['queue'] as List;
      expect(window, hasLength(PlayerConnectPort.maxTransferTracks));
      expect(s['offset'], 50 - PlayerConnectPort.queueBehind);
      expect(s['index'], PlayerConnectPort.queueBehind);
      expect((window[s['index'] as int] as Map)['id'], '50');
    });

    test('al principio de la cola no hay canciones anteriores', () {
      player
        ..items = tracks(10)
        ..pos = 2
        ..current = t('2');
      final s = port.snapshot()!;
      expect(s['offset'], 0);
      expect(s['index'], 2);
      expect(s['queue'] as List, hasLength(10));
    });

    test('sin duración del reproductor usa la de la pista', () {
      player
        ..items = [t('1', duration: '90')]
        ..pos = 0
        ..current = t('1', duration: '90');
      expect(port.snapshot()!['durationMs'], 90000);
    });

    test('la firma de la cola cambia si cambia la ventana', () {
      player
        ..items = tracks(5)
        ..pos = 0
        ..current = t('0');
      final first = port.snapshot()!['queueSig'];
      expect(port.snapshot()!['queueSig'], first, reason: 'estable');
      player.items = [...tracks(5), t('nueva')];
      expect(port.snapshot()!['queueSig'], isNot(first));
    });

    test('el repeat uno se publica como "one" y apagado como "off"', () {
      player
        ..items = tracks(2)
        ..pos = 0
        ..current = t('0')
        ..repeat = LoopMode.one;
      expect(port.snapshot()!['repeat'], 'one');
      player.repeat = LoopMode.off;
      expect(port.snapshot()!['repeat'], 'off');
    });
  });

  group('exportTransfer', () {
    test('null sin pista o sin servidor', () {
      expect(port.exportTransfer(), isNull);
      player
        ..items = tracks(3)
        ..pos = 0
        ..current = t('0');
      nav.scopeValue = null;
      expect(port.exportTransfer(), isNull);
    });

    test('lleva lo que falta por sonar desde la actual, con su posición', () {
      player
        ..items = tracks(10)
        ..pos = 4
        ..current = t('4')
        ..isPlaying = true
        ..at = const Duration(seconds: 33);
      final transfer = port.exportTransfer()!;
      expect(transfer.scope, 'srv-1');
      expect([for (final m in transfer.tracks) m['id']],
          ['4', '5', '6', '7', '8', '9']);
      expect(transfer.index, 0);
      expect(transfer.positionMs, 33000);
      expect(transfer.playing, isTrue);
    });

    test('tiene el mismo tope de canciones que el reparto en trozos', () {
      player
        ..items = tracks(1500)
        ..pos = 0
        ..current = t('0');
      expect(port.exportTransfer()!.tracks,
          hasLength(ConnectQueueChunks.maxTotal));
    });
  });

  group('adopt', () {
    ConnectTransfer transfer(
            {int index = 0,
            int positionMs = 0,
            bool playing = true,
            String? xfer,
            int more = 0}) =>
        ConnectTransfer(
            scope: 'srv-1',
            tracks: [j('a'), j('b'), j('c')],
            index: index,
            positionMs: positionMs,
            playing: playing,
            xfer: xfer,
            more: more);

    test('reproduce la cola en la posición indicada', () async {
      await port.adopt(transfer(index: 1, positionMs: 5000));
      expect(player.calls, ['playQueue', 'seek:5000']);
      expect(player.lastStart, 1);
      expect(player.lastPlayed.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('sin posición no hace seek y si estaba en pausa, pausa', () async {
      await port.adopt(transfer(playing: false));
      expect(player.calls, ['playQueue', 'pause']);
    });

    test('tras adoptar acepta los trozos de esa transferencia, en orden',
        () async {
      await port.adopt(transfer(xfer: 'abc12345', more: 3));
      await port.apply(ConnectCommand.queueAppend, null, {
        'scope': 'srv-1',
        'xfer': 'abc12345',
        'seq': 0,
        'tracks': [j('d'), j('e')],
      });
      await port.apply(ConnectCommand.queueAppend, null, {
        'scope': 'srv-1',
        'xfer': 'abc12345',
        'seq': 1,
        'tracks': [j('f')],
      });
      expect(player.calls.where((c) => c.startsWith('addAll')),
          ['addAll:d,e', 'addAll:f']);
    });

    test('un trozo de otra transferencia se ignora', () async {
      await port.adopt(transfer(xfer: 'abc12345', more: 3));
      await port.apply(ConnectCommand.queueAppend, null, {
        'scope': 'srv-1',
        'xfer': 'otraotra',
        'seq': 0,
        'tracks': [j('d')],
      });
      expect(player.calls.where((c) => c.startsWith('addAll')), isEmpty);
    });
  });

  group('apply', () {
    Future<void> run(String command,
            [num? value, Map<String, dynamic> data = const {}]) =>
        port.apply(command, value, data);

    test('los controles básicos llegan al reproductor', () async {
      await run(ConnectCommand.toggle);
      await run(ConnectCommand.play);
      await run(ConnectCommand.pause);
      await run(ConnectCommand.next);
      await run(ConnectCommand.previous);
      await run(ConnectCommand.shuffle);
      await run(ConnectCommand.repeat);
      expect(player.calls, [
        'togglePlay',
        'play',
        'pause',
        'skipNext',
        'skipPrevious',
        'toggleShuffle',
        'toggleRepeat',
      ]);
    });

    test('seek y volumen usan su valor; sin valor no hacen nada', () async {
      await run(ConnectCommand.seek, 42500);
      await run(ConnectCommand.volume, 0.3);
      await run(ConnectCommand.seek);
      await run(ConnectCommand.volume);
      expect(player.calls, ['seek:42500', 'volume:0.3']);
    });

    test('un seek negativo se acota a 0', () async {
      await run(ConnectCommand.seek, -500);
      expect(player.calls, ['seek:0']);
    });

    test('playQueue con servidor correcto reproduce; con otro no', () async {
      await run(ConnectCommand.playQueue, null, {
        'scope': 'srv-1',
        'tracks': [j('a'), j('b')],
        'index': 1,
        'shuffle': false,
      });
      expect(player.calls, ['playQueue']);
      expect(player.lastStart, 1);

      player.calls.clear();
      await run(ConnectCommand.playQueue, null, {
        'scope': 'otro-servidor',
        'tracks': [j('a')],
      });
      expect(player.calls, isEmpty);
    });

    test('playQueue aleatorio usa la cola barajada', () async {
      await run(ConnectCommand.playQueue, null, {
        'scope': 'srv-1',
        'tracks': [j('a'), j('b')],
        'shuffle': true,
      });
      expect(player.calls, ['playShuffledQueue']);
    });

    test('playQueue sin canciones válidas no hace nada', () async {
      await run(
          ConnectCommand.playQueue, null, {'scope': 'srv-1', 'tracks': []});
      await run(ConnectCommand.playQueue, null, {'scope': 'srv-1'});
      expect(player.calls, isEmpty);
    });

    test('añadir y poner a continuación exigen servidor y canción válidos',
        () async {
      await run(
          ConnectCommand.queueAdd, null, {'scope': 'srv-1', 'track': j('q')});
      await run(
          ConnectCommand.queueNext, null, {'scope': 'srv-1', 'track': j('n')});
      await run(
          ConnectCommand.queueAdd, null, {'scope': 'otro', 'track': j('x')});
      await run(
          ConnectCommand.queueAdd, null, {'scope': 'srv-1', 'track': 'raro'});
      await run(ConnectCommand.queueNext, null, {'scope': 'srv-1'});
      expect(player.calls, ['add:q', 'addNext:n']);
    });

    test('quitar y mover validan sus argumentos', () async {
      await run(ConnectCommand.queueRemove, 7);
      await run(ConnectCommand.queueRemove);
      await run(ConnectCommand.queueMove, null, {'from': 1, 'to': 4});
      await run(ConnectCommand.queueMove, null, {'from': '1', 'to': 4});
      await run(ConnectCommand.queueMove, null, {'from': 1});
      await run(ConnectCommand.queueClear);
      expect(player.calls, ['remove:7', 'reorder:1>4', 'clear']);
    });

    test('queueAppend sin transferencia previa se ignora', () async {
      await run(ConnectCommand.queueAppend, null, {
        'scope': 'srv-1',
        'xfer': 'abc12345',
        'seq': 0,
        'tracks': [j('d')],
      });
      expect(player.calls, isEmpty);
    });

    test('un comando desconocido no hace nada ni lanza', () async {
      await run('no_existe', 1, {'x': 1});
      expect(player.calls, isEmpty);
    });
  });

  test('pauseLocal pausa el reproductor local', () async {
    await port.pauseLocal();
    expect(player.calls, ['pause']);
  });

  group('ConnectIdentity', () {
    test('es un valor simple con id, nombre y tipo', () {
      const identity = ConnectIdentity('abc', 'Mi PC', ConnectKind.desktop);
      expect(identity.id, 'abc');
      expect(identity.name, 'Mi PC');
      expect(identity.kind, ConnectKind.desktop);
    });
  });
}
