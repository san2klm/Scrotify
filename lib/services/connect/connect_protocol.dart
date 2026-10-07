import 'dart:convert';

/// Tipos de dispositivo que se muestran en el selector de Connect.
enum ConnectKind { phone, tablet, desktop, other }

ConnectKind connectKindFrom(String? name) => ConnectKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => ConnectKind.other,
    );

/// Dispositivo del mismo usuario visible por LAN y/o por el servidor Jam.
class ConnectDevice {
  const ConnectDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.viaLan = false,
    this.viaRelay = false,
  });

  final String id;
  final String name;
  final ConnectKind kind;
  final bool viaLan;
  final bool viaRelay;

  ConnectDevice copyWith({bool? viaLan, bool? viaRelay}) => ConnectDevice(
        id: id,
        name: name,
        kind: kind,
        viaLan: viaLan ?? this.viaLan,
        viaRelay: viaRelay ?? this.viaRelay,
      );
}

/// Pista tal como viaja entre dispositivos (subconjunto de `Track`).
class ConnectTrack {
  const ConnectTrack(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get title => (json['title'] as String?) ?? '';
  String get artist => (json['artist'] as String?) ?? '';
  String? get artUrl => json['albumArtUrl'] as String?;
}

/// Lo que está sonando en un dispositivo, publicado para los demás.
class ConnectRemoteState {
  const ConnectRemoteState({
    required this.scope,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.volume,
    this.track,
    required this.receivedAt,
  });

  final String? scope;
  final ConnectTrack? track;
  final bool playing;
  final int positionMs;
  final int durationMs;
  final double volume;
  final DateTime receivedAt;

  /// Posición estimada ahora mismo (avanza sola mientras suena).
  Duration estimatedPosition(DateTime now) {
    final elapsed = playing ? now.difference(receivedAt).inMilliseconds : 0;
    final ms =
        (positionMs + elapsed).clamp(0, durationMs > 0 ? durationMs : 1 << 31);
    return Duration(milliseconds: ms);
  }

  static ConnectRemoteState fromJson(Map<String, dynamic> m, DateTime now) =>
      ConnectRemoteState(
        scope: m['scope'] as String?,
        track: m['track'] is Map
            ? ConnectTrack(Map<String, dynamic>.from(m['track'] as Map))
            : null,
        playing: m['playing'] == true,
        positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        volume: ((m['volume'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0),
        receivedAt: now,
      );
}

/// Cola y posición que pasan de un dispositivo a otro al transferir.
class ConnectTransfer {
  const ConnectTransfer({
    required this.scope,
    required this.tracks,
    required this.index,
    required this.positionMs,
    required this.playing,
  });

  final String scope;
  final List<Map<String, dynamic>> tracks;
  final int index;
  final int positionMs;
  final bool playing;

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'tracks': tracks,
        'index': index,
        'positionMs': positionMs,
        'playing': playing,
      };

  static ConnectTransfer? tryParse(Map<String, dynamic> m) {
    final scope = m['scope'];
    final tracks = m['tracks'];
    if (scope is! String || tracks is! List || tracks.isEmpty) return null;
    final list = [
      for (final t in tracks)
        if (t is Map && t['id'] is String) Map<String, dynamic>.from(t),
    ];
    if (list.isEmpty) return null;
    final index =
        ((m['index'] as num?)?.toInt() ?? 0).clamp(0, list.length - 1);
    return ConnectTransfer(
      scope: scope,
      tracks: list,
      index: index,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      playing: m['playing'] == true,
    );
  }
}

/// Comandos que un controlador puede mandar al dispositivo que reproduce.
class ConnectCommand {
  static const toggle = 'toggle';
  static const play = 'play';
  static const pause = 'pause';
  static const next = 'next';
  static const previous = 'previous';
  static const seek = 'seek'; // value: milisegundos
  static const volume = 'volume'; // value: 0.0 – 1.0
  static const all = {toggle, play, pause, next, previous, seek, volume};
}

/// Mensajes cifrados entre dispositivos. `t` es el tipo y `n` un contador
/// creciente por emisor para descartar repeticiones.
class ConnectMessage {
  const ConnectMessage(this.type, this.body);
  final String type;
  final Map<String, dynamic> body;

  static const state = 'state';
  static const command = 'cmd';
  static const transfer = 'transfer';
  static const handoff = 'handoff';
  static const ack = 'ack';

  List<int> encode(int counter) =>
      utf8.encode(jsonEncode({...body, 't': type, 'n': counter}));
}

/// Mensaje ya descifrado y verificado.
class IncomingConnectMessage {
  const IncomingConnectMessage(this.from, this.type, this.body, this.counter);
  final String from;
  final String type;
  final Map<String, dynamic> body;
  final int counter;
}
