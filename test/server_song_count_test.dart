import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

void main() {
  test('El total del servidor no se limita a la primera página de canciones',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/rest/getScanStatus.view');
      expect(request.url.queryParameters.containsKey('p'), isFalse);
      return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'scanStatus': {'scanning': false, 'count': 2874}
            }
          }),
          200);
    });
    final nav = NavidromeService(httpClient: client)
      ..setConnectedForTesting(
          url: 'https://servidor.test',
          username: 'usuario',
          password: 'clave-de-prueba');
    expect(await nav.getServerSongCount(), 2874);
    nav.dispose();
  });

  for (final response in [
    {
      'status': 'ok',
      'scanStatus': {'scanning': true, 'count': 200}
    },
    {'status': 'failed'},
    {'status': 'ok'},
  ]) {
    test(
        'Un conteo parcial o no disponible no se muestra como total: $response',
        () async {
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'subsonic-response': response}), 200));
      final nav = NavidromeService(httpClient: client)
        ..setConnectedForTesting(
            url: 'https://servidor.test',
            username: 'usuario',
            password: 'clave-de-prueba');
      expect(await nav.getServerSongCount(), isNull);
      nav.dispose();
    });
  }

  test('Sin conexión no intenta consultar el servidor', () async {
    final client =
        MockClient((request) async => throw StateError('Petición inesperada'));
    final nav = NavidromeService(httpClient: client);
    expect(await nav.getServerSongCount(), isNull);
    nav.dispose();
  });
}
