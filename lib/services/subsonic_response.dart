import 'dart:convert';

import 'package:http/http.dart' as http;

import 'diagnostics_log.dart' show redactSecrets;

/// Fallo de una petición Subsonic que SÍ llegó al servidor. Distinguirlos del
/// fallo de transporte (`SocketException`, `TimeoutException`...) evita tomar
/// una respuesta rechazada por un catálogo vacío.
sealed class SubsonicException implements Exception {
  const SubsonicException();
}

/// El servidor respondió con un HTTP que no es 2xx. Los 5xx son transitorios
/// (proxy caído, servidor arrancando) y se tratan como transporte.
class SubsonicHttpException extends SubsonicException {
  const SubsonicHttpException(this.statusCode);
  final int statusCode;
  bool get isTransient => statusCode >= 500;
  @override
  String toString() => 'El servidor respondió HTTP $statusCode.';
}

/// `status=failed` dentro de un envelope válido (credenciales, id inexistente...).
class SubsonicApiException extends SubsonicException {
  const SubsonicApiException(this.code, this.serverMessage);
  final int? code;
  final String? serverMessage;
  bool get isAuth => code == 40 || code == 41 || code == 42 || code == 44;

  /// [serverMessage] es texto del servidor y puede repetir datos de la petición
  /// (usuario, token): en credenciales rechazadas no se muestra y en el resto
  /// pasa por [redactSecrets] (el mensaje explica fallos de playlist, etc.).
  @override
  String toString() {
    if (isAuth) return 'El servidor rechazó las credenciales (código $code).';
    final message = serverMessage?.trim() ?? '';
    return 'El servidor rechazó la petición'
        '${code == null ? '' : ' (código $code)'}'
        '${message.isEmpty ? '' : ': ${redactSecrets(message)}'}.';
  }
}

/// Cuerpo que no es JSON o no trae un envelope `subsonic-response` utilizable.
class SubsonicFormatException extends SubsonicException {
  const SubsonicFormatException();
  @override
  String toString() => 'Respuesta del servidor ilegible (¿no es Navidrome?).';
}

/// Valida [response] y devuelve el contenido de `subsonic-response`.
///
/// Lanza [SubsonicHttpException], [SubsonicFormatException] o
/// [SubsonicApiException]. Un envelope sin `status` se acepta (servidores y
/// fixtures antiguos); con [requireOk] se exige `status == 'ok'`.
Map<String, dynamic> parseSubsonicEnvelope(http.Response response,
    {bool requireOk = false}) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw SubsonicHttpException(response.statusCode);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    throw const SubsonicFormatException();
  }
  final envelope = decoded is Map ? decoded['subsonic-response'] : null;
  if (envelope is! Map) throw const SubsonicFormatException();
  final status = envelope['status'];
  // Un status explícito distinto de ok/failed es una respuesta malformada. Solo
  // se tolera que falte (fixtures antiguos), y no cuando se exige `ok`.
  if ((status != null && status != 'ok' && status != 'failed') ||
      (requireOk && status == null)) {
    throw const SubsonicFormatException();
  }
  if (status == 'failed' || (requireOk && status != 'ok')) {
    final error = envelope['error'];
    final rawCode = error is Map ? error['code'] : null;
    throw SubsonicApiException(
      rawCode is num
          ? rawCode.toInt()
          : rawCode is String
              ? int.tryParse(rawCode)
              : null,
      error is Map ? error['message']?.toString() : null,
    );
  }
  return Map<String, dynamic>.from(envelope);
}

/// `true` para un error que merece un reintento acotado como si fuera de red.
bool isTransientServerError(Object error) =>
    error is SubsonicHttpException && error.isTransient;
