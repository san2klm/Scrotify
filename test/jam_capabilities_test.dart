import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/jam_capabilities.dart';

void main() {
  group('JamCapabilities.tryParse', () {
    test('lee funciones y límites de un servidor actual', () {
      final caps = JamCapabilities.tryParse({
        'protocolVersion': 2,
        'features': {
          'publicListing': true,
          'chat': true,
          'reactions': false,
          'persistentRooms': true,
          'webLink': false,
          'sync': true,
          'connect': true,
        },
        'limits': {
          'maxParticipants': 25,
          'maxQueueItems': 300,
          'maxMessageBytes': 16384,
        },
        'publicUrl': 'https://jam.example.com',
      })!;
      expect(caps.protocolVersion, 2);
      expect(caps.publicListing, isTrue);
      expect(caps.chat, isTrue);
      expect(caps.reactions, isFalse);
      expect(caps.persistentRooms, isTrue);
      expect(caps.webLink, isFalse);
      expect(caps.sync, isTrue);
      expect(caps.connect, isTrue);
      expect(caps.maxParticipants, 25);
      expect(caps.maxQueueItems, 300);
      expect(caps.maxMessageBytes, 16384);
      expect(caps.publicUrl, 'https://jam.example.com');
    });

    test('campos ausentes usan valores conservadores', () {
      final caps = JamCapabilities.tryParse({'features': <String, Object?>{}})!;
      expect(caps.chat, isFalse);
      expect(caps.persistentRooms, isFalse);
      expect(caps.reactions, isTrue); // igual que antes: salvo que se apague
      expect(caps.publicListing, isTrue);
      expect(caps.maxQueueItems, isNull);
    });

    test('ignora campos desconocidos y tipos erróneos', () {
      final caps = JamCapabilities.tryParse({
        'features': {'chat': 'yes', 'futuro': true, 'reactions': 0},
        'limits': {'maxQueueItems': 'mucho', 'maxParticipants': -4},
        'publicUrl': 7,
      })!;
      expect(caps.chat, isFalse);
      expect(caps.reactions, isTrue);
      expect(caps.maxQueueItems, isNull);
      expect(caps.maxParticipants, isNull);
      expect(caps.publicUrl, isNull);
    });

    test('sin bloque features no es un servidor válido', () {
      expect(JamCapabilities.tryParse({'protocolVersion': 2}), isNull);
      expect(JamCapabilities.tryParse('hola'), isNull);
      expect(JamCapabilities.tryParse(null), isNull);
    });
  });

  test('legacy: un servidor sin endpoint mantiene el comportamiento anterior',
      () {
    const caps = JamCapabilities.legacy;
    expect(caps.known, isFalse);
    expect(caps.reactions, isTrue);
    expect(caps.chat, isFalse);
    expect(caps.publicListing, isTrue);
    // Sin información no se oculta ninguna opción de la interfaz.
    expect(caps.offersPersistentRooms, isTrue);
    expect(caps.offersPublicListing, isTrue);
  });

  test('un servidor que declara no ofrecer algo oculta la opción', () {
    final caps = JamCapabilities.tryParse({
      'features': {'persistentRooms': false, 'publicListing': false}
    })!;
    expect(caps.known, isTrue);
    expect(caps.offersPersistentRooms, isFalse);
    expect(caps.offersPublicListing, isFalse);
  });
}
