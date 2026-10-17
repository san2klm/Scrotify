import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Clave de sincronización: 256 bits aleatorios que el usuario copia o escanea
/// en cada dispositivo. Se escribe en base32 agrupado (`ABCD-EFGH-…`).
class SyncKey {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const _bytes = 32;

  static Uint8List generate([Random? random]) {
    final rng = random ?? Random.secure();
    return Uint8List.fromList(List.generate(_bytes, (_) => rng.nextInt(256)));
  }

  static String format(Uint8List secret) {
    var bits = 0;
    var value = 0;
    final out = StringBuffer();
    for (final byte in secret) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
      value &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(value << (5 - bits)) & 31]);
    final raw = out.toString();
    return [
      for (var i = 0; i < raw.length; i += 4)
        raw.substring(i, min(i + 4, raw.length)),
    ].join('-');
  }

  /// Devuelve `null` si el texto no es una clave válida.
  static Uint8List? parse(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (clean.length != 52) return null;
    var bits = 0;
    var value = 0;
    final out = <int>[];
    for (final unit in clean.codeUnits) {
      final index = _alphabet.indexOf(String.fromCharCode(unit));
      if (index < 0) return null;
      value = (value << 5) | index;
      bits += 5;
      if (bits >= 8) {
        out.add((value >> (bits - 8)) & 255);
        bits -= 8;
        value &= (1 << bits) - 1;
      }
    }
    return out.length == _bytes ? Uint8List.fromList(out) : null;
  }
}

/// Deriva de la clave tres valores independientes: identificador de bóveda,
/// credencial de acceso y clave de cifrado. El servidor solo conoce los dos
/// primeros; nunca puede descifrar los documentos.
class SyncCrypto {
  SyncCrypto._(this.vaultId, this.authToken, this._cipherKey);

  static const _version = 1;
  static final _aes = AesGcm.with256bits();

  final String vaultId;
  final String authToken;
  final SecretKey _cipherKey;

  static Future<SyncCrypto> fromSecret(Uint8List secret) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final root = SecretKey(secret);
    Future<List<int>> derive(String label) async => (await hkdf.deriveKey(
          secretKey: root,
          nonce: utf8.encode('crotowave-sync-v1'),
          info: utf8.encode(label),
        ))
            .extractBytes();
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return SyncCrypto._(
      hex(await derive('vault')),
      hex(await derive('auth')),
      SecretKey(await derive('enc')),
    );
  }

  /// Identificador opaco de un documento (`d-` + HMAC del nombre): el servidor
  /// no llega a ver nombres de archivo ni identificadores de servidor/usuario.
  Future<String> docKey(String name) async {
    final mac = await Hmac.sha256()
        .calculateMac(utf8.encode(name), secretKey: _cipherKey);
    return 'd-${mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 32)}';
  }

  /// `base64(versión || nonce || cifrado || mac)`; el nombre del documento
  /// va autenticado, así que el servidor no puede cambiar un blob de sitio.
  Future<String> encrypt(List<int> plain, {required String docKey}) async {
    final box = await _aes.encrypt(plain,
        secretKey: _cipherKey, aad: utf8.encode(docKey));
    return base64.encode([_version, ...box.concatenation()]);
  }

  /// Lanza [FormatException] si el blob está corrupto, es de otra clave o
  /// pertenece a otro documento.
  Future<List<int>> decrypt(String blob, {required String docKey}) async {
    try {
      final bytes = base64.decode(blob);
      if (bytes.isEmpty || bytes.first != _version) {
        throw const FormatException('Versión de cifrado desconocida');
      }
      final box = SecretBox.fromConcatenation(bytes.sublist(1),
          nonceLength: 12, macLength: 16);
      return await _aes.decrypt(box,
          secretKey: _cipherKey, aad: utf8.encode(docKey));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('No se pudo descifrar el documento');
    }
  }
}
