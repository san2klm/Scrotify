import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Wrapper tipado sobre `flutter_secure_storage` para credenciales de Navidrome.
///
/// En Linux `flutter_secure_storage` usa libsecret y necesita el servicio
/// D-Bus `org.freedesktop.secrets` (gnome-keyring, oo7, KWallet con Secret
/// Service, ...). Si no existe, libsecret lanza:
/// `PlatformException(Libsecret error, secret_service_get_sync:
/// The name is not activatable, null, null)`.
///
/// Para que la app no se caiga en esos equipos, cada operación intenta
/// primero el almacenamiento seguro y, si falla, usa un archivo local de
/// respaldo (`fallback`) con permisos 600. Es menos seguro que el keyring,
/// pero evita el crash y permite seguir usando la app.
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: LinuxOptions(),
  );

  // Claves de almacenamiento
  static const _kServerUrl = 'scrotify.server_url';
  static const _kUsername = 'scrotify.username';
  static const _kPassword = 'scrotify.password';
  static const _kHasCredentials = 'scrotify.has_credentials';

  static const _fallbackFileName = 'scrotify_credentials_fallback.json';
  static bool _fallbackWarned = false;

  /// `true` si ya tuvimos que usar el archivo de respaldo (keyring no usable).
  static bool get usingFallback => _fallbackWarned;

  static void _noteFallback(Object e) {
    if (_fallbackWarned) return;
    _fallbackWarned = true;
    debugPrint(
      'SecureStorage: Secret Service no disponible ($e). '
      'Usando archivo local de respaldo. Instala oo7 o gnome-keyring '
      'para usar el keyring del sistema.',
    );
  }

  static Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fallbackFileName');
  }

  static Future<Map<String, String>> _loadFallback() async {
    try {
      final file = await _fallbackFile();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveFallback(Map<String, String> data) async {
    try {
      final file = await _fallbackFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data), flush: true);
      // Solo el usuario puede leerlo (mejor que nada si no hay keyring).
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {
        // Windows / plataformas sin chmod: ignorar.
      }
    } catch (e) {
      debugPrint('SecureStorage: no se pudo escribir fallback: $e');
    }
  }

  static Future<String?> _secureRead(String key) async {
    try {
      final value = await _storage.read(key: key);
      // Si el keyring responde, úsalo. Si está vacío, mira también
      // el fallback (por si se guardó antes sin keyring).
      if (value != null) return value;
      final fallback = await _loadFallback();
      return fallback[key];
    } catch (e) {
      _noteFallback(e);
      final fallback = await _loadFallback();
      return fallback[key];
    }
  }

  static Future<void> _secureWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _noteFallback(e);
      final fallback = await _loadFallback();
      fallback[key] = value;
      await _saveFallback(fallback);
    }
  }

  static Future<void> _secureDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      _noteFallback(e);
    }
    // Mantener el fallback sincronizado en ambos casos.
    try {
      final fallback = await _loadFallback();
      if (fallback.remove(key) != null) {
        await _saveFallback(fallback);
      }
    } catch (_) {}
  }

  /// Guarda las credenciales completas.
  static Future<void> saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    // Secuencial a propósito: con Future.wait un fallo de libsecret
    // cancelaba las otras escrituras y dejaba estado parcial.
    await _secureWrite(_kServerUrl, serverUrl);
    await _secureWrite(_kUsername, username);
    await _secureWrite(_kPassword, password);
    await _secureWrite(_kHasCredentials, 'true');
  }

  /// Lee la URL del servidor guardada.
  static Future<String?> getServerUrl() => _secureRead(_kServerUrl);

  /// Lee el usuario guardado.
  static Future<String?> getUsername() => _secureRead(_kUsername);

  /// Lee la contraseña guardada.
  static Future<String?> getPassword() => _secureRead(_kPassword);

  /// Devuelve `true` si hay credenciales guardadas.
  static Future<bool> hasCredentials() async {
    final v = await _secureRead(_kHasCredentials);
    if (v == 'true') return true;
    // Compatibilidad: si existen las 3 piezas, hay sesión aunque
    // falte el flag (p. ej. guardado parcial anterior).
    final creds = await getAll();
    return creds.serverUrl != null &&
        creds.username != null &&
        creds.password != null;
  }

  /// Borra todas las credenciales (logout).
  static Future<void> clearCredentials() async {
    await _secureDelete(_kServerUrl);
    await _secureDelete(_kUsername);
    await _secureDelete(_kPassword);
    await _secureDelete(_kHasCredentials);
  }

  /// Lee todas las credenciales de una vez (para auto-login).
  static Future<({
    String? serverUrl,
    String? username,
    String? password,
  })> getAll() async {
    final serverUrl = await _secureRead(_kServerUrl);
    final username = await _secureRead(_kUsername);
    final password = await _secureRead(_kPassword);
    return (
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }
}