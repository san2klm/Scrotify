import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crotowave/services/artist_image_service.dart';

void main() {
  test('sin opt-in no se contacta a terceros', () async {
    var calls = 0;
    final service = ArtistImageService(client: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));
    expect(await service.lookup('Queen'), isNull);
    expect(calls, 0);
  });

  test('el servidor tiene prioridad y el resultado se cachea', () async {
    var serverCalls = 0;
    var httpCalls = 0;
    final service = ArtistImageService(client: MockClient((_) async {
      httpCalls++;
      return http.Response('{}', 200);
    }));
    Future<String?> server() async {
      serverCalls++;
      return 'https://srv.example.invalid/queen.jpg';
    }

    final a = await service.lookup('Queen',
        serverLookup: server, allowThirdParty: true);
    final b = await service.lookup('queen ',
        serverLookup: server, allowThirdParty: true);
    expect(a, 'https://srv.example.invalid/queen.jpg');
    expect(b, a);
    expect(serverCalls, 1);
    expect(httpCalls, 0);
  });

  test('con opt-in cae a TheAudioDB y luego a Deezer', () async {
    final urls = <String>[];
    final service = ArtistImageService(client: MockClient((req) async {
      urls.add(req.url.host);
      if (req.url.host.contains('theaudiodb')) {
        return http.Response('{"artists":null}', 200);
      }
      return http.Response(
          '{"data":[{"picture_xl":"https://cdn.example.invalid/x.jpg"}]}', 200);
    }));
    final url = await service.lookup('Queen', allowThirdParty: true);
    expect(url, 'https://cdn.example.invalid/x.jpg');
    expect(urls, ['www.theaudiodb.com', 'api.deezer.com']);
  });
}
