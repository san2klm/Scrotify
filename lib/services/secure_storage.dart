import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/dpapi.dart';

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
  /// Sustituye el almacén del sistema y el archivo de respaldo en pruebas.
  @visibleForTesting
  static SecureStorageBackend? backendOverride;

  @visibleForTesting
  static File? fallbackFileOverride;

  static SecureStorageBackend get _backend =>
      backendOverride ?? _FlutterBackend();

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
  static const _dpapiPrefix = 'dpapi:';
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
    final override = fallbackFileOverride;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fallbackFileName');
  }

  static Future<Map<String, String>> _loadFallback() async {
    try {
      final file = await _fallbackFile();
      if (!await file.exists()) return {};
      var raw = await file.readAsString();
      if (raw.isEmpty) return {};
      if (raw.startsWith(_dpapiPrefix)) {
        // Respaldo cifrado con DPAPI (Windows).
        final blob = base64Decode(raw.substring(_dpapiPrefix.length));
        raw = utf8.decode(Dpapi.unprotect(Uint8List.fromList(blob)));
      }
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
      // Crear vacío y restringir permisos ANTES de escribir secretos, para no
      // dejar una ventana con los permisos por defecto del umask.
      if (!await file.exists()) {
        await file.create();
        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['600', file.path]);
          } catch (e) {
            debugPrint(
                'SecureStorage: no se pudo restringir los permisos del archivo de respaldo: $e');
          }
        }
      }
      var contents = jsonEncode(data);
      if (Dpapi.isSupported) {
        // En Windows no hay `chmod`: el respaldo se cifra con DPAPI para que
        // solo este usuario pueda leerlo.
        final blob = Dpapi.protect(Uint8List.fromList(utf8.encode(contents)));
        contents = '$_dpapiPrefix${base64Encode(blob)}';
      }
      await file.writeAsString(contents, flush: true);
    } catch (e) {
      debugPrint('SecureStorage: no se pudo escribir fallback: $e');
    }
  }

  /// Almacén en memoria exclusivo para pruebas unitarias e instrumentadas.
  @visibleForTesting
  static Map<String, String>? inMemoryTestStore;

  static Future<String?> secureRead(String key) async {
    if (inMemoryTestStore != null) {
      return inMemoryTestStore![key];
    }
    try {
      final value = await _backend.read(key);
      // Si el keyring responde, úsalo. Si está vacío, mira también
      // el fallback (por si se guardó antes sin keyring).
      if (value != null) {
        await _dropFromFallback(key); // migración: ya no hace falta el respaldo
        return value;
      }
      final fallback = await _loadFallback();
      return fallback[key];
    } catch (e) {
      _noteFallback(e);
      final fallback = await _loadFallback();
      return fallback[key];
    }
  }

  static Future<void> secureWrite(String key, String value) async {
    if (inMemoryTestStore != null) {
      inMemoryTestStore![key] = value;
      return;
    }
    try {
      await _backend.write(key, value);
      // El keyring funciona: el respaldo en disco ya no debe guardar el secreto.
      await _dropFromFallback(key);
    } catch (e) {
      _noteFallback(e);
      final fallback = await _loadFallback();
      fallback[key] = value;
      await _saveFallback(fallback);
    }
  }

  static Future<void> secureDelete(String key) async {
    if (inMemoryTestStore != null) {
      inMemoryTestStore!.remove(key);
      return;
    }
    try {
      await _backend.delete(key);
    } catch (e) {
      _noteFallback(e);
    }
    // Mantener el fallback sincronizado en ambos casos.
    try {
      final fallback = await _loadFallback();
      if (fallback.remove(key) != null) {
        await _saveFallback(fallback);
      }
    } catch (e) {
      debugPrint(
          'SecureStorage: no se pudo actualizar el respaldo al borrar una clave: $e');
    }
  }

  /// Quita [key] del archivo de respaldo y lo borra si queda vacío.
  static Future<void> _dropFromFallback(String key) async {
    try {
      final file = await _fallbackFile();
      if (!await file.exists()) return;
      final fallback = await _loadFallback();
      if (fallback.remove(key) == null) return;
      if (fallback.isEmpty) {
        await file.delete();
      } else {
        await _saveFallback(fallback);
      }
    } catch (e) {
      debugPrint('SecureStorage: no se pudo limpiar el respaldo: $e');
    }
  }

  /// Guarda las credenciales completas.
  static Future<void> saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    // Secuencial a propósito: con Future.wait un fallo de libsecret
    // cancelaba las otras escrituras y dejaba estado parcial.
    await secureWrite(_kServerUrl, serverUrl);
    await secureWrite(_kUsername, username);
    await secureWrite(_kPassword, password);
    await secureWrite(_kHasCredentials, 'true');
  }

  /// Lee la URL del servidor guardada.
  static Future<String?> getServerUrl() => secureRead(_kServerUrl);

  /// Lee el usuario guardado.
  static Future<String?> getUsername() => secureRead(_kUsername);

  /// Lee la contraseña guardada.
  static Future<String?> getPassword() => secureRead(_kPassword);

  /// Devuelve `true` si hay credenciales guardadas.
  static Future<bool> hasCredentials() async {
    final v = await secureRead(_kHasCredentials);
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
    await secureDelete(_kServerUrl);
    await secureDelete(_kUsername);
    await secureDelete(_kPassword);
    await secureDelete(_kHasCredentials);
  }

  /// Lee todas las credenciales de una vez (para auto-login).
  static Future<
      ({
        String? serverUrl,
        String? username,
        String? password,
      })> getAll() async {
    final serverUrl = await secureRead(_kServerUrl);
    final username = await secureRead(_kUsername);
    final password = await secureRead(_kPassword);
    return (
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }
}

/// Almacén seguro del sistema (keyring / Keychain / Credential Locker).
abstract class SecureStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _FlutterBackend implements SecureStorageBackend {
  @override
  Future<String?> read(String key) => SecureStorage._storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      SecureStorage._storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => SecureStorage._storage.delete(key: key);
}
