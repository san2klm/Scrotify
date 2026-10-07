import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/scrotify_audio_handler.dart';

class FakePlayerController extends ChangeNotifier implements PlayerController {
  Track? _currentTrack;
  List<Track> _queue = [];
  int _pos = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  LoopMode _repeatMode = LoopMode.off;
  bool _shuffleEnabled = false;
  ProcessingState _processingState = ProcessingState.ready;
  ScrotifyAudioHandler? _audioHandler;

  int togglePlayCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int skipNextCalls = 0;
  int skipPreviousCalls = 0;
  int toggleShuffleCalls = 0;
  int toggleRepeatCalls = 0;
  Duration? lastSeekTarget;

  @override
  Track? get currentTrack => _currentTrack;

  @override
  List<Track> get orderedQueue => _queue;

  @override
  int get currentOrderPos => _pos;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  @override
  LoopMode get repeatMode => _repeatMode;

  @override
  bool get shuffleEnabled => _shuffleEnabled;

  @override
  ProcessingState get processingState => _processingState;

  @override
  ScrotifyAudioHandler? get audioHandler => _audioHandler;

  @override
  void setAudioHandler(ScrotifyAudioHandler? handler) {
    _audioHandler = handler;
  }

  void setTrack(
    Track? track, {
    List<Track>? queue,
    int pos = 0,
    Duration? duration,
    bool playing = true,
  }) {
    _currentTrack = track;
    if (queue != null) _queue = queue;
    _pos = pos;
    _duration = duration;
    _playing = playing;
    _processingState =
        track != null ? ProcessingState.ready : ProcessingState.idle;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    togglePlayCalls++;
    _playing = !_playing;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> skipNext() async {
    skipNextCalls++;
  }

  @override
  Future<void> skipPrevious() async {
    skipPreviousCalls++;
  }

  @override
  Future<void> seek(Duration target) async {
    lastSeekTarget = target;
    _position = target;
    _audioHandler?.updatePosition(target);
    notifyListeners();
  }

  @override
  Future<void> toggleShuffle() async {
    toggleShuffleCalls++;
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
  }

  @override
  Future<void> toggleRepeat() async {
    toggleRepeatCalls++;
    _repeatMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    notifyListeners();
  }

  @override
  void clearQueue() {
    _currentTrack = null;
    _queue = [];
    _pos = -1;
    _playing = false;
    _processingState = ProcessingState.idle;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Simula el comportamiento de just_audio cuando un Future de play() no completa
/// hasta que la canción termina o se pausa.
class HangingPlayFakePlayerController extends FakePlayerController {
  final Completer<void> playCompleter = Completer<void>();
  bool playInitiated = false;
  bool skipNextInitiated = false;
  bool skipPreviousInitiated = false;

  @override
  Future<void> togglePlay() async {
    togglePlayCalls++;
    playInitiated = true;
    _playing = true;
    notifyListeners();
    await playCompleter.future;
  }

  @override
  Future<void> play() async {
    playCalls++;
    playInitiated = true;
    _playing = true;
    notifyListeners();
    await playCompleter.future;
  }

  @override
  Future<void> skipNext() async {
    skipNextCalls++;
    skipNextInitiated = true;
    await playCompleter.future;
  }

  @override
  Future<void> skipPrevious() async {
    skipPreviousCalls++;
    skipPreviousInitiated = true;
    await playCompleter.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleTrack1 = Track(
    id: 'track-42',
    title: 'Starman',
    artist: 'David Bowie',
    album: 'The Rise and Fall of Ziggy Stardust',
    genre: 'Rock',
    duration: '254',
    albumArtUrl: 'https://navidrome.example.com/rest/getCoverArt?id=al-1',
  );

  final sampleTrack2 = Track(
    id: 'track-99',
    title: 'Life on Mars?',
    artist: 'David Bowie',
    album: 'Hunky Dory',
    genre: 'Rock',
    duration: '235',
    albumArtUrl: 'https://navidrome.example.com/rest/getCoverArt?id=al-2',
  );

  final sampleCredentialTrack1 = Track(
    id: 'track-auth-1',
    title: 'Modern Love',
    artist: 'David Bowie',
    album: 'Let\'s Dance',
    genre: 'Rock',
    duration: '286',
    albumArtUrl:
        'https://navidrome.example.com/rest/getCoverArt.view?id=al-auth1&u=fakeAdminUser&s=fakeSaltSalt999&t=fakeTokenSecret888&v=1.16.1&c=ScrotifyClient',
  );

  final sampleCredentialTrack2 = Track(
    id: 'track-auth-2',
    title: 'China Girl',
    artist: 'David Bowie',
    album: 'Let\'s Dance',
    genre: 'Rock',
    duration: '332',
    albumArtUrl:
        'https://navidrome.example.com/rest/getCoverArt.view?id=al-auth2&u=fakeAdminUser&s=fakeSaltSalt999&t=fakeTokenSecret888&v=1.16.1&c=ScrotifyClient',
  );

  test('la acción personalizada toggleLike llama al callback del widget',
      () async {
    final handler = ScrotifyAudioHandler();
    var calls = 0;
    handler.onToggleLike = () async => calls++;
    await handler.customAction(ScrotifyAudioHandler.customActionToggleLike);
    await handler.customAction('otra');
    expect(calls, 1);
  });

  group('ScrotifyAudioHandler - carátula local en la notificación', () {
    test('publica solo la copia local, nunca la URL con credenciales',
        () async {
      final fetched = <String>[];
      final handler = ScrotifyAudioHandler(coverFetcher: (track) async {
        fetched.add(track.id);
        return '/cache/media_art/${track.id}.img';
      });
      final player = FakePlayerController();
      player.setAudioHandler(handler);
      handler.attachPlayerController(player);
      addTearDown(handler.detachPlayerController);

      player.setTrack(sampleTrack1,
          queue: [sampleTrack1, sampleTrack2],
          pos: 0,
          duration: const Duration(seconds: 254),
          playing: true);
      // Mientras se descarga no se publica nada remoto.
      expect(handler.mediaItem.value!.artUri, isNull);

      await pumpEventQueue();
      expect(fetched, ['track-42']);
      final art = handler.mediaItem.value!.artUri;
      expect(art, Uri.file('/cache/media_art/track-42.img'));
      expect(art.toString(), isNot(contains('token')));

      // Una nueva sincronización no vuelve a pedir la misma carátula.
      player.notifyListeners();
      await pumpEventQueue();
      expect(fetched, ['track-42']);
    });

    test('si la descarga falla se reintenta en la siguiente sincronización',
        () async {
      var calls = 0;
      final handler = ScrotifyAudioHandler(coverFetcher: (track) async {
        calls++;
        return calls == 1 ? null : '/cache/media_art/ok.img';
      });
      final player = FakePlayerController();
      player.setAudioHandler(handler);
      handler.attachPlayerController(player);
      addTearDown(handler.detachPlayerController);

      player.setTrack(sampleTrack1,
          queue: [sampleTrack1], pos: 0, playing: true);
      await pumpEventQueue();
      expect(handler.mediaItem.value!.artUri, isNull);
      player.notifyListeners();
      await pumpEventQueue();
      expect(
          handler.mediaItem.value!.artUri, Uri.file('/cache/media_art/ok.img'));
    });
  });

  group('ScrotifyAudioHandler - FASE B1 Android media controls', () {
    late ScrotifyAudioHandler handler;
    late FakePlayerController player;

    setUp(() {
      handler = ScrotifyAudioHandler();
      player = FakePlayerController();
      player.setAudioHandler(handler);
      handler.attachPlayerController(player);
    });

    tearDown(() {
      handler.detachPlayerController();
    });

    test('initial state when player is idle with no track', () {
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
      expect(handler.playbackState.value.playing, isFalse);
    });

    test(
        'metadata reflects current lead track without exposing auth tokens as id',
        () {
      player.setTrack(
        sampleTrack1,
        queue: [sampleTrack1, sampleTrack2],
        pos: 0,
        duration: const Duration(seconds: 254),
        playing: true,
      );

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.id, 'track-42');
      expect(item.id, isNot(contains('http')));
      expect(item.id, isNot(contains('token')));
      expect(item.id, isNot(contains('salt')));
      expect(item.title, 'Starman');
      expect(item.artist, 'David Bowie');
      expect(item.album, 'The Rise and Fall of Ziggy Stardust');
      expect(item.genre, 'Rock');
      expect(item.duration, const Duration(seconds: 254));
      // En esta fase las URLs remotas se omiten para evitar fugas de credenciales
      expect(item.artUri, isNull);

      // Queue reflection
      expect(handler.queue.value.length, 2);
      expect(handler.queue.value[0].title, 'Starman');
      expect(handler.queue.value[1].title, 'Life on Mars?');

      // PlaybackState reflection
      final state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.androidCompactActionIndices, [0, 1, 3]);
      expect(state.controls.length, 4);
    });

    test(
        'SECURITY: omits artUri when URL contains credential parameters (t/s/u/c) and does not leak secrets in metadata or queue',
        () {
      player.setTrack(
        sampleCredentialTrack1,
        queue: [sampleCredentialTrack1, sampleCredentialTrack2],
        pos: 0,
        duration: const Duration(seconds: 286),
        playing: true,
      );

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      // artUri DEBE omitirse (ser null) para URLs con credenciales
      expect(item!.artUri, isNull);

      // Asegurar que ningún secreto o parámetro sensible se filtre en metadatos
      expect(item.id, isNot(contains('fakeTokenSecret888')));
      expect(item.id, isNot(contains('fakeSaltSalt999')));
      expect(item.id, isNot(contains('fakeAdminUser')));
      expect(item.title, isNot(contains('fakeTokenSecret888')));
      expect(item.artist, isNot(contains('fakeTokenSecret888')));
      expect(item.album, isNot(contains('fakeTokenSecret888')));

      // Verificar que los ítems de la cola también omiten artUri y no filtran secretos
      expect(handler.queue.value.length, 2);
      for (final qItem in handler.queue.value) {
        expect(qItem.artUri, isNull);
        expect(qItem.id, isNot(contains('fakeTokenSecret888')));
        expect(qItem.id, isNot(contains('fakeSaltSalt999')));
        expect(qItem.id, isNot(contains('fakeAdminUser')));
        expect(qItem.title, isNot(contains('fakeTokenSecret888')));
      }
    });

    test(
        'preserves artUri ONLY for safe local file/content URIs and omits remote URLs entirely',
        () {
      final safeLocalTrack = Track(
        id: 'track-safe-local',
        title: 'Rebel Rebel',
        artist: 'David Bowie',
        album: 'Diamond Dogs',
        duration: '270',
        albumArtUrl:
            'file:///data/user/0/com.scrotify/cache/covers/al-safe.jpg',
      );
      final safeContentTrack = Track(
        id: 'track-safe-content',
        title: 'Sound and Vision',
        artist: 'David Bowie',
        album: 'Low',
        duration: '183',
        albumArtUrl: 'content://media/external/images/media/42',
      );
      final safeRemoteTrack = Track(
        id: 'track-safe-remote',
        title: 'Heroes',
        artist: 'David Bowie',
        album: 'Heroes',
        duration: '360',
        albumArtUrl: 'https://images.example.com/covers/heroes.jpg',
      );

      player.setTrack(
        safeLocalTrack,
        queue: [safeLocalTrack, safeContentTrack, safeRemoteTrack],
        pos: 0,
      );

      expect(
        handler.mediaItem.value?.artUri,
        Uri.parse('file:///data/user/0/com.scrotify/cache/covers/al-safe.jpg'),
      );
      expect(
        handler.queue.value[0].artUri,
        Uri.parse('file:///data/user/0/com.scrotify/cache/covers/al-safe.jpg'),
      );
      expect(
        handler.queue.value[1].artUri,
        Uri.parse('content://media/external/images/media/42'),
      );
      // Remoto debe omitirse totalmente
      expect(handler.queue.value[2].artUri, isNull);
    });

    test(
        'SECURITY: omits credential-free remote HTTP and HTTPS artUri completely (lockscreen art pending authenticated local cache)',
        () {
      final cleanHttpTrack = Track(
        id: 'track-clean-http',
        title: 'Be My Wife',
        artist: 'David Bowie',
        album: 'Low',
        duration: '178',
        albumArtUrl: 'http://images.example.com/covers/low.jpg',
      );
      final cleanHttpsTrack = Track(
        id: 'track-clean-https',
        title: 'Warszawa',
        artist: 'David Bowie',
        album: 'Low',
        duration: '380',
        albumArtUrl: 'https://images.example.com/covers/low.jpg',
      );

      player.setTrack(
        cleanHttpTrack,
        queue: [cleanHttpTrack, cleanHttpsTrack],
        pos: 0,
      );

      expect(handler.mediaItem.value?.artUri, isNull);
      expect(handler.queue.value[0].artUri, isNull);
      expect(handler.queue.value[1].artUri, isNull);

      expect(
          ScrotifyAudioHandler.sanitizeArtUri(
              'http://images.example.com/covers/low.jpg'),
          isNull);
      expect(
          ScrotifyAudioHandler.sanitizeArtUri(
              'https://images.example.com/covers/low.jpg'),
          isNull);
      expect(
          ScrotifyAudioHandler.sanitizeArtUri(
              'https://cdn.example.com/art.png'),
          isNull);
    });

    test(
        'sanitizeArtUri accepts ONLY safe local URIs and rejects remote URLs and credential-bearing URIs',
        () {
      // Remote HTTP/HTTPS (con o sin credenciales en query o path) se omiten siempre
      expect(ScrotifyAudioHandler.sanitizeArtUri('http://example.com/art.jpg'),
          isNull);
      expect(
          ScrotifyAudioHandler.sanitizeArtUri(
              'https://cdn.example.com/art.png'),
          isNull);
      expect(
        ScrotifyAudioHandler.sanitizeArtUri(
            'https://srv/rest/getCoverArt.view?u=user&s=salt&t=token&v=1.16.1'),
        isNull,
      );
      expect(
        ScrotifyAudioHandler.sanitizeArtUri(
            'https://srv/rest/getCoverArt.view?id=123&t=secretToken'),
        isNull,
      );
      expect(
        ScrotifyAudioHandler.sanitizeArtUri(
            'https://srv/rest/getCoverArt.view?id=123&p=secretPassword'),
        isNull,
      );
      expect(
        ScrotifyAudioHandler.sanitizeArtUri(
            'https://user:password@srv/art.jpg'),
        isNull,
      );

      // URIs locales no seguras o con credenciales
      expect(
        ScrotifyAudioHandler.sanitizeArtUri('file://user:password@srv/art.jpg'),
        isNull,
      );
      expect(
        ScrotifyAudioHandler.sanitizeArtUri(
            'file:///path/to/cover.jpg?token=secret'),
        isNull,
      );

      // URIs locales seguras permitidas
      expect(
        ScrotifyAudioHandler.sanitizeArtUri('file:///path/to/cover.jpg'),
        Uri.parse('file:///path/to/cover.jpg'),
      );
      expect(
        ScrotifyAudioHandler.sanitizeArtUri(
            'content://media/external/images/media/42'),
        Uri.parse('content://media/external/images/media/42'),
      );

      // Null y cadenas vacías
      expect(ScrotifyAudioHandler.sanitizeArtUri(null), isNull);
      expect(ScrotifyAudioHandler.sanitizeArtUri(''), isNull);
      expect(ScrotifyAudioHandler.sanitizeArtUri('   '), isNull);
    });

    test(
        'system play and pause commands route directly to the single PlayerController',
        () async {
      player.setTrack(sampleTrack1, playing: false);
      expect(player.playing, isFalse);

      await handler.play();
      expect(player.togglePlayCalls, 1);
      expect(player.playing, isTrue);

      await handler.pause();
      expect(player.pauseCalls, 1);
      expect(player.playing, isFalse);
    });

    test(
        'play does not block system controls when player togglePlay future does not complete until paused',
        () async {
      final hangingPlayer = HangingPlayFakePlayerController();
      handler.attachPlayerController(hangingPlayer);
      hangingPlayer.setTrack(sampleTrack1, playing: false);

      // handler.play() debe retornar de inmediato sin bloquearse en la Future no completada
      await expectLater(
        handler.play().timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(hangingPlayer.playInitiated, isTrue);
      expect(hangingPlayer.playing, isTrue);

      // Limpiar el completer para no dejar futuros colgando
      hangingPlayer.playCompleter.complete();
    });

    test('skipNext and skipPrevious commands route to PlayerController',
        () async {
      player.setTrack(sampleTrack1, queue: [sampleTrack1, sampleTrack2]);

      await handler.skipToNext();
      expect(player.skipNextCalls, 1);

      await handler.skipToPrevious();
      expect(player.skipPreviousCalls, 1);
    });

    test(
        'skipToNext and skipToPrevious complete promptly without blocking system controls when underlying player future hangs',
        () async {
      final hangingPlayer = HangingPlayFakePlayerController();
      handler.attachPlayerController(hangingPlayer);
      hangingPlayer.setTrack(
        sampleTrack1,
        queue: [sampleTrack1, sampleTrack2],
        pos: 0,
        playing: true,
      );

      // handler.skipToNext() y skipToPrevious() deben completar de inmediato sin quedarse
      // bloqueados en futuros de play() no resueltos
      await expectLater(
        handler.skipToNext().timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(hangingPlayer.skipNextCalls, 1);
      expect(hangingPlayer.skipNextInitiated, isTrue);

      await expectLater(
        handler.skipToPrevious().timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(hangingPlayer.skipPreviousCalls, 1);
      expect(hangingPlayer.skipPreviousInitiated, isTrue);

      hangingPlayer.playCompleter.complete();
    });

    test(
        'seek command updates PlayerController and immediately updates playbackState',
        () async {
      player.setTrack(sampleTrack1, playing: true);

      await handler.seek(const Duration(seconds: 120));
      expect(player.lastSeekTarget, const Duration(seconds: 120));
      expect(handler.playbackState.value.updatePosition,
          const Duration(seconds: 120));
    });

    test('crossfade handoff / lead switch updates metadata to new lead track',
        () {
      player.setTrack(
        sampleTrack1,
        queue: [sampleTrack1, sampleTrack2],
        pos: 0,
        duration: const Duration(seconds: 254),
        playing: true,
      );
      expect(handler.mediaItem.value!.title, 'Starman');

      // Simular A/B crossfade handoff (_finishHandoff) cambiando el lead a la pista 2
      player.setTrack(
        sampleTrack2,
        queue: [sampleTrack1, sampleTrack2],
        pos: 1,
        duration: const Duration(seconds: 235),
        playing: true,
      );

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.id, 'track-99');
      expect(item.title, 'Life on Mars?');
      expect(item.album, 'Hunky Dory');
      expect(item.duration, const Duration(seconds: 235));
      expect(handler.playbackState.value.queueIndex, 1);
    });

    test(
        'clearQueue thoroughly resets playbackState to idle with zero position and empty controls',
        () {
      player.setTrack(sampleTrack1, queue: [sampleTrack1], playing: true);
      expect(handler.mediaItem.value, isNotNull);

      player.clearQueue();

      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      expect(handler.playbackState.value.queueIndex, isNull);
      expect(handler.playbackState.value.controls, isEmpty);
    });

    test(
        'stop command pauses player and sets clean idle state with zero position and empty controls',
        () async {
      player.setTrack(sampleTrack1, playing: true);
      expect(player.playing, isTrue);

      await handler.stop();
      expect(player.pauseCalls, 1);
      expect(player.playing, isFalse);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls, isEmpty);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
    });

    test(
        'detachPlayerController clears player reference, mediaItem, queue and resets state to idle',
        () {
      player.setTrack(sampleTrack1, queue: [sampleTrack1], playing: true);
      expect(handler.mediaItem.value, isNotNull);
      expect(handler.queue.value.isNotEmpty, isTrue);
      expect(handler.playbackState.value.playing, isTrue);

      handler.detachPlayerController();

      expect(handler.player, isNull);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls, isEmpty);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
    });

    test('shuffle and repeat modes route to PlayerController', () async {
      player.setTrack(sampleTrack1);

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(player.toggleShuffleCalls, 1);
      expect(player.shuffleEnabled, isTrue);

      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      expect(player.toggleRepeatCalls, 1);
    });

    test('media button clicks route to appropriate PlayerController actions',
        () async {
      player.setTrack(sampleTrack1);

      await handler.click(MediaButton.media);
      expect(player.togglePlayCalls, 1);

      await handler.click(MediaButton.next);
      expect(player.skipNextCalls, 1);

      await handler.click(MediaButton.previous);
      expect(player.skipPreviousCalls, 1);
    });
  });
}
