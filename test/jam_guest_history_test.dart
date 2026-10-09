import 'dart:io' show HttpOverrides;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/jam_host_service.dart';
import 'package:navidrome_client/models/jam_models.dart';
import 'package:navidrome_client/services/jam_history.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/jam_history_dialog.dart';
import 'package:provider/provider.dart';

import 'support/app_fakes.dart';

Track t(String id, {String duration = '200'}) =>
    Track(id: id, title: 'T$id', artist: 'A', album: 'B', duration: duration);

JamParticipant p(String id, [String? name]) => JamParticipant(
    id: id,
    name: name ?? 'n$id',
    avatarColorValue: 0,
    isHost: false,
    joinedAt: DateTime(2026));

JamQueueItem q(String trackId, JamParticipant? by) => JamQueueItem(
    id: 'q$trackId', track: t(trackId), addedBy: by, addedAt: DateTime(2026));

class _RecordingNavidrome extends FakeNavidrome {
  final created = <String>[];
  final added = <List<String>>[];
  @override
  Future<Playlist?> createPlaylist(String name,
      {List<int>? coverBytes, String? coverFileName}) async {
    created.add(name);
    return Playlist(id: 'pl1', name: name, songCount: 0, duration: 0);
  }

  @override
  Future<void> updatePlaylist(
      {required String playlistId,
      String? name,
      List<String>? songIdsToAdd,
      List<int>? songIndexesToRemove}) async {
    added.add(songIdsToAdd ?? const []);
  }
}

void main() {
  late JamHistory history;
  late JamGuestHistoryTracker tracker;
  setUp(() {
    history = JamHistory();
    tracker = JamGuestHistoryTracker(history);
  });

  test('registra la pista al cambiar a la siguiente', () {
    final a = p('1');
    tracker.observe(track: t('a'), addedBy: a, positionMs: 0);
    tracker.observe(track: t('a'), addedBy: a, positionMs: 60000);
    expect(history.isEmpty, isTrue, reason: 'sigue sonando: aún no cuenta');
    tracker.observe(track: t('b'), addedBy: a, positionMs: 0);
    expect(history.entries.map((e) => e.track.id), ['a']);
    expect(history.entries.single.addedBy?.id, '1');
  });

  test('aplica el mismo umbral que el anfitrión (30 s o 50 %)', () {
    tracker.observe(track: t('corta', duration: '200'), positionMs: 0);
    tracker.observe(track: t('corta', duration: '200'), positionMs: 10000);
    tracker.observe(track: t('x', duration: '40'), positionMs: 0);
    expect(history.entries, isEmpty, reason: 'saltada a los 10 s');

    tracker.observe(track: t('x', duration: '40'), positionMs: 20000);
    tracker.observe(track: t('y'), positionMs: 0); // 20 s de 40 s: 50 %
    expect(history.entries.map((e) => e.track.id), ['x']);
  });

  test('si entra a mitad de una pista solo cuenta lo que oyó', () {
    // Entra a los 2:50 de una pista de 3:00 y se cambia a los 10 s.
    tracker.observe(track: t('a', duration: '180'), positionMs: 170000);
    tracker.observe(track: t('a', duration: '180'), positionMs: 180000);
    tracker.observe(track: t('b'), positionMs: 0);
    expect(history.entries, isEmpty);
  });

  test('recuerda quién añadió cada pista a partir de la cola', () {
    final ana = p('7', 'Ana');
    tracker.rememberQueue([q('a', ana), q('b', null)]);
    // El estado remoto no trae quién la añadió: se toma de la cola.
    tracker.observe(track: t('a'), positionMs: 0);
    tracker.observe(track: t('a'), positionMs: 90000);
    tracker.observe(track: t('b'), positionMs: 0);
    expect(history.entries.single.addedBy?.name, 'Ana');
  });

  test('lo informado en el estado manda sobre lo recordado', () {
    tracker.rememberQueue([q('a', p('7', 'Ana'))]);
    tracker.observe(track: t('a'), addedBy: p('9', 'Luis'), positionMs: 0);
    tracker.observe(track: t('a'), positionMs: 90000);
    tracker.observe(track: null, positionMs: 0);
    expect(history.entries.single.addedBy?.name, 'Luis');
  });

  test('finalize cierra la pista en curso y no duplica', () {
    tracker.observe(track: t('a'), positionMs: 0);
    tracker.observe(track: t('a'), positionMs: 100000);
    tracker.finalize();
    tracker.finalize();
    expect(history.entries.map((e) => e.track.id), ['a']);
  });

  test('una pista repetida seguida cuenta como una sola', () {
    for (final ms in [0, 40000, 80000, 0, 40000]) {
      tracker.observe(track: t('a'), positionMs: ms);
    }
    tracker.finalize();
    expect(history.entries, hasLength(1));
  });

  test('reset olvida lo observado sin tocar el historial ya guardado', () {
    tracker.observe(track: t('a'), positionMs: 0);
    tracker.observe(track: t('a'), positionMs: 100000);
    tracker.observe(track: t('b'), positionMs: 0);
    tracker.reset();
    tracker.finalize();
    expect(history.entries.map((e) => e.track.id), ['a']);
  });

  test('la memoria de la cola está acotada', () {
    final big = [for (var i = 0; i < 1000; i++) q('t$i', p('$i'))];
    tracker.rememberQueue(big);
    expect(tracker.rememberedCount, lessThanOrEqualTo(300));
    // Las más recientes se conservan.
    tracker.observe(track: t('t999'), positionMs: 0);
    tracker.observe(track: t('t999'), positionMs: 100000);
    tracker.finalize();
    expect(history.entries.single.addedBy?.id, '999');
  });

  group('JamController como invitado (host LAN real por loopback)', () {
    late JamHostService host;
    late JamController guest;

    // El binding de testWidgets simula HTTP con respuestas 400; aquí se
    // necesita el socket real contra el host de la misma máquina.
    setUpAll(() => HttpOverrides.global = null);

    setUp(() async {
      host = JamHostService();
      await host.start(
        sessionId: 'jam_hist',
        pinCode: JamCode('JK94MN'),
        hostName: 'Host',
        mode: JamMode.partySpeaker,
      );
      guest = JamController(IdlePlayer(), FakeNavidrome());
    });

    tearDown(() async {
      await guest.leaveOrEndSession();
      await host.stop();
      guest.dispose();
    });

    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 100 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('construye su historial con lo que suena y lo conserva al salir',
        () async {
      final joined = await guest.joinSession(
        host: '127.0.0.1',
        port: host.port,
        pin: 'JK94MN',
        customName: 'Lucía',
        tlsFingerprint: host.tlsFingerprint!,
      );
      expect(joined, isTrue);
      expect(guest.history.isEmpty, isTrue);
      expect(guest.historyOwnerName, 'Lucía');

      void play(Track track, int ms) => host.broadcastPlaybackUpdate(
          track: track, isPlaying: true, positionMs: ms);

      play(t('a'), 0);
      await until(() => guest.session?.currentTrack?.id == 'a');
      play(t('a'), 90000);
      await until(() => guest.session?.positionMs == 90000);
      play(t('b'), 0);
      await until(() => guest.session?.currentTrack?.id == 'b');

      expect(guest.history.entries.map((e) => e.track.id), ['a']);

      play(t('b'), 100000);
      await until(() => guest.session?.positionMs == 100000);
      await guest.leaveOrEndSession();
      expect(guest.history.entries.map((e) => e.track.id), ['a', 'b'],
          reason: 'al salir se cierra la pista que estaba sonando');
    });

    testWidgets('el diálogo guarda solo las aportaciones del invitado',
        (tester) async {
      final nav = _RecordingNavidrome();
      final me = JamController(IdlePlayer(), nav);
      addTearDown(me.dispose);
      await tester.runAsync(() async {
        await me.joinSession(
          host: '127.0.0.1',
          port: host.port,
          pin: 'JK94MN',
          customName: 'Lucía',
          tlsFingerprint: host.tlsFingerprint!,
        );
        JamParticipant by(String name) => JamParticipant(
            id: name,
            name: name,
            avatarColorValue: 0,
            isHost: false,
            joinedAt: DateTime(2026));
        Future<void> song(Track track, JamParticipant who) async {
          host.broadcastPlaybackUpdate(
              track: track, addedBy: who, isPlaying: true, positionMs: 0);
          await Future<void>.delayed(const Duration(milliseconds: 150));
          host.broadcastPlaybackUpdate(
              track: track, addedBy: who, isPlaying: true, positionMs: 100000);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }

        await song(t('mia1'), by('Lucía'));
        await song(t('otra'), by('Pedro'));
        await song(t('mia2'), by('Lucía'));
        await me.leaveOrEndSession();
      });
      expect(
          me.history.entries.map((e) => e.track.id), ['mia1', 'otra', 'mia2']);
      expect(me.myContributions.map((e) => e.track.id), ['mia1', 'mia2']);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: MaterialApp(home: Scaffold(body: JamHistoryDialog(jam: me))),
      ));
      await tester.tap(find.text('Guardar mis aportaciones'));
      await tester.pumpAndSettle();

      expect(nav.created.single, startsWith('Mis aportaciones a la Jam'));
      expect(nav.added.single, ['mia1', 'mia2']);
      expect(find.textContaining('2 pistas'), findsWidgets);
    });

    test('entrar en otra sala empieza un historial limpio', () async {
      await guest.joinSession(
        host: '127.0.0.1',
        port: host.port,
        pin: 'JK94MN',
        customName: 'Lucía',
        tlsFingerprint: host.tlsFingerprint!,
      );
      host.broadcastPlaybackUpdate(
          track: t('a'), isPlaying: true, positionMs: 0);
      await until(() => guest.session?.currentTrack?.id == 'a');
      host.broadcastPlaybackUpdate(
          track: t('a'), isPlaying: true, positionMs: 100000);
      await until(() => guest.session?.positionMs == 100000);
      await guest.leaveOrEndSession();
      expect(guest.history.isEmpty, isFalse);

      await guest.joinSession(
        host: '127.0.0.1',
        port: host.port,
        pin: 'JK94MN',
        customName: 'Otro',
        tlsFingerprint: host.tlsFingerprint!,
      );
      expect(guest.history.isEmpty, isTrue);
      expect(guest.historyOwnerName, 'Otro');
    });
  });
}
