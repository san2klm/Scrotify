import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pairing_models.dart';
import '../utils/crypto_helper.dart';

/// Cliente de emparejamiento para el teléfono.
///
/// Permite:
/// 1. Escanear la red Wi-Fi buscando computadoras con Scrotify en modo emparejamiento ([discoverPcs]).
/// 2. Encontrar un PC en la red local por su código de 6 caracteres ([findPcByCode]).
/// 3. Reclamar credenciales de forma segura vía HTTP + sealed-box ([claim]).
/// 4. Procesar un URI escaneado desde el QR ([claimFromQr]).
class PairingClient {
  /// Escanea la red local por broadcast UDP buscando todas las instancias de
  /// Scrotify activas en modo emparejamiento.
  static Future<List<DiscoveredPc>> discoverPcs({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discovered = <String, DiscoveredPc>{};
    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    final completer = Completer<List<DiscoveredPc>>();

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null) return;
          try {
            final text = utf8.decode(dg.data);
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (json['app'] == kPairingDiscoveryAppTag &&
                (json['op'] == 'presence' || json['op'] == 'here')) {
              final pc = DiscoveredPc.fromJson(json, dg.address.address);
              if (pc.port > 0) {
                final key = '${pc.host}:${pc.port}';
                discovered[key] = pc;
              }
            }
          } catch (_) {}
        }
      });

      final queryPayload = jsonEncode({
        'app': kPairingDiscoveryAppTag,
        'op': 'discover',
      });
      final bytes = utf8.encode(queryPayload);

      void sendBroadcasts() async {
        try {
          try {
            socket?.send(bytes, InternetAddress.loopbackIPv4, kPairingDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(bytes, InternetAddress('255.255.255.255'), kPairingDiscoveryPort);
          } catch (_) {}

          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnetBcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
                try {
                  socket?.send(bytes, InternetAddress(subnetBcast), kPairingDiscoveryPort);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      sendBroadcasts();
      Timer(const Duration(milliseconds: 500), () => sendBroadcasts());
      Timer(const Duration(milliseconds: 1200), () => sendBroadcasts());

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(discovered.values.toList());
        }
      });

      final result = await completer.future;
      return result;
    } catch (e) {
      debugPrint('PairingClient.discoverPcs error: $e');
      return discovered.values.toList();
    } finally {
      timeoutTimer?.cancel();
      socket?.close();
    }
  }

  /// Busca un PC en la LAN que tenga activo el código [code].
  /// Emite tramas UDP broadcast a la red local y espera una respuesta unicast.
  static Future<DiscoveredPc?> findPcByCode(
    String code, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final cleanCode = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleanCode.length != 6) return null;

    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    final completer = Completer<DiscoveredPc?>();

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Escuchar respuestas
      socket.listen((event) {
        if (event == RawSocketEvent.read && !completer.isCompleted) {
          final dg = socket?.receive();
          if (dg == null) return;
          try {
            final text = utf8.decode(dg.data);
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (json['app'] == kPairingDiscoveryAppTag &&
                json['op'] == 'here' &&
                (json['code'] as String?)?.toUpperCase() == cleanCode) {
              final pc = DiscoveredPc.fromJson(json, dg.address.address);
              if (pc.port > 0 && !completer.isCompleted) {
                completer.complete(pc);
              }
            }
          } catch (_) {}
        }
      });

      // Preparar mensaje de búsqueda
      final queryPayload = jsonEncode({
        'app': kPairingDiscoveryAppTag,
        'op': 'find',
        'code': cleanCode,
      });
      final bytes = utf8.encode(queryPayload);

      // Enviar por broadcast general, loopback y broadcast de interfaces
      void sendBroadcasts() async {
        try {
          try {
            socket?.send(bytes, InternetAddress.loopbackIPv4, kPairingDiscoveryPort);
          } catch (_) {}

          try {
            socket?.send(bytes, InternetAddress('255.255.255.255'), kPairingDiscoveryPort);
          } catch (_) {}

          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnetBcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
                try {
                  socket?.send(bytes, InternetAddress(subnetBcast), kPairingDiscoveryPort);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      // Enviar varias ráfagas espaciadas para compensar pérdida de paquetes UDP
      sendBroadcasts();
      Timer(const Duration(milliseconds: 600), () {
        if (!completer.isCompleted) sendBroadcasts();
      });
      Timer(const Duration(milliseconds: 1400), () {
        if (!completer.isCompleted) sendBroadcasts();
      });

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final result = await completer.future;
      return result;
    } catch (e) {
      debugPrint('PairingClient.findPcByCode error: $e');
      return null;
    } finally {
      timeoutTimer?.cancel();
      socket?.close();
    }
  }

  /// Reclama las credenciales del PC enviando la clave pública efímera del móvil
  /// y descifrando el payload con la clave privada correspondiente.
  static Future<PairCredentials> claim({
    required String host,
    required int port,
    required String code,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final cleanCode = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // 1. Generar par de claves efímero del teléfono (X25519)
    final mobileKeyPair = await generateKeyPair();
    final mobilePublicKeyBytes = await extractPublicKeyBytes(mobileKeyPair);
    final mobilePublicKeyB64 = publicKeyToBase64(mobilePublicKeyBytes);

    // 2. Enviar claim request
    final uri = Uri.parse('http://$host:$port/pair/claim');
    final claimRequest = PairClaimRequest(
      code: cleanCode,
      publicKey: mobilePublicKeyB64,
    );

    final client = http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: claimRequest.toJsonString(),
          )
          .timeout(timeout);

      if (response.statusCode == 401) {
        throw Exception('Código incorrecto o no coincide con la sesión del PC');
      } else if (response.statusCode == 410) {
        throw Exception('La sesión de emparejamiento en el PC ya expiró');
      } else if (response.statusCode != 200) {
        throw Exception(
            'Error al reclamar credenciales (HTTP ${response.statusCode}): ${response.body}');
      }

      // 3. Parsear respuesta con credenciales cifradas
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final claimResponse = PairClaimResponse.fromJson(json);

      // 4. Descifrar el payload con sealed-box
      final decryptedBytes = await sealDecrypt(
        recipientKeyPair: mobileKeyPair,
        ephemeralPublicKeyB64: claimResponse.ephemeralPublicKey,
        nonceB64: claimResponse.nonce,
        ciphertextB64: claimResponse.ciphertext,
        macB64: claimResponse.mac,
      );

      final decryptedJson =
          jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
      return PairCredentials.fromJson(decryptedJson);
    } finally {
      client.close();
    }
  }

  /// Procesa directamente los datos extraídos de un código QR.
  static Future<PairCredentials> claimFromQr(String qrContent) async {
    final qrData = QrData.fromUri(qrContent);
    if (qrData == null) {
      throw Exception('El código QR escaneado no es un QR de Scrotify válido');
    }
    return claim(
      host: qrData.host,
      port: qrData.port,
      code: qrData.code,
    );
  }
}
