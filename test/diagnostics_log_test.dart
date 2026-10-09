import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/diagnostics_log.dart';

void main() {
  group('DiagnosticsLog', () {
    test('conserva solo las últimas entradas', () {
      final log = DiagnosticsLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.add('línea $i');
      }
      expect(log.length, 3);
      expect(
          log.entries.map((e) => e.message), ['línea 2', 'línea 3', 'línea 4']);
    });

    test('recorta los mensajes enormes', () {
      final log = DiagnosticsLog(maxMessageLength: 20);
      log.add('x' * 500);
      expect(log.entries.single.message.length, lessThanOrEqualTo(21));
      expect(log.entries.single.message, endsWith('…'));
    });

    test('ignora mensajes vacíos', () {
      final log = DiagnosticsLog();
      log.add(null);
      log.add('   ');
      expect(log.length, 0);
    });

    test('clear vacía el registro y avisa', () {
      final log = DiagnosticsLog()..add('algo');
      var notified = 0;
      log.addListener(() => notified++);
      log.clear();
      expect(log.length, 0);
      expect(notified, 1);
    });

    test('export incluye cabecera y entradas en orden', () {
      var now = DateTime.utc(2026, 10, 9, 12, 0, 0);
      final log = DiagnosticsLog(clock: () => now);
      log.add('primero');
      now = now.add(const Duration(seconds: 5));
      log.add('segundo');
      final text = log.export(header: {'App': 'Scrotify 1.0.0'});
      expect(text, contains('App: Scrotify 1.0.0'));
      expect(text.indexOf('primero'), lessThan(text.indexOf('segundo')));
      expect(text, contains('2026-10-09T12:00:05'));
    });

    test('attach captura debugPrint y detach lo restaura', () {
      final original = debugPrint;
      final forwarded = <String?>[];
      debugPrint = (message, {wrapWidth}) => forwarded.add(message);
      addTearDown(() => debugPrint = original);

      final log = DiagnosticsLog();
      log.attach();
      debugPrint('hola');
      expect(log.entries.single.message, 'hola');
      expect(forwarded, ['hola'], reason: 'sigue llegando a la consola');

      log.attach(); // idempotente: no duplica
      debugPrint('otra');
      expect(log.length, 2);

      log.detach();
      debugPrint('fuera');
      expect(log.length, 2);
      expect(forwarded, ['hola', 'otra', 'fuera']);
    });
  });

  group('redactSecrets', () {
    test('oculta credenciales Subsonic en la query', () {
      final out = redactSecrets(
          'GET https://nd.ejemplo.com/rest/ping?u=lau&t=abc123&s=salt9&v=1.16.1&c=scrotify');
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('salt9')));
      expect(out, isNot(contains('u=lau')));
      expect(out, contains('v=1.16.1'));
      expect(out, contains('c=scrotify'));
    });

    test('oculta contraseña en claro, tokens y claves', () {
      for (final secret in [
        'http://x/rest/ping?p=enc:70617373',
        'wss://jam/ws?token=SECRETO&room=AB12',
        'https://x/api?apiKey=SECRETO',
        'https://x/api?password=SECRETO',
        'https://x/share?jwt=SECRETO',
        'https://x/sync?key=SECRETO',
      ]) {
        final out = redactSecrets(secret);
        expect(out, isNot(contains('SECRETO')), reason: secret);
        expect(out, isNot(contains('70617373')), reason: secret);
      }
      expect(redactSecrets('wss://jam/ws?token=S&room=AB12'),
          contains('room=AB12'));
    });

    test('oculta usuario y contraseña embebidos en la URL', () {
      final out = redactSecrets('https://lau:hunter2@nd.ejemplo.com/rest');
      expect(out, isNot(contains('hunter2')));
      expect(out, contains('nd.ejemplo.com'));
    });

    test('oculta la clave de sincronización y cabeceras de autorización', () {
      expect(redactSecrets('vinculado con scrotify-sync://AAAA-BBBB-CCCC'),
          isNot(contains('AAAA-BBBB-CCCC')));
      expect(redactSecrets('Authorization: Bearer abc.def.ghi'),
          isNot(contains('abc.def.ghi')));
    });

    test('oculta secretos en JSON', () {
      final out = redactSecrets(
          '{"username":"lau","password":"hunter2","token":"tok","roomPassword":"sala"}');
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('"tok"')));
      expect(out, isNot(contains('"sala"')));
      expect(out, contains('"username":"lau"'));
    });

    test('no toca texto normal', () {
      const text = 'Jam: reconectando en 4 s (intento 3), pista=42 status: 200';
      expect(redactSecrets(text), text);
    });

    test('add redacta antes de guardar', () {
      final log = DiagnosticsLog()
        ..add('fallo en https://x/rest?u=lau&t=abc123');
      expect(log.export(), isNot(contains('abc123')));
    });
  });
}
