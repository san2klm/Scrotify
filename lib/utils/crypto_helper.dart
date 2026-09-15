import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Genera un par de claves X25519 efímero.
Future<SimpleKeyPair> generateKeyPair() async {
  return X25519().newKeyPair();
}

/// Extrae la clave pública en bytes (32 bytes, formato raw).
Future<Uint8List> extractPublicKeyBytes(SimpleKeyPair keyPair) async {
  final publicKey = await keyPair.extractPublicKey();
  return Uint8List.fromList(publicKey.bytes);
}

/// Exporta clave pública a base64url (seguro para JSON/URL).
String publicKeyToBase64(Uint8List bytes) => base64Url.encode(bytes);

/// Importa clave pública desde base64url.
Future<SimplePublicKey> publicKeyFromBase64(String b64) async {
  return SimplePublicKey(base64Url.decode(b64), type: KeyPairType.x25519);
}

/// Cifra datos con "sealed box" NaCl:
/// - Deriva clave compartida X25519 entre `ephemeralKeyPair` (PC) y `recipientPublicKey` (móvil)
/// - Cifra con XChaCha20-Poly1305 (AEAD)
/// Retorna mapa JSON-serializable: { ephemeralPublicKey, nonce, ciphertext, mac }
Future<Map<String, String>> sealEncrypt({
  required SimpleKeyPair ephemeralKeyPair,
  required SimplePublicKey recipientPublicKey,
  required Uint8List plaintext,
}) async {
  // 1. Derivar clave secreta compartida
  final sharedSecret = await X25519().sharedSecretKey(
    keyPair: ephemeralKeyPair,
    remotePublicKey: recipientPublicKey,
  );

  // 2. Cifrar con XChaCha20-Poly1305
  final cipher = Xchacha20.poly1305Aead();
  final secretBox = await cipher.encrypt(
    plaintext,
    secretKey: sharedSecret,
  );

  // 3. Extraer clave pública efímera para que el receptor pueda derivar la misma clave
  final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();
  final ephemeralBytes = Uint8List.fromList(ephemeralPublicKey.bytes);

  return {
    'ephemeralPublicKey': base64Url.encode(ephemeralBytes),
    'nonce': base64Url.encode(secretBox.nonce),
    'ciphertext': base64Url.encode(secretBox.cipherText),
    'mac': base64Url.encode(secretBox.mac.bytes),
  };
}

/// Descifra datos "sealed box" NaCl:
/// - Deriva la misma clave compartida con `recipientKeyPair` (móvil) y `ephemeralPublicKey` (del PC)
/// - Descifra con XChaCha20-Poly1305
Future<List<int>> sealDecrypt({
  required SimpleKeyPair recipientKeyPair,
  required String ephemeralPublicKeyB64,
  required String nonceB64,
  required String ciphertextB64,
  required String macB64,
}) async {
  // 1. Reconstruir clave pública efímera del PC
  final ephemeralPublicKey = SimplePublicKey(
    base64Url.decode(ephemeralPublicKeyB64),
    type: KeyPairType.x25519,
  );

  // 2. Derivar clave secreta compartida (igual que en el PC)
  final sharedSecret = await X25519().sharedSecretKey(
    keyPair: recipientKeyPair,
    remotePublicKey: ephemeralPublicKey,
  );

  // 3. Reconstruir SecretBox y descifrar
  final cipher = Xchacha20.poly1305Aead();
  final secretBox = SecretBox(
    base64Url.decode(ciphertextB64),
    nonce: base64Url.decode(nonceB64),
    mac: Mac(base64Url.decode(macB64)),
  );

  return cipher.decrypt(secretBox, secretKey: sharedSecret);
}

/// Helper para codificar/decodificar UTF-8 + base64url
String encodeUtf8(String s) => base64Url.encode(utf8.encode(s));
String decodeUtf8(String b64) => utf8.decode(base64Url.decode(b64));