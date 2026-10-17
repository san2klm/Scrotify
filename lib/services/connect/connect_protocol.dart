import 'dart:convert';
import 'dart:math';

/// Tipos de dispositivo que se muestran en el selector de Connect.
enum ConnectKind { phone, tablet, desktop, other }

ConnectKind connectKindFrom(String? name) => ConnectKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => ConnectKind.other,
    );

/// Dispositivo del mismo usuario visible por LAN y/o por el servidor CrotoLink.
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
    this.queue = const [],
    this.queueOffset = 0,
    this.index = -1,
    this.shuffle = false,
    this.repeat = 'off',
  });

  final String? scope;
  final ConnectTrack? track;

  /// Ventana de la cola del dispositivo (en orden de reproducción), el
  /// índice absoluto de su primer elemento y la posición de la actual en ella.
  final List<Map<String, dynamic>> queue;
  final int queueOffset;
  final int index;
  final bool shuffle;

  /// `off`, `all` o `one`.
  final String repeat;
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

  static ConnectRemoteState fromJson(Map<String, dynamic> m, DateTime now,
          {ConnectRemoteState? previous}) =>
      ConnectRemoteState(
        // La cola solo viaja cuando cambia: si no llega, se conserva la anterior.
        queue: m['queue'] is List
            ? [
                for (final t in m['queue'] as List)
                  if (t is Map) Map<String, dynamic>.from(t),
              ]
            : (previous?.queue ?? const []),
        queueOffset: (m['offset'] as num?)?.toInt() ??
            (m['queue'] is List ? 0 : previous?.queueOffset ?? 0),
        index: (m['index'] as num?)?.toInt() ?? -1,
        shuffle: m['shuffle'] == true,
        repeat: (m['repeat'] as String?) ?? 'off',
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
///
/// Una cola larga no cabe en un mensaje: viaja la primera parte aquí (la
/// suficiente para empezar a sonar) y el resto en comandos
/// [ConnectCommand.queueAppend] identificados por [xfer]; [more] dice cuántas
/// canciones faltan por llegar.
class ConnectTransfer {
  const ConnectTransfer({
    required this.scope,
    required this.tracks,
    required this.index,
    required this.positionMs,
    required this.playing,
    this.xfer,
    this.more = 0,
  });

  final String scope;
  final List<Map<String, dynamic>> tracks;
  final int index;
  final int positionMs;
  final bool playing;
  final String? xfer;
  final int more;

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'tracks': tracks,
        'index': index,
        'positionMs': positionMs,
        'playing': playing,
        if (xfer != null) 'xfer': xfer,
        if (xfer != null) 'more': more,
      };

  /// Copia con solo la primera parte de la cola y los datos de los trozos.
  ConnectTransfer headOf(ConnectQueueChunks split) => ConnectTransfer(
        scope: scope,
        tracks: split.head,
        index: index.clamp(0, split.head.length - 1),
        positionMs: positionMs,
        playing: playing,
        xfer: split.xfer,
        more: split.more,
      );

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
    final xfer = ConnectQueueChunks.validXfer(m['xfer']);
    return ConnectTransfer(
      scope: scope,
      tracks: list,
      index: index,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      playing: m['playing'] == true,
      xfer: xfer,
      more: xfer == null
          ? 0
          : ((m['more'] as num?)?.toInt() ?? 0)
              .clamp(0, ConnectQueueChunks.maxTotal),
    );
  }
}

/// Reparte una cola en una primera parte reproducible al instante y trozos
/// que se añaden después. Cada trozo lleva un número de secuencia: si falta
/// uno, el receptor deja de añadir y su cola sigue siendo un prefijo válido de
/// la original (nunca una cola con huecos).
class ConnectQueueChunks {
  ConnectQueueChunks._(this.head, this.rest, this.xfer);

  /// Canciones que viajan con el mensaje principal.
  static const firstChunk = 40;

  /// Máximo de canciones por trozo (~25 KB cifrados, muy por debajo del tope
  /// de trama del servidor).
  static const chunkSize = 80;

  /// Tope de canciones de una cola transferida.
  static const maxTotal = 1000;

  final List<Map<String, dynamic>> head;
  final List<List<Map<String, dynamic>>> rest;

  /// Identificador de esta transferencia; `null` si todo cabe en [head].
  final String? xfer;

  int get more => rest.fold(0, (a, c) => a + c.length);

  static ConnectQueueChunks split(List<Map<String, dynamic>> tracks,
      {Random? random}) {
    final capped =
        tracks.length > maxTotal ? tracks.sublist(0, maxTotal) : tracks;
    if (capped.length <= firstChunk) {
      return ConnectQueueChunks._(capped, const [], null);
    }
    final rng = random ?? Random.secure();
    final id = List.generate(
        6, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return ConnectQueueChunks._(
      capped.sublist(0, firstChunk),
      [
        for (var i = firstChunk; i < capped.length; i += chunkSize)
          capped.sublist(i, min(capped.length, i + chunkSize)),
      ],
      id,
    );
  }

  /// Datos del comando [ConnectCommand.queueAppend] del trozo [seq].
  Map<String, dynamic> appendData(String scope, int seq) =>
      {'scope': scope, 'xfer': xfer, 'seq': seq, 'tracks': rest[seq]};

  /// `value` si es un identificador de transferencia válido, si no `null`.
  static String? validXfer(Object? value) =>
      value is String && RegExp(r'^[A-Za-z0-9]{4,32}$').hasMatch(value)
          ? value
          : null;
}

/// Lado receptor de [ConnectQueueChunks]: acepta solo los trozos de la última
/// transferencia, en orden y sin saltos, durante un tiempo limitado.
class ConnectQueueReceiver {
  ConnectQueueReceiver({
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  String? _xfer;
  int _next = 0;
  int _remaining = 0;
  DateTime _since = DateTime.fromMillisecondsSinceEpoch(0);

  /// Se llama al adoptar una cola: [xfer] y [more] vienen del transfer.
  void expect(String? xfer, int more) {
    _xfer = more > 0 ? xfer : null;
    _next = 0;
    _remaining = more;
    _since = _now();
  }

  /// Canciones (JSON) a añadir si [data] es el siguiente trozo esperado.
  List<Map<String, dynamic>>? accept(Map<String, dynamic> data, String? scope) {
    final xfer = ConnectQueueChunks.validXfer(data['xfer']);
    final seq = data['seq'];
    final tracks = data['tracks'];
    if (xfer == null || xfer != _xfer || data['scope'] != scope) return null;
    if (seq != _next || tracks is! List || tracks.isEmpty) return null;
    if (_now().difference(_since) > ttl) {
      _xfer = null;
      return null;
    }
    if (tracks.length > ConnectQueueChunks.chunkSize ||
        tracks.length > _remaining) {
      _xfer = null; // Trozo incoherente: se abandona el resto.
      return null;
    }
    final valid = [
      for (final t in tracks)
        if (t is Map && t['id'] is String) Map<String, dynamic>.from(t),
    ];
    if (valid.length != tracks.length) {
      _xfer = null;
      return null;
    }
    _next++;
    _remaining -= valid.length;
    if (_remaining <= 0) _xfer = null;
    return valid;
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
  static const shuffle = 'shuffle'; // alterna
  static const repeat = 'repeat'; // alterna off → all → one
  static const playQueue = 'play_queue'; // data: scope, tracks, index, shuffle
  static const queueAdd = 'queue_add'; // data: track
  static const queueNext = 'queue_next'; // data: track
  static const queueRemove = 'queue_remove'; // value: índice absoluto
  static const queueMove = 'queue_move'; // data: from, to (absolutos)
  static const queueClear = 'queue_clear';
  static const queueAppend = 'queue_append'; // data: scope, xfer, seq, tracks
  static const all = {
    toggle,
    play,
    pause,
    next,
    previous,
    seek,
    volume,
    shuffle,
    repeat,
    playQueue,
    queueAdd,
    queueNext,
    queueRemove,
    queueMove,
    queueClear,
    queueAppend,
  };
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
