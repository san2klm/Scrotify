import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../models/crotolink_models.dart';
import '../models/server_profile.dart';
import 'offline_cache_service.dart';
import 'local_music_service.dart';
import 'offline_download_manager.dart';
import 'hifi/hifi_profiles.dart' show StreamQuality;
import 'replay_gain.dart';
import 'scrobble_queue.dart';
import 'server_profiles_controller.dart';
import 'settings_controller.dart';
import 'subsonic_response.dart';

export 'replay_gain.dart';
export 'subsonic_response.dart';

part 'navidrome_models.dart';
part 'navidrome_playlists.dart';
part 'navidrome_favorites.dart';
part 'navidrome_library.dart';
part 'navidrome_extras.dart';
part 'navidrome_discovery.dart';

/// Nombre con el que la app se identifica ante el servidor (`c=` de Subsonic).
const _clientName = 'CrotoWave';

/// Estado de [NavidromeService]. Vive en una clase base para que las áreas de la API
/// (en archivos aparte) puedan ser mixins sobre el mismo estado.
abstract class _NavidromeBase with ChangeNotifier {
  /// GET con timeout. Un servidor que no responde ya no deja la UI esperando.
  Future<http.Response> _get(Uri uri,
          {Duration timeout = const Duration(seconds: 20)}) =>
      _client.get(uri).timeout(timeout);

  /// GET que devuelve el contenido de `subsonic-response` ya validado: un HTTP
  /// no 2xx, un cuerpo ilegible o `status=failed` lanzan un [SubsonicException]
  /// en vez de pasar por un catálogo vacío.
  Future<Map<String, dynamic>> _getEnvelope(Uri uri,
          {Duration timeout = const Duration(seconds: 20)}) async =>
      parseSubsonicEnvelope(await _get(uri, timeout: timeout));

  /// El servidor responde al ping pero las consultas de catálogo siguen
  /// fallando (5xx o corte de transporte tras el reintento). No es «sin
  /// conexión»: la UI puede ofrecer reintentar. Va ligado a la sesión, así que
  /// cerrar sesión, reconectar o cambiar de cuenta lo descarta solo.
  String? _degradedSession;

  bool _disposed = false;

  String? _lastProbeNote;

  ServerProfilesController? _profilesController;

  String? _url;

  String? _user;

  String? _pass;

  LocalMusicService? localMusic;

  bool _offlineMode = false;

  bool _connected = false;

  http.Client? _injectedClient;

  late http.Client _client;

  int _sessionVersion = 0;

  SettingsController? _settings;

  // Tamaño de portadas y una versión que sube cada vez que cambia, para que
  // las pantallas puedan refrescar su contenido con la nueva resolución.
  int _coverArtSize = 600;

  int _coverArtVersion = 0;

  // Versión de playlists: sube tras una importación/creación/borrado para que
  // las pantallas vuelvan a cargar la lista de playlists.
  int _playlistVersion = 0;

  // Salt/token fijos durante la sesión: con un salt aleatorio por petición, la
  // misma carátula tenía una URL distinta cada vez y la caché de imágenes
  // (indexada por URL) nunca acertaba.
  String? _coverSalt;

  String? _coverToken;

  Timer? _reconnectTimer;

  bool _autoReconnecting = false;

  final Set<String> _starredIds = {};

  final List<String> _starredSongOrder = [];

  // ---------------------------------------------------------------------------
  // Fijar (pin) playlists, artistas seguidos y excluidos
  // ---------------------------------------------------------------------------
  final Set<String> _pinnedPlaylistIds = {};

  final Set<String> _followedArtistIds = {};

  final Set<String> _excludedArtistIds = {};

  final Map<String, Artist> _artistCache = {};
  // Una sola petición por artista a la vez y sin repetir un fallo reciente:
  // las listas reconstruyen sus FutureBuilder y cada build lanzaba otra.
  final Map<String, Future<Artist?>> _artistInFlight = {};
  final Map<String, DateTime> _artistFailedAt = {};

  // ---------------------------------------------------------------------------
  // Rating 1-5 estrellas (Fase 8)
  // ---------------------------------------------------------------------------
  final Map<String, int> _trackRatings = {};

  /// Reloj de la caché del catálogo (sustituible en tests).
  @visibleForTesting
  DateTime Function() recoveryClock = DateTime.now;

  ({String? session, DateTime at, List<Track> tracks})? _recoveryCatalog;

  ({String? session, Future<List<Track>> future})? _recoveryInFlight;

  /// Calidad de reproducción impuesta por el modo de fidelidad (Alta fidelidad
  /// o Bit-perfect). `null` = la calidad elegida en los ajustes. No afecta a
  /// las descargas.
  StreamQuality? hifiStream;

  // ---------------------------------------------------------------------------
  // Descubrimiento y Filtrado (Fase 9)
  // ---------------------------------------------------------------------------

  List<String>? _cachedGenres;

  String? _lastSelectedGenreSuggestion;

  /// Base HTTP del relay CrotoLink usada para el chat comunitario. Navidrome no
  /// implementa el chat de Subsonic (responde 410), así que se hospeda allí.
  Uri? lobbyBaseUrl;

  /// Publica o anuncia una sesión CrotoLink activa en el servidor Navidrome para que
  /// cualquier usuario conectado a la misma instancia pueda descubrirla y unirse.
  DateTime? _lastCrotoLinkAnnounce;

  (String, String) _auth();
  String? _coverArtUrl(
    Object? coverArtId,
    String salt,
    String token, {
    // ignore: unused_element_parameter
    int? size,
  });
  String _md5(String input);
  Map<String, dynamic> _playlistResponse(http.Response response);
  String _randomSalt();
  Future<T> _readLibrary<T>(
    Future<T> Function() fetch,
    T Function(LocalMusicService music, String scope, String user) fallback, {
    Future<void> Function(LocalMusicService music, String user, T data)?
        remember,
    String? key,
  });
  Future<File?> _resolveScopedFile(String name);
  String _scopedName(String name);
  void bumpPlaylists();
  bool get connected;
  String? get currentSessionKey;
  Future<List<Track>> getAlbumTracks(String albumId);
  Future<List<Album>> getAlbums({
    String type = 'newest',
    int limit = 50,
    int offset = 0,
  });
  Future<List<Track>> getTracks({
    String? artist,
    String? album,
    int limit = 500,
    int offset = 0,
  });
  bool get offlineMode;
  String? get serverScope;
}

class NavidromeService extends _NavidromeBase
    with
        _NavidromePlaylists,
        _NavidromeFavorites,
        _NavidromeLibrary,
        _NavidromeExtras,
        _NavidromeDiscovery {
  NavidromeService(
      {SettingsController? settings,
      http.Client? httpClient,
      ServerProfilesController? profilesController}) {
    _injectedClient = httpClient;
    _client = httpClient ?? http.Client();
    if (settings != null) {
      _settings = settings;
      _coverArtSize = settings.coverArtSize;
      settings.addListener(_syncFromSettings);
    }

    // Listen to profile changes for automatic reconnection
    if (profilesController != null) {
      _profilesController = profilesController;
      _profilesController!.addListener(_onActiveProfileChanged);
      // Load initial profile if exists
      // Wait until end of frame to avoid notifying during build
      Future.microtask(() => _loadInitialProfile());
    }

    loadLastSelectedGenre();
  }

  void _onActiveProfileChanged() {
    // When active profile changes, reconnect with new credentials
    final activeProfile = _profilesController?.activeProfile;
    if (activeProfile != null &&
        (normalizeServerUrl(activeProfile.url) != _url ||
            activeProfile.username != _user ||
            activeProfile.password != _pass)) {
      debugPrint(
          'Active profile changed, reconnecting to ${activeProfile.url} as ${activeProfile.username}');
      unawaited(_disconnectAndReconnect(activeProfile));
    } else if (activeProfile == null && (_connected || _offlineMode)) {
      // No active profile, disconnect
      debugPrint('No active profile, disconnecting');
      disconnect();
    }
  }

  void _loadInitialProfile() {
    final activeProfile = _profilesController?.activeProfile;
    if (activeProfile != null) {
      debugPrint('Loading initial profile: ${activeProfile.url}');
      connectByUrl(
              activeProfile.url, activeProfile.username, activeProfile.password)
          .catchError((Object _) {});
    }
  }

  Future<void> _disconnectAndReconnect(ServerProfile profile) async {
    if (_connected || _offlineMode) {
      disconnect();
    }
    try {
      await connectByUrl(profile.url, profile.username, profile.password);
    } catch (e) {
      if (isNetworkFailure(e)) {
        await openOfflineLibrary(
            profile.url, profile.username, profile.password);
      }
      debugPrint('No se pudo reconectar con el servidor.');
    }
  }

  @override
  bool get offlineMode => _offlineMode;

  int get sessionVersion => _sessionVersion;

  /// Clave única representativa de la sesión y usuario actual conectado.
  @override
  String? get currentSessionKey =>
      (_connected || _offlineMode) && _url != null && _user != null
          ? '$_url|$_user#$_sessionVersion'
          : null;

  /// Opaque cache scope segment identifying the current connected server.
  /// Never exposes URLs, usernames, passwords, or tokens.
  @override
  String? get serverScope {
    if (_url == null || _url!.isEmpty) return null;
    return OfflineCacheService.safeScopeSegment(_url!);
  }

  /// Retorna un segmento de ámbito seguro específico para el usuario y servidor actual.
  String? get userScope {
    if (_url == null || _url!.isEmpty) return null;
    final u = _user ?? '';
    if (u.isEmpty) return serverScope;
    return OfflineCacheService.safeScopeSegment('$_url|$u');
  }

  @override
  String _scopedName(String name) {
    final scope = userScope ?? serverScope;
    if (scope == null) return name;
    final parts = name.split('.');
    final ext = parts.length > 1 ? '.${parts.last}' : '';
    final base =
        parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : name;
    return '${base}_$scope$ext';
  }

  @override
  Future<File?> _resolveScopedFile(String name) async {
    try {
      final dir = await getAppDataDirectory();
      final userScopedFile = File('${dir.path}/${_scopedName(name)}');
      if (await userScopedFile.exists()) {
        return userScopedFile;
      }
      final sScope = serverScope;
      if (sScope != null) {
        final parts = name.split('.');
        final ext = parts.length > 1 ? '.${parts.last}' : '';
        final base = parts.length > 1
            ? parts.sublist(0, parts.length - 1).join('.')
            : name;
        final legacyFile = File('${dir.path}/${base}_$sScope$ext');
        if (await legacyFile.exists()) {
          return legacyFile;
        }
      }
      return userScopedFile;
    } catch (_) {
      return null;
    }
  }

  int get coverArtVersion => _coverArtVersion;

  int get playlistVersion => _playlistVersion;

  @override
  void bumpPlaylists() {
    _playlistVersion++;
    notifyListeners();
  }

  String? get serverUrl => _url;

  String? get username => _user;

  @override
  bool get connected => _connected;

  /// Sets connected state directly for isolated testing without credentials or network.
  @visibleForTesting
  void setConnectedForTesting({
    required String url,
    required String username,
    required String password,
    http.Client? client,
  }) {
    _url = url;
    _user = username;
    _pass = password;
    _resetCoverAuth();
    _connected = true;
    _offlineMode = false;
    _sessionVersion++;
    _starredIds.clear();
    _starredSongOrder.clear();
    _pinnedPlaylistIds.clear();
    _followedArtistIds.clear();
    _excludedArtistIds.clear();
    _artistCache.clear();
    _artistFailedAt.clear();
    _trackRatings.clear();
    _cachedGenres = null;
    if (client != null) {
      _injectedClient = client;
      _client = client;
    }
    notifyListeners();
  }

  /// Retorna las credenciales actuales si la sesión está conectada,
  /// útil para compartirlas con el teléfono mediante emparejamiento.
  ({String url, String username, String password})? get currentCredentials {
    if (!_connected || _url == null || _user == null || _pass == null) {
      return null;
    }
    return (url: _url!, username: _user!, password: _pass!);
  }

  void _syncFromSettings() {
    final size = _settings!.coverArtSize;
    if (size != _coverArtSize) {
      _coverArtSize = size;
      _coverArtVersion++;
      notifyListeners();
    }
  }

  @override
  String _randomSalt() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  @override
  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  void _resetCoverAuth() {
    _coverSalt = null;
    _coverToken = null;
  }

  /// Los parámetros `salt`/`token` se mantienen por compatibilidad de firma;
  /// la URL usa credenciales estables de sesión.
  @override
  String? _coverArtUrl(Object? coverArtId, String salt, String token,
      {int? size}) {
    if (coverArtId == null) return null;
    _coverSalt ??= _randomSalt();
    _coverToken ??= _md5('$_pass$_coverSalt');
    return '$_url/rest/getCoverArt.view'
        '?u=${Uri.encodeQueryComponent(_user!)}'
        '&s=$_coverSalt&t=$_coverToken&v=1.16.1&c=$_clientName'
        '&id=${Uri.encodeQueryComponent(coverArtId.toString())}'
        '&size=${size ?? _coverArtSize}';
  }

  /// Vuelve a firmar con la sesión actual una carátula de este servidor que
  /// se guardó sin credenciales (`sanitizeArtUrl`). Otras URLs no cambian.
  String? authorizeCoverArtUrl(String? url) {
    if (url == null || _url == null || _user == null || _pass == null) {
      return url;
    }
    if (!url.startsWith('$_url/rest/getCoverArt.view')) return url;
    final query = Uri.tryParse(url)?.queryParameters;
    final id = query?['id'];
    if (query == null || id == null || query.containsKey('t')) return url;
    return _coverArtUrl(id, '', '', size: int.tryParse(query['size'] ?? ''));
  }

  /// URL tal como la usa la sesión: con esquema y sin `/` final.
  static String normalizeServerUrl(String url) {
    var normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    return normalized;
  }

  /// Generación de la última conexión pedida: una respuesta de una conexión
  /// anterior (más lenta) no debe pisar a la más reciente.
  int _connectGen = 0;

  Future<void> connectByUrl(String url, String user, String pass) async {
    final processedUrl = normalizeServerUrl(url);
    final gen = ++_connectGen;

    debugPrint('Connecting to $processedUrl');

    // Las credenciales nuevas solo se aplican si el servidor las acepta: un
    // intento fallido no deja la sesión actual apuntando a otro perfil.
    final client = _injectedClient ?? http.Client();
    void dropClient() {
      if (_injectedClient == null) client.close();
    }

    try {
      final salt = _randomSalt();
      final token = _md5('$pass$salt');

      final uri =
          Uri.parse('$processedUrl/rest/ping.view').replace(queryParameters: {
        'u': user,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': _clientName,
        'f': 'json',
      });

      final response =
          await client.get(uri).timeout(const Duration(seconds: 8));

      debugPrint('Auth response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('Server error: Status ${response.statusCode}. '
            'Check your Navidrome URL and make sure the API is accessible. '
            'Response: ${response.body.substring(0, min(50, response.body.length))}');
      }

      final dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        throw Exception('Invalid response from server. '
            'The server may not be a Navidrome instance or the API endpoint is incorrect. '
            'Make sure you are using the correct Navidrome URL with /rest/ endpoints.');
      }
      if (data['subsonic-response']['status'] != 'ok') {
        throw Exception(
            'Authentication failed: ${data['subsonic-response']['error']['message']}');
      }
      if (gen != _connectGen) {
        throw StateError('Conexión reemplazada por otra más reciente.');
      }

      final previous = _client;
      _client = client;
      if (_injectedClient == null && !identical(previous, client)) {
        previous.close();
      }
      _url = processedUrl;
      _user = user;
      _pass = pass;
      _resetCoverAuth();
      _connected = true;
      _offlineMode = false;
      _stopAutoReconnect();
      unawaited(flushScrobbles());
      _sessionVersion++;
      _starredIds.clear();
      _starredSongOrder.clear();
      _pinnedPlaylistIds.clear();
      _followedArtistIds.clear();
      _excludedArtistIds.clear();
      _artistCache.clear();
      _artistFailedAt.clear();
      _trackRatings.clear();
      _cachedGenres = null;
      await _loadPins();
      await _loadStarredOrder();
      await loadLastSelectedGenre();
      notifyListeners();
    } catch (_) {
      if (!identical(client, _client)) dropClient();
      rethrow;
    }
  }

  static bool isNetworkFailure(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;

  /// Solo restaura una cuenta guardada con audio disponible; no autentica contra el servidor.
  Future<bool> openOfflineLibrary(
      String url, String username, String password) async {
    final music = localMusic;
    if (music == null) return false;
    await music.initialize();
    final normalized = normalizeServerUrl(url);
    final scope = OfflineCacheService.safeScopeSegment(normalized);
    if (music.count(scope) == 0) return false;
    _url = normalized;
    _user = username;
    _pass = password;
    _connected = false;
    _offlineMode = true;
    _startAutoReconnect();
    _sessionVersion++;
    _resetCoverAuth();
    _starredIds.clear();
    _starredSongOrder.clear();
    _pinnedPlaylistIds.clear();
    _followedArtistIds.clear();
    _excludedArtistIds.clear();
    _artistCache.clear();
    _artistFailedAt.clear();
    _trackRatings.clear();
    _cachedGenres = null;
    await music.bindLegacyCollections(scope, userScope!);
    await _loadPins();
    await _loadStarredOrder();
    _starredIds
        .addAll(music.offlineLikes(scope, userScope!).map((track) => track.id));
    notifyListeners();
    return true;
  }

  Future<void> reconnect() async {
    if (_url == null || _user == null || _pass == null) return;
    await connectByUrl(_url!, _user!, _pass!);
  }

  /// Un fallo de red puntual no debe dejar la app en modo sin conexión para
  /// siempre: mientras esté offline se sondea el servidor y, en cuanto
  /// responde, se vuelve a conectar sin intervención del usuario.
  static const _reconnectEvery = 5;

  /// Cadencia del sondeo de reconexión (sustituible en tests).
  @visibleForTesting
  Duration reconnectInterval = const Duration(seconds: _reconnectEvery);

  /// Plazo de una consulta de catálogo; cada petición HTTP ya tiene el suyo (20 s).
  static const _libraryTimeout = Duration(seconds: 25);

  void _startAutoReconnect() {
    if (_disposed) return;
    _reconnectTimer ??= Timer.periodic(
        reconnectInterval, (_) => unawaited(_tryAutoReconnect()));
  }

  void _stopAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<bool>? _serverProbe;

  String? _serverProbeSession;

  /// El servidor responde al ping pero las consultas de catálogo fallan.
  bool get serverDegraded =>
      _degradedProbes.isNotEmpty &&
      _degradedSession != null &&
      _degradedSession == currentSessionKey;

  /// Consultas de catálogo que siguen fallando con el servidor vivo, por
  /// endpoint, para poder repetirlas tal cual en un reintento manual.
  final Map<String, Future<void> Function()> _degradedProbes = {};

  /// Reintento manual desde la UI: repite las consultas que fallaron. Si alguna
  /// sigue fallando lanza su error y el aviso se mantiene; solo cuando todas
  /// responden se reconecta (la sesión nueva hace que las pantallas recarguen).
  Future<void> retryDegraded() async {
    if (!serverDegraded) return;
    final session = currentSessionKey;
    for (final probe in List.of(_degradedProbes.values)) {
      if (_disposed || currentSessionKey != session) return;
      await probe();
    }
    if (_disposed || currentSessionKey != session) return;
    _degradedProbes.clear();
    _degradedSession = null;
    await reconnect();
  }

  /// `true` si el servidor responde a `ping` con un envelope Subsonic `ok` y la
  /// sesión sigue siendo la misma que la que lo pidió. Usa un cliente nuevo (no
  /// las conexiones que pudieron quedar colgadas) y comparte la sonda solo
  /// entre llamadas simultáneas de la misma sesión: un ping de la cuenta
  /// anterior no puede dar por viva a la nueva.
  Future<bool> _pingServer() {
    final session = currentSessionKey;
    final running = _serverProbe;
    if (running != null && _serverProbeSession == session) return running;
    late final Future<bool> tracked;
    tracked = _pingOnce(session).whenComplete(() {
      if (identical(_serverProbe, tracked)) {
        _serverProbe = null;
        _serverProbeSession = null;
      }
    });
    _serverProbeSession = session;
    return _serverProbe = tracked;
  }

  /// Motivo de un fallo sin credenciales ni cuerpos de respuesta.
  String _safeReason(Object error) =>
      error is SubsonicException ? error.toString() : '${error.runtimeType}';

  Future<bool> _pingOnce(String? session) async {
    final url = _url, user = _user, pass = _pass;
    if (session == null || url == null || user == null || pass == null) {
      return false;
    }
    try {
      final salt = _randomSalt();
      final uri = Uri.parse('$url/rest/ping.view').replace(queryParameters: {
        'u': user,
        's': salt,
        't': _md5('$pass$salt'),
        'v': '1.16.1',
        'c': _clientName,
        'f': 'json',
      });
      final probe = _injectedClient ?? http.Client();
      try {
        final response =
            await probe.get(uri).timeout(const Duration(seconds: 6));
        parseSubsonicEnvelope(response, requireOk: true);
      } finally {
        if (_injectedClient == null) probe.close();
      }
    } catch (error) {
      final reason = _safeReason(error);
      if (reason != _lastProbeNote) {
        _lastProbeNote = reason;
        debugPrint('El servidor no pasó el ping: $reason');
      }
      return false;
    }
    _lastProbeNote = null;
    return currentSessionKey == session;
  }

  String? _lastReconnectNote;

  Future<void> _tryAutoReconnect() async {
    if (_disposed ||
        !_offlineMode ||
        _url == null ||
        _user == null ||
        _pass == null) {
      _stopAutoReconnect();
      return;
    }
    if (_autoReconnecting) return;
    _autoReconnecting = true;
    final session = currentSessionKey;
    try {
      if (!await _pingServer()) return;
      if (_disposed || !_offlineMode || currentSessionKey != session) return;
      await reconnect();
      _lastReconnectNote = null;
      debugPrint('Conexión con el servidor restablecida automáticamente.');
    } catch (error) {
      // Se reintenta en el próximo ciclo; el motivo se registra una vez por
      // cambio para no inundar el log cada 5 s.
      final reason = _safeReason(error);
      if (reason != _lastReconnectNote) {
        _lastReconnectNote = reason;
        debugPrint('Reconexión automática fallida: $reason');
      }
    } finally {
      _autoReconnecting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectGen++; // una conexión en curso no debe revivir la sesión
    _stopAutoReconnect();
    super.dispose();
  }

  /// Conserva datos por cuenta y recurre a los archivos locales al perder la red.
  @override
  Future<T> _readLibrary<T>(Future<T> Function() fetch,
      T Function(LocalMusicService music, String scope, String user) fallback,
      {Future<void> Function(LocalMusicService music, String user, T data)?
          remember,
      String? key}) async {
    final endpoint = key ?? '$T';
    final music = localMusic;
    final scope = serverScope;
    final user = userScope;
    if (music == null || scope == null || user == null) return fetch();
    try {
      await music.initialize();
    } catch (_) {
      if (_connected && !_offlineMode) return fetch();
      rethrow;
    }
    await music.bindLegacyCollections(scope, user);
    if (!_connected || _offlineMode) return fallback(music, scope, user);
    final session = currentSessionKey;
    T data;
    // Transporte = corte de red o 5xx. Credenciales rechazadas, 4xx o cuerpos
    // ilegibles no se reintentan ni se esconden tras el respaldo local.
    bool isTransport(Object error) =>
        isNetworkFailure(error) || isTransientServerError(error);
    try {
      try {
        data = await fetch().timeout(_libraryTimeout);
      } catch (error) {
        // Un enlace saturado hace tardar la primera petición; si el servidor
        // responde al ping se reintenta una vez antes de caer al respaldo local
        // (que puede estar vacío y Home no lo vuelve a pedir).
        if (!isTransport(error) ||
            currentSessionKey != session ||
            !await _pingServer()) {
          rethrow;
        }
        debugPrint(
            'Biblioteca lenta (${_safeReason(error)}); se reintenta una vez.');
        data = await fetch().timeout(_libraryTimeout);
      }
      // Solo este endpoint deja de estar degradado: que otro responda bien no
      // borra el aviso de uno que sigue fallando.
      if (_degradedSession == session &&
          _degradedProbes.remove(endpoint) != null) {
        if (_degradedProbes.isEmpty) _degradedSession = null;
        if (!_disposed) notifyListeners();
      }
    } catch (error) {
      if (currentSessionKey != session || !isTransport(error)) rethrow;
      // Una petición lenta o cortada no es una caída: solo se pasa a «sin
      // conexión» si el servidor tampoco responde a un ping. Si no, cada
      // lentitud puntual tiraba a toda la app y la reconexión recargaba todo.
      final alive = await _pingServer();
      if (currentSessionKey != session) rethrow;
      if (!alive) {
        if (_connected) {
          debugPrint('Sin conexión: ${_safeReason(error)} y el servidor no '
              'respondió al ping; se reintenta cada $_reconnectEvery s.');
          _connected = false;
          _offlineMode = true;
          _startAutoReconnect();
          if (!_disposed) notifyListeners();
        }
        return fallback(music, scope, user);
      }
      // El servidor está vivo pero la consulta sigue fallando: no se presenta
      // un respaldo vacío como si fuera el catálogo. Con respaldo útil se
      // muestra y se marca la degradación; sin él, el error llega a la UI.
      debugPrint(
          'Consulta fallida con el servidor vivo: ${_safeReason(error)}');
      if (_degradedSession != session) {
        _degradedProbes.clear();
        _degradedSession = session;
      }
      final firstFailure = !_degradedProbes.containsKey(endpoint);
      _degradedProbes[endpoint] =
          () async => await fetch().timeout(_libraryTimeout);
      if (firstFailure && !_disposed) notifyListeners();
      final stored = fallback(music, scope, user);
      if (stored == null || (stored is Iterable && stored.isEmpty)) rethrow;
      return stored;
    }
    // Una respuesta atrasada no debe guardarse bajo una cuenta nueva.
    if (currentSessionKey == session && remember != null) {
      try {
        await remember(music, user, data);
      } catch (_) {
        debugPrint('No se pudo guardar la biblioteca sin conexión.');
      }
    }
    if (currentSessionKey == session) {
      Future<void> cacheArtwork() async {
        if (data is List<Track>) {
          await music.cacheDownloadedArtwork(scope, data);
        } else if (data is List<Playlist>) {
          for (final playlist in data) {
            await music.cachePlaylistArtwork(scope, playlist);
          }
        } else if (data is Playlist) {
          await music.cachePlaylistArtwork(scope, data);
        }
      }

      // Las portadas se completan sin bloquear la apertura de la biblioteca.
      unawaited(cacheArtwork().catchError((Object _) {}));
    }
    return data;
  }

  Future<List<dynamic>> getMusicFolders() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getMusicFolders.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
    });

    final data = await _getEnvelope(uri);
    final folders = _asListOrNull(data['musicFolder']);
    return folders ?? [];
  }

  Future<List<dynamic>> getArtists() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getArtists.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
    });

    final data = await _getEnvelope(uri);

    dynamic indexes = data['artists']?['index'];

    if (indexes == null) {
      return [];
    }

    // getArtists devuelve el id de coverArt, no una URL. Normalizarlo aquí
    // para que los consumidores de este método puedan cargar la imagen igual
    // que los álbumes y resultados de búsqueda.
    final List<dynamic> allArtists = [];
    for (final index in _asList(indexes)) {
      if (index is! Map) continue;

      for (final rawArtist in _asList(index['artist'])) {
        if (rawArtist is! Map) continue;

        final artist = Map<String, dynamic>.from(rawArtist);
        artist['coverArt'] = _coverArtUrl(artist['coverArt'], salt, token);
        allArtists.add(artist);
        try {
          final model = Artist.fromJson(artist,
              coverArtUrl: artist['coverArt'] as String?);
          _artistCache[model.id] = model;
        } catch (err) {
          debugPrint('navidrome_service:688 ignorado: $err');
        }
      }
    }

    debugPrint('getArtists result count: ${allArtists.length}');
    return allArtists;
  }

  Future<List<dynamic>> getIndexes() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getIndexes.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
    });

    final data = await _getEnvelope(uri);

    dynamic indexes = data['indexes'];

    if (indexes == null) {
      return [];
    }

    if (indexes is Map && indexes.containsKey('index')) {
      final list = _asListOrNull(indexes['index']);
      return list ?? [];
    }

    if (indexes is List) {
      return indexes;
    }

    debugPrint('getIndexes unknown format: $indexes');
    return [];
  }

  @override
  (String, String) _auth() {
    final salt = _randomSalt();
    return (salt, _md5('$_pass$salt'));
  }

  /// Una canción por ID (`getSong.view`); `null` si no existe en este servidor.
  Future<Track?> getSong(String id) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getSong.view').replace(queryParameters: {
      'id': id,
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
    });
    final response = await _get(uri);
    final resp = jsonDecode(response.body)['subsonic-response'];
    final song = resp?['song'];
    if (resp?['status'] == 'failed' || song is! Map<String, dynamic>) {
      return null;
    }
    return Track.fromJson(song,
        albumArtUrl: _coverArtUrl(song['coverArt'], salt, token));
  }

  Future<SearchResults> search(String query) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();

    final params = <String, String>{
      'query': query,
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
      'songCount': '100',
      'albumCount': '24',
      'artistCount': '24',
    };
    final uri =
        Uri.parse('$_url/rest/search3.view').replace(queryParameters: params);

    final data = await _getEnvelope(uri);
    final result = data['searchResult3'] as Map<String, dynamic>?;
    if (result == null) {
      return SearchResults(songs: [], albums: [], artists: []);
    }

    Track mapSong(dynamic j) => Track.fromJson(
          j as Map<String, dynamic>,
          albumArtUrl: _coverArtUrl(j['coverArt'], salt, token),
        );
    Album mapAlbum(dynamic j) => Album.fromJson(
          j as Map<String, dynamic>,
          coverArtUrl: _coverArtUrl(j['coverArt'], salt, token),
        );
    Artist mapArtist(dynamic j) => Artist.fromJson(
          j as Map<String, dynamic>,
          coverArtUrl: _coverArtUrl(j['coverArt'], salt, token),
        );

    return SearchResults(
      songs: _asList(result['song']).map(mapSong).toList(),
      albums: _asList(result['album']).map(mapAlbum).toList(),
      artists: _asList(result['artist']).map(mapArtist).toList(),
    );
  }

  static List<dynamic>? _asListOrNull(dynamic value) =>
      value == null ? null : _asList(value);

  static List<dynamic> _asList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    return [value];
  }

  /// Cuánto se reutiliza el catálogo de recuperación antes de pedirlo otra vez.
  /// Es corto a propósito: cubre reescaneos seguidos (p. ej. tras cancelar) sin
  /// esconder canciones que se acaban de añadir al servidor.
  static const recoveryCatalogTtl = Duration(minutes: 3);

  void disconnect() {
    _connectGen++; // un login en curso no debe reconectar tras cerrar sesión
    _stopAutoReconnect();
    _connected = false;
    _offlineMode = false;
    _url = null;
    _user = null;
    _pass = null;
    _resetCoverAuth();
    _client.close();
    _client = _injectedClient ?? http.Client();

    // Clear state
    _starredIds.clear();
    _starredSongOrder.clear();
    _pinnedPlaylistIds.clear();
    _followedArtistIds.clear();
    _excludedArtistIds.clear();
    _artistCache.clear();
    _artistFailedAt.clear();
    _trackRatings.clear();
    _cachedGenres = null;

    notifyListeners();
  }
}
