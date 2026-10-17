import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Prueba de que quien responde conoce el código de emparejamiento, sin que
/// el código viaje por la red: `HMAC-SHA256(clave = código, "crotowave-pair|" + nonce)`.
///
/// El móvil manda un `nonce` aleatorio en el `find`; solo el PC que tiene el
/// código puede devolver una prueba válida. Así el código no se entrega a
/// quien responda primero por UDP.
String pairingProof(String code, String nonce) {
  final mac = Hmac(sha256, utf8.encode(code.toUpperCase()));
  return mac.convert(utf8.encode('crotowave-pair|$nonce')).toString();
}

/// Comparación en tiempo constante de dos pruebas.
bool pairingProofEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
