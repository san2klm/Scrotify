import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/models/pairing_models.dart';
import 'package:crotowave/services/pairing_client.dart';
import 'package:crotowave/services/pairing_server.dart';
import 'package:crotowave/utils/crypto_helper.dart';

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
      final original =
          QrData(host: '192.168.1.50', port: 54321, code: 'X7K9MP');
      final uri = original.toUri();
      expect(uri, 'crotowave://pair?host=192.168.1.50&port=54321&code=X7K9MP');

      final parsed = QrData.fromUri(uri);
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.50');
      expect(parsed.port, 54321);
      expect(parsed.code, 'X7K9MP');
    });

    test('QrData acepta los QR con el esquema anterior (crotowave://)', () {
      final parsed = QrData.fromUri(
          'crotowave://pair?host=192.168.1.50&port=54321&code=X7K9MP');
      expect(parsed?.host, '192.168.1.50');
      expect(parsed?.code, 'X7K9MP');
      expect(QrData.fromUri('otra://pair?host=1.1.1.1&port=1&code=X7K9MP'),
          isNull);
    });

    test('QrData relay serialization & deserialization', () {
      final original = QrData(
        code: 'X7K9MP',
        relayTopic: 'crotowave-0123456789abcdefghijklmnopqrstuv',
      );
      final parsed = QrData.fromUri(original.toUri());
      expect(parsed, isNotNull);
      expect(parsed!.usesRelay, isTrue);
      expect(parsed.relayTopic, original.relayTopic);
    });

    test('Sealed-box encryption and decryption (X25519 + XChaCha20-Poly1305)',
        () async {
      // 1. PC genera clave efímera
      final pcKeyPair = await generateKeyPair();

      // 2. Móvil genera clave efímera y extrae su clave pública
      final mobileKeyPair = await generateKeyPair();
      final mobilePublicKey = await mobileKeyPair.extractPublicKey();

      // 3. PC cifra credenciales para el móvil
      const secretMessage =
          '{"url":"https://navidrome.test","user":"testuser","pass":"secret123"}';
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
      final server = PairingServer(useRelay: false);

      try {
        // Iniciar servidor
        await server.start(
          serverUrl: 'https://navidrome.example.invalid',
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

        expect(creds.url, 'https://navidrome.example.invalid');
        expect(creds.username, 'demoUser');
        expect(creds.password, 'demoPassword');
        expect(server.status, PairingStatus.paired);
      } finally {
        await server.stop();
      }
    });

    test('/pair/status no revela el código de emparejamiento', () async {
      final server = PairingServer(useRelay: false);
      final http = HttpClient();
      try {
        await server.start(
            serverUrl: 'https://nd.example', username: 'u', password: 'p');
        final req = await http
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}/pair/status'));
        final body = await (await req.close()).transform(utf8.decoder).join();
        expect(body.contains(server.currentCode!), isFalse);
        expect(jsonDecode(body).containsKey('code'), isFalse);
      } finally {
        http.close(force: true);
        await server.stop();
      }
    });

    test('5 códigos erróneos bloquean a esa IP sin cerrar la sesión', () async {
      final server = PairingServer(useRelay: false);
      final http = HttpClient();
      try {
        await server.start(
            serverUrl: 'https://nd.example', username: 'u', password: 'p');
        final port = server.port;
        final key = base64Url.encode(List<int>.filled(32, 7));
        var lastStatus = 0;
        for (var i = 0; i < 5; i++) {
          final req = await http
              .postUrl(Uri.parse('http://127.0.0.1:$port/pair/claim'));
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode({'code': 'AAAAAA', 'publicKey': key}));
          final res = await req.close();
          lastStatus = res.statusCode;
          await res.drain();
        }
        expect(lastStatus, HttpStatus.tooManyRequests);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // La sesión sigue activa: un atacante no la corta para los demás.
        expect(server.isActive, isTrue);
      } finally {
        http.close(force: true);
        await server.stop();
      }
    });

    test('UDP discovery beacon finds PC by code on local loopback', () async {
      final server = PairingServer(useRelay: false);

      try {
        await server.start(
          serverUrl: 'https://navidrome.example.invalid',
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

    test('UDP radar discoverPcs lists active PC on local network', () async {
      final server = PairingServer(useRelay: false);

      try {
        await server.start(
          serverUrl: 'https://navidrome.example.invalid',
          username: 'demoUser',
          password: 'demoPassword',
          customDeviceName: 'Mi-Super-PC',
        );

        final list = await PairingClient.discoverPcs(
          timeout: const Duration(seconds: 2),
        );

        expect(list.isNotEmpty, isTrue);
        final found = list.firstWhere((p) => p.port == server.port);
        expect(found.deviceName, 'Mi-Super-PC');
        // El radar no revela a qué servidor está conectado el PC.
        expect(found.serverUrl, isEmpty);
      } finally {
        await server.stop();
      }
    });

    test('un PC falso que responde sin conocer el código es ignorado',
        () async {
      final fake = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4, kPairingDiscoveryPort,
          reuseAddress: true);
      final seen = <String>[];
      fake.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = fake.receive();
        if (dg == null) return;
        seen.add(utf8.decode(dg.data));
        fake.send(
            utf8.encode(jsonEncode({
              'app': kPairingDiscoveryAppTag,
              'op': 'here',
              'proof': 'f' * 64,
              'port': 4242,
              'deviceName': 'Impostor',
            })),
            dg.address,
            dg.port);
      });
      try {
        final found = await PairingClient.findPcByCode('ABC234',
            timeout: const Duration(seconds: 2));
        expect(found, isNull);
        expect(seen, isNotEmpty);
        // El código nunca sale del móvil en la búsqueda.
        expect(seen.any((m) => m.contains('ABC234')), isFalse);
      } finally {
        fake.close();
      }
    });

    test('PairingClient claim with invalid code fails', () async {
      final server = PairingServer(useRelay: false);

      try {
        await server.start(
          serverUrl: 'https://navidrome.example.invalid',
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
