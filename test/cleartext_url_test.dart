import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/utils/cleartext_url.dart';

void main() {
  group('isPublicCleartextUrl', () {
    test('https nunca avisa', () {
      expect(isPublicCleartextUrl('https://navidrome.ejemplo.com'), isFalse);
      expect(isPublicCleartextUrl('https://8.8.8.8:4533'), isFalse);
    });

    test('sin esquema se asume https (como hace el login)', () {
      expect(isPublicCleartextUrl('navidrome.ejemplo.com'), isFalse);
      expect(isPublicCleartextUrl(''), isFalse);
      expect(isPublicCleartextUrl('   '), isFalse);
    });

    test('http hacia la red local no avisa', () {
      for (final url in [
        'http://localhost:4533',
        'http://127.0.0.1:4533',
        'http://10.0.0.5',
        'http://172.16.0.1',
        'http://172.31.255.255',
        'http://192.168.1.25:4533/',
        'http://169.254.10.10',
        'http://100.64.0.1', // CGNAT / Tailscale
        'http://100.127.255.254',
        'http://nas:4533',
        'http://nas.local',
        'http://musica.lan',
        'http://srv.home.arpa',
        'http://navidrome.internal',
        'http://[::1]:4533',
        'http://[fd12:3456::1]',
        'http://[fe80::1]',
        'HTTP://192.168.1.25',
      ]) {
        expect(isPublicCleartextUrl(url), isFalse, reason: url);
      }
    });

    test('http hacia un host público avisa', () {
      for (final url in [
        'http://navidrome.ejemplo.com',
        'http://8.8.8.8:4533',
        'http://172.32.0.1',
        'http://172.15.0.1',
        'http://100.128.0.1',
        'http://192.169.1.1',
        'http://[2001:db8::1]',
        '  HTTP://Musica.Ejemplo.com/  ',
      ]) {
        expect(isPublicCleartextUrl(url), isTrue, reason: url);
      }
    });

    test('una URL ilegible no avisa ni lanza', () {
      expect(isPublicCleartextUrl('http://'), isFalse);
      expect(isPublicCleartextUrl('http://[zz'), isFalse);
    });
  });
}
