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
    } catch (_) {}
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
    final local = await _localDocs(crypto);
    final applied = <String>{};
    for (final key in {...local.keys, ...remote.keys}) {
      final l = local[key];
      final r = remote[key];
      final st = _state[key];
      final action = _decide(l, r, st);
      if (action == _Action.pull) {
        final name = await _pull(crypto, base, key, r!);
        if (name != null) applied.add(name);
      } else if (action == _Action.push) {
        await _push(crypto, base, key, l!,
            minUpdatedAt: (st?['updatedAt'] as int? ?? 0) + 1);
      }
    }
    await _saveState();
    return applied;
  }

  _Action _decide(_LocalDoc? l, _RemoteDoc? r, Map<String, dynamic>? st) {
    if (l == null && r == null) return _Action.none;
    if (l == null) return _Action.pull;
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
      'updatedAt': remote.updatedAt
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
    _state[key] = {'hash': doc.hash, 'updatedAt': updatedAt};
  }

  // ---------------------------------------------------------------------------
  // Documentos locales
  // ---------------------------------------------------------------------------

  Future<Map<String, _LocalDoc>> _localDocs(SyncCrypto crypto) async {
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
    if (await themes.exists()) {
      await for (final entity in themes.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is! File || !name.toLowerCase().endsWith('.zip')) continue;
        docs[await crypto.docKey(name)] = await _readDoc(name, entity);
      }
    }
    return docs;
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

enum _Action { none, pull, push }

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
