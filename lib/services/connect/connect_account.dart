import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:cryptography/cryptography.dart';

import '../sync/sync_crypto.dart';

/// Cuenta de Navidrome con la que se identifica Connect: los dispositivos con
/// el mismo usuario se ven entre sí y solo entre sí.
///
/// - Ante el servidor CrotoLink se prueba con el token de Subsonic
///   (`md5(clave + salt)`); el servidor lo verifica con Navidrome y nunca
///   recibe la clave.
/// - Los mensajes se cifran de extremo a extremo con una clave derivada de la
///   clave del usuario (PBKDF2), que el servidor no conoce.
class ConnectAccount {
  const ConnectAccount({required this.user, required this.password});

  final String user;
  final String password;

  static const _iterations = 100000;
  static final _derived = <String, Future<SyncCrypto>>{};

  String get _normalizedUser => user.trim().toLowerCase();

  /// Token y salt nuevos para una conexión.
  ({String token, String salt}) authToken([Random? random]) {
    final rng = random ?? Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final salt =
        List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
    return (
      token: md5.convert(utf8.encode('$password$salt')).toString(),
      salt: salt
    );
  }

  /// Claves de cifrado de la cuenta. El resultado se guarda en memoria: el
  /// estirado de la clave es costoso y solo cambia si cambian usuario o clave.
  Future<SyncCrypto> deriveCrypto() => _derived.putIfAbsent(
        '$_normalizedUser\n$password',
        () => _stretch(_normalizedUser, password).then(SyncCrypto.fromSecret),
      );

  static Future<Uint8List> _stretch(String user, String password) =>
      Isolate.run(() async {
        final key = await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: _iterations,
          bits: 256,
        ).deriveKeyFromPassword(
          password: password,
          nonce: utf8.encode('crotowave-connect-v1|$user'),
        );
        return Uint8List.fromList(await key.extractBytes());
      });
}
