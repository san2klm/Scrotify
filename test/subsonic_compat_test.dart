import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navidrome_client/services/navidrome_service.dart';

void main() {
  NavidromeService serviceWith(String body) {
    final client = MockClient((_) async => http.Response(body, 200));
    return NavidromeService(httpClient: client)
      ..setConnectedForTesting(
          url: 'https://musica.example.invalid',
          username: 'ana',
          password: 'clave',
          client: client);
  }

  test('un álbum con una sola canción (objeto suelto) se lee como lista',
      () async {
    final nav = serviceWith(
        '{"subsonic-response":{"status":"ok","album":{"id":"al","song":'
        '{"id":"1","title":"Única","artist":"A","album":"B","duration":10}}}}');
    final tracks = await nav.getAlbumTracks('al');
    expect(tracks, hasLength(1));
    expect(tracks.single.title, 'Única');
  });

  test('un álbum sin canciones ni campos opcionales devuelve lista vacía',
      () async {
    final nav = serviceWith(
        '{"subsonic-response":{"status":"ok","album":{"id":"al"}}}');
    expect(await nav.getAlbumTracks('al'), isEmpty);
  });
}
