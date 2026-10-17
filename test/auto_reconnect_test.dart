import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:navidrome_client/services/navidrome_service.dart';

class _MockClient extends http.BaseClient {
  _MockClient(this._handler);
  final Future<http.Response> Function(http.Request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final httpRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    final res = await _handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NavidromeService connects successfully and clears offline mode', () async {
    final client = _MockClient((request) async {
      if (request.url.path.contains('ping.view')) {
        return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'type': 'navidrome',
            }
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final service = NavidromeService(httpClient: client);
    await service.connectByUrl('https://demo.server', 'testuser', 'testpass');

    expect(service.offlineMode, isFalse);
    expect(service.serverScope, isNotNull);
  });

  test('NavidromeService deduplicates concurrent connectByUrl calls', () async {
    int pingCalls = 0;
    final client = _MockClient((request) async {
      if (request.url.path.contains('ping.view')) {
        pingCalls++;
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'type': 'navidrome',
            }
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final service = NavidromeService(httpClient: client);
    final f1 = service.connectByUrl('https://demo.server', 'user', 'pass');
    final f2 = service.connectByUrl('https://demo.server', 'user', 'pass');
    await Future.wait([f1, f2]);

    expect(pingCalls, equals(1));
    expect(service.offlineMode, isFalse);
  });
}
