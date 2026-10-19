import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crotowave/services/local_music_service.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/offline_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// Un servidor Subsonic simulado: cada ruta responde según el modo actual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late OfflineCacheService cache;
  late LocalMusicService music;
  late NavidromeService nav;
  late Map<String, int> hits;

  // Modos de /rest/ping.view: ok | failed | html | http503 | socket.
  var ping = 'ok';
  // Modos de /rest/search3.view: ok | http503 | http503Once | failed | socket.
  var search = 'ok';
  Completer<void>? pingGate;

  String envelope(Map<String, dynamic> data) => jsonEncode({
        'subsonic-response': {'status': 'ok', ...data}
      });
  final failedBody = jsonEncode({
    'subsonic-response': {
      'status': 'failed',
      'error': {'code': 40, 'message': 'Wrong username or password'}
    }
  });

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    hits[path] = (hits[path] ?? 0) + 1;
    if (path == '/rest/ping.view') {
      await pingGate?.future;
      switch (ping) {
        case 'socket':
          throw const SocketException('Sin red');
        case 'html':
          return http.Response('<html>mantenimiento</html>', 200);
        case 'http503':
          return http.Response('{}', 503);
        case 'failed':
          return http.Response(failedBody, 200);
        default:
          return http.Response(envelope({}), 200);
      }
    }
    if (path == '/rest/search3.view') {
      switch (search) {
        case 'socket':
          throw const SocketException('Sin red');
        case 'http503':
          return http.Response('<html>503</html>', 503);
        case 'http503Once':
          search = 'ok';
          return http.Response('<html>503</html>', 503);
        case 'failed':
          return http.Response(failedBody, 200);
        default:
          return http.Response(
              envelope({
                'searchResult3': {
                  'song': [
                    {
                      'id': '1',
                      'title': 'Primera',
                      'artist': 'Artista',
                      'album': 'Álbum',
                      'duration': 180,
                      'suffix': 'mp3'
                    }
                  ]
                }
              }),
              200);
      }
    }
    if (path == '/rest/getAlbumList2.view') {
      return http.Response(failedBody, 200);
    }
    return http.Response(envelope({}), 200);
  }

  NavidromeService newNav() => NavidromeService(httpClient: MockClient(handle))
    ..localMusic = music
    ..reconnectInterval = const Duration(milliseconds: 40);

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crotowave-recuperacion-');
    ping = 'ok';
    search = 'ok';
    pingGate = null;
    hits = {};
    cache = OfflineCacheService(
        cacheRootDir: Directory(p.join(temp.path, 'cache')),
        metadataStore: InMemoryOfflineCacheMetadataStore());
    music = LocalMusicService(cache,
        stateFile: File(p.join(temp.path, 'biblioteca.json')),
        defaultRoot: Directory(p.join(temp.path, 'Música', 'CrotoWave')));
    await music.initialize();
    nav = newNav()
      ..setConnectedForTesting(
          url: 'https://musica.test', username: 'ana', password: 'clave');
  });

  tearDown(() async {
    await music.settled().timeout(const Duration(seconds: 2), onTimeout: () {});
    nav.dispose();
    music.dispose();
    await cache.close();
    await temp.delete(recursive: true);
  });

  test('status=failed en el catálogo es un error, no una lista vacía',
      () async {
    await expectLater(
        nav.getAlbums(),
        throwsA(isA<SubsonicApiException>()
            .having((e) => e.isAuth, 'isAuth', isTrue)));
  });

  test(
      'credenciales rechazadas en la biblioteca no se reintentan ni se ocultan',
      () async {
    search = 'failed';
    await expectLater(nav.getTracks(), throwsA(isA<SubsonicApiException>()));
    expect(hits['/rest/search3.view'], 1);
    expect(hits['/rest/ping.view'], isNull); // no se sondea como si fuera red
    expect(nav.connected, isTrue);
    expect(nav.offlineMode, isFalse);
    expect(nav.serverDegraded, isFalse);
  });

  test('un 503 transitorio se reintenta una vez con ping válido y se recupera',
      () async {
    search = 'http503Once';
    final tracks = await nav.getTracks();
    expect(tracks.map((t) => t.id), ['1']); // trae lo del servidor en la 2ª
    expect(hits['/rest/search3.view'], 2);
    expect(hits['/rest/ping.view'], 1);
    expect(nav.serverDegraded, isFalse);
  });

  test('un 503 persistente con el servidor vivo es un error visible', () async {
    search = 'http503';
    await expectLater(
        nav.getTracks(),
        throwsA(isA<SubsonicHttpException>()
            .having((e) => e.statusCode, 'statusCode', 503)));
    expect(hits['/rest/search3.view'], 2); // original + un único reintento
    expect(nav.connected, isTrue);
    expect(nav.offlineMode, isFalse);
    expect(nav.serverDegraded, isTrue);
    // Al recuperarse el servidor el estado degradado desaparece.
    search = 'ok';
    await nav.getTracks();
    expect(nav.serverDegraded, isFalse);
  });

  test('cerrar sesión descarta el estado degradado', () async {
    search = 'http503';
    await expectLater(nav.getTracks(), throwsA(isA<SubsonicHttpException>()));
    expect(nav.serverDegraded, isTrue);
    nav.disconnect();
    expect(nav.serverDegraded, isFalse);
  });

  test('un ping HTTP 200 sin envelope ok no cuenta como servidor vivo',
      () async {
    search = 'socket';
    ping = 'html';
    await nav.getTracks();
    expect(nav.offlineMode, isTrue);
    expect(nav.connected, isFalse);
  });

  test('un ping con status=failed tampoco cuenta como servidor vivo', () async {
    search = 'socket';
    ping = 'failed';
    await nav.getTracks();
    expect(nav.offlineMode, isTrue);
  });

  test('desconexión real: pasa a sin conexión y se recupera sola', () async {
    search = 'socket';
    ping = 'socket';
    await nav.getTracks();
    expect(nav.offlineMode, isTrue);

    // Un 200 sin envelope no debe revivir la sesión.
    ping = 'html';
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(nav.offlineMode, isTrue);

    search = 'ok';
    ping = 'ok';
    await until(() => nav.connected);
    expect(nav.connected, isTrue);
    expect(nav.offlineMode, isFalse);
  });

  test('tras dispose el sondeo de reconexión no vuelve a pedir nada', () async {
    final other = newNav()
      ..setConnectedForTesting(
          url: 'https://otra.test', username: 'ana', password: 'clave');
    search = 'socket';
    ping = 'socket';
    await other.getTracks();
    expect(other.offlineMode, isTrue);
    other.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final before = hits['/rest/ping.view'];
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(hits['/rest/ping.view'], before);
  });

  test('un ping de la cuenta anterior no respalda a la cuenta nueva', () async {
    search = 'socket';
    pingGate = Completer<void>();
    final old = nav.getTracks();
    await until(() => (hits['/rest/ping.view'] ?? 0) > 0);

    nav.setConnectedForTesting(
        url: 'https://musica.test', username: 'berta', password: 'otra');
    pingGate!.complete();

    await expectLater(old, throwsA(isA<SocketException>()));
    expect(nav.connected, isTrue); // la cuenta nueva sigue conectada
    expect(nav.offlineMode, isFalse);
  });

  test('otro endpoint que responde bien no borra el aviso de uno que falla',
      () async {
    search = 'http503';
    await expectLater(nav.getTracks(), throwsA(isA<SubsonicHttpException>()));
    expect(nav.serverDegraded, isTrue);
    expect(await nav.getPlaylists(), isEmpty); // otro endpoint, éxito
    expect(nav.serverDegraded, isTrue);
  });

  test('el reintento manual persiste el fallo si la consulta principal falla',
      () async {
    search = 'http503';
    await expectLater(nav.getTracks(), throwsA(isA<SubsonicHttpException>()));
    await expectLater(
        nav.retryDegraded(), throwsA(isA<SubsonicHttpException>()));
    expect(nav.serverDegraded, isTrue);

    search = 'ok';
    final session = nav.currentSessionKey;
    await nav.retryDegraded();
    expect(nav.serverDegraded, isFalse);
    expect(nav.currentSessionKey, isNot(session)); // las pantallas recargan
  });

  group('parseSubsonicEnvelope', () {
    http.Response body(Object json, [int status = 200]) =>
        http.Response(jsonEncode(json), status);

    test('rechaza un status explícito que no sea ok ni failed', () {
      expect(
          () => parseSubsonicEnvelope(body({
                'subsonic-response': {'status': 'banana'}
              })),
          throwsA(isA<SubsonicFormatException>()));
    });

    test('tolera status ausente salvo que se exija ok', () {
      final response = body({'subsonic-response': <String, dynamic>{}});
      expect(parseSubsonicEnvelope(response), isEmpty);
      expect(() => parseSubsonicEnvelope(response, requireOk: true),
          throwsA(isA<SubsonicFormatException>()));
    });

    test(
        'el código de error de tipo inesperado no lanza TypeError y no se '
        'expone el mensaje del servidor', () {
      for (final code in ['40', 40, 40.0, null, <int>[], 'x']) {
        final response = body({
          'subsonic-response': {
            'status': 'failed',
            'error': {'code': code, 'message': 'Fallo en /x?t=abc123&s=sal'}
          }
        });
        expect(
            () => parseSubsonicEnvelope(response),
            throwsA(isA<SubsonicApiException>().having(
                (e) => e.toString(), 'toString', isNot(contains('abc123')))));
      }
      final numeric = body({
        'subsonic-response': {
          'status': 'failed',
          'error': {'code': '40'}
        }
      });
      expect(
          () => parseSubsonicEnvelope(numeric),
          throwsA(
              isA<SubsonicApiException>().having((e) => e.code, 'code', 40)));
    });
  });
}
