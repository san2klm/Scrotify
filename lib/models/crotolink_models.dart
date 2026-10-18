import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../services/navidrome_service.dart';
import '../utils/app_links.dart';

/// Elimina las credenciales Subsonic (`u`, `s`, `t`, `p`) de una URL de
/// carátula antes de compartirla con invitados o servidores CrotoLink.
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
const int kCrotoLinkHostPort = 47620;

/// Puerto UDP por defecto para el descubrimiento broadcast de sesiones CrotoLink en LAN.
const int kCrotoLinkDiscoveryPort = 47623;

/// Grupo multicast local usado además del broadcast para redes que lo filtran.
const String kCrotoLinkDiscoveryMulticastGroup = '239.255.0.1';

/// Identificador de protocolo para las tramas UDP de CrotoLink.
const String kCrotoLinkDiscoveryAppTag = 'crotolink';

/// Servidor CrotoLink por defecto: ninguno. Cada usuario configura el suyo (o
/// el de quien se lo comparta) en Ajustes; sin él no hay salas remotas,
/// CrotoWave Connect por internet ni sincronización.
const String kDefaultRemoteCrotoLinkEndpoint = '';

/// Ejemplo para el campo de Ajustes.
const String kExampleRemoteCrotoLinkEndpoint =
    'wss://crotolink.tu-dominio.com/';

/// Mensaje cuando una función necesita el servidor y no hay ninguno.
const String kNoCrotoLinkServerMessage =
    'Configurá un servidor CrotoLink en Ajustes para usar salas remotas.';

/// Resultado de validar la URL del servidor CrotoLink configurada por el usuario.
class CrotoLinkServerEndpoint {
  /// URL normalizada (`wss://host[:puerto]/`), o `null` si no es válida.
  final String? url;

  /// Motivo del rechazo, en español, listo para mostrar en UI.
  final String? error;

  /// Aviso no bloqueante (p. ej. `ws://` en red local sin cifrado).
  final String? warning;

  const CrotoLinkServerEndpoint._({this.url, this.error, this.warning});

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
  static CrotoLinkServerEndpoint parse(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return const CrotoLinkServerEndpoint._(
          error: 'Introduce la URL del servidor.');
    }
    if (!text.contains('://')) text = 'wss://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      return const CrotoLinkServerEndpoint._(error: 'La URL no es válida.');
    }
    var scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') scheme = 'wss';
    if (scheme == 'http') scheme = 'ws';
    if (scheme != 'wss' && scheme != 'ws') {
      return const CrotoLinkServerEndpoint._(
          error: 'Usa wss:// (o ws:// solo en red local).');
    }
    String? warning;
    if (scheme == 'ws') {
      if (!isPrivateHost(uri.host)) {
        return const CrotoLinkServerEndpoint._(
            error:
                'ws:// sin cifrado solo se permite en red local. Usa wss://.');
      }
      warning = 'Conexión sin cifrar (ws://): úsala solo en tu red local.';
    }
    final normalized = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/',
    ).toString();
    return CrotoLinkServerEndpoint._(url: normalized, warning: warning);
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
    // Solo direcciones IPv6 literales: `fdx.atacante.com` no es red local.
    final ip = InternetAddress.tryParse(h);
    if (ip == null || ip.type != InternetAddressType.IPv6) return false;
    return h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80');
  }
}

/// Serializa una pista para el protocolo CrotoLink. Incluye metadatos opcionales
/// (`mbid`, `isrc`, `trackNumber`, `durationSec`) para que otros servidores
/// Navidrome puedan emparejarla; sin credenciales (`sanitizeArtUrl`).
Map<String, dynamic> trackToCrotoLinkJson(Track t) {
  final secs = int.tryParse(t.duration);
  return {
    'id': t.id,
    'title': t.title,
    'artist': t.artist,
    'album': t.album,
    'duration': t.duration,
    'albumArtUrl': sanitizeArtUrl(t.albumArtUrl),
    if (t.mbid != null) 'mbid': t.mbid,
    if (t.isrc != null) 'isrc': t.isrc,
    if (t.trackNumber != null) 'trackNumber': t.trackNumber,
    if (secs != null) 'durationSec': secs,
  };
}

/// Inverso tolerante de [trackToCrotoLinkJson] (campos ausentes → valores por defecto).
Track trackFromCrotoLinkJson(Map<String, dynamic> j) {
  return Track(
    id: (j['id'] as String?) ?? '',
    title: (j['title'] as String?) ?? 'Unknown',
    artist: (j['artist'] as String?) ?? 'Unknown',
    album: (j['album'] as String?) ?? 'Unknown',
    duration: (j['duration'] as String?) ?? '',
    albumArtUrl: j['albumArtUrl'] as String?,
    mbid: j['mbid'] as String?,
    isrc: j['isrc'] as String?,
    trackNumber: (j['trackNumber'] as num?)?.toInt(),
  );
}

/// Enlace de invitación a una CrotoLink en la nube: `crotowave://join?code=ABC234&server=host`
/// o `https://host/j/ABC234`. Solo lleva el PIN (y el servidor) — nunca credenciales.
class CrotoLinkInviteLink {
  final String code;

  /// Servidor del relay (`host[:puerto]`), si el enlace lo indica.
  final String? server;

  const CrotoLinkInviteLink(this.code, this.server);

  /// `wss://server/` listo para `joinRemoteSession(customEndpoint:)`, o `null`
  /// si el enlace no trae servidor o este no es válido.
  String? get endpoint {
    final s = server;
    if (s == null || s.isEmpty) return null;
    return CrotoLinkServerEndpoint.parse(s).url;
  }

  static CrotoLinkInviteLink? parse(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.isEmpty) return null;
    String? rawCode;
    String? server;
    if (isAppLinkScheme(uri.scheme) && uri.host == 'join') {
      rawCode = uri.queryParameters['code'];
      server = uri.queryParameters['server'];
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'j') {
      rawCode = uri.pathSegments[1];
      server = uri.scheme == 'http'
          ? uri
              .origin // CrotoLinkServerEndpoint lo valida (ws:// solo en red local)
          : (uri.hasPort ? '${uri.host}:${uri.port}' : uri.host);
    }
    if (rawCode == null) return null;
    try {
      return CrotoLinkInviteLink(CrotoLinkCode(rawCode).value, server);
    } on ArgumentError {
      return null;
    }
  }
}

/// Rol del usuario actual en la sesión CrotoLink.
enum CrotoLinkRole { none, host, guest }

/// Modo de funcionamiento de la sesión CrotoLink.
enum CrotoLinkMode {
  /// Modo Altavoz de Fiesta: La música suena únicamente en el dispositivo Host.
  /// Los invitados usan sus dispositivos como mando a distancia social y cola compartida.
  partySpeaker,

  /// Modo Escucha Sincronizada: La música se reproduce simultáneamente en todos los
  /// dispositivos conectados, sincronizando tiempo y posición.
  synchronizedListening,
}

/// Cómo se ordena la cola compartida. Lo decide el host (y puede cambiarlo en
/// vivo). `approval` equivale a orden libre con aprobación previa; la
/// aprobación también se puede combinar con `fairTurns` vía
/// [CrotoLinkSessionState.requireApproval]. `voting` excluye a `fairTurns`.
enum CrotoLinkQueueMode {
  free,
  fairTurns,
  voting,
  approval;

  static CrotoLinkQueueMode fromName(String? name) => CrotoLinkQueueMode.values
      .firstWhere((m) => m.name == name, orElse: () => CrotoLinkQueueMode.free);

  String get label => switch (this) {
        CrotoLinkQueueMode.free => 'Libre',
        CrotoLinkQueueMode.fairTurns => 'Turnos justos',
        CrotoLinkQueueMode.voting => 'Votación',
        CrotoLinkQueueMode.approval => 'Aprobación del anfitrión',
      };
}

/// Estado de la conexión de red en una sesión CrotoLink.
enum CrotoLinkConnectionState {
  connected,
  reconnecting,
  disconnected,
  failed,
}

/// Código PIN de 6 caracteres para unirse a un CrotoLink (sin caracteres ambiguos).
class CrotoLinkCode {
  static const charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _charset = charset;
  static const length = 6;

  final String value;

  CrotoLinkCode._(this.value);

  factory CrotoLinkCode.generate([Random? random]) {
    final rnd = random ?? Random.secure();
    final chars = List.generate(
      length,
      (_) => _charset[rnd.nextInt(_charset.length)],
    ).join();
    return CrotoLinkCode._(chars);
  }

  factory CrotoLinkCode(String value) {
    final upper = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (upper.length != length ||
        upper.split('').any((character) => !_charset.contains(character))) {
      throw ArgumentError('Código CrotoLink debe tener $length caracteres');
    }
    return CrotoLinkCode._(upper);
  }

  @override
  String toString() => value;

  /// Formato legible en dos bloques de 3: "AB3-4EF"
  String get formatted => '${value.substring(0, 3)}-${value.substring(3)}';
}

/// Datos contenidos en el código QR de CrotoLink: `crotowave://crotolink?host=...&port=...&code=...&sessionId=...`
class CrotoLinkQrData {
  final String host;
  final int port;
  final String code;
  final String? sessionId;
  final String? remoteHost;
  final int? remotePort;
  final String? tlsFingerprint;

  CrotoLinkQrData({
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
      scheme: kAppLinkScheme,
      host: 'crotolink',
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

  static CrotoLinkQrData? fromUri(String uri) {
    try {
      final u = Uri.parse(uri);
      if (!isAppLinkScheme(u.scheme) || u.host != 'crotolink') return null;
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
      final normalizedCode = CrotoLinkCode(code).value;
      return CrotoLinkQrData(
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

/// Participante conectado a la sesión CrotoLink.
class CrotoLinkParticipant {
  final String id;
  final String name;
  final int avatarColorValue;
  final bool isHost;
  final DateTime joinedAt;
  final bool canControlPlayback;
  final bool canManageQueue;

  const CrotoLinkParticipant({
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

  factory CrotoLinkParticipant.fromJson(Map<String, dynamic> json) =>
      CrotoLinkParticipant(
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

  CrotoLinkParticipant copyWith({
    String? id,
    String? name,
    int? avatarColorValue,
    bool? isHost,
    DateTime? joinedAt,
    bool? canControlPlayback,
    bool? canManageQueue,
  }) {
    return CrotoLinkParticipant(
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
class CrotoLinkQueueItem {
  final String id;
  final Track track;
  final CrotoLinkParticipant? addedBy;
  final DateTime addedAt;

  /// Suma de votos (+1/-1) de los participantes (modo votación).
  final int votes;

  /// Ítem fijado por el host: conserva su sitio al reordenar por modo.
  final bool pinned;

  const CrotoLinkQueueItem({
    required this.id,
    required this.track,
    this.addedBy,
    required this.addedAt,
    this.votes = 0,
    this.pinned = false,
  });

  CrotoLinkQueueItem copyWith({int? votes, bool? pinned}) => CrotoLinkQueueItem(
        id: id,
        track: track,
        addedBy: addedBy,
        addedAt: addedAt,
        votes: votes ?? this.votes,
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': trackToCrotoLinkJson(track),
        if (addedBy != null) 'addedBy': addedBy!.toJson(),
        'addedAt': addedAt.toIso8601String(),
        if (votes != 0) 'votes': votes,
        if (pinned) 'pinned': true,
      };

  factory CrotoLinkQueueItem.fromJson(Map<String, dynamic> json) {
    final trackJson = json['track'] as Map<String, dynamic>;
    return CrotoLinkQueueItem(
      id: json['id'] as String,
      track: trackFromCrotoLinkJson(trackJson),
      addedBy: json['addedBy'] != null
          ? CrotoLinkParticipant.fromJson(
              json['addedBy'] as Map<String, dynamic>)
          : null,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}

/// Propuesta de un invitado pendiente de aprobación del host (modo aprobación).
class CrotoLinkQueueRequest {
  final String id;
  final Track track;
  final String requestedById;
  final String requestedByName;
  final DateTime requestedAt;
  final bool playNext;

  const CrotoLinkQueueRequest({
    required this.id,
    required this.track,
    required this.requestedById,
    required this.requestedByName,
    required this.requestedAt,
    this.playNext = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': trackToCrotoLinkJson(track),
        'requestedById': requestedById,
        'requestedByName': requestedByName,
        'requestedAt': requestedAt.toIso8601String(),
        if (playNext) 'playNext': true,
      };

  factory CrotoLinkQueueRequest.fromJson(Map<String, dynamic> json) {
    final t = json['track'] as Map<String, dynamic>;
    return CrotoLinkQueueRequest(
      id: json['id'] as String,
      track: trackFromCrotoLinkJson(t),
      requestedById: (json['requestedById'] as String?) ?? '',
      requestedByName: (json['requestedByName'] as String?) ?? 'Invitado',
      requestedAt: DateTime.tryParse((json['requestedAt'] as String?) ?? '') ??
          DateTime.now(),
      playNext: json['playNext'] as bool? ?? false,
    );
  }
}

/// Estado global de la sesión CrotoLink transmitido por el Host.
class CrotoLinkSessionState {
  final String sessionId;
  final String pinCode;
  final String hostName;
  final String hostIp;
  final int port;
  final CrotoLinkMode mode;
  final Track? currentTrack;
  final CrotoLinkParticipant? currentTrackAddedBy;
  final bool isPlaying;
  final int positionMs;
  final int
      updatedAtMs; // Unix timestamp del Host para compensación de latencia
  final List<CrotoLinkQueueItem> queue;
  final List<CrotoLinkParticipant> participants;
  final bool allowGuestControls;
  final bool allowGuestQueueManage;
  final String? remoteHost;
  final int? remotePort;
  final bool isPublic;
  final String? initialPlaylistId;
  final int maxParticipants;
  final int queueRevision;
  final CrotoLinkQueueMode queueMode;
  final int fairTurnsPerPerson;
  final bool requireApproval;
  final List<CrotoLinkQueueRequest> pendingRequests;

  /// Aprobación efectiva (modo `approval` o bandera combinable).
  bool get approvalActive =>
      requireApproval || queueMode == CrotoLinkQueueMode.approval;

  const CrotoLinkSessionState({
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
    this.queueMode = CrotoLinkQueueMode.free,
    this.fairTurnsPerPerson = 1,
    this.requireApproval = false,
    this.pendingRequests = const [],
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'pinCode': pinCode,
        'hostName': hostName,
        'hostIp': hostIp,
        'port': port,
        'mode': mode.name,
        if (currentTrack != null)
          'currentTrack': trackToCrotoLinkJson(currentTrack!),
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
        'queueMode': queueMode.name,
        'fairTurnsPerPerson': fairTurnsPerPerson,
        'requireApproval': requireApproval,
        if (pendingRequests.isNotEmpty)
          'pendingRequests': pendingRequests.map((r) => r.toJson()).toList(),
      };

  factory CrotoLinkSessionState.fromJson(Map<String, dynamic> json) {
    Track? track;
    if (json['currentTrack'] != null) {
      final t = json['currentTrack'] as Map<String, dynamic>;
      track = trackFromCrotoLinkJson(t);
    }

    CrotoLinkParticipant? addedBy;
    if (json['currentTrackAddedBy'] != null) {
      addedBy = CrotoLinkParticipant.fromJson(
          json['currentTrackAddedBy'] as Map<String, dynamic>);
    }

    final modeName = json['mode'] as String? ?? CrotoLinkMode.partySpeaker.name;
    final mode = CrotoLinkMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => CrotoLinkMode.partySpeaker,
    );

    final qList = (json['queue'] as List<dynamic>?) ?? [];
    final pList = (json['participants'] as List<dynamic>?) ?? [];

    return CrotoLinkSessionState(
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
      queue: _parseEach(qList, 'cola', CrotoLinkQueueItem.fromJson),
      participants:
          _parseEach(pList, 'participantes', CrotoLinkParticipant.fromJson),
      allowGuestControls: json['allowGuestControls'] as bool? ?? true,
      allowGuestQueueManage: json['allowGuestQueueManage'] as bool? ?? true,
      remoteHost: json['remoteHost'] as String?,
      remotePort: (json['remotePort'] as num?)?.toInt(),
      isPublic: json['isPublic'] as bool? ?? true,
      initialPlaylistId: json['initialPlaylistId'] as String?,
      maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 0,
      queueRevision: (json['queueRevision'] as num?)?.toInt() ?? 0,
      queueMode: CrotoLinkQueueMode.fromName(json['queueMode'] as String?),
      fairTurnsPerPerson:
          ((json['fairTurnsPerPerson'] as num?)?.toInt() ?? 1).clamp(1, 10),
      requireApproval: json['requireApproval'] as bool? ?? false,
      pendingRequests: parseCrotoLinkRequests(json['pendingRequests']),
    );
  }

  CrotoLinkSessionState copyWith({
    String? sessionId,
    String? pinCode,
    String? hostName,
    String? hostIp,
    int? port,
    CrotoLinkMode? mode,
    Track? currentTrack,
    CrotoLinkParticipant? currentTrackAddedBy,
    bool clearCurrentTrack = false,
    bool clearCurrentTrackAddedBy = false,
    bool? isPlaying,
    int? positionMs,
    int? updatedAtMs,
    List<CrotoLinkQueueItem>? queue,
    List<CrotoLinkParticipant>? participants,
    bool? allowGuestControls,
    bool? allowGuestQueueManage,
    String? remoteHost,
    int? remotePort,
    bool? isPublic,
    String? initialPlaylistId,
    int? maxParticipants,
    int? queueRevision,
    CrotoLinkQueueMode? queueMode,
    int? fairTurnsPerPerson,
    bool? requireApproval,
    List<CrotoLinkQueueRequest>? pendingRequests,
  }) {
    return CrotoLinkSessionState(
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
      queueMode: queueMode ?? this.queueMode,
      fairTurnsPerPerson: fairTurnsPerPerson ?? this.fairTurnsPerPerson,
      requireApproval: requireApproval ?? this.requireApproval,
      pendingRequests: pendingRequests ?? this.pendingRequests,
    );
  }
}

/// Parsea una lista de solicitudes ignorando entradas corruptas.
List<CrotoLinkQueueRequest> parseCrotoLinkRequests(Object? raw) {
  if (raw is! List) return const [];
  final out = <CrotoLinkQueueRequest>[];
  for (final e in raw) {
    if (e is Map) {
      try {
        out.add(CrotoLinkQueueRequest.fromJson(Map<String, dynamic>.from(e)));
      } catch (e) {
        debugPrint('CrotoLinkQueueRequest: solicitud de cola ilegible: $e');
      }
    }
  }
  return out;
}

/// Sesión CrotoLink descubierta mediante radar UDP en la LAN.
class DiscoveredCrotoLinkSession {
  final String host;
  final int port;
  final String pin;
  final String sessionTitle;
  final String hostName;
  final int participantCount;
  final String? currentTrackTitle;
  final String? currentTrackArtist;
  final String? albumArtUrl;
  final CrotoLinkMode mode;
  final String? remoteHost;
  final int? remotePort;
  final String? tlsFingerprint;
  final bool hasPassword;

  const DiscoveredCrotoLinkSession({
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
    this.hasPassword = false,
  });

  /// Construye una sesión descubierta. Para una respuesta que llega por UDP se
  /// debe usar [preferFallbackHost]: la IP de origen del datagrama es la que
  /// realmente alcanzó al invitado y es más fiable que una IP anunciada por el
  /// host (que puede pertenecer a una VPN, Docker o una red anterior).
  factory DiscoveredCrotoLinkSession.fromJson(
    Map<String, dynamic> json,
    String fallbackHost, {
    bool preferFallbackHost = false,
  }) {
    final modeName = json['mode'] as String? ?? CrotoLinkMode.partySpeaker.name;
    final mode = CrotoLinkMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => CrotoLinkMode.partySpeaker,
    );

    final advertisedHost = json['host'] as String?;
    final hasSenderHost = fallbackHost.isNotEmpty && fallbackHost != '0.0.0.0';

    return DiscoveredCrotoLinkSession(
      host: preferFallbackHost && hasSenderHost
          ? fallbackHost
          : advertisedHost?.isNotEmpty == true
              ? advertisedHost!
              : fallbackHost,
      port: (json['port'] as num?)?.toInt() ?? 0,
      pin: (json['pin'] as String?) ?? '',
      sessionTitle: (json['sessionTitle'] as String?) ?? 'CrotoLink',
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
      hasPassword: json['hasPassword'] == true,
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

/// Convierte cada elemento por separado: uno mal formado se descarta (y queda
/// anotado en el diagnóstico) en vez de tirar el snapshot entero.
List<T> _parseEach<T>(
    List<dynamic> raw, String what, T Function(Map<String, dynamic>) parse) {
  final out = <T>[];
  for (var i = 0; i < raw.length; i++) {
    try {
      out.add(parse(Map<String, dynamic>.from(raw[i] as Map)));
    } catch (e) {
      debugPrint(
          'CrotoLink: elemento $i de «$what» inválido, se descarta ($e)');
    }
  }
  return out;
}
