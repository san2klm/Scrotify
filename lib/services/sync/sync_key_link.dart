import 'sync_crypto.dart';

/// Enlace `crotowave-sync://<clave>` para pasar la clave de sincronización de
/// un dispositivo a otro con un código QR, sin teclearla.
///
/// Es un secreto: quien lo lea puede descifrar lo sincronizado. Solo se genera
/// a petición expresa del usuario y nunca se escribe en registros.
class SyncKeyLink {
  static const scheme = 'crotowave-sync://';

  /// `true` si [text] parece un enlace de sincronización (antes de validarlo).
  static bool isSyncLink(String text) {
    final t = text.trim().toLowerCase();
    return t.startsWith(scheme);
  }

  /// Enlace para [keyText], o `null` si no es una clave válida.
  static String? build(String keyText) {
    final secret = SyncKey.parse(keyText);
    return secret == null ? null : '$scheme${SyncKey.format(secret)}';
  }

  /// Clave canónica contenida en [input], o `null`. Admite el enlace completo
  /// o la clave sola; rechaza cualquier otro esquema y todo lo que sobre.
  static String? parse(String input) {
    var text = input.trim();
    if (text.contains('://')) {
      if (!isSyncLink(text)) return null;
      text = text.substring(text.indexOf('://') + 3);
    }
    final secret = SyncKey.parse(text);
    return secret == null ? null : SyncKey.format(secret);
  }
}
