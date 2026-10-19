import 'dart:async';
import 'dart:io';

import 'package:crotowave/services/audio_waveform_service.dart';
import 'package:crotowave/services/ffmpeg_waveform_decoder.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/settings_controller.dart';
import 'package:crotowave/services/waveform_service.dart';
import 'package:crotowave/widgets/waveform_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/app_fakes.dart';
import 'support/fake_audio_player.dart';
import 'support/wait_for.dart';
import 'support/wav_synth.dart';

const _duration = Duration(seconds: 10);

class _Navidrome extends FakeNavidrome {
  @override
  bool get connected => true;

  @override
  String getStreamUrl(String trackId,
          {AudioQuality? quality, Map<String, String>? extraQuery}) =>
      'https://a.example.invalid/stream/$trackId?q=${quality?.name}';

  @override
  String getPlaybackStreamUrl(String trackId, {AudioQuality? quality}) =>
      'https://a.example.invalid/play/$trackId?q=${quality?.name}';
}

/// Servicio de waveform que registra qué se le pidió y qué pistas quedan
/// pendientes de resolver.
class _RecordingWaveform implements WaveformService {
  final requests = <({String trackId, String source})>[];
  final pending = <String, Completer<WaveformData>>{};
  final holdTracks = <String>{};
  Object? failWith;

  @override
  Future<WaveformData> getWaveform(
      String trackId, String streamUrl, Duration duration) {
    requests.add((trackId: trackId, source: streamUrl));
    final failure = failWith;
    if (failure != null) return Future.error(failure);
    if (holdTracks.contains(trackId)) {
      return (pending[trackId] = Completer<WaveformData>()).future;
    }
    return Future.value(WaveformData(
        trackId: trackId, duration: duration, amplitudes: const [0.2, 0.9]));
  }
}

Track _t(String id) => Track(
    id: id,
    title: 'T$id',
    artist: 'A',
    album: 'B',
    duration: '180',
    suffix: 'flac');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioWaveformService', () {
    late Directory cache;
    setUp(() => cache = Directory.systemTemp.createTempSync('wf_loading_'));
    tearDown(() => cache.deleteSync(recursive: true));

    test('cargas simultáneas de la misma pista descargan y analizan una vez',
        () async {
      var hits = 0;
      final client = MockClient((request) async {
        hits++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response.bytes(
            WavSynth.silenceToneSilenceWav(duration: _duration), 200);
      });
      final service =
          AudioWaveformService(httpClient: client, cacheDirOverride: cache);
      const url = 'https://a.example.invalid/rest/stream.view?id=t1&t=x';

      final results = await Future.wait([
        service.getWaveform('t1', url, _duration),
        service.getWaveform('t1', url, _duration),
        service.getWaveform('t1', url, _duration),
      ]);

      expect(hits, 1, reason: 'el trabajo en vuelo debe compartirse');
      expect(results[1].amplitudes, results[0].amplitudes);
    });

    test('la caché distingue el servidor de origen, no solo el trackId',
        () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        final wav = request.url.host == 'a.example.invalid'
            ? WavSynth.constantToneWav(duration: _duration)
            : WavSynth.silenceToneSilenceWav(duration: _duration);
        return http.Response.bytes(wav, 200);
      });
      final service =
          AudioWaveformService(httpClient: client, cacheDirOverride: cache);

      final a = await service.getWaveform(
          'same-id', 'https://a.example.invalid/stream?id=1', _duration);
      final b = await service.getWaveform(
          'same-id', 'https://b.example.invalid/stream?id=1', _duration);
      // Misma fuente otra vez: ahora sí debe salir de la caché.
      final a2 = await service.getWaveform(
          'same-id', 'https://a.example.invalid/stream?id=1&t=otro', _duration);

      expect(hosts, ['a.example.invalid', 'b.example.invalid']);
      expect(b.amplitudes, isNot(a.amplitudes));
      expect(a2.amplitudes, a.amplitudes);
    });

    test('un archivo local de más de 30 MB se analiza por ruta, sin cargarlo',
        () async {
      if (!await FfmpegWaveformDecoder.isAvailable()) {
        markTestSkipped('sin ffmpeg en esta plataforma');
        return;
      }
      final big = File('${cache.path}/grande.wav');
      final made = await Process.run('ffmpeg', [
        '-v', 'error', '-f', 'lavfi', '-i',
        'sine=frequency=440:duration=200', //
        '-ar', '44100', '-ac', '2', '-y', big.path,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      expect(big.lengthSync(), greaterThan(30 * 1024 * 1024));

      final service = AudioWaveformService(cacheDirOverride: cache);
      final wave = await service.getWaveform(
          'grande', big.uri.toString(), const Duration(seconds: 200));

      expect(wave.amplitudes, isNotEmpty);
      final mean =
          wave.amplitudes.reduce((a, b) => a + b) / wave.amplitudes.length;
      expect(mean, greaterThan(0.5), reason: 'el tono real debe verse');
    });

    test('dos archivos locales distintos con el mismo trackId no colisionan',
        () async {
      final one = File('${cache.path}/uno.wav')
        ..writeAsBytesSync(WavSynth.constantToneWav(duration: _duration));
      final two = File('${cache.path}/dos.wav')
        ..writeAsBytesSync(WavSynth.silenceToneSilenceWav(duration: _duration));
      final service = AudioWaveformService(cacheDirOverride: cache);

      final a = await service.getWaveform('mismo', one.path, _duration);
      final b = await service.getWaveform('mismo', two.path, _duration);

      expect(b.amplitudes, isNot(a.amplitudes));
    });

    test('un archivo local modificado deja de usar la caché anterior',
        () async {
      final file = File('${cache.path}/pista.wav')
        ..writeAsBytesSync(WavSynth.constantToneWav(duration: _duration));
      final service = AudioWaveformService(cacheDirOverride: cache);
      final before = await service.getWaveform('p', file.path, _duration);

      file
        ..writeAsBytesSync(WavSynth.silenceToneSilenceWav(duration: _duration))
        ..setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
      final after = await service.getWaveform('p', file.path, _duration);

      expect(after.amplitudes, isNot(before.amplitudes));
    });

    test('mismo host con otra subruta o cuenta es otra identidad; rotar t/s no',
        () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add('${request.url.path}|${request.url.queryParameters['u']}');
        return http.Response.bytes(
            WavSynth.constantToneWav(duration: _duration), 200);
      });
      final service =
          AudioWaveformService(httpClient: client, cacheDirOverride: cache);
      const base = 'https://h.example.invalid';

      Future<void> load(String path, String user, String salt) =>
          service.getWaveform(
              't', '$base$path?id=1&u=$user&s=$salt&t=$salt', _duration);

      await load('/nd1/rest/stream.view', 'ana', 's1');
      await load('/nd2/rest/stream.view', 'ana', 's1'); // otra subruta
      await load('/nd1/rest/stream.view', 'bob', 's1'); // otra cuenta
      await load('/nd1/rest/stream.view', 'ana', 's2'); // token rotado: caché

      expect(seen, [
        '/nd1/rest/stream.view|ana',
        '/nd2/rest/stream.view|ana',
        '/nd1/rest/stream.view|bob',
      ]);
    });

    for (final scenario in <(String, int, int?)>[
      ('un HTTP de error', 500, null),
      ('un Content-Length por encima del tope', 200, 100 * 1024 * 1024),
    ]) {
      test('${scenario.$1} cancela el cuerpo sin descargarlo', () async {
        final client = _BodyClient(scenario.$2, scenario.$3);
        final service =
            AudioWaveformService(httpClient: client, cacheDirOverride: cache);

        await expectLater(
            service.getWaveform(
                't', 'https://h.example.invalid/s?id=1', _duration),
            throwsA(isA<WaveformDecodeException>()));

        expect(client.cancelled, isTrue,
            reason: 'el socket no debe quedar con el cuerpo pendiente');
      });
    }
  });

  group('PlayerController y la fuente de la waveform', () {
    late _RecordingWaveform waveform;
    late PlayerController player;

    setUp(() {
      waveform = _RecordingWaveform();
      player = PlayerController(_Navidrome(), SettingsController(),
          playerA: FakeAudioPlayer('a'), playerB: FakeAudioPlayer('b'))
        ..waveformServiceForTesting = waveform;
    });
    tearDown(() => player.dispose());

    test('analiza un stream liviano, no la calidad de reproducción', () async {
      await player.playQueue([_t('1')]);
      await waitFor(() => waveform.requests.isNotEmpty);

      expect(waveform.requests.single.trackId, '1');
      expect(waveform.requests.single.source, contains('/stream/1'));
      expect(waveform.requests.single.source,
          contains('q=${AudioQuality.low96.name}'));
    });

    test('una pista descargada se analiza desde su archivo local', () async {
      player.localFileResolver = (id) => '/musica/$id.flac';
      await player.playQueue([_t('1')]);
      await waitFor(() => waveform.requests.isNotEmpty);

      expect(waveform.requests.single.source, '/musica/1.flac');
    });

    test('al cambiar de pista no se muestra la onda de la anterior', () async {
      waveform.holdTracks.add('2');
      await player.playQueue([_t('1'), _t('2')]);
      await waitFor(() => player.waveformData?.trackId == '1');

      await player.skipNext();
      await waitFor(() => player.currentTrack?.id == '2');

      expect(player.waveformData, isNull);
      expect(player.isWaveformLoading, isTrue);
    });

    test('no se pide dos veces la misma pista mientras ya se carga', () async {
      waveform.holdTracks.add('1');
      await player.playQueue([_t('1')]);
      await waitFor(() => waveform.requests.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(waveform.requests.where((r) => r.trackId == '1'), hasLength(1));
    });

    test('sin decodificador queda un motivo visible, no una carga eterna',
        () async {
      waveform.failWith = const WaveformDecodeException('requires ffmpeg',
          kind: WaveformFailure.unsupported);
      await player.playQueue([_t('1')]);
      await waitFor(() => player.waveformError != null);

      expect(player.isWaveformLoading, isFalse);
      expect(player.waveformData, isNull);
      expect(player.waveformError, contains('Forma de onda no disponible'));
    });

    test('un fallo inesperado no filtra su detalle al texto de la UI',
        () async {
      waveform.failWith = Exception('GET https://h.invalid/s?u=ana&t=SECRETO');
      await player.playQueue([_t('1')]);
      await waitFor(() => player.waveformError != null);

      expect(player.waveformError, isNot(contains('SECRETO')));
      expect(player.waveformError, isNot(contains('h.invalid')));
    });

    test('el error se borra al cambiar de pista', () async {
      waveform.failWith = const WaveformDecodeException('x');
      await player.playQueue([_t('1'), _t('2')]);
      await waitFor(() => player.waveformError != null);

      waveform.failWith = null;
      await player.skipNext();
      await waitFor(() => player.waveformData?.trackId == '2');

      expect(player.waveformError, isNull);
    });

    test('vaciar la cola reinicia estado y permite recargar la misma pista',
        () async {
      waveform.holdTracks.add('1');
      await player.playQueue([_t('1')]);
      await waitFor(() => waveform.requests.length == 1);

      player.clearQueue();
      expect(player.isWaveformLoading, isFalse);
      expect(player.waveformError, isNull);

      await player.playQueue([_t('1')]);
      await waitFor(() => waveform.requests.length == 2,
          reason: 'la carga anulada no debe bloquear la misma pista');
    });

    test('una radio en directo no se descarga y explica por qué', () async {
      await player.playInternetRadio(
          'r1', 'Radio', 'https://radio.invalid/live');
      await waitFor(() => player.waveformError != null);

      expect(waveform.requests, isEmpty);
      expect(player.isWaveformLoading, isFalse);
      expect(player.waveformError, contains('directo'));
    });
  });

  group('WaveformProgressBar: estado visible', () {
    Future<void> pump(WidgetTester tester,
        {bool loading = false, String? message, WaveformData? wave}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 60,
            child: WaveformProgressBar(
              waveform: wave,
              loading: loading,
              unavailableMessage: message,
              position: Duration.zero,
              duration: const Duration(seconds: 60),
              onSeek: (_) {},
            ),
          ),
        ),
      ));
    }

    testWidgets('mientras analiza lo dice', (tester) async {
      await pump(tester, loading: true);
      expect(find.text('Analizando audio…'), findsOneWidget);
    });

    testWidgets('si falla muestra el motivo y no «Analizando»', (tester) async {
      await pump(tester,
          message: 'Forma de onda no disponible: sin decodificador');
      expect(find.text('Forma de onda no disponible: sin decodificador'),
          findsOneWidget);
      expect(find.text('Analizando audio…'), findsNothing);
    });

    testWidgets('con onda real no muestra ningún aviso', (tester) async {
      await pump(tester,
          loading: true,
          message: 'x',
          wave: const WaveformData(
              trackId: 't',
              duration: Duration(seconds: 60),
              amplitudes: [0.1, 0.8, 0.4]));
      expect(find.text('Analizando audio…'), findsNothing);
      expect(find.text('x'), findsNothing);
    });
  });
}

/// Cliente cuyo cuerpo registra si lo cancelaron (sin leerlo entero).
class _BodyClient extends http.BaseClient {
  _BodyClient(this.status, this.contentLength);

  final int status;
  final int? contentLength;
  bool cancelled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = StreamController<List<int>>(onCancel: () => cancelled = true)
      ..add(List.filled(1024, 0));
    return http.StreamedResponse(body.stream, status,
        contentLength: contentLength);
  }
}
