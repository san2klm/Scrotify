import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/jam_models.dart';

void main() {
  group('sanitizeArtUrl', () {
    test('elimina las credenciales Subsonic y conserva el resto', () {
      final out = sanitizeArtUrl(
          'https://nd.example/rest/getCoverArt.view?u=bob&s=abc&t=tok&v=1.16.1&c=Psysonic&id=7&size=300');
      expect(out, isNot(contains('tok')));
      expect(out, isNot(contains('u=bob')));
      expect(out, contains('id=7'));
      expect(out, contains('size=300'));
    });

    test('deja intactas null, vacías y URLs sin query', () {
      expect(sanitizeArtUrl(null), isNull);
      expect(sanitizeArtUrl(''), '');
      expect(sanitizeArtUrl('https://x.example/a.png'),
          'https://x.example/a.png');
    });

    test('JamQueueItem.toJson no filtra el token', () {
      final json = sanitizeArtUrl('https://nd/x?u=a&s=b&t=SECRET&id=1');
      expect(json, isNot(contains('SECRET')));
    });
  });
}
