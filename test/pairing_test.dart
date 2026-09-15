import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/pairing_models.dart';
import 'package:navidrome_client/services/pairing_client.dart';
import 'package:navidrome_client/services/pairing_server.dart';
import 'package:navidrome_client/utils/crypto_helper.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  group('Crypto & Pairing Protocol Tests', () {
    test('PairCode generation and formatting', () {
      final code = PairCode.generate();
      expect(code.value.length, 6);
      expect(code.formatted.length, 7);
      expect(code.formatted[3], '-');
    });

    test('QrData serialization & deserialization', () {
      final original = QrData(host: '192.168.1.50', port: 54321, code: 'X7K9MP');
      final uri = original.toUri();
      expect(uri, 'scrotify://pair?host=192.168.1.50&port=54321&code=X7K9MP');

      final parsed = QrData.fromUri(uri);
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.50');
      expect(parsed.port, 54321);
      expect(parsed.code, 'X7K9MP');
    });

    test('Sealed-box encryption and decryption (X25519 + XChaCha20-Poly1305)', () async {
      // 1. PC genera clave efímera
      final pcKeyPair = await generateKeyPair();

      // 2. Móvil genera clave efímera y extrae su clave pública
      final mobileKeyPair = await generateKeyPair();
      final mobilePublicKey = await mobileKeyPair.extractPublicKey();

      // 3. PC cifra credenciales para el móvil
      const secretMessage = '{"url":"https://navidrome.test","user":"testuser","pass":"secret123"}';
      final encryptedMap = await sealEncrypt(
        ephemeralKeyPair: pcKeyPair,
        recipientPublicKey: mobilePublicKey,
        plaintext: Uint8List.fromList(utf8.encode(secretMessage)),
      );

      // 4. Móvil descifra con su clave privada y los datos del payload
      final decryptedBytes = await sealDecrypt(
        recipientKeyPair: mobileKeyPair,
        ephemeralPublicKeyB64: encryptedMap['ephemeralPublicKey']!,
        nonceB64: encryptedMap['nonce']!,
        ciphertextB64: encryptedMap['ciphertext']!,
        macB64: encryptedMap['mac']!,
      );

      final decryptedMessage = utf8.decode(decryptedBytes);
      expect(decryptedMessage, secretMessage);
    });

    test('PairingServer ↔ PairingClient end-to-end HTTP claim', () async {
      final server = PairingServer();

      try {
        // Iniciar servidor
        await server.start(
          serverUrl: 'https://navidrome.templo.cloud',
          username: 'demoUser',
          password: 'demoPassword',
        );

        expect(server.isActive, isTrue);
        expect(server.currentCode, isNotNull);
        expect(server.port, isNonZero);

        final code = server.currentCode!;
        final port = server.port;

        // Cliente reclama credenciales mediante localhost
        final creds = await PairingClient.claim(
          host: '127.0.0.1',
          port: port,
          code: code,
        );

        expect(creds.url, 'https://navidrome.templo.cloud');
        expect(creds.username, 'demoUser');
        expect(creds.password, 'demoPassword');
        expect(server.status, PairingStatus.paired);
      } finally {
        await server.stop();
      }
    });

    test('UDP discovery beacon finds PC by code on local loopback', () async {
      final server = PairingServer();

      try {
        await server.start(
          serverUrl: 'https://navidrome.templo.cloud',
          username: 'demoUser',
          password: 'demoPassword',
        );

        final code = server.currentCode!;

        // El cliente busca el PC por código
        final discovered = await PairingClient.findPcByCode(
          code,
          timeout: const Duration(seconds: 2),
        );

        expect(discovered, isNotNull);
        expect(discovered!.code, code);
        expect(discovered.port, server.port);
      } finally {
        await server.stop();
      }
    });

    test('PairingClient claim with invalid code fails', () async {
      final server = PairingServer();

      try {
        await server.start(
          serverUrl: 'https://navidrome.templo.cloud',
          username: 'demoUser',
          password: 'demoPassword',
        );

        expect(
          () => PairingClient.claim(
            host: '127.0.0.1',
            port: server.port,
            code: 'WRONG1',
          ),
          throwsA(isA<Exception>()),
        );
      } finally {
        await server.stop();
      }
    });
  });
}
