import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper tipado sobre `flutter_secure_storage` para credenciales de Navidrome.
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

  /// Guarda las credenciales completas.
  static Future<void> saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    await Future.wait([
      _storage.write(key: _kServerUrl, value: serverUrl),
      _storage.write(key: _kUsername, value: username),
      _storage.write(key: _kPassword, value: password),
      _storage.write(key: _kHasCredentials, value: 'true'),
    ]);
  }

  /// Lee la URL del servidor guardada.
  static Future<String?> getServerUrl() => _storage.read(key: _kServerUrl);

  /// Lee el usuario guardado.
  static Future<String?> getUsername() => _storage.read(key: _kUsername);

  /// Lee la contraseña guardada.
  static Future<String?> getPassword() => _storage.read(key: _kPassword);

  /// Devuelve `true` si hay credenciales guardadas.
  static Future<bool> hasCredentials() async {
    final v = await _storage.read(key: _kHasCredentials);
    return v == 'true';
  }

  /// Borra todas las credenciales (logout).
  static Future<void> clearCredentials() async {
    await Future.wait([
      _storage.delete(key: _kServerUrl),
      _storage.delete(key: _kUsername),
      _storage.delete(key: _kPassword),
      _storage.delete(key: _kHasCredentials),
    ]);
  }

  /// Lee todas las credenciales de una vez (para auto-login).
  static Future<({
    String? serverUrl,
    String? username,
    String? password,
  })> getAll() async {
    final results = await Future.wait([
      _storage.read(key: _kServerUrl),
      _storage.read(key: _kUsername),
      _storage.read(key: _kPassword),
    ]);
    return (
      serverUrl: results[0],
      username: results[1],
      password: results[2],
    );
  }
}