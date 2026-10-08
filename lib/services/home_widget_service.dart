import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';
import 'player_controller.dart';

/// Mantiene sincronizado el widget de pantalla de inicio de Android
/// (carátula, título, artista y estado play/pausa) con el reproductor.
///
/// Solo empuja datos cuando cambia algo visible (pista o play/pausa) y agrupa
/// cambios rápidos (p. ej. saltar varias pistas seguidas) con un debounce, así
/// no despierta al lanzador del sistema en cada notificación del reproductor.
class HomeWidgetService {
  /// Nombres calificados de los `AppWidgetProvider` nativos (un diseño cada uno).
  static const List<String> androidProviders = [
    'com.example.navidrome_client.ScrotifyWidgetProvider',
    'com.example.navidrome_client.ScrotifyCompactWidgetProvider',
    'com.example.navidrome_client.ScrotifyCoverWidgetProvider',
  ];

  // Claves compartidas con ScrotifyWidgetProvider.kt
  static const String keyTitle = 'widget_title';
  static const String keyArtist = 'widget_artist';
  static const String keyAlbum = 'widget_album';
  static const String keyLiked = 'widget_liked';
  static const String keyPlaying = 'widget_playing';
  static const String keyCoverPath = 'widget_cover_path';

  final PlayerController _player;
  final NavidromeService? _library;
  final bool Function(Track track)? _isLiked;
  final Duration debounce;

  // Puntos de inyección (tests): por defecto usan el plugin real.
  final Future<void> Function(String key, Object? value) _save;
  final Future<void> Function() _refresh;
  final Future<String?> Function(Track track) _fetchCover;

  Timer? _timer;
  String? _lastSignature;
  bool _started = false;

  HomeWidgetService(
    this._player, {
    NavidromeService? library,
    bool Function(Track track)? isLiked,
    this.debounce = const Duration(milliseconds: 400),
    Future<void> Function(String key, Object? value)? save,
    Future<void> Function()? refresh,
    Future<String?> Function(Track track)? fetchCover,
  })  : _library = library,
        _isLiked = isLiked ??
            (library == null ? null : (t) => library.isStarred(t.id)),
        _save = save ?? _defaultSave,
        _refresh = refresh ?? _defaultRefresh,
        _fetchCover = fetchCover ?? _defaultFetchCover;

  /// El widget solo existe en Android.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  void start() {
    if (_started) return;
    _started = true;
    _player.addListener(_onPlayerChanged);
    _library?.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }

  void dispose() {
    _timer?.cancel();
    if (_started) {
      _player.removeListener(_onPlayerChanged);
      _library?.removeListener(_onPlayerChanged);
    }
    _started = false;
  }

  void _onPlayerChanged() {
    final track = _player.currentTrack;
    final signature = '${track?.id}|${_player.playing}|${_liked(track)}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    _timer?.cancel();
    _timer = Timer(debounce, push);
  }

  bool _liked(Track? track) =>
      track != null && (_isLiked?.call(track) ?? false);

  /// Escribe el estado actual y pide al sistema que redibuje el widget.
  @visibleForTesting
  Future<void> push() async {
    try {
      final track = _player.currentTrack;
      final playing = _player.playing;
      String? coverPath;
      if (track != null) coverPath = await _fetchCover(track);

      await _save(keyTitle, track?.title);
      await _save(keyArtist, track?.artist);
      await _save(keyAlbum, track?.album);
      await _save(keyLiked, _liked(track));
      await _save(keyPlaying, track != null && playing);
      await _save(keyCoverPath, coverPath);
      await _refresh();
    } catch (e) {
      debugPrint('HomeWidgetService.push: $e');
    }
  }

  static Future<void> _defaultSave(String key, Object? value) =>
      HomeWidget.saveWidgetData<dynamic>(key, value);

  static Future<void> _defaultRefresh() async {
    for (final provider in androidProviders) {
      await HomeWidget.updateWidget(qualifiedAndroidName: provider);
    }
  }

  /// Descarga la carátula a un archivo estable que lee el código nativo.
  static String? _coverTrackId;
  static String? _coverPath;

  static Future<String?> _defaultFetchCover(Track track) async {
    final url = track.albumArtUrl;
    if (url == null || url.isEmpty) return null;
    if (_coverTrackId == track.id && _coverPath != null) return _coverPath;
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/widget_cover.img');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      _coverTrackId = track.id;
      _coverPath = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
