import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:navidrome_client/services/connect/connect_mirror.dart';
import 'package:navidrome_client/services/connect/connect_protocol.dart';
import 'package:navidrome_client/services/connect/track_codec.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/sync/sync_crypto.dart';

import 'connect_service_test.dart' show FakeNetwork, FakePort, Node, settle;

Track t(String id) =>
    Track(id: id, title: 'T$id', artist: 'A', album: 'B', duration: '100');

Map<String, dynamic> json(String id) => trackToConnectJson(t(id));

void main() {
  late FakeNetwork net;
  late Node phone; // el mando
  late Node pc; // el dispositivo controlado
  late ConnectMirror mirror;
  String? scope = 'srv-1';

  setUp(() async {
    scope = 'srv-1';
    final crypto = await SyncCrypto.fromSecret(SyncKey.generate(Random(5)));
    net = FakeNetwork();
    phone = Node(
        net, 'phone-0001', 'Teléfono', ConnectKind.phone, FakePort('srv-1'));
    pc = Node(net, 'desktop-001', 'PC', ConnectKind.desktop, FakePort('srv-1'));
    await phone.service.configure(crypto);
    await pc.service.configure(crypto);
    await settle();
    mirror = ConnectMirror(phone.service, scope: () => scope);
    addTearDown(mirror.dispose);
  });

  /// Espera por condición (no por tiempo); el límite solo evita un cuelgue.
  Future<void> until(bool Function() ok, String what) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Nunca ocurrió: $what');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  /// El PC suena y el teléfono pasa a controlarlo.
  Future<void> controlPc() async {
    pc.port
      ..track = json('a')
      ..playing = true
      ..positionMs = 10000
      ..volume = 0.4
      ..queue = [json('x'), json('y'), json('z')]
      ..queueIndex = 1;
    await phone.service.transferTo('desktop-001');
    await until(
        () => phone.service.controlled != null, 'el mando controla al PC');
    // El PC publica su estado al atender cualquier comando.
    phone.service.command(ConnectCommand.play);
    await until(() => phone.service.controlledState?.queue.isNotEmpty ?? false,
        'llega el estado del PC');
  }

  group('sin dispositivo controlado', () {
    test('está inactivo, vacío y no envía comandos', () async {
      expect(mirror.active, isFalse);
      expect(mirror.queue, isEmpty);
      expect(mirror.index, -1);
      expect(mirror.playing, isFalse);
      expect(mirror.position, Duration.zero);
      expect(mirror.duration, isNull);
      expect(mirror.volume, 1);
      expect(mirror.shuffle, isFalse);
      expect(mirror.repeat, LoopMode.off);

      mirror
        ..toggle()
        ..next()
        ..addToQueue(t('q'))
        ..playQueue([t('a'), t('b')], 0);
      await settle();
      expect(pc.port.applied, isEmpty);
    });
  });

  group('controlando al PC', () {
    test('refleja su estado: activo, cola, posición, volumen y duración',
        () async {
      await controlPc();
      expect(mirror.active, isTrue);
      expect(mirror.queue.map((e) => e.id), ['x', 'y', 'z']);
      expect(mirror.queue.first.title, 'Tx');
      expect(mirror.index, 1);
      expect(mirror.playing, isTrue);
      expect(mirror.volume, closeTo(0.4, 1e-9));
      expect(mirror.duration, const Duration(milliseconds: 200000));
      // La posición avanza sola desde la última actualización mientras suena.
      expect(mirror.position.inMilliseconds, greaterThanOrEqualTo(10000));
      expect(mirror.shuffle, isFalse);
      expect(mirror.repeat, LoopMode.off);
    });

    test('la cola convertida se reutiliza mientras el estado no cambie',
        () async {
      await controlPc();
      expect(identical(mirror.queue, mirror.queue), isTrue);
    });

    test('notifica cuando cambia el dispositivo controlado', () async {
      var notified = 0;
      mirror.addListener(() => notified++);
      await controlPc();
      expect(notified, greaterThan(0));
    });

    test('los controles de reproducción se traducen en comandos', () async {
      await controlPc();
      pc.port.applied.clear();
      mirror
        ..toggle()
        ..play()
        ..pause()
        ..next()
        ..previous()
        ..seek(const Duration(seconds: 42))
        ..setVolume(0.25)
        ..toggleShuffle()
        ..toggleRepeat()
        ..clearQueue();
      await until(() => pc.port.applied.length >= 10, 'llegan los 10 comandos');
      expect(pc.port.applied, [
        'toggle',
        'play',
        'pause',
        'next',
        'previous',
        'seek:42000',
        'volume:0.25',
        'shuffle',
        'repeat',
        'queue_clear',
      ]);
    });

    test('añadir y poner a continuación envían la canción con su servidor',
        () async {
      await controlPc();
      pc.port.applied.clear();
      pc.port.appliedData.clear();
      mirror
        ..addToQueue(t('q'))
        ..addNext(t('n'));
      await until(() => pc.port.applied.length >= 2, 'llegan los 2 comandos');
      expect(pc.port.applied, ['queue_add', 'queue_next']);
      expect(pc.port.appliedData.map((d) => d['scope']), ['srv-1', 'srv-1']);
      expect(pc.port.appliedData.map((d) => (d['track'] as Map)['id']),
          ['q', 'n']);
    });

    test('quitar y mover suman el desplazamiento de la ventana de cola',
        () async {
      await controlPc(); // el PC publica offset 3
      pc.port.applied.clear();
      pc.port.appliedData.clear();
      mirror
        ..removeFromQueue(2)
        ..reorderQueue(0, 4);
      await until(() => pc.port.applied.length >= 2, 'llegan los 2 comandos');
      expect(pc.port.applied, ['queue_remove:5', 'queue_move']);
      expect(pc.port.appliedData.single, {'from': 3, 'to': 7});
    });

    test('sin servidor activo no se envían canciones', () async {
      await controlPc();
      pc.port.applied.clear();
      scope = null;
      mirror
        ..addToQueue(t('q'))
        ..addNext(t('n'))
        ..playQueue([t('a')], 0);
      await settle();
      expect(pc.port.applied, isEmpty);
    });
  });

  group('playQueue', () {
    test('una cola corta viaja de una vez desde la canción elegida', () async {
      await controlPc();
      pc.port.applied.clear();
      pc.port.appliedData.clear();
      mirror
          .playQueue([for (var i = 0; i < 10; i++) t('$i')], 4, shuffle: true);
      await settle();
      expect(pc.port.applied, ['play_queue']);
      final data = pc.port.appliedData.single;
      expect(data['shuffle'], isTrue);
      expect(data['index'], 0);
      expect([for (final m in data['tracks'] as List) (m as Map)['id']],
          ['4', '5', '6', '7', '8', '9']);
      expect(data.containsKey('xfer'), isFalse);
    });

    test('un índice fuera de rango se acota a la cola', () async {
      await controlPc();
      pc.port.appliedData.clear();
      mirror.playQueue([t('a'), t('b')], 99);
      await until(() => pc.port.appliedData.isNotEmpty, 'llega play_queue');
      expect([
        for (final m in pc.port.appliedData.single['tracks'] as List)
          (m as Map)['id']
      ], [
        'b'
      ]);
      pc.port.appliedData.clear();
      mirror.playQueue([t('a'), t('b')], -5);
      await until(() => pc.port.appliedData.isNotEmpty, 'llega play_queue');
      expect([
        for (final m in pc.port.appliedData.single['tracks'] as List)
          (m as Map)['id']
      ], [
        'a',
        'b'
      ]);
    });

    test('una cola vacía no envía nada', () async {
      await controlPc();
      pc.port.applied.clear();
      mirror.playQueue(const [], 0);
      await settle();
      expect(pc.port.applied, isEmpty);
    });

    test('una cola larga se reparte: primeros 40 y el resto en orden',
        () async {
      await controlPc();
      pc.port.applied.clear();
      pc.port.appliedData.clear();
      mirror.playQueue([for (var i = 0; i < 300; i++) t('$i')], 0);
      // 1 play_queue + ceil(260/80) = 4 trozos
      await until(() => pc.port.applied.length >= 5, 'llegan todos los trozos');
      expect(pc.port.applied.first, 'play_queue');
      expect(pc.port.applied.skip(1).toSet(), {'queue_append'});
      final head = pc.port.appliedData.first;
      expect(
          (head['tracks'] as List), hasLength(ConnectQueueChunks.firstChunk));
      expect(head['more'], 300 - ConnectQueueChunks.firstChunk);
      final seqs = [
        for (final d in pc.port.appliedData.skip(1)) d['seq'] as int
      ];
      expect(seqs, List.generate(seqs.length, (i) => i));
      final ids = [
        for (final m in head['tracks'] as List) (m as Map)['id'],
        for (final d in pc.port.appliedData.skip(1))
          for (final m in d['tracks'] as List) (m as Map)['id'],
      ];
      expect(ids, [for (var i = 0; i < 300; i++) '$i']);
    });
  });

  test('dispose deja de escuchar al servicio', () async {
    var notified = 0;
    final other = ConnectMirror(phone.service, scope: () => scope)
      ..addListener(() => notified++);
    other.dispose();
    await controlPc();
    expect(notified, 0);
  });
}
