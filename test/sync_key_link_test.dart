import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/sync/sync_crypto.dart';
import 'package:navidrome_client/services/sync/sync_key_link.dart';

void main() {
  final key = SyncKey.format(SyncKey.generate());

  group('SyncKeyLink.build', () {
    test('genera crotowave-sync:// con la clave', () {
      final link = SyncKeyLink.build(key);
      expect(link, startsWith('crotowave-sync://'));
      expect(SyncKeyLink.parse(link!), key);
    });

    test('una clave inválida no genera enlace', () {
      expect(SyncKeyLink.build('no-es-una-clave'), isNull);
      expect(SyncKeyLink.build(''), isNull);
    });
  });

  group('SyncKeyLink.parse', () {
    test('acepta el enlace en mayúsculas, minúsculas y con espacios', () {
      expect(
          SyncKeyLink.parse('  scrotify-sync://${key.toLowerCase()}\n'), key);
      expect(SyncKeyLink.parse('CROTOWAVE-SYNC://$key'), key);
    });

    test('acepta el esquema anterior al cambio de nombre (scrotify-sync://)', () {
      expect(SyncKeyLink.parse('scrotify-sync://$key'), key);
      expect(SyncKeyLink.isSyncLink('SCROTIFY-SYNC://$key'), isTrue);
    });

    test('acepta también la clave a pelo (pegada o escrita)', () {
      expect(SyncKeyLink.parse(key), key);
      expect(SyncKeyLink.parse(key.replaceAll('-', ' ')), key);
    });

    test('rechaza otros esquemas, aunque lleven una clave válida dentro', () {
      expect(SyncKeyLink.parse('scrotify://pair?key=$key'), isNull);
      expect(SyncKeyLink.parse('https://ejemplo.com/$key'), isNull);
      expect(SyncKeyLink.parse('scrotify-sync-x://$key'), isNull);
    });

    test('rechaza basura, claves truncadas y restos añadidos', () {
      expect(SyncKeyLink.parse(''), isNull);
      expect(SyncKeyLink.parse('crotowave-sync://'), isNull);
      expect(
          SyncKeyLink.parse('crotowave-sync://${key.substring(0, 20)}'), isNull);
      expect(SyncKeyLink.parse('crotowave-sync://$key?x=1'), isNull);
      expect(SyncKeyLink.parse('scrotify-sync://$key$key'), isNull);
    });
  });

  test('isSyncLink distingue el QR de sincronización del de emparejamiento',
      () {
    expect(SyncKeyLink.isSyncLink('crotowave-sync://algo'), isTrue);
    expect(SyncKeyLink.isSyncLink('crotowave://pair?x=1'), isFalse);
    expect(SyncKeyLink.isSyncLink('scrotify://pair?x=1'), isFalse);
  });
}
