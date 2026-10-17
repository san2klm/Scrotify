import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crotowave/services/cover_fallback_service.dart';

void main() {
  final service = CoverFallbackService.instance;
  setUp(service.clearCache);

  Future<T> withClient<T>(Future<http.Response> Function(http.Request) handler,
      Future<T> Function() body) {
    return http.runWithClient(body, () => MockClient(handler));
  }

  test('sin datos suficientes no hace ninguna petición', () async {
    var calls = 0;
    final url = await withClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }, () => service.findCover());
    expect(url, isNull);
    expect(calls, 0);
  });

  test('iTunes tiene prioridad, ajusta el tamaño y se cachea', () async {
    var calls = 0;
    Future<http.Response> handler(http.Request r) async {
      calls++;
      return http.Response(
          '{"results":[{"artworkUrl100":"https://img.example.invalid/a/100x100bb.jpg"}]}',
          200);
    }

    final first = await withClient(handler,
        () => service.findCover(artist: 'Queen', album: 'Jazz', size: 600));
    final second = await withClient(handler,
        () => service.findCover(artist: 'Queen', album: 'Jazz', size: 600));
    expect(first, 'https://img.example.invalid/a/600x600bb.jpg');
    expect(second, first);
    expect(calls, 1, reason: 'el segundo resultado sale de la caché');
  });

  test('los fallos no se cachean: se puede reintentar', () async {
    var online = false;
    Future<http.Response> handler(http.Request r) async {
      if (!online) return http.Response('error', 500);
      return http.Response(
          '{"results":[{"artworkUrl100":"https://img.example.invalid/b/100x100bb.jpg"}]}',
          200);
    }

    expect(
        await withClient(
            handler, () => service.findCover(artist: 'Muse', album: 'Origin')),
        isNull);
    online = true;
    expect(
        await withClient(
            handler, () => service.findCover(artist: 'Muse', album: 'Origin')),
        isNotNull);
  });
}
