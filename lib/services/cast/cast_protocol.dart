import 'dart:convert';
import 'dart:typed_data';

/// Mensaje CASTV2 (protobuf `CastMessage`, solo payload de texto).
class CastMessage {
  const CastMessage({
    required this.source,
    required this.destination,
    required this.namespace,
    required this.payload,
  });

  final String source;
  final String destination;
  final String namespace;

  /// JSON ya serializado.
  final String payload;

  Map<String, dynamic>? get json {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  String? get type => json?['type'] as String?;
}

/// Namespaces de Cast usados por un emisor sencillo.
class CastNamespaces {
  static const connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const receiver = 'urn:x-cast:com.google.cast.receiver';
  static const media = 'urn:x-cast:com.google.cast.media';
}

/// Codificación protobuf mínima del `CastMessage` y su trama TCP
/// (`longitud uint32 big-endian | mensaje`).
class CastCodec {
  CastCodec._();

  static void _varint(BytesBuilder out, int value) {
    var v = value;
    while (v > 0x7F) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  static void _string(BytesBuilder out, int field, String value) {
    final bytes = utf8.encode(value);
    out.addByte((field << 3) | 2);
    _varint(out, bytes.length);
    out.add(bytes);
  }

  /// Mensaje protobuf (sin la longitud de trama).
  static Uint8List encodeMessage(CastMessage m) {
    final out = BytesBuilder();
    out.addByte((1 << 3) | 0); // protocol_version = CASTV2_1_0
    _varint(out, 0);
    _string(out, 2, m.source);
    _string(out, 3, m.destination);
    _string(out, 4, m.namespace);
    out.addByte((5 << 3) | 0); // payload_type = STRING
    _varint(out, 0);
    _string(out, 6, m.payload);
    return out.toBytes();
  }

  /// Trama completa lista para enviar por el socket.
  static Uint8List encodeFrame(CastMessage m) {
    final body = encodeMessage(m);
    final out = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, body.length, Endian.big))
          .buffer
          .asUint8List())
      ..add(body);
    return out.toBytes();
  }

  /// Decodifica un mensaje protobuf; `null` si es inválido o no es de texto.
  static CastMessage? decodeMessage(List<int> bytes) {
    var i = 0;
    int readVarint() {
      var result = 0, shift = 0;
      while (i < bytes.length) {
        final b = bytes[i++];
        result |= (b & 0x7F) << shift;
        if (b & 0x80 == 0) return result;
        shift += 7;
        if (shift > 35) break;
      }
      throw const FormatException('varint inválido');
    }

    String? source, destination, namespace, payload;
    try {
      while (i < bytes.length) {
        final tag = readVarint();
        final field = tag >> 3, wire = tag & 7;
        if (wire == 0) {
          readVarint();
        } else if (wire == 2) {
          final length = readVarint();
          if (i + length > bytes.length) return null;
          final chunk = bytes.sublist(i, i + length);
          i += length;
          switch (field) {
            case 2:
              source = utf8.decode(chunk);
            case 3:
              destination = utf8.decode(chunk);
            case 4:
              namespace = utf8.decode(chunk);
            case 6:
              payload = utf8.decode(chunk);
          }
        } else {
          return null;
        }
      }
    } on FormatException {
      return null;
    }
    if (source == null ||
        destination == null ||
        namespace == null ||
        payload == null) {
      return null;
    }
    return CastMessage(
      source: source,
      destination: destination,
      namespace: namespace,
      payload: payload,
    );
  }

  /// Separa tramas de un flujo TCP que llega en trozos arbitrarios.
  static CastFrameReader reader() => CastFrameReader();
}

class CastFrameReader {
  final BytesBuilder _buffer = BytesBuilder();

  /// Añade [chunk] y devuelve los mensajes completos que ya se pueden leer.
  List<CastMessage> add(List<int> chunk) {
    _buffer.add(chunk);
    final out = <CastMessage>[];
    var data = _buffer.toBytes();
    var offset = 0;
    while (data.length - offset >= 4) {
      final length = ByteData.sublistView(data, offset, offset + 4)
          .getUint32(0, Endian.big);
      // Un mensaje Cast legítimo es pequeño; esto corta basura/ataques.
      if (length > 1 << 20) {
        _buffer.clear();
        return out;
      }
      if (data.length - offset - 4 < length) break;
      final message = CastCodec.decodeMessage(
          data.sublist(offset + 4, offset + 4 + length));
      if (message != null) out.add(message);
      offset += 4 + length;
    }
    _buffer.clear();
    if (offset < data.length) _buffer.add(data.sublist(offset));
    return out;
  }
}

/// Construcción de las cargas JSON que usa el emisor.
class CastPayloads {
  CastPayloads._();

  static const defaultMediaReceiverAppId = 'CC1AD845';

  static String connect() => jsonEncode({'type': 'CONNECT'});
  static String close() => jsonEncode({'type': 'CLOSE'});
  static String ping() => jsonEncode({'type': 'PING'});
  static String pong() => jsonEncode({'type': 'PONG'});

  static String launch(int requestId,
          {String appId = defaultMediaReceiverAppId}) =>
      jsonEncode({'type': 'LAUNCH', 'appId': appId, 'requestId': requestId});

  static String getStatus(int requestId) =>
      jsonEncode({'type': 'GET_STATUS', 'requestId': requestId});

  static String load(
    int requestId, {
    required String url,
    required String contentType,
    String? title,
    String? artist,
    String? album,
    String? imageUrl,
    double? durationSeconds,
  }) =>
      jsonEncode({
        'type': 'LOAD',
        'requestId': requestId,
        'autoplay': true,
        'currentTime': 0,
        'media': {
          'contentId': url,
          'streamType': 'BUFFERED',
          'contentType': contentType,
          if (durationSeconds != null && durationSeconds > 0)
            'duration': durationSeconds,
          'metadata': {
            'metadataType': 3, // MusicTrackMediaMetadata
            if (title != null) 'title': title,
            if (artist != null) 'artist': artist,
            if (album != null) 'albumName': album,
            if (imageUrl != null)
              'images': [
                {'url': imageUrl}
              ],
          },
        },
      });

  static String mediaControl(String type, int requestId, int mediaSessionId,
          {double? currentTime}) =>
      jsonEncode({
        'type': type, // PLAY | PAUSE | STOP | SEEK
        'requestId': requestId,
        'mediaSessionId': mediaSessionId,
        if (currentTime != null) 'currentTime': currentTime,
      });

  static String setVolume(int requestId, double level) => jsonEncode({
        'type': 'SET_VOLUME',
        'requestId': requestId,
        'volume': {'level': level.clamp(0.0, 1.0)},
      });
}

/// `contentType` según la extensión del archivo.
String castContentTypeFor(String? suffix) => switch (suffix?.toLowerCase()) {
      'flac' => 'audio/flac',
      'ogg' || 'oga' => 'audio/ogg',
      'opus' => 'audio/ogg',
      'm4a' || 'aac' => 'audio/mp4',
      'wav' => 'audio/wav',
      _ => 'audio/mpeg',
    };
