import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/jam_models.dart';

void main() {
  group('JamServerEndpoint.parse', () {
    test('accepts wss and normalizes path', () {
      final e = JamServerEndpoint.parse(' wss://jam.example.org ');
      expect(e.url, 'wss://jam.example.org/');
      expect(e.host, 'jam.example.org');
      expect(e.port, 443);
      expect(e.httpBase.toString(), 'https://jam.example.org/');
      expect(e.warning, isNull);
    });

    test('bare host defaults to wss and keeps custom port', () {
      final e = JamServerEndpoint.parse('jam.example.org:8443');
      expect(e.url, 'wss://jam.example.org:8443/');
      expect(e.port, 8443);
    });

    test('https/http are converted', () {
      expect(JamServerEndpoint.parse('https://a.example.org').url,
          'wss://a.example.org/');
      expect(JamServerEndpoint.parse('http://192.168.1.10:8080').url,
          'ws://192.168.1.10:8080/');
    });

    test('ws:// only on private hosts, with a warning', () {
      final ok = JamServerEndpoint.parse('ws://192.168.1.10:8080');
      expect(ok.isValid, isTrue);
      expect(ok.warning, isNotNull);
      expect(ok.httpBase.scheme, 'http');
      expect(JamServerEndpoint.parse('ws://localhost:8080').isValid, isTrue);
      expect(JamServerEndpoint.parse('ws://jam.example.org').isValid, isFalse);
      expect(JamServerEndpoint.parse('ws://8.8.8.8').isValid, isFalse);
      expect(JamServerEndpoint.parse('ws://172.32.0.1').isValid, isFalse);
    });

    test('rejects empty, garbage and foreign schemes', () {
      expect(JamServerEndpoint.parse('').isValid, isFalse);
      expect(JamServerEndpoint.parse('   ').error, isNotNull);
      expect(JamServerEndpoint.parse('ftp://x.org').isValid, isFalse);
      expect(JamServerEndpoint.parse('wss://').isValid, isFalse);
    });

    test('default endpoint is valid', () {
      expect(JamServerEndpoint.parse(kDefaultRemoteJamEndpoint).url,
          kDefaultRemoteJamEndpoint);
    });
  });
}
