import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/secure_storage.dart';

class _MemoryBackend implements SecureStorageBackend {
  final data = <String, String>{};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) throw PlatformException(code: 'libsecret');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (broken) throw PlatformException(code: 'libsecret');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (broken) throw PlatformException(code: 'libsecret');
    data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late File fallback;
  late _MemoryBackend backend;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scrotify-secure-');
    fallback = File('${tmp.path}/fallback.json');
    backend = _MemoryBackend();
    SecureStorage.backendOverride = backend;
    SecureStorage.fallbackFileOverride = fallback;
  });

  tearDown(() async {
    SecureStorage.backendOverride = null;
    SecureStorage.fallbackFileOverride = null;
    await tmp.delete(recursive: true);
  });

  test('con el keyring roto, el secreto va al respaldo y se lee de vuelta',
      () async {
    backend.broken = true;
    await SecureStorage.secureWrite('k', 'secreto');
    expect(await fallback.exists(), isTrue);
    // En disco no queda en claro (DPAPI en Windows).
    if (Platform.isWindows) {
      expect(await fallback.readAsString(), isNot(contains('secreto')));
    }
    expect(await SecureStorage.secureRead('k'), 'secreto');
  });

  test('keyring recuperado + respaldo presente: la escritura borra el respaldo',
      () async {
    backend.broken = true;
    await SecureStorage.secureWrite('k', 'v1');
    expect(await fallback.exists(), isTrue);

    backend.broken = false;
    await SecureStorage.secureWrite('k', 'v2');
    expect(backend.data['k'], 'v2');
    expect(await fallback.exists(), isFalse);
  });

  test('un respaldo en claro heredado se lee y se migra al leer con keyring',
      () async {
    await fallback.writeAsString(jsonEncode({'k': 'viejo'}));
    backend.data['k'] = 'nuevo';
    expect(await SecureStorage.secureRead('k'), 'nuevo');
    expect(await fallback.exists(), isFalse);
  });
}
