import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/crotolink_capabilities.dart';
import '../models/crotolink_models.dart';
import '../utils/app_links.dart';
import 'crotolink_guest_service.dart';
import 'crotolink_clock.dart';
import 'crotolink_history.dart';
import 'crotolink_notification.dart';
import 'crotolink_host_service.dart';
import 'crotolink_queue_logic.dart';
import 'crotolink_social.dart';
import 'crotolink_track_resolver.dart';
import 'crotolink_tls_identity.dart';
import 'navidrome_service.dart';
import 'player_controller.dart';
import 'remote_crotolink_service.dart';
import 'settings_controller.dart';

part 'crotolink_social_part.dart';
part 'crotolink_host_queue.dart';
part 'crotolink_guest_remote.dart';
part 'crotolink_host_session.dart';
part 'crotolink_join.dart';
part 'crotolink_guest_sync.dart';

/// Estado de [CrotoLinkController]. Vive en una clase base para que las áreas de la CrotoLink
/// (en archivos aparte) puedan ser mixins sobre el mismo estado.
abstract class _CrotoLinkBase extends ChangeNotifier {
  final CrotoLinkHostService _hostService = CrotoLinkHostService();

  final CrotoLinkGuestService _guestService = CrotoLinkGuestService();

  final RemoteCrotoLinkService _remoteService = RemoteCrotoLinkService();

  CrotoLinkRole _role = CrotoLinkRole.none;

  CrotoLinkSessionState? _session;

  CrotoLinkParticipant? _localParticipant;

  final List<CrotoLinkParticipant> _remoteParticipants = [];

  final Set<String> _kickedRemoteNames = {};

  List<DiscoveredCrotoLinkSession> _discoveredSessions = [];

  bool _isScanningRadar = false;

  /// Motivo legible del último [joinSession] fallido, para mostrar en UI.
  String? lastJoinError;

  /// Motivo legible del último fallo de acción colaborativa, para mostrar en UI.
  String? lastActionError;

  // Cola de items con trazabilidad (solo en Host)
  final List<CrotoLinkQueueItem> _hostCrotoLinkQueue = [];

  final Map<String, CrotoLinkParticipant?> _trackAddedBy = {};

  CrotoLinkParticipant? _currentTrackAddedBy;

  int _queueRevision = 0;

  // Modos de cola (decididos por el host; el relay solo reenvía).
  CrotoLinkQueueMode _queueMode = CrotoLinkQueueMode.free;

  int _fairTurnsPerPerson = 1;

  bool _requireApproval = false;

  final List<CrotoLinkQueueRequest> _pendingRequests = [];

  final CrotoLinkVoteBook _votes = CrotoLinkVoteBook();

  final Set<String> _pinnedIds = {};

  final Map<String, int> _myVotes = {}; // lado invitado (optimista)

  bool _hasRoomPassword = false;

  // Reacciones y chat (efímeros, solo RAM).
  final CrotoLinkReactionFeed _reactions = CrotoLinkReactionFeed();

  final CrotoLinkChatLog _chat = CrotoLinkChatLog();

  CrotoLinkCapabilities _cloudCaps = CrotoLinkCapabilities.legacy;

  String? _cloudCapsEndpoint;

  bool _chatEnabledForRoom = true;

  Timer? _reactionSweep;

  late final CrotoLinkTrackResolver _resolver = CrotoLinkTrackResolver(
    getSong: _navidrome.getSong,
    searchSongs: (q) async => (await _navidrome.search(q)).songs,
  );

  bool _resolvingQueue = false;

  /// Aviso discreto cuando la pista actual del host no existe en mi biblioteca.
  String? unavailableNotice;

  String? _hintSentForTrackId;

  String? _hintPreloadedTrackId;

  // Historial (en RAM): el host lo registra al reproducir; el invitado lo
  // reconstruye observando el estado de la sala (solo desde que entró).
  final CrotoLinkHistory _history = CrotoLinkHistory();

  late final CrotoLinkGuestHistoryTracker _guestHistory =
      CrotoLinkGuestHistoryTracker(_history);

  String? _historyOwnerName;

  Track? _histTrack;

  CrotoLinkParticipant? _histAddedBy;

  Duration _histMaxPos = Duration.zero;

  final Map<String, int> _lastVotesByTrack = {};

  int _lastSyncServerTimestamp = 0;

  int _syncGeneration = 0;

  bool _remoteCreating = false;

  int _remoteCreateFailures = 0;

  DateTime? _nextRemoteCreateAt;

  Timer? _hostSyncHeartbeat;

  Timer? _hostPublishTimer;

  Future<void> _addTrackAsHost(
    Track track,
    CrotoLinkParticipant? addedBy, {
    required bool playNext,
    // ignore: unused_element_parameter
    bool bypassApproval = false,
  });
  Future<void> _applyPlaybackAction(String action, {Duration? position});
  void _applyRemoteStateSync(Map<String, dynamic> state);
  void _clearActionError();
  String _getDefaultDeviceName();
  void _handleNextHint(Track next, int startAtServerMs);
  Future<void> _handleRemoteHostChanged(
    bool youAreHost,
    String hostName,
    List<Map<String, dynamic>> guests,
  );
  void _handleVote(String itemId, int value, String participantId);
  Future<void> _loadCloudCapabilities();
  NavidromeService get _navidrome;
  ({Track track, int startAtLocalMs})? _nextTrackHint();
  PlayerController get _player;
  void _publishHostState({bool includePlayback = false});
  void _publishToNavidromeIfPublic();
  void _rebuildHostQueueFromPlayer();
  // ignore: unused_element_parameter
  void _receiveChat(String from, String text, {bool mine = false});
  void _receiveReaction(String from, String emoji);
  CrotoLinkServerEndpoint get _remoteEndpoint;
  void _removeTrackAsHost(String queueItemId);
  void _reorderQueueAsHost(int oldIndex, int newIndex);
  void _reportActionError(String message);
  void _scheduleQueueResolve();
  void _startGuestHistory(String name);
  Future<void> _syncGuestAudioIfApplicable({
    Track? track,
    required bool isPlaying,
    required int positionMs,
    required int serverTs,
    bool tsIsLocal = false,
  });
  void _syncHostState();
  Map<String, dynamic> _trackHintJson(Track t);
  bool get inCrotoLink;
  bool get isGuest;
  bool get isHost;
  bool get isPublic;
  Future<void> leaveOrEndSession();
}

/// Controlador principal de sesiones CrotoLink.
/// Actúa como puente entre los servicios de red ([CrotoLinkHostService], [CrotoLinkGuestService], [RemoteCrotoLinkService])
/// y el reproductor de audio ([PlayerController]).
class CrotoLinkController extends _CrotoLinkBase
    with
        _CrotoLinkSocial,
        _CrotoLinkHostQueue,
        _CrotoLinkGuestRemote,
        _CrotoLinkHostSession,
        _CrotoLinkJoin,
        _CrotoLinkGuestSync {
  @override
  final PlayerController _player;

  @override
  final NavidromeService _navidrome;

  static const int _maxPendingRequests = 50;

  /// ¿Esta pista de la CrotoLink no está en MI biblioteca? (solo invitado en modo
  /// sincronizado, y solo si ya se resolvió).
  bool isUnavailableForMe(String remoteTrackId) {
    if (_role != CrotoLinkRole.guest ||
        _session?.mode != CrotoLinkMode.synchronizedListening) {
      return false;
    }
    final r = _resolver.cached(remoteTrackId);
    return r != null && !r.isAvailable;
  }

  /// Resuelve la cola por lotes en segundo plano (no bloquea la UI).
  @override
  void _scheduleQueueResolve() {
    if (_resolvingQueue ||
        _role != CrotoLinkRole.guest ||
        _session?.mode != CrotoLinkMode.synchronizedListening) {
      return;
    }
    final tracks = [
      if (_session!.currentTrack != null) _session!.currentTrack!,
      ..._session!.queue.map((q) => q.track),
    ];
    if (tracks.every((t) => _resolver.cached(t.id) != null)) return;
    _resolvingQueue = true;
    unawaited(_resolver
        .resolveBatch(tracks,
            onProgress: notifyListeners,
            isCancelled: () => _role != CrotoLinkRole.guest)
        .whenComplete(() {
      _resolvingQueue = false;
    }));
  }

  bool get hasRoomPassword => _hasRoomPassword;

  final SettingsController? _settings;

  /// Endpoint remoto vigente ya validado (host/puerto para anunciar salas).
  @override
  CrotoLinkServerEndpoint get _remoteEndpoint =>
      CrotoLinkServerEndpoint.parse(_remoteService.endpoint);

  CrotoLinkController(this._player, this._navidrome,
      {SettingsController? settings})
      : _settings = settings {
    _applyServerUrl();
    _settings?.addListener(_applyServerUrl);
    _initHostCallbacks();
    _initGuestCallbacks();
    _initRemoteCallbacks();
    debugPrint(
      '[CROTOLINK] CrotoLinkController init: id=${identityHashCode(this)} '
      'rev=${_session?.queueRevision ?? 0} qLen=${_session?.queue.length ?? 0} '
      'trackId=${_session?.currentTrack?.id} '
      'canCtrl=${_localParticipant?.canControlPlayback ?? false} '
      'canQueue=${_localParticipant?.canManageQueue ?? false}',
    );
  }

  void _applyServerUrl() {
    final url = _settings?.crotoLinkServerUrl;
    if (url != null) {
      final ep = CrotoLinkServerEndpoint.parse(url);
      _navidrome.lobbyBaseUrl = ep.isValid ? ep.httpBase : null;
    }
    if (url != null && url != _remoteService.endpoint) {
      _remoteService.setEndpoint(url);
    }
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  CrotoLinkRole get role => _role;

  CrotoLinkSessionState? get session => _session;

  CrotoLinkParticipant? get localParticipant => _localParticipant;

  List<CrotoLinkParticipant> get participants => _session?.participants ?? [];

  List<CrotoLinkQueueItem> get crotoLinkQueue => _session?.queue ?? [];

  List<CrotoLinkQueueItem> get queue => crotoLinkQueue;

  bool isTrackInCrotoLinkQueue(String trackId) =>
      crotoLinkQueue.any((qi) => qi.track.id == trackId);

  CrotoLinkMode get mode =>
      _session?.mode ?? CrotoLinkMode.synchronizedListening;

  @override
  bool get isHost => _role == CrotoLinkRole.host;

  @override
  bool get isGuest => _role == CrotoLinkRole.guest;

  @override
  bool get inCrotoLink => _role != CrotoLinkRole.none;

  List<DiscoveredCrotoLinkSession> get discoveredSessions =>
      _discoveredSessions;

  bool get isScanningRadar => _isScanningRadar;

  String? get allHostIpsFormatted => _hostService.allLocalIps.isEmpty
      ? null
      : _hostService.allLocalIps.join(', ');

  String? get currentCodeFormatted =>
      _hostService.pinCode?.formatted ??
      (_session?.pinCode.isNotEmpty == true
          ? '${_session!.pinCode.substring(0, 3)}-${_session!.pinCode.substring(3)}'
          : null);

  /// QR de invitación: con el relay (dominio de la CrotoLink) conectado lleva el
  /// dominio y funciona desde cualquier red; si no, usa la IP local (LAN).
  String? get qrUri {
    final pin = _hostService.pinCode?.value;
    final ep = _remoteEndpoint;
    if (pin != null && _remoteService.isConnected && ep.isValid) {
      final server = ep.port == 443 ? ep.host : '${ep.host}:${ep.port}';
      return Uri(
        scheme: kAppLinkScheme,
        host: 'join',
        queryParameters: {'code': pin, 'server': server},
      ).toString();
    }
    return _hostService.qrDataUri;
  }

  String? get hostIp => _hostService.hostIp;

  int get port => _hostService.port;

  bool get allowGuestControls => _session?.allowGuestControls ?? true;

  bool get allowGuestQueueManage => _session?.allowGuestQueueManage ?? true;

  @override
  bool get isPublic => _session?.isPublic ?? true;

  int get maxParticipants => _session?.maxParticipants ?? 0;

  CrotoLinkParticipant? get currentTrackAddedBy => _currentTrackAddedBy;

  /// Datos de la CrotoLink para la notificación de medios; `null` fuera de una sala.
  CrotoLinkNotificationInfo? get notificationInfo {
    final session = _session;
    if (_role == CrotoLinkRole.none || session == null) return null;
    // El número solo es fiable si lo conoce este dispositivo: el anfitrión, o
    // un invitado de LAN (recibe la lista). Por el servidor central, no.
    final known = _role == CrotoLinkRole.host || _guestService.isConnected;
    return CrotoLinkNotificationInfo(
      hostName: session.hostName,
      isHost: _role == CrotoLinkRole.host,
      participants: known ? session.participants.length : null,
    );
  }

  CrotoLinkHistory get history => _history;

  CrotoLinkHistorySummary get historySummary => _history.summary();

  /// Nombre con el que este dispositivo entró en la última CrotoLink como invitado,
  /// para ofrecer «guardar mis aportaciones». `null` si fue anfitrión.
  String? get historyOwnerName => _historyOwnerName;

  /// Aportaciones del invitado local en el historial (por nombre: en la nube el
  /// id que ve el invitado no es estable).
  List<CrotoLinkHistoryEntry> get myContributions {
    final me = _historyOwnerName;
    if (me == null) return const [];
    return [
      for (final e in _history.entries)
        if (e.addedBy?.name == me) e
    ];
  }

  /// Crea en Navidrome una playlist con lo que añadió este invitado.
  Future<int> saveMyContributionsAsPlaylist() =>
      _savePlaylist(myContributions, 'Mis aportaciones al CrotoLink');

  /// Crea en Navidrome una playlist "CrotoLink {fecha}" con el historial (opcionalmente
  /// solo las pistas de [participantId]). Devuelve cuántas pistas guardó.
  Future<int> saveHistoryAsPlaylist({String? participantId}) {
    final entries = participantId == null
        ? _history.entries
        : _history.byParticipant(participantId);
    return _savePlaylist(entries, 'CrotoLink');
  }

  Future<int> _savePlaylist(
      List<CrotoLinkHistoryEntry> entries, String prefix) async {
    if (entries.isEmpty) return 0;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final playlist = await _navidrome.createPlaylist('$prefix $date');
    if (playlist == null) throw Exception('No se pudo crear la playlist.');
    await _navidrome.updatePlaylist(
      playlistId: playlist.id,
      songIdsToAdd: entries.map((e) => e.track.id).toList(),
    );
    return entries.length;
  }

  CrotoLinkQueueMode get queueMode => _session?.queueMode ?? _queueMode;

  int get fairTurnsPerPerson =>
      _session?.fairTurnsPerPerson ?? _fairTurnsPerPerson;

  bool get requireApproval => _session?.requireApproval ?? _requireApproval;

  bool get approvalActive => _session?.approvalActive ?? false;

  List<CrotoLinkQueueRequest> get pendingRequests =>
      _session?.pendingRequests ?? const [];

  /// Solicitudes propias de este invitado (por nombre; en remoto el id lo
  /// asigna el host y el invitado no lo conoce).
  List<CrotoLinkQueueRequest> get myPendingRequests => pendingRequests
      .where((r) => r.requestedByName == _localParticipant?.name)
      .toList();

  /// Mi voto (−1/0/+1) sobre un ítem de la cola.
  int myVoteFor(String itemId) =>
      isHost ? _votes.myVote(itemId, 'host_local') : (_myVotes[itemId] ?? 0);

  CrotoLinkConnectionState get connectionState => _guestService.connectionState;

  int get queueRevision =>
      isGuest ? _guestService.queueRevision : _queueRevision;

  String? get lastError =>
      lastActionError ?? lastJoinError ?? _guestService.lastError;

  // ---------------------------------------------------------------------------
  // Acciones Compartidas (Cola y Reproducción)
  // ---------------------------------------------------------------------------

  Future<void> addTrackToCrotoLink(Track track, {bool playNext = false}) async {
    if (!inCrotoLink) return;
    _clearActionError();

    if (isHost) {
      await _addTrackAsHost(track, _localParticipant, playNext: playNext);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.addToQueue(track, playNext: playNext);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('queue_add', {
          'track': {
            'id': track.id,
            'title': track.title,
            'artist': track.artist,
            'album': track.album,
            'albumArtUrl': sanitizeArtUrl(track.albumArtUrl),
            'duration': track.duration,
          },
          'playNext': playNext,
        });
      } else {
        _reportActionError(
            'No hay conexión activa con el anfitrión CrotoLink.');
      }
    }
  }

  void removeTrackFromCrotoLink(String queueItemId, {int? orderIndex}) {
    if (!inCrotoLink) return;
    _clearActionError();

    if (isHost) {
      _removeTrackAsHost(queueItemId);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.removeFromQueue(queueItemId);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('queue_remove', {
          'queueItemId': queueItemId,
        });
      } else {
        _reportActionError(
            'No hay conexión activa con el anfitrión CrotoLink.');
      }
    }
  }

  void reorderCrotoLinkQueue(int oldIndex, int newIndex) {
    if (!inCrotoLink) return;
    _clearActionError();

    if (isHost) {
      _reorderQueueAsHost(oldIndex, newIndex);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.reorderQueue(oldIndex, newIndex);
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('queue_reorder', {
          'oldIndex': oldIndex,
          'newIndex': newIndex,
        });
      } else {
        _reportActionError(
            'No hay conexión activa con el anfitrión CrotoLink.');
      }
    }
  }

  Future<void> playbackAction(String action, {Duration? position}) async {
    if (!inCrotoLink) return;
    _clearActionError();

    if (isHost) {
      await _applyPlaybackAction(action, position: position);
    } else if (isGuest) {
      if (_guestService.isConnected) {
        _guestService.sendPlaybackControl(
          action,
          positionMs: position?.inMilliseconds,
        );
      } else if (_remoteService.isConnected) {
        _remoteService.sendGuestAction('playback_control', {
          'action': action,
          'position': position?.inMilliseconds,
        });
      } else {
        _reportActionError(
            'No hay conexión activa con el anfitrión CrotoLink.');
      }
    }
  }

  @override
  void _clearActionError() {
    if (lastActionError == null) return;
    lastActionError = null;
    notifyListeners();
  }

  @override
  void _reportActionError(String message) {
    lastActionError = message;
    notifyListeners();
  }

  void updateCrotoLinkSettings({
    CrotoLinkMode? mode,
    bool? allowGuestControls,
    bool? allowGuestQueueManage,
    bool? isPublic,
    int? maxParticipants,
    String? initialPlaylistId,
  }) {
    if (!isHost) return;

    _hostService.updateSettings(
      mode: mode,
      allowGuestControls: allowGuestControls,
      allowGuestQueueManage: allowGuestQueueManage,
      isPublic: isPublic,
      maxParticipants: maxParticipants,
      initialPlaylistId: initialPlaylistId,
    );

    if (allowGuestControls != null || allowGuestQueueManage != null) {
      for (var i = 0; i < _remoteParticipants.length; i++) {
        _remoteParticipants[i] = _remoteParticipants[i].copyWith(
          canControlPlayback:
              allowGuestControls ?? _remoteParticipants[i].canControlPlayback,
          canManageQueue:
              allowGuestQueueManage ?? _remoteParticipants[i].canManageQueue,
        );
      }
    }

    _syncHostState();
    if (_session != null) {
      _hostService.broadcastSessionState(_session!);
      if (_remoteService.isConnected) {
        _remoteService.updateState({
          'mode': _session!.mode.name,
          'allowGuestControls': _session!.allowGuestControls,
          'allowGuestQueueManage': _session!.allowGuestQueueManage,
        });
      }
    }
    _publishToNavidromeIfPublic();
    notifyListeners();
  }

  void kickParticipant(String participantId) {
    if (!isHost) return;
    // 1. Expulsar de la sesión local (LAN)
    _hostService.kickParticipant(participantId);

    // 2. Expulsar de la sesión remota (Cloud CrotoLink)
    final remoteIdx =
        _remoteParticipants.indexWhere((p) => p.id == participantId);
    if (remoteIdx != -1) {
      final remoteP = _remoteParticipants[remoteIdx];
      _kickedRemoteNames.add(remoteP.name.trim().toLowerCase());
      _remoteService.kickGuest(remoteP.name);
      _remoteParticipants.removeAt(remoteIdx);
    }

    _syncHostState();
    _publishHostState();
    if (_session != null) _hostService.broadcastSessionState(_session!);
    notifyListeners();
  }

  @override
  Future<void> leaveOrEndSession() async {
    _syncGeneration++;
    _lastSyncServerTimestamp = 0;
    _hostSyncHeartbeat?.cancel();
    _hostSyncHeartbeat = null;
    _hostPublishTimer?.cancel();
    _hostPublishTimer = null;

    _player.removeListener(_onPlayerChangedAsHost);
    if (_role == CrotoLinkRole.guest) _guestHistory.finalize();
    if (_role == CrotoLinkRole.host) {
      _trackHistory(finalize: true);
      final ending = _session;
      if (ending != null) {
        unawaited(_navidrome.publishServerCrotoLinkEnded(ending));
      }
    }
    _guestService.roomPassword = null;
    _remoteService.roomPassword = null;
    _hintSentForTrackId = null;
    _hintPreloadedTrackId = null;
    _resolver.clear();
    unavailableNotice = null;
    _reactions.clear();
    _chat.clear();
    _chatEnabledForRoom = true;
    _reactionSweep?.cancel();
    if (_role == CrotoLinkRole.guest) unawaited(_player.setPlaybackSpeed(1.0));
    _hasRoomPassword = false;
    _remoteCreateFailures = 0;
    _nextRemoteCreateAt = null;

    if (_role == CrotoLinkRole.host) {
      await _hostService.stop();
      await _remoteService.disconnect(endRoom: true);
    } else if (_role == CrotoLinkRole.guest) {
      await _guestService.disconnect();
      await _remoteService.disconnect();
    }

    _role = CrotoLinkRole.none;
    _session = null;
    _localParticipant = null;
    _hostCrotoLinkQueue.clear();
    _trackAddedBy.clear();
    _remoteParticipants.clear();
    _kickedRemoteNames.clear();
    _currentTrackAddedBy = null;
    notifyListeners();
  }

  @override
  String _getDefaultDeviceName() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'Dispositivo';
  }

  @override
  void dispose() {
    _settings?.removeListener(_applyServerUrl);
    _syncGeneration++;
    _lastSyncServerTimestamp = 0;
    _hostSyncHeartbeat?.cancel();
    _hostPublishTimer?.cancel();
    _player.removeListener(_onPlayerChangedAsHost);
    _hostService.stop();
    _guestService.disconnect();
    super.dispose();
  }
}
