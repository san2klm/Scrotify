import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:cryptography/cryptography.dart' as cg show Hmac;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../secure_storage.dart';
import 'sync_crypto.dart';

/// Sincroniza en segundo plano los datos del usuario (ajustes, temas
/// importados, seguidos, valoraciones…) con el servidor Jam. Todo viaja
/// cifrado de extremo a extremo con la clave de sincronización: el servidor
/// solo ve blobs opacos. Gana el cambio más reciente de cada documento.
///
/// Fuera de la sincronización quedan los datos propios de cada dispositivo
/// (rutas, cachés, URL del servidor Jam) y la música descargada.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.dataDir,
    required this.themeImportsDir,
    required this.serverBase,
    http.Client? client,
    this.interval = const Duration(minutes: 5),
    DateTime Function()? now,
    Future<String?> Function()? readKey,
    Future<void> Function(String?)? writeKey,
    Future<bool> Function()? readOptOut,
    Future<void> Function(bool)? writeOptOut,
  })  : _readOptOut = readOptOut ?? _defaultReadOptOut,
        _writeOptOut = writeOptOut ?? _defaultWriteOptOut,
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _readKey = readKey ?? (() => SecureStorage.secureRead(_keyName)),
        _writeKey = writeKey ?? _defaultWriteKey;

  static const _keyName = 'scrotify.sync_key';
  static const _optOutName = 'scrotify.sync_opt_out';
  static const _stateFile = 'sync_state.json';

  /// Documentos JSON de la app que se sincronizan (con o sin sufijo de servidor).
  static final RegExp syncedFile =
      RegExp(r'^(settings|equalizer_v2|followed_artists|excluded_artists|'
          r'pinned_playlists|starred_track_order|track_ratings)'
          r'(_[a-z0-9_]+)?\.json$');

  /// Clave del aviso de borrado de un documento. Se deriva de la clave del
  /// documento (sin necesitar su nombre) y no empieza por `d-`, así que
  /// cualquier cliente la distingue de un documento.
  static String tombstoneKey(String docKey) =>
      'x-${docKey.startsWith('d-') ? docKey.substring(2) : docKey}';

  static bool _isTombstoneKey(String key) => key.startsWith('x-');

  /// Cuánto se conserva un tema borrado en la papelera local, y cuánto vive un
  /// aviso de borrado en el servidor. Un dispositivo que pase más tiempo sin
  /// conectarse puede recuperar un tema borrado: es preferible a perder uno.
  static const retention = Duration(days: 30);

  /// Con al menos tantos temas desaparecidos a la vez, y más de la mitad de los
  /// conocidos, se supone un accidente (carpeta vaciada) y no se propaga.
  static const massDeletionMin = 3;

  /// Carpeta (dentro de los datos de la app) donde van los temas borrados.
  static const trashDir = 'sync_trash';

  /// Ajustes que pertenecen al dispositivo y no viajan.
  static const _deviceSettings = ['jamServerUrl'];

  final Future<Directory> Function() dataDir;
  final Future<Directory> Function() themeImportsDir;
  final Uri? Function() serverBase;
  final Duration interval;
  final http.Client _client;
  final DateTime Function() _now;
  final Future<String?> Function() _readKey;
  final Future<void> Function(String?) _writeKey;
  final Future<bool> Function() _readOptOut;
  final Future<void> Function(bool) _writeOptOut;

  /// Se llama tras escribir archivos traídos de otro dispositivo, con sus
  /// nombres, para que los controladores recarguen lo que puedan.
  void Function(Set<String> files)? onApplied;

  SyncCrypto? _crypto;
  Uint8List? _secret;
  bool _enabled = false;
  bool _syncing = false;
  String? _cycleNote;
  DateTime? _lastSync;
  String? _error;
  Timer? _timer;
  Map<String, Map<String, dynamic>> _state = {};

  bool get enabled => _enabled;

  /// Claves derivadas de la clave de sincronización (para Connect).
  SyncCrypto? get crypto => _crypto;
  bool get syncing => _syncing;
  DateTime? get lastSync => _lastSync;
  String? get error => _error;

  /// Clave legible para mostrar en la UI (solo si la sincronización está activa).
  String? get keyText => _secret == null ? null : SyncKey.format(_secret!);

  static Future<bool> _defaultReadOptOut() async =>
      await SecureStorage.secureRead(_optOutName) == '1';

  static Future<void> _defaultWriteOptOut(bool value) => value
      ? SecureStorage.secureWrite(_optOutName, '1')
      : SecureStorage.secureDelete(_optOutName);

  static Future<void> _defaultWriteKey(String? value) => value == null
      ? SecureStorage.secureDelete(_keyName)
      : SecureStorage.secureWrite(_keyName, value);

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Reanuda la sincronización si ya había una clave guardada.
  Future<void> initialize() async {
    final stored = await _readKey();
    final secret = stored == null ? null : SyncKey.parse(stored);
    if (secret == null) return;
    await _useSecret(secret);
    await _loadState();
    _start();
  }

  bool _autoEnabling = false;

  /// Sincronización automática: la clave sale de la propia cuenta de
  /// Navidrome, así que todos los dispositivos con la misma cuenta comparten
  /// datos sin copiar ninguna clave. No hace nada si ya hay sincronización o si
  /// el usuario la desactivó a propósito.
  Future<void> enableForAccount({
    required String url,
    required String username,
    required String password,
  }) async {
    if (_enabled || _autoEnabling) return;
    _autoEnabling = true;
    try {
      if (await _readOptOut()) return;
      final secret = await deriveAccountSecret(url, username, password);
      if (_enabled) return;
      await link(SyncKey.format(secret));
    } finally {
      _autoEnabling = false;
    }
  }

  /// Clave determinista de 256 bits a partir de la cuenta (PBKDF2). Se calcula
  /// en otro isolate: es deliberadamente lenta.
  static Future<Uint8List> deriveAccountSecret(
      String url, String username, String password) {
    final server = url.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
    return Isolate.run(() async {
      final key = await Pbkdf2(
        macAlgorithm: cg.Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: utf8.encode('scrotify-sync-account-v1|$server|$username'),
      );
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  /// Primer dispositivo: crea una clave nueva y empieza a subir sus datos.
  Future<String> enableNew() async {
    final secret = SyncKey.generate();
    await link(SyncKey.format(secret));
    return SyncKey.format(secret);
  }

  /// Dispositivo nuevo: usa la clave de otro y descarga sus datos.
  /// Devuelve `false` si la clave no es válida.
  Future<bool> link(String keyText) async {
    final secret = SyncKey.parse(keyText);
    if (secret == null) return false;
    await _writeOptOut(false);
    await _useSecret(secret);
    await _writeKey(SyncKey.format(secret));
    _state = {};
    await _saveState();
    _start();
    unawaited(syncNow());
    return true;
  }

  /// Deja de sincronizar en este dispositivo (los datos del servidor y de los
  /// demás dispositivos no se tocan).
  Future<void> disable() async {
    _timer?.cancel();
    _timer = null;
    _enabled = false;
    _crypto = null;
    _secret = null;
    _error = null;
    _state = {};
    await _writeOptOut(true);
    await _writeKey(null);
    try {
      final file = File(p.join((await dataDir()).path, _stateFile));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint(
          'SyncService: no se pudo borrar el estado local de sincronización: $e');
    }
    notifyListeners();
  }

  Future<void> _useSecret(Uint8List secret) async {
    _secret = secret;
    _crypto = await SyncCrypto.fromSecret(secret);
    _enabled = true;
    notifyListeners();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => syncNow());
    unawaited(syncNow());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sincronización
  // ---------------------------------------------------------------------------

  Future<void> syncNow() async {
    final crypto = _crypto;
    final base = serverBase();
    if (!_enabled || crypto == null || _syncing) return;
    if (base == null) {
      _fail('Configura un servidor Jam válido para sincronizar.');
      return;
    }
    _syncing = true;
    _error = null;
    notifyListeners();
    try {
      final applied = await _cycle(crypto, base);
      _error = _cycleNote; // aviso no fatal del ciclo (p. ej. borrados masivos)
      _lastSync = _now();
      if (applied.isNotEmpty) onApplied?.call(applied);
    } on _SyncFailure catch (failure) {
      _error = failure.message;
    } catch (error) {
      debugPrint('sync: $error');
      _error = 'No se pudo sincronizar. Se reintentará en unos minutos.';
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }

  Future<Set<String>> _cycle(SyncCrypto crypto, Uri base) async {
    final remote = await _listRemote(crypto, base);
    final listing = await _localDocs(crypto);
    final local = listing.docs;
    final applied = <String>{};
    final nowMs = _now().millisecondsSinceEpoch;
    _cycleNote = null;

    final docKeys = {
      ...local.keys,
      ...remote.keys.where((k) => !_isTombstoneKey(k)),
    };
    _RemoteDoc? tombstoneOf(String key) => remote[tombstoneKey(key)];

    // Un tema que ya estaba sincronizado y ya no está en esta carpeta es un
    // borrado. Solo se infiere si se pudo leer la carpeta y si no son muchos a
    // la vez (una carpeta vaciada por error no debe borrar los de los demás).
    var inferDelete = listing.themesListed;
    if (inferDelete) {
      final known = _state.values.where(_isSyncedTheme).length;
      final vanished = [
        for (final key in docKeys)
          if (local[key] == null &&
              remote[key] != null &&
              _isSyncedTheme(_state[key]) &&
              !_tombstoneWins(remote[key], tombstoneOf(key)))
            key
      ];
      if (vanished.length >= massDeletionMin && vanished.length * 2 > known) {
        inferDelete = false;
        _cycleNote = 'Se detectaron ${vanished.length} temas borrados de '
            'golpe; por seguridad no se propagan.';
      }
    }

    for (final key in docKeys) {
      final l = local[key];
      final r = remote[key];
      final t = tombstoneOf(key);
      final st = _state[key];
      switch (_decide(l, r, t, st, inferDelete: inferDelete)) {
        case _Action.pull:
          final name = await _pull(crypto, base, key, r!);
          if (name != null) applied.add(name);
        case _Action.push:
          final afterTombstone = _tombstoneWins(r, t)
              ? t!.updatedAt + 1
              : 0; // por encima del aviso
          final afterState = (st?['updatedAt'] as int? ?? 0) + 1;
          await _push(crypto, base, key, l!,
              minUpdatedAt:
                  afterState > afterTombstone ? afterState : afterTombstone);
        case _Action.deleteLocal:
          if (await _tombstoneAuthentic(
              crypto, base, tombstoneKey(key), l!.name)) {
            await _moveToTrash(await _targetFile(l.name));
            _state.remove(key);
            applied.add(l.name);
          }
        case _Action.pushTombstone:
          await _pushTombstone(
              crypto, base, key, st!['name'] as String, r!, nowMs);
        case _Action.markMissing:
          _state[key] = {...st!, 'missing': 1};
        case _Action.none:
          if (l != null && st != null) {
            // Se recuerda el nombre (para saber si es un tema) y se olvida
            // cualquier sospecha de borrado anterior.
            _state[key] = {...st, 'name': l.name}..remove('missing');
          }
      }
    }
    await _pruneTombstones(crypto, base, remote, nowMs);
    await _purgeTrash(nowMs);
    await _saveState();
    return applied;
  }

  static bool _isSyncedTheme(Map<String, dynamic>? st) =>
      (st?['name'] as String?)?.toLowerCase().endsWith('.zip') ?? false;

  /// El aviso de borrado es posterior al documento del servidor (o este ya no
  /// está).
  static bool _tombstoneWins(_RemoteDoc? doc, _RemoteDoc? tombstone) =>
      tombstone != null && (doc == null || tombstone.updatedAt > doc.updatedAt);

  _Action _decide(
      _LocalDoc? l, _RemoteDoc? r, _RemoteDoc? tomb, Map<String, dynamic>? st,
      {required bool inferDelete}) {
    final name = l?.name ?? st?['name'] as String?;
    final theme = name != null && name.toLowerCase().endsWith('.zip');
    // Solo los temas importados se pueden borrar por sincronización; los
    // ajustes y demás datos se reescriben, nunca se borran.
    if (theme && _tombstoneWins(r, tomb)) {
      if (l == null) return _Action.none;
      // Lo editado en este dispositivo (o que nunca se sincronizó aquí) gana
      // al borrado: se devuelve a los demás.
      if (st == null || st['hash'] != l.hash) return _Action.push;
      return _Action.deleteLocal;
    }
    if (l == null && r == null) return _Action.none;
    if (l == null) {
      if (inferDelete && theme && st != null) {
        // Hace falta verlo ausente en dos ciclos seguidos: un archivo que se
        // está moviendo o reescribiendo no cuenta como borrado.
        return (st['missing'] as int? ?? 0) >= 1
            ? _Action.pushTombstone
            : _Action.markMissing;
      }
      return _Action.pull;
    }
    if (r == null) return _Action.push;
    // Primer contacto de este dispositivo con la bóveda: se adopta lo que ya
    // hay (los valores por defecto recién creados no deben pisar los datos).
    if (st == null) return _Action.pull;
    final remoteChanged = r.updatedAt > (st['updatedAt'] as int? ?? 0);
    final localChanged = st['hash'] != l.hash;
    if (remoteChanged && localChanged) {
      return l.modified > r.updatedAt ? _Action.push : _Action.pull;
    }
    if (remoteChanged) return _Action.pull;
    if (localChanged) return _Action.push;
    return _Action.none;
  }

  /// Comprueba que el aviso de borrado es auténtico (cifrado con la clave de la
  /// bóveda) y que habla de [name]: un servidor no puede fabricarlo.
  Future<bool> _tombstoneAuthentic(
      SyncCrypto crypto, Uri base, String tombKey, String name) async {
    try {
      final response = await _send('GET', _uri(base, crypto, tombKey), crypto);
      if (response.statusCode == 404) return false;
      final doc = jsonDecode(response.body) as Map<String, dynamic>;
      final plain =
          await crypto.decrypt(doc['blob'] as String, docKey: tombKey);
      final envelope = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      return envelope['deleted'] == name;
    } on _SyncFailure {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Publica el aviso de borrado de [name] y retira el documento del servidor.
  /// El nombre del aviso termina en `.deleted`: un cliente sin esta función lo
  /// descarta en vez de crear un archivo.
  Future<void> _pushTombstone(SyncCrypto crypto, Uri base, String key,
      String name, _RemoteDoc remote, int nowMs) async {
    final tombKey = tombstoneKey(key);
    final updatedAt = nowMs > remote.updatedAt ? nowMs : remote.updatedAt + 1;
    final blob = await crypto.encrypt(
        utf8.encode(jsonEncode({
          'name': '$name.deleted',
          'deleted': name,
          'data': '',
          'at': updatedAt,
        })),
        docKey: tombKey);
    final response = await _send('PUT', _uri(base, crypto, tombKey), crypto,
        body: jsonEncode({'updatedAt': updatedAt, 'blob': blob}));
    if (response.statusCode == 409) return;
    try {
      // El aviso ya manda; quitar el documento solo libera espacio.
      await _send('DELETE', _uri(base, crypto, key), crypto);
    } on _SyncFailure {
      rethrow;
    } catch (_) {}
    _state.remove(key);
  }

  /// Elimina del servidor los avisos más antiguos que [retention].
  Future<void> _pruneTombstones(SyncCrypto crypto, Uri base,
      Map<String, _RemoteDoc> remote, int nowMs) async {
    final limit = nowMs - retention.inMilliseconds;
    for (final entry in remote.entries) {
      if (!_isTombstoneKey(entry.key) || entry.value.updatedAt >= limit) {
        continue;
      }
      try {
        await _send('DELETE', _uri(base, crypto, entry.key), crypto);
      } on _SyncFailure {
        rethrow;
      } catch (_) {}
    }
  }

  /// Mueve [file] a la papelera local en vez de borrarlo.
  Future<void> _moveToTrash(File? file) async {
    if (file == null || !await file.exists()) return;
    final dir = Directory(p.join((await dataDir()).path, trashDir));
    await dir.create(recursive: true);
    final target = File(p.join(
        dir.path, '${_now().millisecondsSinceEpoch}_${p.basename(file.path)}'));
    try {
      await file.rename(target.path);
    } on FileSystemException {
      await file.copy(target.path);
      await file.delete();
    }
  }

  /// Vacía de la papelera lo que lleva más de [retention].
  Future<void> _purgeTrash(int nowMs) async {
    try {
      final dir = Directory(p.join((await dataDir()).path, trashDir));
      if (!await dir.exists()) return;
      final limit = nowMs - retention.inMilliseconds;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final stamp = int.tryParse(p.basename(entity.path).split('_').first);
        final when =
            stamp ?? (await entity.stat()).modified.millisecondsSinceEpoch;
        if (when < limit) await entity.delete();
      }
    } catch (error) {
      debugPrint('sync: no se pudo limpiar la papelera: $error');
    }
  }

  Future<Map<String, _RemoteDoc>> _listRemote(
      SyncCrypto crypto, Uri base) async {
    final response = await _send('GET', _uri(base, crypto, null), crypto);
    if (response.statusCode == 404) return {};
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      for (final doc in body['docs'] as List)
        (doc as Map)['key'] as String:
            _RemoteDoc((doc['updatedAt'] as num).toInt()),
    };
  }

  Future<String?> _pull(
      SyncCrypto crypto, Uri base, String key, _RemoteDoc remote) async {
    final response = await _send('GET', _uri(base, crypto, key), crypto);
    if (response.statusCode == 404) return null;
    final doc = jsonDecode(response.body) as Map<String, dynamic>;
    final plain = await crypto.decrypt(doc['blob'] as String, docKey: key);
    final envelope = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final name = envelope['name'] as String;
    final bytes = base64.decode(envelope['data'] as String);
    final file = await _targetFile(name);
    if (file == null) return null; // Nombre no permitido: se ignora.
    final merged =
        name == 'settings.json' ? await _mergeSettings(file, bytes) : bytes;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.sync-tmp');
    await tmp.writeAsBytes(merged, flush: true);
    await tmp.rename(file.path);
    _state[key] = {
      'hash': _hash(await _normalized(name, file)),
      'updatedAt': remote.updatedAt,
      'name': name,
    };
    return name;
  }

  Future<void> _push(SyncCrypto crypto, Uri base, String key, _LocalDoc doc,
      {required int minUpdatedAt}) async {
    final updatedAt = doc.modified > minUpdatedAt ? doc.modified : minUpdatedAt;
    final envelope = utf8.encode(jsonEncode({
      'name': doc.name,
      'data': base64.encode(doc.bytes),
    }));
    final blob = await crypto.encrypt(envelope, docKey: key);
    final response = await _send('PUT', _uri(base, crypto, key), crypto,
        body: jsonEncode({'updatedAt': updatedAt, 'blob': blob}));
    // 409: hay algo más nuevo en el servidor; se baja en el próximo ciclo.
    if (response.statusCode == 409) return;
    _state[key] = {'hash': doc.hash, 'updatedAt': updatedAt, 'name': doc.name};
  }

  // ---------------------------------------------------------------------------
  // Documentos locales
  // ---------------------------------------------------------------------------

  Future<_LocalListing> _localDocs(SyncCrypto crypto) async {
    final docs = <String, _LocalDoc>{};
    final dir = await dataDir();
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is! File || !syncedFile.hasMatch(name)) continue;
        if (name.length > 64) continue;
        docs[await crypto.docKey(name)] = await _readDoc(name, entity);
      }
    }
    final themes = await themeImportsDir();
    final themesListed = await themes.exists();
    if (themesListed) {
      await for (final entity in themes.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is! File || !name.toLowerCase().endsWith('.zip')) continue;
        docs[await crypto.docKey(name)] = await _readDoc(name, entity);
      }
    }
    return _LocalListing(docs, themesListed);
  }

  Future<_LocalDoc> _readDoc(String name, File file) async {
    final bytes = await _normalized(name, file);
    final stat = await file.stat();
    return _LocalDoc(
        name, bytes, _hash(bytes), stat.modified.millisecondsSinceEpoch);
  }

  /// Contenido que viaja: en los ajustes se quitan los datos del dispositivo.
  Future<Uint8List> _normalized(String name, File file) async {
    final bytes = await file.readAsBytes();
    if (name != 'settings.json') return bytes;
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      for (final key in _deviceSettings) {
        data.remove(key);
      }
      return Uint8List.fromList(utf8.encode(jsonEncode(data)));
    } catch (_) {
      return bytes;
    }
  }

  Future<Uint8List> _mergeSettings(File file, Uint8List incoming) async {
    try {
      final data = jsonDecode(utf8.decode(incoming)) as Map<String, dynamic>;
      if (await file.exists()) {
        final mine =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final key in _deviceSettings) {
          if (mine.containsKey(key)) data[key] = mine[key];
        }
      }
      return Uint8List.fromList(utf8.encode(jsonEncode(data)));
    } catch (_) {
      return incoming;
    }
  }

  /// Destino seguro de un documento recibido, o `null` si el nombre no es de
  /// los permitidos (nunca se escribe fuera de las dos carpetas de la app).
  Future<File?> _targetFile(String name) async {
    if (name != p.basename(name)) return null;
    if (syncedFile.hasMatch(name) && name.length <= 64) {
      return File(p.join((await dataDir()).path, name));
    }
    if (name.toLowerCase().endsWith('.zip') && !name.startsWith('.')) {
      return File(p.join((await themeImportsDir()).path, name));
    }
    return null;
  }

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  // ---------------------------------------------------------------------------
  // HTTP y estado
  // ---------------------------------------------------------------------------

  Uri _uri(Uri base, SyncCrypto crypto, String? key) => base.replace(
      path: '/api/sync/v1/${crypto.vaultId}${key == null ? '' : '/$key'}');

  Future<http.Response> _send(String method, Uri uri, SyncCrypto crypto,
      {String? body}) async {
    final request = http.Request(method, uri)
      ..headers['authorization'] = 'Bearer ${crypto.authToken}'
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = body;
    final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)));
    final code = response.statusCode;
    if (code == 403) {
      throw const _SyncFailure(
          'El servidor Jam no tiene la sincronización activada.');
    }
    if (code == 401) {
      throw const _SyncFailure(
          'El servidor rechazó la clave de sincronización.');
    }
    if (code == 429) {
      throw const _SyncFailure('Demasiadas peticiones; se reintentará luego.');
    }
    if (code == 507) {
      throw const _SyncFailure(
          'El servidor no tiene espacio para sincronizar.');
    }
    if (code >= 400 && code != 404 && code != 409) {
      throw _SyncFailure('El servidor respondió con error ($code).');
    }
    return response;
  }

  Future<void> _loadState() async {
    try {
      final file = File(p.join((await dataDir()).path, _stateFile));
      if (!await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _state = {
        for (final e in data.entries)
          e.key: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      _state = {};
    }
  }

  Future<void> _saveState() async {
    try {
      final file = File(p.join((await dataDir()).path, _stateFile));
      await file.writeAsString(jsonEncode(_state));
    } catch (error) {
      debugPrint('sync: no se pudo guardar el estado: $error');
    }
  }
}

enum _Action { none, pull, push, deleteLocal, pushTombstone, markMissing }

class _LocalListing {
  const _LocalListing(this.docs, this.themesListed);
  final Map<String, _LocalDoc> docs;

  /// `false` si la carpeta de temas no existe: entonces la ausencia de un tema
  /// no significa que se borró.
  final bool themesListed;
}

class _LocalDoc {
  const _LocalDoc(this.name, this.bytes, this.hash, this.modified);
  final String name;
  final Uint8List bytes;
  final String hash;
  final int modified;
}

class _RemoteDoc {
  const _RemoteDoc(this.updatedAt);
  final int updatedAt;
}

class _SyncFailure implements Exception {
  const _SyncFailure(this.message);
  final String message;
}
