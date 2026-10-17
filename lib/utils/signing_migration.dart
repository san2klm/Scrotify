import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/secure_storage.dart';

/// Pasa los datos de una instalación de Android a otra con distinta firma o
/// applicationId (ver docs/SIGNING.md y tool/migrate_android_signing.sh).
///
/// Los archivos de la app se copian con `run-as`, pero el almacén seguro
/// (perfiles de servidor, clave de sincronización…) está cifrado con claves
/// del Keystore de Android atadas a la instalación: copiarlo no sirve. Por eso,
/// solo en un build con `--dart-define=CROTOWAVE_SIGNING_MIGRATION=true`, al
/// arrancar la app:
///  - si existe [exportRequest], vuelca el almacén a [exportFile];
///  - si existe [importFile], lo escribe en el almacén y lo borra.
/// En los builds normales la constante es `false` y este código no se incluye.
class SigningMigration {
  static const enabled = bool.fromEnvironment('CROTOWAVE_SIGNING_MIGRATION');

  static const exportRequest = 'signing_migration.export';
  static const exportFile = 'signing_migration_export.json';
  static const importFile = 'signing_migration_import.json';

  static Future<void> maybeRun() async {
    if (!enabled) return;
    try {
      final dir = await getApplicationSupportDirectory();
      // `run-as` no entra si la carpeta de datos es legible por otros (una
      // restauración vieja la dejó en 755): solo la propia app puede cerrarla.
      if (Platform.isAndroid) {
        await Process.run('chmod', ['700', dir.parent.path]);
      }
      await run(dir);
    } catch (e) {
      debugPrint('SigningMigration: $e');
    }
  }

  @visibleForTesting
  static Future<void> run(Directory dir) async {
    final request = File('${dir.path}/$exportRequest');
    if (await request.exists()) {
      final all = await SecureStorage.secureReadAll();
      await File('${dir.path}/$exportFile')
          .writeAsString(jsonEncode(all), flush: true);
      await request.delete();
      debugPrint('SigningMigration: exportadas ${all.length} claves');
    }
    final import = File('${dir.path}/$importFile');
    if (await import.exists()) {
      final data = (jsonDecode(await import.readAsString()) as Map)
          .map((k, v) => MapEntry(k as String, v as String));
      for (final e in data.entries) {
        await SecureStorage.secureWrite(e.key, e.value);
      }
      await import.delete();
      debugPrint('SigningMigration: importadas ${data.length} claves');
    }
  }
}
