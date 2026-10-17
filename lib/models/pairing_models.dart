import 'dart:convert';
import 'dart:math';

import '../utils/app_links.dart';

/// Puerto UDP por defecto para el descubrimiento broadcast en la LAN.
const int kPairingDiscoveryPort = 47622;

/// Identificador de protocolo para las tramas UDP de emparejamiento.
const String kPairingDiscoveryAppTag = 'crotowave-pair';

/// Datos que van en el QR. Los QR nuevos usan un topic temporal de ntfy; se
/// conserva el formato LAN para que los QR existentes no dejen de funcionar.
class QrData {
  final String? host;
  final int? port;
  final String code;
  final String? relayTopic;

  QrData({
    this.host,
    this.port,
    required this.code,
    this.relayTopic,
  }) : assert(
          relayTopic != null || (host != null && port != null),
          'Se requiere relayTopic o host y port.',
        );

  bool get usesRelay => relayTopic != null;

  /// URI nueva: `crotowave://pair?topic=crotowave-...&code=X7K9MP`.
  String toUri() {
    if (relayTopic != null) {
      return Uri(
        scheme: kAppLinkScheme,
        host: 'pair',
        queryParameters: {'topic': relayTopic!, 'code': code},
      ).toString();
    }
    // Mismo formato que los QR LAN ya emitidos (solo cambia el esquema).
    return '$kAppLinkScheme://pair?host=$host&port=$port&code=$code';
  }

  /// Parsea tanto el relay actual como el QR LAN anterior.
  static QrData? fromUri(String uri) {
    try {
      final u = Uri.parse(uri);
      if (!isAppLinkScheme(u.scheme) || u.host != 'pair') return null;
      final code = u.queryParameters['code'];
      if (code == null) return null;
      final topic = u.queryParameters['topic'];
      if (topic != null &&
          RegExp(r'^crotowave-[a-z0-9]{32}$').hasMatch(topic)) {
        return QrData(code: code, relayTopic: topic);
      }
      final host = u.queryParameters['host'];
      final port = int.tryParse(u.queryParameters['port'] ?? '');
      if (host == null || port == null) return null;
      return QrData(host: host, port: port, code: code);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => toUri();
}

/// Dispositivo PC descubierto en la red local.
class DiscoveredPc {
  final String host;
  final int port;
  final String deviceName;
  final String serverUrl;
  final String? code;
  final int expiresIn;

  const DiscoveredPc({
    required this.host,
    required this.port,
    required this.deviceName,
    required this.serverUrl,
    this.code,
    this.expiresIn = 300,
  });

  factory DiscoveredPc.fromJson(
      Map<String, dynamic> json, String fallbackHost) {
    return DiscoveredPc(
      host: (json['host'] as String?)?.isNotEmpty == true
          ? json['host'] as String
          : fallbackHost,
      port: (json['port'] as num?)?.toInt() ?? 0,
      deviceName: (json['deviceName'] as String?) ??
          (json['name'] as String?) ??
          'PC Desconocido',
      serverUrl: (json['serverUrl'] as String?) ?? '',
      code: json['code'] as String?,
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 300,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'deviceName': deviceName,
        'serverUrl': serverUrl,
        if (code != null) 'code': code,
        'expiresIn': expiresIn,
      };
}

/// Código de emparejamiento de 6 caracteres (A-Z0-9 sin ambiguos).
class PairCode {
  static const _charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 6;

  final String value;

  PairCode._(this.value);

  factory PairCode.generate() {
    final random = Random.secure();
    final chars =
        List.generate(length, (_) => _charset[random.nextInt(_charset.length)])
            .join();
    return PairCode._(chars);
  }

  factory PairCode(String value) {
    final upper = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (upper.length != length) {
      throw ArgumentError('Código debe tener $length caracteres');
    }
    return PairCode._(upper);
  }

  @override
  String toString() => value;

  /// Formato legible: "X7K9-MP" (grupos de 3)
  String get formatted => '${value.substring(0, 3)}-${value.substring(3)}';
}

/// Request que envía el móvil al PC: `{ "code": "X7K9MP", "publicKey": "base64url..." }`
class PairClaimRequest {
  final String code;
  final String publicKey; // base64url de 32 bytes X25519

  PairClaimRequest({required this.code, required this.publicKey});

  Map<String, dynamic> toJson() => {'code': code, 'publicKey': publicKey};

  factory PairClaimRequest.fromJson(Map<String, dynamic> json) =>
      PairClaimRequest(
          code: json['code'] as String, publicKey: json['publicKey'] as String);

  String toJsonString() => jsonEncode(toJson());
}

/// Response que devuelve el PC al móvil (credenciales cifradas):
class PairClaimResponse {
  final String ephemeralPublicKey;
  final String nonce;
  final String ciphertext;
  final String mac;

  PairClaimResponse({
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
        'ephemeralPublicKey': ephemeralPublicKey,
        'nonce': nonce,
        'ciphertext': ciphertext,
        'mac': mac,
      };

  factory PairClaimResponse.fromJson(Map<String, dynamic> json) =>
      PairClaimResponse(
        ephemeralPublicKey: json['ephemeralPublicKey'] as String,
        nonce: json['nonce'] as String,
        ciphertext: json['ciphertext'] as String,
        mac: json['mac'] as String,
      );

  String toJsonString() => jsonEncode(toJson());
}

/// Estado del servidor de emparejamiento en el PC.
enum PairingStatus { idle, waiting, paired, expired, error }

/// Payload descifrado que recibe el móvil: `{ "url": "...", "user": "...", "pass": "..." }`
class PairCredentials {
  final String url;
  final String username;
  final String password;

  PairCredentials({
    required this.url,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'user': username,
        'pass': password,
      };

  factory PairCredentials.fromJson(Map<String, dynamic> json) =>
      PairCredentials(
        url: json['url'] as String,
        username: json['user'] as String,
        password: json['pass'] as String,
      );
}
