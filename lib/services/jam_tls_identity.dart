import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Ephemeral TLS credentials for one LAN Jam session.
///
/// The private key never leaves host memory. Guests receive only the SHA-256
/// fingerprint through the QR payload or signed-in-session discovery packet and
/// use it to pin the self-signed certificate before joining.
class JamTlsIdentity {
  final Uint8List certificatePem;
  final Uint8List privateKeyPem;
  final String fingerprintSha256;

  const JamTlsIdentity._({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprintSha256,
  });

  static JamTlsIdentity generate({String commonName = 'CrotoLink'}) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': commonName},
      privateKey,
      publicKey,
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      1,
    );
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    final certificatePem = utf8.encode(certificate);

    return JamTlsIdentity._(
      certificatePem: Uint8List.fromList(certificatePem),
      privateKeyPem: Uint8List.fromList(utf8.encode(privateKeyPem)),
      fingerprintSha256: fingerprintForPem(certificate),
    );
  }

  static String fingerprintForPem(String pem) {
    final der = _derFromPem(pem);
    return crypto.sha256.convert(der).toString();
  }

  static String fingerprintForDer(List<int> der) =>
      crypto.sha256.convert(der).toString();

  static bool isValidFingerprint(String? fingerprint) =>
      fingerprint != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint);

  static List<int> _derFromPem(String pem) {
    final body = pem
        .split(RegExp(r'\r?\n'))
        .where((line) => !line.startsWith('---'))
        .join();
    return base64Decode(body);
  }
}
