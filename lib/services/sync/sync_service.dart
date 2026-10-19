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

import '../offline_cache_service.dart';
import '../secure_storage.dart';
import 'sync_crypto.dart';

/// Sincroniza en segundo plano los datos del usuario (ajustes, temas
/// importados, seguidos, valoraciones…) con el servidor CrotoLink. Todo viaja
/// cifrado de extremo a extremo con la clave de sincronización: el servidor
/// solo ve blobs opacos. Gana el cambio más reciente de cada documento.
///
/// Fuera de la sincronización quedan los datos propios de cada dispositivo
/// (rutas, cachés, URL del servidor CrotoLink) y la música descargada.
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
    Future<bool> Function()? readAccountBound,
    Future<void> Function(bool)? writeAccountBound,
    Future<bool> Function()? readManualLinked,
    Future<void> Function(bool)? writeManualLinked,
    Future<void> Function(String)? writeLegacyKey,
    this.requestTimeout = const Duration(seconds: 30),
  })  : _readOptOut = readOptOut ?? _defaultReadOptOut,
        _writeOptOut = writeOptOut ?? _defaultWriteOptOut,
        _readAccountBound = readAccountBound ?? _defaultReadBound,
        _writeAccountBound = writeAccountBound ?? _defaultWriteBound,
        _readManualLinked = readManualLinked ?? _defaultReadManual,
        _writeManualLinked = writeManualLinked ?? _defaultWriteManual,
        _writeLegacyKey = writeLegacyKey ?? _defaultWriteLegacyKey,
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _readKey = readKey ?? (() => SecureStorage.secureRead(_keyName)),
        _writeKey = writeKey ?? _defaultWriteKey;

  static const _keyName = 'crotowave.sync_key';
  static const _optOutName = 'crotowave.sync_opt_out';
  static const _boundName = 'crotowave.sync_account_bound';
  static const _manualName = 'crotowave.sync_manual_linked';
  static const _legacyKeyName = 'crotowave.sync_key_legacy';
  static const _legacyNote =
      'Hay una clave de sincronización anterior sin cuenta asociada. Inicia '
      'sesión para confirmarla o vuelve a vincularla con su clave.';
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
  static const _deviceSettings = ['crotoLinkServerUrl'];

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
  final Future<bool> Function() _readAccountBound;
  final Future<void> Function(bool) _writeAccountBound;
  final Future<bool> Function() _readManualLinked;
  final Future<void> Function(bool) _writeManualLinked;
  final Future<void> Function(String) _writeLegacyKey;

  /// Plazo de cada petición completa (cabeceras y cuerpo).
  final Duration requestTimeout;

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

  /// Sube con cada cambio de identidad (vincular, desactivar, suspender,
  /// cambiar de cuenta). Una activación que empezó con otro valor se abandona.
  int _lifecycle = 0;

  /// Activación en curso: su ticket, si es de cuenta (`bound`) y la huella de
  /// la cuenta (nunca la contraseña).
  ({int ticket, bool bound, String? fingerprint})? _activation;

  /// La clave activa se derivó de la cuenta Navidrome (no la vinculó el
  /// usuario a mano) y [_boundFingerprint] es la cuenta a la que corresponde.
  bool _accountBound = false;
  String? _boundFingerprint;

  /// Cuenta ya comparada con una clave manual: evita repetir el PBKDF2.
  String? _manualChecked;

  /// Clave de cuenta conservada mientras la sincronización está suspendida (o
  /// restaurada sin confirmar la cuenta actual), para retomarla si vuelve la
  /// misma cuenta.
  Uint8List? _heldSecret;
  bool _suspended = false;

  /// La clave retenida no tiene procedencia conocida (guardada antes de que se
  /// recordara): solo se retoma si coincide con la cuenta actual.
  bool _heldLegacy = false;

  bool get enabled => _enabled;

  /// Suspendida porque no hay cuenta (cerrar sesión), sin que el usuario la
  /// haya desactivado: vuelve sola al iniciar sesión.
  bool get suspended => _suspended;

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

  static Future<bool> _defaultReadBound() async =>
      await SecureStorage.secureRead(_boundName) == '1';

  static Future<void> _defaultWriteBound(bool value) => value
      ? SecureStorage.secureWrite(_boundName, '1')
      : SecureStorage.secureDelete(_boundName);

  static Future<bool> _defaultReadManual() async =>
      await SecureStorage.secureRead(_manualName) == '1';

  static Future<void> _defaultWriteManual(bool value) => value
      ? SecureStorage.secureWrite(_manualName, '1')
      : SecureStorage.secureDelete(_manualName);

  static Future<void> _defaultWriteLegacyKey(String value) =>
      SecureStorage.secureWrite(_legacyKeyName, value);

  static Future<void> _defaultWriteKey(String? value) => value == null
      ? SecureStorage.secureDelete(_keyName)
      : SecureStorage.secureWrite(_keyName, value);

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Reanuda la sincronización si ya había una clave guardada. Una clave que
  /// salió de una cuenta no se usa hasta que [enableForAccount] confirme que
  /// la cuenta actual es la misma: podría haberse cerrado sesión o cambiado de
  /// usuario con la app cerrada.
  Future<void> initialize() async {
    final ticket = ++_lifecycle;
    final stored = await _readKey();
    final secret = stored == null ? null : SyncKey.parse(stored);
    if (secret == null || ticket != _lifecycle) return;
    final bound = await _readBound();
    final manual = bound ? false : await _readManual();
    if (ticket != _lifecycle) return;
    if (manual) {
      // Vinculada a propósito por el usuario: no depende de la cuenta.
      await _activate(secret,
          bound: false, resume: true, ticket: ticket, persist: false);
      return;
    }
    // De cuenta, o de origen desconocido (guardada antes de recordarlo): no se
    // usa hasta confirmar la cuenta. Una clave desconocida nunca se da por
    // manual, y no se borra: si no coincide con la cuenta se guarda aparte.
    _heldSecret = secret;
    _heldLegacy = !bound;
    _suspended = true;
    _error = _heldLegacy ? _legacyNote : null;
    notifyListeners();
  }

  /// Sincronización automática: la clave sale de la propia cuenta de
  /// Navidrome, así que todos los dispositivos con la misma cuenta comparten
  /// datos sin copiar ninguna clave. Si la cuenta cambia, pasa a la bóveda de
  /// la nueva. No hace nada si el usuario la desactivó a propósito ni sobre
  /// una clave vinculada a mano.
  Future<void> enableForAccount({
    required String url,
    required String username,
    required String password,
  }) async {
    final fingerprint = _fingerprint(url, username, password);
    if (_enabled && _accountBound && _boundFingerprint == fingerprint) return;
    if (_enabled && !_accountBound && _manualChecked == fingerprint) return;
    final running = _activation;
    if (running != null &&
        (!running.bound ||
            (running.fingerprint == fingerprint &&
                running.ticket == _lifecycle))) {
      return; // una vinculación manual manda; la misma cuenta ya se está activando
    }
    final ticket = ++_lifecycle;
    _activation = (ticket: ticket, bound: true, fingerprint: fingerprint);
    try {
      if (await _readOptOut() || ticket != _lifecycle) return;
      final secret = await deriveAccountSecret(url, username, password);
      if (ticket != _lifecycle) return;
      final current = _secret;
      if (_enabled && current != null && listEquals(current, secret)) {
        // La misma bóveda: una clave derivada antes de que se recordara su
        // origen, o la misma cuenta escrita de otra forma.
        _boundFingerprint = fingerprint;
        _accountScopes = _scopesOf(url, username);
        if (!_accountBound) {
          _accountBound = true;
          await _persist(ticket, () async {
            await _writeBound(true);
            await _writeManual(false);
          });
        }
        return;
      }
      if (_enabled && !_accountBound) {
        _manualChecked = fingerprint; // clave manual explícita: se respeta
        return;
      }
      final held = _heldSecret;
      final same = held != null && listEquals(held, secret);
      await _activate(secret,
          bound: true,
          fingerprint: fingerprint,
          resume: same,
          ticket: ticket,
          scopes: _scopesOf(url, username),
          legacyBackup: _heldLegacy && !same ? held : null);
    } finally {
      if (_activation?.ticket == ticket) _activation = null;
    }
  }

  /// Cierra la sesión de la cuenta: detiene la sincronización de una clave de
  /// cuenta sin desactivarla ni borrar nada (no es un opt-out). Una clave
  /// vinculada a mano no depende de la cuenta y sigue activa. Los ciclos y
  /// activaciones en curso dejan de aplicar y de subir datos.
  Future<void> suspendForLogout() async {
    final running = _activation;
    if (running != null && !running.bound) return;
    if (_enabled && !_accountBound) return;
    _lifecycle++;
    _activation = null;
    final secret = _secret ?? _heldSecret;
    _teardown();
    _heldSecret = secret;
    _suspended = secret != null;
    _boundFingerprint = null;
    _manualChecked = null;
    if (_heldLegacy) _error = _legacyNote;
    notifyListeners();
  }

  // Marcadores de procedencia de la clave guardada. Sin ninguno (instalaciones
  // anteriores) el origen es desconocido, no «manual».
  Future<bool> _readManual() async {
    try {
      return await _readManualLinked();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeManual(bool value) async {
    try {
      await _writeManualLinked(value);
    } catch (error) {
      debugPrint('sync: no se pudo recordar la vinculación manual: $error');
    }
  }

  /// Escrituras de configuración persistente, en orden de llegada y cada una
  /// validada contra la generación ANTES de ejecutarse: si mientras esperaba
  /// turno hubo una intención más reciente, no se ejecuta. Así la última
  /// intención gana aunque una escritura anterior tarde más en terminar.
  Future<void> _persistQueue = Future.value();

  Future<bool> _persist(int ticket, Future<void> Function() write) {
    final run = _persistQueue.then((_) async {
      if (ticket != _lifecycle) return false;
      await write();
      return true;
    });
    _persistQueue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Huella de la cuenta: identifica «esta cuenta» sin guardar la contraseña.
  static String _fingerprint(String url, String username, String password) {
    final server = url.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
    return sha256
        .convert(utf8.encode('$server\n$username\n$password'))
        .toString();
  }

  Future<bool> _readBound() async {
    try {
      return await _readAccountBound();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeBound(bool value) async {
    try {
      await _writeAccountBound(value);
    } catch (error) {
      debugPrint('sync: no se pudo recordar el origen de la clave: $error');
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
        nonce: utf8.encode('crotowave-sync-account-v1|$server|$username'),
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
    final ticket = ++_lifecycle;
    _activation = (ticket: ticket, bound: false, fingerprint: null);
    try {
      return await _activate(secret,
          bound: false, resume: false, ticket: ticket);
    } finally {
      if (_activation?.ticket == ticket) _activation = null;
    }
  }

  /// Deja de sincronizar en este dispositivo (los datos del servidor y de los
  /// demás dispositivos no se tocan).
  Future<void> disable() async {
    final ticket = ++_lifecycle;
    _activation = null;
    _teardown();
    _heldSecret = null;
    _heldLegacy = false;
    _suspended = false;
    _accountBound = false;
    _boundFingerprint = null;
    _manualChecked = null;
    // Si antes de que le toque turno se vincula otra clave, esa intención
    // posterior gana y esta limpieza no se ejecuta.
    await _persist(ticket, () async {
      await _writeOptOut(true);
      await _writeKey(null);
      await _writeBound(false);
      await _writeManual(false);
      try {
        final file = File(p.join((await dataDir()).path, _stateFile));
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint(
            'SyncService: no se pudo borrar el estado local de sincronización: $e');
      }
    });
    notifyListeners();
  }

  /// Detiene la sincronización en memoria. Quitar [_crypto] basta para que los
  /// ciclos en vuelo se abandonen en su siguiente paso (ver [_ensureLive]).
  void _teardown() {
    _timer?.cancel();
    _timer = null;
    _enabled = false;
    _crypto = null;
    _secret = null;
    _error = null;
    _state = {};
    _accountScopes = null;
  }

  /// Segmentos (`srv_…`) de los archivos por cuenta que pertenecen a la cuenta
  /// de la bóveda activa; `null` con una clave manual (sin cuenta, sin filtro).
  Set<String>? _accountScopes;

  static Set<String> _scopesOf(String url, String username) {
    var server = url.trim();
    if (server.endsWith('/')) server = server.substring(0, server.length - 1);
    if (!server.startsWith('http://') && !server.startsWith('https://')) {
      server = 'https://$server';
    }
    return {
      OfflineCacheService.safeScopeSegment('$server|$username'),
      OfflineCacheService.safeScopeSegment(
          server), // nombre anterior, por servidor
    };
  }

  /// Los ajustes, temas y demás documentos globales viajan siempre; los
  /// archivos con sufijo de cuenta (`followed_artists_srv_….json`) solo si
  /// son de la cuenta activa: en la misma carpeta conviven los de otras
  /// cuentas, que no deben subirse a esta bóveda ni recibirse de ella.
  bool _belongsHere(String name) {
    final scopes = _accountScopes;
    if (scopes == null) return true;
    final suffix = syncedFile.firstMatch(name)?.group(2);
    return suffix == null || scopes.any((s) => suffix == '_$s');
  }

  /// Pasa a la bóveda de [secret]. Cada espera comprueba el [ticket]: si
  /// mientras tanto se suspendió, desactivó o eligió otra cuenta, se abandona
  /// sin guardar ni activar nada.
  Future<bool> _activate(
    Uint8List secret, {
    required bool bound,
    String? fingerprint,
    required bool resume,
    required int ticket,
    bool persist = true,
    Set<String>? scopes,
    Uint8List? legacyBackup,
  }) async {
    bool stale() => ticket != _lifecycle;
    _teardown();
    final crypto = await SyncCrypto.fromSecret(secret);
    if (stale()) return false;
    if (persist) {
      // Un solo bloque en la cola: o se ejecuta entero o, si ya hay una
      // intención posterior, no se ejecuta.
      final done = await _persist(ticket, () async {
        if (legacyBackup != null) {
          // La clave desconocida que se va a reemplazar no se pierde.
          await _writeLegacyKey(SyncKey.format(legacyBackup));
        }
        await _writeOptOut(false);
        await _writeKey(SyncKey.format(secret));
        await _writeBound(bound);
        await _writeManual(!bound);
        if (!resume) await _saveState();
      });
      if (!done || stale()) return false;
    }
    if (resume) {
      final loaded = await _readState();
      if (stale()) return false;
      _state = loaded;
    }
    _secret = secret;
    _crypto = crypto;
    _enabled = true;
    _suspended = false;
    _heldSecret = null;
    _heldLegacy = false;
    _accountBound = bound;
    _boundFingerprint = fingerprint;
    _manualChecked = null;
    _accountScopes = scopes;
    notifyListeners();
    _start();
    return true;
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => syncNow());
    unawaited(syncNow());
  }

  bool _disposed = false;

  /// Tras `dispose` un ciclo o activación en vuelo ya no avisa a nadie.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle++; // activaciones en curso se abandonan
    _activation = null;
    _teardown(); // los ciclos en vuelo dejan de ser vigentes
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
      _fail('Configura un servidor CrotoLink válido para sincronizar.');
      return;
    }
    _syncing = true;
    _error = null;
    notifyListeners();
    var superseded = false;
    try {
      final applied = await _cycle(crypto, base);
      _ensureLive(crypto);
      _error = _cycleNote; // aviso no fatal del ciclo (p. ej. borrados masivos)
      _lastSync = _now();
      if (applied.isNotEmpty) onApplied?.call(applied);
    } on _Superseded {
      superseded = true; // otra cuenta o suspensión: nada de este ciclo vale
    } on _SyncFailure catch (failure) {
      if (_isLive(crypto)) _error = failure.message;
    } catch (error) {
      debugPrint('sync: $error');
      if (_isLive(crypto)) {
        _error = 'No se pudo sincronizar. Se reintentará en unos minutos.';
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
    // La bóveda nueva no pudo arrancar mientras este ciclo seguía en curso.
    if (superseded && _enabled) unawaited(syncNow());
  }

  bool _isLive(SyncCrypto crypto) => _enabled && identical(crypto, _crypto);

  /// Cada activación crea un [SyncCrypto] nuevo, así que seguir siendo el
  /// vigente identifica al ciclo de la identidad actual. Se llama tras cada
  /// espera antes de aplicar, subir o guardar algo.
  void _ensureLive(SyncCrypto crypto) {
    if (!_isLive(crypto)) throw const _Superseded();
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }

  Future<Set<String>> _cycle(SyncCrypto crypto, Uri base) async {
    final remote = await _listRemote(crypto, base);
    final listing = await _localDocs(crypto);
    _ensureLive(crypto);
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
      _ensureLive(crypto);
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
            final target = await _targetFile(l.name);
            _ensureLive(crypto);
            await _moveToTrash(target, crypto);
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
    await _saveState(crypto);
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
    if (r == null) {
      // Un tema que ya estaba sincronizado, sin cambios locales y que falta en
      // el servidor, se borró en otro dispositivo cuyo aviso ya se purgó:
      // subirlo lo resucitaría.
      if (theme && st != null && st['hash'] == l.hash) return _Action.none;
      return _Action.push;
    }
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
  Future<void> _moveToTrash(File? file, SyncCrypto crypto) async {
    if (file == null || !await file.exists()) return;
    final dir = Directory(p.join((await dataDir()).path, trashDir));
    await dir.create(recursive: true);
    _ensureLive(crypto);
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
    _ensureLive(crypto);
    final envelope = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final name = envelope['name'] as String;
    if (!_belongsHere(name)) return null; // archivo por cuenta de otra cuenta
    final bytes = base64.decode(envelope['data'] as String);
    final file = await _targetFile(name);
    if (file == null) return null; // Nombre no permitido: se ignora.
    final merged =
        name == 'settings.json' ? await _mergeSettings(file, bytes) : bytes;
    _ensureLive(crypto);
    await file.parent.create(recursive: true);
    _ensureLive(crypto);
    final tmp = File('${file.path}.sync-tmp');
    await tmp.writeAsBytes(merged, flush: true);
    if (!_isLive(crypto)) {
      // Cambió la identidad mientras se escribía: no se instala lo de otra bóveda.
      try {
        await tmp.delete();
      } catch (_) {}
      throw const _Superseded();
    }
    await tmp.rename(file.path);
    final hash = _hash(await _normalized(name, file));
    _ensureLive(crypto);
    _state[key] = {
      'hash': hash,
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
        if (name.length > 64 || !_belongsHere(name)) continue;
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
    // Ni antes ni después de la red: una identidad anterior no envía ni
    // interpreta respuestas.
    _ensureLive(crypto);
    final request = http.Request(method, uri)
      ..headers['authorization'] = 'Bearer ${crypto.authToken}'
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = body;
    // El plazo cubre la petición entera: un cuerpo que se queda a medias no
    // puede dejar el ciclo (y con él `syncing`) colgado para siempre.
    final response = await (() async {
      return http.Response.fromStream(await _client.send(request));
    })()
        .timeout(requestTimeout);
    _ensureLive(crypto);
    final code = response.statusCode;
    if (code == 403) {
      throw const _SyncFailure(
          'El servidor CrotoLink no tiene la sincronización activada.');
    }
    if (code == 401) {
      throw const _SyncFailure(
          'El servidor rechazó la clave de sincronización.');
    }
    if (code == 429) {
      throw const _SyncFailure('Demasiadas peticiones; se reintentará luego.');
    }
    if (code == 507) {
      throw _SyncFailure(_serverError(response) ??
          'El servidor no tiene espacio para sincronizar.');
    }
    if (code >= 400 && code != 404 && code != 409) {
      throw _SyncFailure('El servidor respondió con error ($code).');
    }
    return response;
  }

  /// Mensaje `error` del cuerpo JSON de una respuesta del servidor, si lo trae.
  static String? _serverError(http.Response response) {
    try {
      // El servidor responde JSON en UTF-8 sin declarar el charset.
      final body =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      final error = body is Map ? body['error'] : null;
      return error is String && error.isNotEmpty ? error : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readState() async {
    try {
      final file = File(p.join((await dataDir()).path, _stateFile));
      if (!await file.exists()) return {};
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return {
        for (final e in data.entries)
          e.key: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  /// Guarda el estado de la bóveda activa. Con [crypto], un ciclo de una
  /// identidad anterior no pisa el estado de la actual.
  Future<void> _saveState([SyncCrypto? crypto]) async {
    try {
      final file = File(p.join((await dataDir()).path, _stateFile));
      if (crypto != null) _ensureLive(crypto);
      await file.writeAsString(jsonEncode(_state));
    } on _Superseded {
      rethrow;
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

/// El ciclo pertenece a una identidad que ya no es la vigente. Es un
/// [_SyncFailure] para atravesar los `rethrow` de los pasos tolerantes a fallos.
class _Superseded extends _SyncFailure {
  const _Superseded() : super('');
}
