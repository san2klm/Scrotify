import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navidrome_client/services/sync/sync_crypto.dart';
import 'package:navidrome_client/services/sync/sync_service.dart';
import 'package:path/path.dart' as p;

/// Servidor Jam mínimo en memoria con el mismo contrato que `/api/sync/v1`.
class FakeVault {
  final docs = <String, Map<String, dynamic>>{};
  String? token;
  bool enabled = true;

  http.Client get client => MockClient((request) async {
        if (!enabled) return http.Response('{}', 403);
        final auth = request.headers['authorization'];
        if (token != null && auth != 'Bearer $token') {
          return http.Response('{}', 401);
        }
        final parts = request.url.pathSegments;
        final key = parts.length > 4 ? parts[4] : null;
        if (request.method == 'GET' && key == null) {
          if (token == null) return http.Response('{}', 404);
          return http.Response(
              jsonEncode({
                'docs': [
                  for (final e in docs.entries)
                    {'key': e.key, 'updatedAt': e.value['updatedAt']}
                ]
              }),
              200);
        }
        if (request.method == 'GET') {
          final doc = docs[key];
          return doc == null
              ? http.Response('{}', 404)
              : http.Response(jsonEncode(doc), 200);
        }
        if (request.method == 'PUT') {
          token ??= auth!.substring(7);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final current = docs[key!];
          if (current != null &&
              (current['updatedAt'] as int) > (body['updatedAt'] as int)) {
            return http.Response('{}', 409);
          }
          docs[key] = {'key': key, ...body};
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('{}', 405);
      });
}

class Device {
  Device(this.vault, this.root) {
    data = Directory(p.join(root.path, 'data'))..createSync(recursive: true);
    themes = Directory(p.join(root.path, 'themes'))
      ..createSync(recursive: true);
    String? stored;
    var optOut = false;
    service = SyncService(
      dataDir: () async => data,
      themeImportsDir: () async => themes,
      serverBase: () => Uri.parse('https://jam.test/'),
      client: vault.client,
      interval: const Duration(days: 1),
      readKey: () async => stored,
      writeKey: (value) async => stored = value,
      readOptOut: () async => optOut,
      writeOptOut: (value) async => optOut = value,
    )..onApplied = applied.addAll;
  }

  final FakeVault vault;
  final Directory root;
  late final Directory data;
  late final Directory themes;
  late final SyncService service;
  final applied = <String>{};

  File file(String name) => File(p.join(data.path, name));
  void write(String name, String content, {DateTime? modified}) {
    final f = file(name)..writeAsStringSync(content);
    if (modified != null) f.setLastModifiedSync(modified);
  }
}

/// `link`/`enableForAccount` lanzan una sincronización en segundo plano; un
/// `syncNow()` mientras otra está en curso no hace nada. Para que las pruebas
/// no dependan de la velocidad de la máquina se espera a que termine la
/// pendiente, se hace una completa y se vuelve a esperar.
Future<void> fullSync(SyncService service) async {
  Future<void> idle() async {
    while (service.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  await idle();
  await service.syncNow();
  await idle();
}

void main() {
  late Directory tmp;
  late FakeVault vault;
  late String key;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync_test');
    vault = FakeVault();
    key = SyncKey.format(SyncKey.generate());
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('la cuenta genera la misma clave en cada dispositivo, sin copiarla',
      () async {
    final a = Device(vault, Directory(p.join(tmp.path, 'a')));
    final b = Device(vault, Directory(p.join(tmp.path, 'b')));
    a.write('settings.json', '{"x":1}');
    await a.service.enableForAccount(
        url: 'https://musica.test/', username: 'ana', password: 'clave');
    await b.service.enableForAccount(
        url: 'https://MUSICA.test', username: 'ana', password: 'clave');
    expect(a.service.enabled, isTrue);
    expect(a.service.keyText, b.service.keyText);
    await fullSync(a.service);
    await fullSync(b.service);
    expect(b.file('settings.json').readAsStringSync(), '{"x":1}');
  });

  test('otra cuenta no comparte clave y desactivar a mano no se revierte',
      () async {
    final a = Device(vault, Directory(p.join(tmp.path, 'a')));
    final b = Device(vault, Directory(p.join(tmp.path, 'b')));
    await a.service.enableForAccount(
        url: 'https://musica.test', username: 'ana', password: 'clave');
    await b.service.enableForAccount(
        url: 'https://musica.test', username: 'luis', password: 'clave');
    expect(a.service.keyText, isNot(b.service.keyText));
    await a.service.disable();
    await a.service.enableForAccount(
        url: 'https://musica.test', username: 'ana', password: 'clave');
    expect(a.service.enabled, isFalse);
  });

  Device device(String name) =>
      Device(vault, Directory(p.join(tmp.path, name))..createSync());

  Future<void> link(Device d) async {
    expect(await d.service.link(key), isTrue);
    // link() lanza un ciclo en segundo plano; esperar a que termine.
    while (d.service.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await fullSync(d.service);
  }

  test('rechaza una clave inválida', () async {
    expect(await device('a').service.link('no-vale'), isFalse);
  });

  test('un dispositivo nuevo recibe los datos y los temas del primero',
      () async {
    final a = device('a');
    a.write('followed_artists_srv_abc.json', '["1","2"]');
    File(p.join(a.themes.path, 'Mi Tema.zip'))
        .writeAsBytesSync(Uint8List.fromList([80, 75, 3, 4, 1, 2, 3]));
    await link(a);

    final b = device('b');
    b.write('settings.json', '{"gapless":false}'); // valores por defecto
    await link(b);

    expect(b.file('followed_artists_srv_abc.json').readAsStringSync(),
        '["1","2"]');
    expect(File(p.join(b.themes.path, 'Mi Tema.zip')).readAsBytesSync(),
        [80, 75, 3, 4, 1, 2, 3]);
    expect(b.applied, contains('followed_artists_srv_abc.json'));
  });

  test('el servidor solo guarda blobs cifrados', () async {
    final a = device('a');
    a.write('track_ratings_srv_x.json', '{"cancion-secreta":5}');
    await link(a);
    final stored = jsonEncode(vault.docs);
    expect(stored, isNot(contains('cancion-secreta')));
    expect(stored, isNot(contains('track_ratings')));
  });

  test('un cambio posterior viaja al otro dispositivo', () async {
    final a = device('a');
    a.write('pinned_playlists_srv_x.json', '["p1"]');
    await link(a);
    final b = device('b');
    await link(b);

    a.write('pinned_playlists_srv_x.json', '["p1","p2"]',
        modified: DateTime.now().add(const Duration(minutes: 1)));
    await fullSync(a.service);
    await fullSync(b.service);
    expect(b.file('pinned_playlists_srv_x.json').readAsStringSync(),
        '["p1","p2"]');
  });

  test('gana el cambio más reciente si ambos editan', () async {
    final a = device('a');
    a.write('followed_artists_srv_x.json', '["base"]');
    await link(a);
    final b = device('b');
    await link(b);

    final now = DateTime.now();
    a.write('followed_artists_srv_x.json', '["de-a"]',
        modified: now.add(const Duration(minutes: 1)));
    b.write('followed_artists_srv_x.json', '["de-b"]',
        modified: now.add(const Duration(minutes: 2)));
    await fullSync(a.service);
    await fullSync(b.service); // b es más reciente y gana
    await fullSync(a.service);
    expect(
        a.file('followed_artists_srv_x.json').readAsStringSync(), '["de-b"]');
  });

  test('la URL del servidor Jam no se sincroniza entre dispositivos', () async {
    final a = device('a');
    a.write(
        'settings.json', '{"gapless":true,"jamServerUrl":"wss://a.example/"}');
    await link(a);
    final b = device('b');
    b.write(
        'settings.json', '{"gapless":false,"jamServerUrl":"wss://b.example/"}');
    await link(b);

    final merged = jsonDecode(b.file('settings.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(merged['gapless'], true);
    expect(merged['jamServerUrl'], 'wss://b.example/');
  });

  test('ignora nombres de archivo peligrosos del servidor', () async {
    final a = device('a');
    a.write('followed_artists_srv_x.json', '[]');
    await link(a);
    // Un servidor malicioso (o clave comprometida) intenta salir de la carpeta.
    final crypto = await SyncCrypto.fromSecret(SyncKey.parse(key)!);
    final blob = await crypto.encrypt(
        utf8.encode(jsonEncode({
          'name': '../../evil.json',
          'data': base64.encode([1])
        })),
        docKey: 'evil');
    vault.docs['evil'] = {'key': 'evil', 'updatedAt': 5, 'blob': blob};
    final b = device('b');
    await link(b);
    expect(File(p.join(b.root.path, 'evil.json')).existsSync(), isFalse);
    expect(File(p.join(tmp.path, 'evil.json')).existsSync(), isFalse);
  });

  test('informa si el servidor no tiene la sincronización activada', () async {
    vault.enabled = false;
    final a = device('a');
    await link(a);
    expect(a.service.error, contains('no tiene la sincronización activada'));
  });

  test('desactivar borra la clave y el estado local', () async {
    final a = device('a');
    a.write('followed_artists_srv_x.json', '[]');
    await link(a);
    await a.service.disable();
    expect(a.service.enabled, isFalse);
    expect(a.service.keyText, isNull);
    expect(File(p.join(a.data.path, 'sync_state.json')).existsSync(), isFalse);
  });
}
