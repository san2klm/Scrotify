import 'dart:convert';
import 'dart:math';

/// Puerto UDP por defecto para el descubrimiento broadcast en la LAN.
const int kPairingDiscoveryPort = 47622;

/// Identificador de protocolo para las tramas UDP de emparejamiento.
const String kPairingDiscoveryAppTag = 'scrotify-pair';

/// Datos que van en el QR: `scrotify://pair?host=192.168.1.42&port=54321&code=X7K9MP`
class QrData {
  final String host;
  final int port;
  final String code;

  QrData({
    required this.host,
    required this.port,
    required this.code,
  });

  /// URI completa para el QR: `scrotify://pair?host=...&port=...&code=...`
  String toUri() =>
      'scrotify://pair?host=$host&port=$port&code=$code';

  /// Parsea `scrotify://pair?host=...&port=...&code=...`
  static QrData? fromUri(String uri) {
    try {
      final u = Uri.parse(uri);
      if (u.scheme != 'scrotify' || u.host != 'pair') return null;
      final host = u.queryParameters['host'];
      final port = int.tryParse(u.queryParameters['port'] ?? '');
      final code = u.queryParameters['code'];
      if (host == null || port == null || code == null) return null;
      return QrData(host: host, port: port, code: code);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => toUri();
}

/// Código de emparejamiento de 6 caracteres (A-Z0-9 sin ambiguos).
class PairCode {
  static const _charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 6;

  final String value;

  PairCode._(this.value);

  factory PairCode.generate() {
    final rnd = DateTime.now().millisecondsSinceEpoch;
    final random = Random(rnd);
    final chars = List.generate(length, (_) => _charset[random.nextInt(_charset.length)]).join();
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
      PairClaimRequest(code: json['code'] as String, publicKey: json['publicKey'] as String);

  String toJsonString() => jsonEncode(toJson());
}

/// Response que devuelve el PC al móvil (credenciales cifradas):
/// ```
/// {
///   "ephemeralPublicKey": "base64url...",  // 32 bytes X25519 del PC
///   "nonce": "base64url...",                // 24 bytes XChaCha20
///   "ciphertext": "base64url...",           // JSON cifrado: {"url":"...","user":"...","pass":"..."}
///   "mac": "base64url..."                   // MAC Poly1305
/// }
/// ```
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