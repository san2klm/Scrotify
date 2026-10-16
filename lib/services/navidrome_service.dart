import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../models/jam_models.dart';
import '../models/server_profile.dart';
import 'offline_cache_service.dart';
import 'local_music_service.dart';
import 'offline_download_manager.dart';
import 'hifi/hifi_profiles.dart' show StreamQuality;
import 'replay_gain.dart';
import 'scrobble_queue.dart';
import 'server_profiles_controller.dart';
import 'settings_controller.dart';

export 'replay_gain.dart';

part 'navidrome_models.dart';
part 'navidrome_playlists.dart';
part 'navidrome_favorites.dart';
part 'navidrome_library.dart';
part 'navidrome_extras.dart';
part 'navidrome_discovery.dart';

/// Estado de [NavidromeService]. Vive en una clase base para que las áreas de la API
/// (en archivos aparte) puedan ser mixins sobre el mismo estado.
abstract class _NavidromeBase with ChangeNotifier {
  /// GET con timeout. Un servidor que no responde ya no deja la UI esperando.
  Future<http.Response> _get(Uri uri,
          {Duration timeout = const Duration(seconds: 20)}) =>
      _client.get(uri).timeout(timeout);

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

  /// Base HTTP del relay Jam usada para el chat comunitario. Navidrome no
  /// implementa el chat de Subsonic (responde 410), así que se hospeda allí.
  Uri? lobbyBaseUrl;

  /// Publica o anuncia una sesión Jam activa en el servidor Navidrome para que
  /// cualquier usuario conectado a la misma instancia pueda descubrirla y unirse.
  DateTime? _lastJamAnnounce;

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
        (activeProfile.url != _url ||
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
        '&s=$_coverSalt&t=$_coverToken&v=1.16.1&c=Psysonic'
        '&id=${Uri.encodeQueryComponent(coverArtId.toString())}'
        '&size=${size ?? _coverArtSize}';
  }

  Future<void> connectByUrl(String url, String user, String pass) async {
    var processedUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    if (!processedUrl.startsWith('http://') &&
        !processedUrl.startsWith('https://')) {
      processedUrl = 'https://$processedUrl';
    }

    _url = processedUrl;
    _user = user;
    _pass = pass;
    _resetCoverAuth();

    debugPrint('Connecting to $_url');

    _client = _injectedClient ?? http.Client();

    try {
      final salt = _randomSalt();
      final token = _md5('$pass$salt');

      final uri = Uri.parse('$_url/rest/ping.view').replace(queryParameters: {
        'u': user,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
      });

      final response = await _get(uri).timeout(const Duration(seconds: 8));

      debugPrint('Auth response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('Server error: Status ${response.statusCode}. '
            'Check your Navidrome URL and make sure the API is accessible. '
            'Response: ${response.body.substring(0, min(50, response.body.length))}');
      }

      try {
        final data = jsonDecode(response.body);

        if (data['subsonic-response']['status'] == 'ok') {
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
          _trackRatings.clear();
          _cachedGenres = null;
          await _loadPins();
          await _loadStarredOrder();
          await loadLastSelectedGenre();
          notifyListeners();
        } else {
          throw Exception(
              'Authentication failed: ${data['subsonic-response']['error']['message']}');
        }
      } catch (e) {
        if (e.toString().contains('Unexpected character')) {
          throw Exception('Invalid response from server. '
              'The server may not be a Navidrome instance or the API endpoint is incorrect. '
              'Make sure you are using the correct Navidrome URL with /rest/ endpoints.');
        }
        rethrow;
      }
    } catch (e) {
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
    var normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
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
  void _startAutoReconnect() {
    _reconnectTimer ??= Timer.periodic(
        const Duration(seconds: 15), (_) => unawaited(_tryAutoReconnect()));
  }

  void _stopAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _tryAutoReconnect() async {
    if (!_offlineMode || _url == null || _user == null || _pass == null) {
      _stopAutoReconnect();
      return;
    }
    if (_autoReconnecting) return;
    _autoReconnecting = true;
    final session = currentSessionKey;
    try {
      final salt = _randomSalt();
      final uri = Uri.parse('$_url/rest/ping.view').replace(queryParameters: {
        'u': _user!,
        's': salt,
        't': _md5('$_pass$salt'),
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
      });
      final probe = _injectedClient ?? http.Client();
      try {
        final response =
            await probe.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return;
      } finally {
        if (_injectedClient == null) probe.close();
      }
      if (!_offlineMode || currentSessionKey != session) return;
      await reconnect();
      debugPrint('Conexión con el servidor restablecida automáticamente.');
    } catch (_) {
      // Sigue sin red: se reintenta en el próximo ciclo.
    } finally {
      _autoReconnecting = false;
    }
  }

  @override
  void dispose() {
    _stopAutoReconnect();
    super.dispose();
  }

  /// Conserva datos por cuenta y recurre a los archivos locales al perder la red.
  @override
  Future<T> _readLibrary<T>(Future<T> Function() fetch,
      T Function(LocalMusicService music, String scope, String user) fallback,
      {Future<void> Function(LocalMusicService music, String user, T data)?
          remember}) async {
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
    try {
      data = await fetch().timeout(const Duration(seconds: 8));
    } catch (error) {
      if (currentSessionKey != session) rethrow;
      if (isNetworkFailure(error)) {
        _connected = false;
        _offlineMode = true;
        _startAutoReconnect();
        notifyListeners();
      }
      return fallback(music, scope, user);
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
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _get(uri);
    final data = jsonDecode(response.body);
    final folders = _asListOrNull(data['subsonic-response']['musicFolder']);
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
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _get(uri);
    final data = jsonDecode(response.body);

    dynamic indexes = data['subsonic-response']['artists']?['index'];

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
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _get(uri);
    final data = jsonDecode(response.body);

    dynamic indexes = data['subsonic-response']['indexes'];

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
      'c': 'Psysonic',
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
      'c': 'Psysonic',
      'f': 'json',
      'songCount': '100',
      'albumCount': '24',
      'artistCount': '24',
    };
    final uri =
        Uri.parse('$_url/rest/search3.view').replace(queryParameters: params);

    final response = await _get(uri);
    final data = jsonDecode(response.body);
    final result =
        data['subsonic-response']?['searchResult3'] as Map<String, dynamic>?;
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
    _trackRatings.clear();
    _cachedGenres = null;

    notifyListeners();
  }
}
