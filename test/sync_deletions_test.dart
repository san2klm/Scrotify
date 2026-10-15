import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/sync/sync_crypto.dart';
import 'package:navidrome_client/services/sync/sync_service.dart';
import 'package:path/path.dart' as p;

import 'sync_service_test.dart' show Device, FakeVault, fullSync;

/// Un tema importado (un .zip cualquiera con contenido reconocible).
Uint8List zip(int seed) => Uint8List.fromList([80, 75, 3, 4, seed, seed, seed]);

void main() {
  late Directory tmp;
  late FakeVault vault;
  late String key;
  late SyncCrypto crypto;
  late DateTime clock;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sync_del');
    vault = FakeVault();
    final secret = SyncKey.generate();
    key = SyncKey.format(secret);
    crypto = await SyncCrypto.fromSecret(secret);
    clock = DateTime.now();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Device device(String name) =>
      Device(vault, Directory(p.join(tmp.path, name))..createSync(),
          now: () => clock);

  Future<void> link(Device d) async {
    expect(await d.service.link(key), isTrue);
    while (d.service.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await fullSync(d.service);
  }

  File theme(Device d, String name) => File(p.join(d.themes.path, name));
  void addTheme(Device d, String name, int seed) =>
      theme(d, name).writeAsBytesSync(zip(seed));
  Directory trash(Device d) => Directory(p.join(d.data.path, 'sync_trash'));

  /// Dos ciclos: el primero ve el archivo ausente, el segundo lo confirma.
  Future<void> confirmedSync(Device d) async {
    await fullSync(d.service);
    await fullSync(d.service);
  }

  Future<String> tombstoneKeyOf(String name) async =>
      SyncService.tombstoneKey(await crypto.docKey(name));

  group('borrar un tema', () {
    test('se propaga al otro dispositivo, que lo manda a la papelera',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final b = device('b');
      await link(b);
      expect(theme(b, 'Mi Tema.zip').existsSync(), isTrue);

      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      b.applied.clear();
      await fullSync(b.service);

      expect(theme(b, 'Mi Tema.zip').existsSync(), isFalse);
      expect(b.applied, contains('Mi Tema.zip'),
          reason: 'avisa para que la app recargue los temas');
      final saved = trash(b).listSync().whereType<File>().toList();
      expect(saved, hasLength(1));
      expect(saved.single.path, endsWith('Mi Tema.zip'));
      expect(saved.single.readAsBytesSync(), zip(1));
    });

    test('tras purgar el aviso, un dispositivo atrasado no resucita el tema',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final b = device('b');
      await link(b);
      final docKey = await crypto.docKey('Mi Tema.zip');

      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      // El servidor purga el aviso antes de que b (sin conexión) lo vea.
      vault.docs.remove(await tombstoneKeyOf('Mi Tema.zip'));
      expect(vault.docs.containsKey(docKey), isFalse);

      await fullSync(b.service);
      await fullSync(b.service);
      expect(vault.docs.containsKey(docKey), isFalse,
          reason: 'no se vuelve a subir');
    });

    test('no resucita en el dispositivo que lo borró', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      await fullSync(a.service);
      await fullSync(a.service);
      expect(theme(a, 'Mi Tema.zip').existsSync(), isFalse);
    });

    test('el servidor guarda un aviso cifrado y libera el tema', () async {
      final a = device('a');
      addTheme(a, 'Secreto Rosa.zip', 1);
      await link(a);
      final docKey = await crypto.docKey('Secreto Rosa.zip');
      expect(vault.docs.containsKey(docKey), isTrue);

      theme(a, 'Secreto Rosa.zip').deleteSync();
      await confirmedSync(a);

      expect(vault.docs.containsKey(docKey), isFalse);
      final tomb = vault.docs[await tombstoneKeyOf('Secreto Rosa.zip')];
      expect(tomb, isNotNull);
      expect(jsonEncode(vault.docs), isNot(contains('Secreto')));
    });

    test('un solo ciclo ausente no basta: protege de estados transitorios',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final bytes = theme(a, 'Mi Tema.zip').readAsBytesSync();
      theme(a, 'Mi Tema.zip').deleteSync();

      await fullSync(a.service); // lo ve ausente por primera vez
      expect(
          vault.docs.containsKey(await tombstoneKeyOf('Mi Tema.zip')), isFalse);

      theme(a, 'Mi Tema.zip').writeAsBytesSync(bytes); // era transitorio
      await confirmedSync(a);
      expect(
          vault.docs.containsKey(await tombstoneKeyOf('Mi Tema.zip')), isFalse);
      expect(theme(a, 'Mi Tema.zip').existsSync(), isTrue);
    });

    test('si reaparece tras verlo ausente se olvida la sospecha', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final bytes = theme(a, 'Mi Tema.zip').readAsBytesSync();
      theme(a, 'Mi Tema.zip').deleteSync();
      await fullSync(a.service); // 1.ª vez ausente
      theme(a, 'Mi Tema.zip').writeAsBytesSync(bytes);
      await fullSync(a.service); // vuelve: se limpia
      theme(a, 'Mi Tema.zip').deleteSync();
      await fullSync(a.service); // otra vez es la 1.ª
      expect(
          vault.docs.containsKey(await tombstoneKeyOf('Mi Tema.zip')), isFalse);
    });
  });

  group('lo editado gana al borrado', () {
    test('un dispositivo que cambió el tema lo conserva y lo devuelve',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final b = device('b');
      await link(b);

      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      // b lo había editado antes de enterarse del borrado.
      theme(b, 'Mi Tema.zip').writeAsBytesSync(zip(9));
      await fullSync(b.service);
      await fullSync(a.service);

      expect(theme(b, 'Mi Tema.zip').readAsBytesSync(), zip(9));
      expect(theme(a, 'Mi Tema.zip').existsSync(), isTrue);
      expect(theme(a, 'Mi Tema.zip').readAsBytesSync(), zip(9));
    });

    test('volver a importar el mismo nombre tras borrarlo llega a todos',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final b = device('b');
      await link(b);

      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      await fullSync(b.service);
      expect(theme(b, 'Mi Tema.zip').existsSync(), isFalse);

      addTheme(a, 'Mi Tema.zip', 5); // se importa otro con el mismo nombre
      await fullSync(a.service);
      await fullSync(b.service);

      expect(theme(b, 'Mi Tema.zip').readAsBytesSync(), zip(5));
      expect(theme(a, 'Mi Tema.zip').readAsBytesSync(), zip(5));
    });

    test('un dispositivo que nunca sincronizó ese tema no lo pierde', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);

      final c = device('c');
      addTheme(c, 'Mi Tema.zip', 7); // lo tenía antes de vincularse
      await link(c);

      expect(theme(c, 'Mi Tema.zip').readAsBytesSync(), zip(7));
    });
  });

  group('seguridad', () {
    test('borrados masivos de golpe no se propagan y se restauran', () async {
      final a = device('a');
      for (var i = 0; i < 6; i++) {
        addTheme(a, 'Tema $i.zip', i + 1);
      }
      await link(a);
      for (var i = 0; i < 6; i++) {
        theme(a, 'Tema $i.zip').deleteSync();
      }
      await fullSync(a.service);

      expect(a.service.error, contains('borrados de golpe'),
          reason: 'se avisa al usuario');
      for (var i = 0; i < 6; i++) {
        expect(theme(a, 'Tema $i.zip').readAsBytesSync(), zip(i + 1),
            reason: 'se recuperan del servidor');
        expect(vault.docs.containsKey(await tombstoneKeyOf('Tema $i.zip')),
            isFalse,
            reason: 'ningún aviso de borrado');
      }
      await confirmedSync(a);
      expect(a.service.error, isNull, reason: 'el aviso no es permanente');
      expect(vault.docs.keys.where((k) => k.startsWith('x-')), isEmpty);
    });

    test('borrar pocos temas sí se propaga aunque sean varios', () async {
      final a = device('a');
      for (var i = 0; i < 6; i++) {
        addTheme(a, 'Tema $i.zip', i + 1);
      }
      await link(a);
      for (var i = 0; i < 2; i++) {
        theme(a, 'Tema $i.zip').deleteSync();
      }
      await confirmedSync(a);
      for (var i = 0; i < 2; i++) {
        expect(vault.docs.containsKey(await tombstoneKeyOf('Tema $i.zip')),
            isTrue);
      }
      expect(
          vault.docs.containsKey(await tombstoneKeyOf('Tema 5.zip')), isFalse);
    });

    test('si la carpeta de temas no existe no se infiere ningún borrado',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      a.themes.deleteSync(recursive: true);
      await confirmedSync(a);
      expect(
          vault.docs.containsKey(await tombstoneKeyOf('Mi Tema.zip')), isFalse);
    });

    test('los documentos JSON nunca se borran por sincronización', () async {
      final a = device('a');
      a.write('followed_artists_srv_x.json', '["1"]');
      await link(a);
      final b = device('b');
      await link(b);

      a.file('followed_artists_srv_x.json').deleteSync();
      await confirmedSync(a);
      await fullSync(b.service);

      expect(b.file('followed_artists_srv_x.json').existsSync(), isTrue);
      expect(a.file('followed_artists_srv_x.json').existsSync(), isTrue,
          reason: 'a lo recupera');
      expect(vault.docs.keys.where((k) => k.startsWith('x-')), isEmpty);
    });

    test('un aviso falso o ilegible no borra nada', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final b = device('b');
      await link(b);

      final docKey = await crypto.docKey('Mi Tema.zip');
      final bogus = SyncService.tombstoneKey(docKey);
      vault.docs[bogus] = {
        'key': bogus,
        'updatedAt': DateTime.now().millisecondsSinceEpoch + 5000,
        'blob': base64.encode(List.filled(60, 3)),
      };
      await fullSync(b.service);
      expect(theme(b, 'Mi Tema.zip').existsSync(), isTrue);
    });

    test('un aviso válido de otro tema no borra este', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      addTheme(a, 'Otro.zip', 2);
      await link(a);
      final b = device('b');
      await link(b);

      // Aviso auténtico (mismo cifrado) pero que dice borrar "Otro.zip",
      // colocado bajo la clave de "Mi Tema.zip".
      final docKey = await crypto.docKey('Mi Tema.zip');
      final tombKey = SyncService.tombstoneKey(docKey);
      final wrong = await crypto.encrypt(
          utf8.encode(jsonEncode(
              {'name': 'Otro.zip.deleted', 'deleted': 'Otro.zip', 'data': ''})),
          docKey: tombKey);
      vault.docs[tombKey] = {
        'key': tombKey,
        'updatedAt': DateTime.now().millisecondsSinceEpoch + 5000,
        'blob': wrong,
      };
      await fullSync(b.service);
      expect(theme(b, 'Mi Tema.zip').existsSync(), isTrue);
    });

    test('un cliente sin esta función nunca crearía un archivo con el aviso',
        () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);

      final tomb = vault.docs[await tombstoneKeyOf('Mi Tema.zip')]!;
      final envelope = jsonDecode(utf8.decode(await crypto.decrypt(
          tomb['blob'] as String,
          docKey: tomb['key'] as String))) as Map<String, dynamic>;
      // Su nombre no es .json de la lista ni termina en .zip: un cliente
      // antiguo lo descarta en vez de escribir un archivo vacío.
      final name = envelope['name'] as String;
      expect(name.toLowerCase().endsWith('.zip'), isFalse);
      expect(SyncService.syncedFile.hasMatch(name), isFalse);
    });
  });

  group('papelera y limpieza', () {
    test('la papelera conserva 30 días y luego se vacía', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      final b = device('b');
      await link(b);
      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      await fullSync(b.service);
      expect(trash(b).listSync(), hasLength(1));

      clock = clock.add(const Duration(days: 29));
      await fullSync(b.service);
      expect(trash(b).listSync(), hasLength(1));

      clock = clock.add(const Duration(days: 2));
      await fullSync(b.service);
      expect(trash(b).listSync(), isEmpty);
    });

    test('los avisos de más de 30 días se eliminan del servidor', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      final tombKey = await tombstoneKeyOf('Mi Tema.zip');
      expect(vault.docs.containsKey(tombKey), isTrue);

      clock = clock.add(const Duration(days: 31));
      await fullSync(a.service);
      expect(vault.docs.containsKey(tombKey), isFalse);
      expect(vault.deleted, contains(tombKey));
    });

    test('un aviso reciente no se elimina', () async {
      final a = device('a');
      addTheme(a, 'Mi Tema.zip', 1);
      await link(a);
      theme(a, 'Mi Tema.zip').deleteSync();
      await confirmedSync(a);
      clock = clock.add(const Duration(days: 10));
      await fullSync(a.service);
      expect(
          vault.docs.containsKey(await tombstoneKeyOf('Mi Tema.zip')), isTrue);
    });
  });
}
