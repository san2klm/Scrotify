import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show LoopMode, ProcessingState;

import 'jam_notification.dart';
import 'navidrome_service.dart' show Track;
import 'player_controller.dart';

/// Controlador del servicio de medios en segundo plano para Scrotify.
/// Conecta los controles del sistema (notificación de medios, pantalla de
/// bloqueo, botones de auriculares/Bluetooth) con la única instancia
/// activa de [PlayerController], sin crear motores de audio secundarios.
class ScrotifyAudioHandler extends BaseAudioHandler with SeekHandler {
  /// [coverFetcher] guarda la carátula de una pista en un archivo local y
  /// devuelve su ruta. Las URLs remotas llevan credenciales y nunca se
  /// publican; una copia local (`file://`) sí es segura para la notificación.
  ScrotifyAudioHandler({this.coverFetcher});

  final Future<String?> Function(Track track)? coverFetcher;

  /// Acción del botón de favorito del widget (se envía como acción
  /// personalizada de la sesión de medios).
  Future<void> Function()? onToggleLike;

  /// Sale de la Jam (invitado) o la termina (anfitrión) desde el botón de la
  /// notificación.
  Future<void> Function()? onLeaveJam;

  JamNotificationInfo? _jam;
  final Map<String, Uri> _localCovers = {};
  final Set<String> _coversRequested = {};

  PlayerController? _player;
  VoidCallback? _removeListener;

  PlayerController? get player => _player;

  /// Nombre de la acción personalizada que envía el widget para marcar favorito.
  static const customActionToggleLike = 'toggleLike';

  /// Acción del botón «Salir de la Jam» de la notificación.
  static const customActionLeaveJam = 'leaveJam';

  static final _credentialQueryParams = <String>{
    'u',
    't',
    's',
    'p',
    'c',
    'user',
    'username',
    'token',
    'salt',
    'password',
    'pass',
    'auth',
    'apikey',
    'api_key',
    'access_token',
    'secret',
    'credential',
  };

  /// Sanitiza la URI de carátula antes de publicarla en la sesión de medios.
  ///
  /// En esta fase publica ÚNICAMENTE URIs locales seguras (`file://`, `content://`).
  /// Las URLs remotas (`http://`, `https://`) se omiten (`null`) completamente,
  /// ya que pueden contener credenciales en la ruta, firmas o tokens JWT
  /// (como las URLs de carátula firmadas de Navidrome), evitando filtrar secretos
  /// a la sesión de medios del sistema y receptores externos (Bluetooth AVRCP,
  /// Android Auto, logs de MediaSession).
  /// La visualización de carátulas en pantalla de bloqueo queda pendiente de una
  /// implementación de caché local autenticada en archivo.
  static Uri? sanitizeArtUri(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return null;

    // Publicar ÚNICAMENTE esquemas locales seguros (file:// o content://)
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'file' && scheme != 'content') {
      return null;
    }

    // Rechazar credenciales embebidas en userInfo (file://user:pass@host)
    if (uri.userInfo.isNotEmpty) return null;

    // Rechazar URIs con parámetros de consulta de autenticación
    final queryKeys = uri.queryParameters.keys.map((k) => k.toLowerCase());
    if (queryKeys.any(_credentialQueryParams.contains)) {
      return null;
    }

    return uri;
  }

  /// Carátula publicable de [track]: la URI local segura si ya está en caché
  /// y, si no, la pide en segundo plano y vuelve a sincronizar al tenerla.
  Uri? _coverUriFor(Track track) {
    final safe = sanitizeArtUri(track.albumArtUrl);
    if (safe != null) return safe;
    final cached = _localCovers[track.id];
    if (cached != null) return cached;
    final fetcher = coverFetcher;
    final url = track.albumArtUrl;
    if (fetcher != null &&
        url != null &&
        url.isNotEmpty &&
        _coversRequested.add(track.id)) {
      unawaited(() async {
        try {
          final path = await fetcher(track);
          if (path == null) {
            _coversRequested.remove(track.id); // reintentar en la próxima sync
            return;
          }
          _localCovers[track.id] = Uri.file(path);
          final player = _player;
          if (player != null) syncFromPlayer(player);
        } catch (_) {
          _coversRequested.remove(track.id);
        }
      }());
    }
    return null;
  }

  /// Enlaza este handler con el [PlayerController] activo de la aplicación.
  void attachPlayerController(PlayerController player) {
    if (identical(_player, player)) return;
    detachPlayerController();
    _player = player;

    void listener() {
      syncFromPlayer(player);
    }

    player.addListener(listener);
    _removeListener = () => player.removeListener(listener);
    syncFromPlayer(player);
  }

  /// Desvincula el [PlayerController] y limpia el estado para evitar referencias huérfanas.
  void detachPlayerController() {
    _removeListener?.call();
    _removeListener = null;
    _player = null;
    playbackState.add(PlaybackState(
      controls: const [],
      systemActions: const {},
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
    ));
    if (mediaItem.value != null) {
      mediaItem.add(null);
    }
    if (queue.value.isNotEmpty) {
      queue.add(const []);
    }
  }

  /// Indica la Jam en curso (`null` al salir) para mostrarla en la notificación
  /// de medios. Reutiliza la notificación de reproducción: no crea otro
  /// servicio en primer plano, así que aparece mientras haya una pista.
  void setJam(JamNotificationInfo? info) {
    if (_jam == info) return;
    _jam = info;
    final player = _player;
    if (player != null) syncFromPlayer(player);
  }

  /// Sincroniza metadatos, estado de reproducción y cola desde [player].
  void syncFromPlayer(PlayerController player) {
    final track = player.currentTrack;

    if (track == null) {
      if (mediaItem.value != null) {
        mediaItem.add(null);
      }
      if (queue.value.isNotEmpty) {
        queue.add(const []);
      }
      final current = playbackState.value;
      if (current.processingState != AudioProcessingState.idle ||
          current.playing ||
          current.updatePosition != Duration.zero ||
          current.bufferedPosition != Duration.zero ||
          current.queueIndex != null ||
          current.controls.isNotEmpty) {
        playbackState.add(PlaybackState(
          controls: const [],
          systemActions: const {},
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          speed: 1.0,
        ));
      }
      return;
    }

    // 1. Metadatos del lead actual
    final duration = player.duration ?? _parseDuration(track.duration);
    final currentItem = mediaItem.value;
    final artUri = _coverUriFor(track);
    final jam = _jam;
    final subtitle = jam == null ? null : '${track.artist} · ${jam.roomLabel}';
    final String? description = jam?.peopleLabel;

    if (currentItem == null ||
        currentItem.displaySubtitle != subtitle ||
        currentItem.displayDescription != description ||
        currentItem.id != track.id ||
        currentItem.title != track.title ||
        currentItem.artist != track.artist ||
        currentItem.album != track.album ||
        currentItem.duration != duration ||
        currentItem.artUri != artUri) {
      mediaItem.add(MediaItem(
        id: track
            .id, // Seguro: sólo el identificador de la pista, jamás tokens ni URLs firmadas
        album: track.album,
        title: track.title,
        artist: track.artist,
        genre: track.genre,
        duration: duration,
        artUri: artUri,
        displaySubtitle: subtitle,
        displayDescription: description,
      ));
    }

    // 2. Cola ordenada
    final ordered = player.orderedQueue;
    final newQueue = ordered
        .map((t) => MediaItem(
              id: t.id,
              album: t.album,
              title: t.title,
              artist: t.artist,
              genre: t.genre,
              duration: _parseDuration(t.duration),
              artUri: sanitizeArtUri(t.albumArtUrl) ?? _localCovers[t.id],
            ))
        .toList();
    queue.add(newQueue);

    // 3. Estado de reproducción (PlaybackState)
    final isPlaying = player.playing;
    final procState = _mapProcessingState(player);
    final pos = player.position;

    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
      if (jam != null)
        MediaControl.custom(
          androidIcon: 'drawable/audio_service_leave_jam',
          label: jam.leaveLabel,
          name: customActionLeaveJam,
        ),
    ];

    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setShuffleMode,
        MediaAction.setRepeatMode,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: procState,
      playing: isPlaying,
      updatePosition: pos,
      bufferedPosition: pos,
      speed: 1.0,
      queueIndex: player.currentOrderPos >= 0 ? player.currentOrderPos : null,
      repeatMode: _mapRepeatMode(player.repeatMode),
      shuffleMode: player.shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  /// Actualiza inmediatamente la posición en la notificación (p. ej. tras un seek en UI).
  void updatePosition(Duration position) {
    if (playbackState.value.processingState == AudioProcessingState.idle) {
      return;
    }
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
      bufferedPosition: position,
    ));
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == customActionToggleLike) {
      await onToggleLike?.call();
    } else if (name == customActionLeaveJam) {
      await onLeaveJam?.call();
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> play() async {
    final p = _player;
    if (p == null) return;
    if (!p.playing) {
      // just_audio's play() Future solo completa cuando finaliza la reproducción
      // o se pausa. Iniciar de forma desacoplada evita bloquear los controles
      // del sistema Android y el canal de plataforma.
      unawaited(p.togglePlay());
    }
  }

  @override
  Future<void> pause() async {
    final p = _player;
    if (p == null) return;
    if (p.playing) {
      await p.pause();
    }
  }

  @override
  Future<void> stop() async {
    final p = _player;
    if (p != null && p.playing) {
      await p.pause();
    }
    playbackState.add(PlaybackState(
      controls: const [],
      systemActions: const {},
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
    ));
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    final p = _player;
    if (p == null) return;
    unawaited(p.skipNext().catchError((error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'scrotify_audio_handler',
        context: ErrorDescription('while executing skipToNext'),
      ));
    }));
  }

  @override
  Future<void> skipToPrevious() async {
    final p = _player;
    if (p == null) return;
    unawaited(p.skipPrevious().catchError((error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'scrotify_audio_handler',
        context: ErrorDescription('while executing skipToPrevious'),
      ));
    }));
  }

  @override
  Future<void> seek(Duration position) async {
    final p = _player;
    if (p == null) return;
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
      bufferedPosition: position,
    ));
    await p.seek(position);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final p = _player;
    if (p == null) return;
    final targetMode = switch (repeatMode) {
      AudioServiceRepeatMode.none ||
      AudioServiceRepeatMode.group =>
        LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
    };
    if (p.repeatMode != targetMode) {
      await p.toggleRepeat();
      if (p.repeatMode != targetMode) {
        await p.toggleRepeat();
      }
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final p = _player;
    if (p == null) return;
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    if (p.shuffleEnabled != enable) {
      await p.toggleShuffle();
    }
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        unawaited(_player?.togglePlay());
        break;
      case MediaButton.next:
        unawaited(_player?.skipNext());
        break;
      case MediaButton.previous:
        unawaited(_player?.skipPrevious());
        break;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    final p = _player;
    if (p == null || !p.playing) {
      await stop();
    }
  }

  static AudioProcessingState _mapProcessingState(PlayerController player) {
    if (player.currentTrack == null) {
      return AudioProcessingState.idle;
    }
    return switch (player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  static AudioServiceRepeatMode _mapRepeatMode(LoopMode mode) {
    return switch (mode) {
      LoopMode.off => AudioServiceRepeatMode.none,
      LoopMode.one => AudioServiceRepeatMode.one,
      LoopMode.all => AudioServiceRepeatMode.all,
    };
  }

  static Duration? _parseDuration(String durationStr) {
    final seconds = int.tryParse(durationStr);
    return seconds != null ? Duration(seconds: seconds) : null;
  }
}
