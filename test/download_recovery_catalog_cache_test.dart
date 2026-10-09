import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

void main() {
  late int requests;
  late DateTime now;
  late NavidromeService nav;
  Completer? gate;

  http.Response page(http.Request request) {
    requests++;
    final offset = int.parse(request.url.queryParameters['songOffset']!);
    return http.Response(
        jsonEncode({
          'subsonic-response': {
            'status': 'ok',
            'searchResult3': {
              'song': List.generate(
                  offset == 0 ? 3 : 0,
                  (i) => {
                        'id': '$i',
                        'title': 'Canción $i',
                        'artist': 'Artista',
                        'album': 'Álbum',
                        'duration': 180
                      })
            }
          }
        }),
        200);
  }

  setUp(() {
    requests = 0;
    now = DateTime(2026, 10, 9, 12);
    gate = null;
    nav = NavidromeService(httpClient: MockClient((request) async {
      if (gate != null) await gate!.future;
      return page(request);
    }))
      ..setConnectedForTesting(
          url: 'https://musica.test', username: 'ana', password: 'prueba')
      ..recoveryClock = () => now;
  });
  tearDown(() => nav.dispose());

  test('la segunda consulta reutiliza el catálogo sin volver a paginar',
      () async {
    final first = await nav.getDownloadRecoveryCatalog();
    final after = requests;
    final second = await nav.getDownloadRecoveryCatalog();
    expect(second.map((t) => t.id), first.map((t) => t.id));
    expect(requests, after);
  });

  test('pasado el tiempo de validez se vuelve a pedir al servidor', () async {
    await nav.getDownloadRecoveryCatalog();
    final after = requests;
    now = now
        .add(NavidromeService.recoveryCatalogTtl + const Duration(seconds: 1));
    await nav.getDownloadRecoveryCatalog();
    expect(requests, greaterThan(after));
  });

  test('forceRefresh ignora la caché', () async {
    await nav.getDownloadRecoveryCatalog();
    final after = requests;
    await nav.getDownloadRecoveryCatalog(forceRefresh: true);
    expect(requests, greaterThan(after));
  });

  test('otra sesión no reutiliza el catálogo de la anterior', () async {
    await nav.getDownloadRecoveryCatalog();
    final after = requests;
    nav.setConnectedForTesting(
        url: 'https://otro.test', username: 'ana', password: 'prueba');
    await nav.getDownloadRecoveryCatalog();
    expect(requests, greaterThan(after));
  });

  test('consultas simultáneas comparten una sola descarga', () async {
    gate = Completer<void>();
    final a = nav.getDownloadRecoveryCatalog();
    final b = nav.getDownloadRecoveryCatalog();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate!.complete();
    final results = await Future.wait([a, b]);
    expect(results[0], hasLength(3));
    expect(results[1], hasLength(3));
    expect(requests, 1, reason: 'una sola descarga para ambas consultas');
  });

  test('un fallo no se guarda en la caché', () async {
    var fail = true;
    final flaky = NavidromeService(httpClient: MockClient((request) async {
      if (fail) throw http.ClientException('sin red');
      return page(request);
    }))
      ..setConnectedForTesting(
          url: 'https://musica.test', username: 'ana', password: 'prueba');
    addTearDown(flaky.dispose);
    await expectLater(
        flaky.getDownloadRecoveryCatalog(), throwsA(isA<Exception>()));
    fail = false;
    expect(await flaky.getDownloadRecoveryCatalog(), hasLength(3));
  });

  test('el catálogo devuelto no se puede modificar', () async {
    final tracks = await nav.getDownloadRecoveryCatalog();
    expect(() => tracks.clear(), throwsUnsupportedError);
  });
}
