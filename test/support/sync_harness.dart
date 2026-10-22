import 'dart:async';
import 'dart:io';

import 'package:crotowave/services/sync/sync_crypto.dart';
import 'package:crotowave/services/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// Petición recibida por el servidor falso, en orden de llegada.
class SyncRequest {
  SyncRequest(this.method, this.vault, this.key);
  final String method;
  final String vault;
  final String? key;
  @override
  String toString() => '$method $vault ${key ?? ''}';
}

/// Dispositivo con su propio servidor CrotoLink falso (bóveda vacía) y
/// almacenes de clave/opt-out en memoria. [listGate] retiene la primera
/// petición de listado hasta completarse, para pausar un ciclo en vuelo.
class SyncHarness {
  SyncHarness(
    Directory root, {
    this.storedKey,
    this.requestTimeout = const Duration(seconds: 30),
    SyncService Function(SyncHarness harness)? build,
  }) {
    data = Directory(p.join(root.path, 'data'))..createSync(recursive: true);
    themes = Directory(p.join(root.path, 'themes'))
      ..createSync(recursive: true);
    service = (build ?? _defaultBuild)(this);
  }

  late final Directory data;
  late final Directory themes;
  late final SyncService service;
  final requests = <SyncRequest>[];
  final applied = <String>{};
  String? storedKey;
  bool optOut = false;
  bool accountBound = false;
  bool manualLinked = false;
  String? legacyBackup;

  /// Si no es `null`, el primer listado espera a que se complete.
  Completer<void>? listGate;

  /// Si no es `null`, la primera escritura de la clave espera a completarse.
  Completer<void>? writeKeyGate;
  int writeKeyCalls = 0;

  /// El primer listado responde cabeceras 200 y un cuerpo que nunca termina.
  bool stallListBody = false;

  /// Escritura de la clave como la haría el almacén seguro: el valor queda
  /// guardado cuando la escritura termina, no cuando empieza.
  Future<void> storeKey(String? value) async {
    writeKeyCalls++;
    final gate = writeKeyGate;
    writeKeyGate = null;
    if (gate != null) await gate.future;
    storedKey = value;
  }

  late final http.Client client = MockClient.streaming((request, _) async {
    final parts = request.url.pathSegments;
    final key = parts.length > 4 ? parts[4] : null;
    requests.add(SyncRequest(request.method, parts[3], key));
    http.StreamedResponse reply(String body, int code) =>
        http.StreamedResponse(Stream.value(body.codeUnits), code,
            contentLength: body.length);
    if (request.method == 'GET' && key == null) {
      if (stallListBody) {
        stallListBody = false;
        return http.StreamedResponse(StreamController<List<int>>().stream, 200);
      }
      final gate = listGate;
      listGate = null;
      if (gate != null) await gate.future;
      return reply('{}', 404);
    }
    if (request.method == 'PUT') return reply('{"ok":true}', 200);
    return reply('{}', 404);
  });

  SyncService _defaultBuild(SyncHarness h) => SyncService(
        dataDir: () async => h.data,
        themeImportsDir: () async => h.themes,
        serverBase: () => Uri.parse('https://crotolink.test/'),
        client: h.client,
        interval: const Duration(days: 1),
        readKey: () async => h.storedKey,
        writeKey: h.storeKey,
        readOptOut: () async => h.optOut,
        writeOptOut: (value) async => h.optOut = value,
        readAccountBound: () async => h.accountBound,
        writeAccountBound: (value) async => h.accountBound = value,
        readManualLinked: () async => h.manualLinked,
        writeManualLinked: (value) async => h.manualLinked = value,
        writeLegacyKey: (value) async => h.legacyBackup = value,
        requestTimeout: h.requestTimeout,
      )..onApplied = h.applied.addAll;

  final Duration requestTimeout;

  void write(String name, String content) =>
      File(p.join(data.path, name)).writeAsStringSync(content);

  /// Bóveda que corresponde a una cuenta, sin pasar por el servicio.
  static Future<String> vaultOf(
      String url, String user, String password) async {
    final secret = await SyncService.deriveAccountSecret(url, user, password);
    return (await SyncCrypto.fromSecret(secret)).vaultId;
  }

  static Future<String> keyOf(String url, String user, String password) async {
    return SyncKey.format(
        await SyncService.deriveAccountSecret(url, user, password));
  }

  /// Espera a que el servicio no tenga un ciclo en curso.
  Future<void> idle() async {
    while (service.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Espera a que el servidor falso haya recibido [count] peticiones.
  Future<void> untilRequests(int count) async {
    for (var i = 0; i < 400 && requests.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}
