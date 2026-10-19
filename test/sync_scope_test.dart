import 'dart:async';
import 'dart:io';

import 'package:crotowave/services/offline_cache_service.dart';
import 'package:crotowave/services/sync/sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/sync_harness.dart';

const _url = 'https://musica.test';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sync_scope'));
  tearDown(() => tmp.deleteSync(recursive: true));

  SyncHarness device() =>
      SyncHarness(Directory(p.join(tmp.path, 'd'))..createSync());

  test('con una cuenta solo suben los archivos por cuenta de esa cuenta',
      () async {
    final scopeA = OfflineCacheService.safeScopeSegment('$_url|ana');
    final scopeB = OfflineCacheService.safeScopeSegment('$_url|beto');
    final fileA = 'followed_artists_$scopeA.json';
    final fileB = 'followed_artists_$scopeB.json';
    final h = device()
      ..write('settings.json', '{"x":1}')
      ..write(fileA, '["de-ana"]')
      ..write(fileB, '["de-beto"]');

    await h.service
        .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
    await h.idle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await h.idle();

    final crypto = h.service.crypto!;
    final pushed = {
      for (final r in h.requests.where((r) => r.method == 'PUT')) r.key
    };
    expect(pushed, contains(await crypto.docKey('settings.json')),
        reason: 'los ajustes globales viajan');
    expect(pushed, contains(await crypto.docKey(fileB)));
    expect(pushed, isNot(contains(await crypto.docKey(fileA))),
        reason: 'lo de ana no se sube a la bóveda de beto');
    expect(File(p.join(h.data.path, fileA)).existsSync(), isTrue,
        reason: 'y no se toca en disco');
  });

  test('una clave manual no filtra nada', () async {
    final scopeA = OfflineCacheService.safeScopeSegment('$_url|ana');
    final fileA = 'followed_artists_$scopeA.json';
    final h = device()..write(fileA, '["de-ana"]');

    expect(await h.service.link(SyncKey.format(SyncKey.generate())), isTrue);
    await h.idle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await h.idle();

    final pushed = {
      for (final r in h.requests.where((r) => r.method == 'PUT')) r.key
    };
    expect(pushed, contains(await h.service.crypto!.docKey(fileA)));
  });

  group('operaciones solapadas', () {
    test('desactivar durante una vinculación no deja una clave guardada',
        () async {
      final h = device();
      final linking = h.service.link(SyncKey.format(SyncKey.generate()));
      final disabling = h.service.disable();
      expect(await linking, isFalse);
      await disabling;

      expect(h.service.enabled, isFalse);
      expect(h.storedKey, isNull);
      expect(h.optOut, isTrue);
    });

    test('la última vinculación gana a una anterior aún en curso', () async {
      final h = device();
      final first = SyncKey.format(SyncKey.generate());
      final second = SyncKey.format(SyncKey.generate());
      final a = h.service.link(first);
      final b = h.service.link(second);

      expect(await a, isFalse);
      expect(await b, isTrue);
      expect(h.storedKey, second);
      expect(h.service.keyText, second);
      await h.idle();
    });
  });

  test('tras dispose un ciclo en vuelo no envía ni avisa', () async {
    final h = device()..write('settings.json', '{"x":1}');
    final gate = h.listGate = Completer<void>();
    await h.service
        .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
    await h.untilRequests(1);

    h.service.dispose();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(h.requests, hasLength(1));
    expect(h.applied, isEmpty);
  });
}
