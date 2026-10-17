import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/secure_storage.dart';
import 'package:crotowave/utils/signing_migration.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('crotowave-migration-');
    SecureStorage.inMemoryTestStore = {};
  });

  tearDown(() async {
    SecureStorage.inMemoryTestStore = null;
    await dir.delete(recursive: true);
  });

  File f(String name) => File('${dir.path}/$name');

  test('sin archivos de migración no toca nada', () async {
    SecureStorage.inMemoryTestStore!['k'] = 'v';
    await SigningMigration.run(dir);
    expect(dir.listSync(), isEmpty);
    expect(SecureStorage.inMemoryTestStore, {'k': 'v'});
  });

  test('con la petición, exporta el almacén y borra la petición', () async {
    SecureStorage.inMemoryTestStore!.addAll({'perfiles': '[]', 'sync': 'x'});
    await f(SigningMigration.exportRequest).create();
    await SigningMigration.run(dir);
    expect(f(SigningMigration.exportRequest).existsSync(), isFalse);
    expect(jsonDecode(f(SigningMigration.exportFile).readAsStringSync()),
        {'perfiles': '[]', 'sync': 'x'});
  });

  test('importa al almacén y borra el archivo con los secretos', () async {
    await f(SigningMigration.importFile)
        .writeAsString(jsonEncode({'perfiles': '[1]', 'sync': 'y'}));
    await SigningMigration.run(dir);
    expect(SecureStorage.inMemoryTestStore, {'perfiles': '[1]', 'sync': 'y'});
    expect(f(SigningMigration.importFile).existsSync(), isFalse);
  });

  test('un build normal no ejecuta la migración', () {
    expect(SigningMigration.enabled, isFalse);
  });
}
