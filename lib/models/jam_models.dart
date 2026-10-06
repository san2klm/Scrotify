import 'dart:math';

import '../services/navidrome_service.dart';

/// Elimina las credenciales Subsonic (`u`, `s`, `t`, `p`) de una URL de
/// carátula antes de compartirla con invitados o servidores Jam.
///
/// El token `t` no caduca: filtrarlo equivale a filtrar la sesión del host.
String? sanitizeArtUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasQuery) return url;
  const secret = {'u', 's', 't', 'p', 'apiKey'};
  final kept = Map<String, String>.fromEntries(
    uri.queryParameters.entries.where((e) => !secret.contains(e.key)),
  );
  return uri.replace(queryParameters: kept.isEmpty ? null : kept).toString();
}

/// Puerto TCP preferido para el servidor WebSocket del anfitrión.
///
/// Se usa un puerto dinámico únicamente si éste ya está ocupado.
const int kJamHostPort = 47620;

/// Puerto UDP por defecto para el descubrimiento broadcast de sesiones Jam en LAN.
const int kJamDiscoveryPort = 47623;

/// Grupo multicast local usado además del broadcast para redes que lo filtran.
const String kJamDiscoveryMulticastGroup = '239.255.0.1';

/// Identificador de protocolo para las tramas UDP de Jam.
const String kJamDiscoveryAppTag = 'scrotify-jam';

/// Endpoint WebSocket remoto por defecto para Scrotify Jam en la nube.
const String kDefaultRemoteJamEndpoint = 'wss://jam.templo.cloud/';

/// Resultado de validar la URL del servidor Jam configurada por el usuario.
class JamServerEndpoint {
  /// URL normalizada (`wss://host[:puerto]/`), o `null` si no es válida.
  final String? url;

  /// Motivo del rechazo, en español, listo para mostrar en UI.
  final String? error;

  /// Aviso no bloqueante (p. ej. `ws://` en red local sin cifrado).
  final String? warning;

  const JamServerEndpoint._({this.url, this.error, this.warning});

  bool get isValid => url != null;

  Uri get _uri => Uri.parse(url!);

  /// Host del servidor (para anunciar las salas descubiertas).
  String get host => _uri.host;

  /// Puerto efectivo (443 para `wss`, 80 para `ws` si no se indicó otro).
  int get port => _uri.hasPort ? _uri.port : (_uri.scheme == 'wss' ? 443 : 80);

  /// Base HTTP(S) equivalente para `/health`, `/rooms`, `/api/capabilities`.
  Uri get httpBase =>
      _uri.replace(scheme: _uri.scheme == 'wss' ? 'https' : 'http');

  /// `wss://` siempre; `ws://` solo hacia host local/privado, con aviso.
  /// Acepta `https://`/`http://` por comodidad y los convierte.
  static JamServerEndpoint parse(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return const JamServerEndpoint._(error: 'Introduce la URL del servidor.');
    }
    if (!text.contains('://')) text = 'wss://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      return const JamServerEndpoint._(error: 'La URL no es válida.');
    }
    var scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') scheme = 'wss';
    if (scheme == 'http') scheme = 'ws';
    if (scheme != 'wss' && scheme != 'ws') {
      return const JamServerEndpoint._(
          error: 'Usa wss:// (o ws:// solo en red local).');
    }
    String? warning;
    if (scheme == 'ws') {
      if (!isPrivateHost(uri.host)) {
        return const JamServerEndpoint._(
            error: 'ws:// sin cifrado solo se permite en red local. Usa wss://.');
      }
      warning = 'Conexión sin cifrar (ws://): úsala solo en tu red local.';
    }
    final normalized = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/',
    ).toString();
    return JamServerEndpoint._(url: normalized, warning: warning);
  }

  /// Loopback, `.local`, y rangos privados RFC 1918 / link-local / ULA.
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h == '::1') return true;
    final parts = h.split('.');
    if (parts.length == 4) {
      final o = parts.map(int.tryParse).toList();
      if (o.every((v) => v != null && v >= 0 && v <= 255)) {
        return o[0] == 10 ||
            o[0] == 127 ||
            (o[0] == 192 && o[1] == 168) ||
            (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31) ||
            (o[0] == 169 && o[1] == 254);
      }
    }
    return h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80');
  }
}

/// Rol del usuario actual en la sesión Jam.
enum JamRole { none, host, guest }

/// Modo de funcionamiento de la sesión Jam.
enum JamMode {
  /// Modo Altavoz de Fiesta: La música suena únicamente en el dispositivo Host.
  /// Los invitados usan sus dispositivos como mando a distancia social y cola compartida.
  partySpeaker,

  /// Modo Escucha Sincronizada: La música se reproduce simultáneamente en todos los
  /// dispositivos conectados, sincronizando tiempo y posición.
  synchronizedListening,
}

/// Estado de la conexión de red en una sesión Jam.
enum JamConnectionState {
  connected,
  reconnecting,
  disconnected,
  failed,
}

/// Código PIN de 6 caracteres para unirse a un Jam (sin caracteres ambiguos).
class JamCode {
  static const charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _charset = charset;
  static const length = 6;

  final String value;

  JamCode._(this.value);

  factory JamCode.generate([Random? random]) {
    final rnd = random ?? Random.secure();
    final chars = List.generate(
      length,
      (_) => _charset[rnd.nextInt(_charset.length)],
    ).join();
    return JamCode._(chars);
  }

  factory JamCode(String value) {
    final upper = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (upper.length != length ||
        upper.split('').any((character) => !_charset.contains(character))) {
      throw ArgumentError('Código Jam debe tener $length caracteres');
    }
    return JamCode._(upper);
  }

  @override
  String toString() => value;

  /// Formato legible en dos bloques de 3: "AB3-4EF"
  String get formatted => '${value.substring(0, 3)}-${value.substring(3)}';
}

/// Datos contenidos en el código QR de Jam: `scrotify://jam?host=...&port=...&code=...&sessionId=...`
class JamQrData {
  final String host;
  final int port;
  final String code;
  final String? sessionId;
  final String? remoteHost;
  final int? remotePort;
  final String? tlsFingerprint;

  JamQrData({
    required this.host,
    required this.port,
    required this.code,
    this.sessionId,
    this.remoteHost,
    this.remotePort,
    this.tlsFingerprint,
  });

  String toUri() {
    return Uri(
      scheme: 'scrotify',
      host: 'jam',
      queryParameters: {
        'host': host,
        'port': '$port',
        'code': code,
        if (sessionId != null) 'sessionId': sessionId!,
        if (remoteHost != null && remotePort != null) 'remoteHost': remoteHost!,
        if (remoteHost != null && remotePort != null)
          'remotePort': '$remotePort',
        if (tlsFingerprint != null) 'transport': 'wss',
        if (tlsFingerprint != null) 'tlsFingerprint': tlsFingerprint!,
      },
    ).toString();
  }

  static JamQrData? fromUri(String uri) {
    try {
      final u = Uri.parse(uri);
      if (u.scheme != 'scrotify' || u.host != 'jam') return null;
      final host = u.queryParameters['host'];
      final port = int.tryParse(u.queryParameters['port'] ?? '');
      final code = u.queryParameters['code'];
      final sessionId = u.queryParameters['sessionId'];
      final remoteHost = u.queryParameters['remoteHost'];
      final remotePort = int.tryParse(u.queryParameters['remotePort'] ?? '');
      final transport = u.queryParameters['transport'];
      final tlsFingerprint = u.queryParameters['tlsFingerprint'];
      if (host == null ||
          host.isEmpty ||
          port == null ||
          port <= 0 ||
          port > 65535 ||
          code == null) {
        return null;
      }
      if (transport != 'wss' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(tlsFingerprint ?? '')) {
        return null;
      }
      final normalizedCode = JamCode(code).value;
      return JamQrData(
        host: host,
        port: port,
        code: normalizedCode,
        sessionId: sessionId,
        remoteHost: remoteHost?.isNotEmpty == true ? remoteHost : null,
        remotePort: remotePort != null && remotePort > 0 && remotePort <= 65535
            ? remotePort
            : null,
        tlsFingerprint: tlsFingerprint,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => toUri();
}

/// Participante conectado a la sesión Jam.
class JamParticipant {
  final String id;
  final String name;
  final int avatarColorValue;
  final bool isHost;
  final DateTime joinedAt;
  final bool canControlPlayback;
  final bool canManageQueue;

  const JamParticipant({
    required this.id,
    required this.name,
    required this.avatarColorValue,
    required this.isHost,
    required this.joinedAt,
    this.canControlPlayback = true,
    this.canManageQueue = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarColorValue': avatarColorValue,
        'isHost': isHost,
        'joinedAt': joinedAt.toIso8601String(),
        'canControlPlayback': canControlPlayback,
        'canManageQueue': canManageQueue,
      };

  factory JamParticipant.fromJson(Map<String, dynamic> json) => JamParticipant(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarColorValue:
            (json['avatarColorValue'] as num?)?.toInt() ?? 0xFF7C3AED,
        isHost: json['isHost'] as bool? ?? false,
        joinedAt: json['joinedAt'] != null
            ? DateTime.tryParse(json['joinedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        canControlPlayback: json['canControlPlayback'] as bool? ?? true,
        canManageQueue: json['canManageQueue'] as bool? ?? true,
      );

  JamParticipant copyWith({
    String? id,
    String? name,
    int? avatarColorValue,
    bool? isHost,
    DateTime? joinedAt,
    bool? canControlPlayback,
    bool? canManageQueue,
  }) {
    return JamParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
      isHost: isHost ?? this.isHost,
      joinedAt: joinedAt ?? this.joinedAt,
      canControlPlayback: canControlPlayback ?? this.canControlPlayback,
      canManageQueue: canManageQueue ?? this.canManageQueue,
    );
  }
}

/// Elemento en la cola compartida con trazabilidad del usuario que lo agregó.
class JamQueueItem {
  final String id;
  final Track track;
  final JamParticipant? addedBy;
  final DateTime addedAt;

  const JamQueueItem({
    required this.id,
    required this.track,
    this.addedBy,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': {
          'id': track.id,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'duration': track.duration,
          'albumArtUrl': sanitizeArtUrl(track.albumArtUrl),
        },
        if (addedBy != null) 'addedBy': addedBy!.toJson(),
        'addedAt': addedAt.toIso8601String(),
      };

  factory JamQueueItem.fromJson(Map<String, dynamic> json) {
    final trackJson = json['track'] as Map<String, dynamic>;
    return JamQueueItem(
      id: json['id'] as String,
      track: Track(
        id: (trackJson['id'] as String?) ?? '',
        title: (trackJson['title'] as String?) ?? 'Unknown',
        artist: (trackJson['artist'] as String?) ?? 'Unknown',
        album: (trackJson['album'] as String?) ?? 'Unknown',
        duration: (trackJson['duration'] as String?) ?? '',
        albumArtUrl: trackJson['albumArtUrl'] as String?,
      ),
      addedBy: json['addedBy'] != null
          ? JamParticipant.fromJson(json['addedBy'] as Map<String, dynamic>)
          : null,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Estado global de la sesión Jam transmitido por el Host.
class JamSessionState {
  final String sessionId;
  final String pinCode;
  final String hostName;
  final String hostIp;
  final int port;
  final JamMode mode;
  final Track? currentTrack;
  final JamParticipant? currentTrackAddedBy;
  final bool isPlaying;
  final int positionMs;
  final int
      updatedAtMs; // Unix timestamp del Host para compensación de latencia
  final List<JamQueueItem> queue;
  final List<JamParticipant> participants;
  final bool allowGuestControls;
  final bool allowGuestQueueManage;
  final String? remoteHost;
  final int? remotePort;
  final bool isPublic;
  final String? initialPlaylistId;
  final int maxParticipants;
  final int queueRevision;

  const JamSessionState({
    required this.sessionId,
    required this.pinCode,
    required this.hostName,
    required this.hostIp,
    required this.port,
    required this.mode,
    this.currentTrack,
    this.currentTrackAddedBy,
    required this.isPlaying,
    required this.positionMs,
    required this.updatedAtMs,
    required this.queue,
    required this.participants,
    this.allowGuestControls = true,
    this.allowGuestQueueManage = true,
    this.remoteHost,
    this.remotePort,
    this.isPublic = true,
    this.initialPlaylistId,
    this.maxParticipants = 0,
    this.queueRevision = 0,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'pinCode': pinCode,
        'hostName': hostName,
        'hostIp': hostIp,
        'port': port,
        'mode': mode.name,
        if (currentTrack != null)
          'currentTrack': {
            'id': currentTrack!.id,
            'title': currentTrack!.title,
            'artist': currentTrack!.artist,
            'album': currentTrack!.album,
            'duration': currentTrack!.duration,
            'albumArtUrl': sanitizeArtUrl(currentTrack!.albumArtUrl),
          },
        if (currentTrackAddedBy != null)
          'currentTrackAddedBy': currentTrackAddedBy!.toJson(),
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'updatedAtMs': updatedAtMs,
        'queue': queue.map((e) => e.toJson()).toList(),
        'participants': participants.map((e) => e.toJson()).toList(),
        'allowGuestControls': allowGuestControls,
        'allowGuestQueueManage': allowGuestQueueManage,
        if (remoteHost != null) 'remoteHost': remoteHost,
        if (remotePort != null) 'remotePort': remotePort,
        'isPublic': isPublic,
        if (initialPlaylistId != null) 'initialPlaylistId': initialPlaylistId,
        'maxParticipants': maxParticipants,
        'queueRevision': queueRevision,
      };

  factory JamSessionState.fromJson(Map<String, dynamic> json) {
    Track? track;
    if (json['currentTrack'] != null) {
      final t = json['currentTrack'] as Map<String, dynamic>;
      track = Track(
        id: (t['id'] as String?) ?? '',
        title: (t['title'] as String?) ?? 'Unknown',
        artist: (t['artist'] as String?) ?? 'Unknown',
        album: (t['album'] as String?) ?? 'Unknown',
        duration: (t['duration'] as String?) ?? '',
        albumArtUrl: t['albumArtUrl'] as String?,
      );
    }

    JamParticipant? addedBy;
    if (json['currentTrackAddedBy'] != null) {
      addedBy = JamParticipant.fromJson(
          json['currentTrackAddedBy'] as Map<String, dynamic>);
    }

    final modeName = json['mode'] as String? ?? JamMode.partySpeaker.name;
    final mode = JamMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => JamMode.partySpeaker,
    );

    final qList = (json['queue'] as List<dynamic>?) ?? [];
    final pList = (json['participants'] as List<dynamic>?) ?? [];

    return JamSessionState(
      sessionId: json['sessionId'] as String? ?? '',
      pinCode: json['pinCode'] as String? ?? '',
      hostName: json['hostName'] as String? ?? 'Host',
      hostIp: json['hostIp'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      mode: mode,
      currentTrack: track,
      currentTrackAddedBy: addedBy,
      isPlaying: json['isPlaying'] as bool? ?? false,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      queue: qList
          .map((e) => JamQueueItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      participants: pList
          .map((e) => JamParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      allowGuestControls: json['allowGuestControls'] as bool? ?? true,
      allowGuestQueueManage: json['allowGuestQueueManage'] as bool? ?? true,
      remoteHost: json['remoteHost'] as String?,
      remotePort: (json['remotePort'] as num?)?.toInt(),
      isPublic: json['isPublic'] as bool? ?? true,
      initialPlaylistId: json['initialPlaylistId'] as String?,
      maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 0,
      queueRevision: (json['queueRevision'] as num?)?.toInt() ?? 0,
    );
  }

  JamSessionState copyWith({
    String? sessionId,
    String? pinCode,
    String? hostName,
    String? hostIp,
    int? port,
    JamMode? mode,
    Track? currentTrack,
    JamParticipant? currentTrackAddedBy,
    bool clearCurrentTrack = false,
    bool clearCurrentTrackAddedBy = false,
    bool? isPlaying,
    int? positionMs,
    int? updatedAtMs,
    List<JamQueueItem>? queue,
    List<JamParticipant>? participants,
    bool? allowGuestControls,
    bool? allowGuestQueueManage,
    String? remoteHost,
    int? remotePort,
    bool? isPublic,
    String? initialPlaylistId,
    int? maxParticipants,
    int? queueRevision,
  }) {
    return JamSessionState(
      sessionId: sessionId ?? this.sessionId,
      pinCode: pinCode ?? this.pinCode,
      hostName: hostName ?? this.hostName,
      hostIp: hostIp ?? this.hostIp,
      port: port ?? this.port,
      mode: mode ?? this.mode,
      currentTrack:
          clearCurrentTrack ? null : currentTrack ?? this.currentTrack,
      currentTrackAddedBy: clearCurrentTrackAddedBy
          ? null
          : currentTrackAddedBy ?? this.currentTrackAddedBy,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      queue: queue ?? this.queue,
      participants: participants ?? this.participants,
      allowGuestControls: allowGuestControls ?? this.allowGuestControls,
      allowGuestQueueManage:
          allowGuestQueueManage ?? this.allowGuestQueueManage,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      isPublic: isPublic ?? this.isPublic,
      initialPlaylistId: initialPlaylistId ?? this.initialPlaylistId,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      queueRevision: queueRevision ?? this.queueRevision,
    );
  }
}

/// Sesión Jam descubierta mediante radar UDP en la LAN.
class DiscoveredJamSession {
  final String host;
  final int port;
  final String pin;
  final String sessionTitle;
  final String hostName;
  final int participantCount;
  final String? currentTrackTitle;
  final String? currentTrackArtist;
  final String? albumArtUrl;
  final JamMode mode;
  final String? remoteHost;
  final int? remotePort;
  final String? tlsFingerprint;

  const DiscoveredJamSession({
    required this.host,
    required this.port,
    required this.pin,
    required this.sessionTitle,
    required this.hostName,
    required this.participantCount,
    this.currentTrackTitle,
    this.currentTrackArtist,
    this.albumArtUrl,
    required this.mode,
    this.remoteHost,
    this.remotePort,
    this.tlsFingerprint,
  });

  /// Construye una sesión descubierta. Para una respuesta que llega por UDP se
  /// debe usar [preferFallbackHost]: la IP de origen del datagrama es la que
  /// realmente alcanzó al invitado y es más fiable que una IP anunciada por el
  /// host (que puede pertenecer a una VPN, Docker o una red anterior).
  factory DiscoveredJamSession.fromJson(
    Map<String, dynamic> json,
    String fallbackHost, {
    bool preferFallbackHost = false,
  }) {
    final modeName = json['mode'] as String? ?? JamMode.partySpeaker.name;
    final mode = JamMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => JamMode.partySpeaker,
    );

    final advertisedHost = json['host'] as String?;
    final hasSenderHost = fallbackHost.isNotEmpty && fallbackHost != '0.0.0.0';

    return DiscoveredJamSession(
      host: preferFallbackHost && hasSenderHost
          ? fallbackHost
          : advertisedHost?.isNotEmpty == true
              ? advertisedHost!
              : fallbackHost,
      port: (json['port'] as num?)?.toInt() ?? 0,
      pin: (json['pin'] as String?) ?? '',
      sessionTitle: (json['sessionTitle'] as String?) ?? 'Jam de Scrotify',
      hostName: (json['hostName'] as String?) ?? 'Anfitrión',
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 1,
      currentTrackTitle: json['currentTrackTitle'] as String?,
      currentTrackArtist: json['currentTrackArtist'] as String?,
      albumArtUrl: json['albumArtUrl'] as String?,
      mode: mode,
      remoteHost: json['remoteHost'] as String?,
      remotePort: (json['remotePort'] as num?)?.toInt(),
      tlsFingerprint:
          json['transport'] == 'wss' ? json['tlsFingerprint'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'pin': pin,
        'sessionTitle': sessionTitle,
        'hostName': hostName,
        'participantCount': participantCount,
        if (currentTrackTitle != null) 'currentTrackTitle': currentTrackTitle,
        if (currentTrackArtist != null)
          'currentTrackArtist': currentTrackArtist,
        if (albumArtUrl != null) 'albumArtUrl': sanitizeArtUrl(albumArtUrl),
        'mode': mode.name,
        if (remoteHost != null) 'remoteHost': remoteHost,
        if (remotePort != null) 'remotePort': remotePort,
        if (tlsFingerprint != null) 'transport': 'wss',
        if (tlsFingerprint != null) 'tlsFingerprint': tlsFingerprint,
      };
}
