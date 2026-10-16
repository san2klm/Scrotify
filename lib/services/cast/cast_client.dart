import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import 'cast_protocol.dart';

/// Dispositivo Cast encontrado en la red.
class CastDevice {
  const CastDevice({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;
  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is CastDevice && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Busca dispositivos Chromecast / Google Cast con mDNS (`_googlecast._tcp`).
Future<List<CastDevice>> discoverCastDevices(
    {Duration timeout = const Duration(seconds: 4)}) async {
  final client = MDnsClient();
  final found = <CastDevice>{};
  try {
    await client.start();
    const service = '_googlecast._tcp.local';
    await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(service),
        timeout: timeout)) {
      String? friendly;
      await for (final txt in client.lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(ptr.domainName),
          timeout: const Duration(seconds: 1))) {
        for (final line in txt.text.split('\n')) {
          if (line.startsWith('fn=')) friendly = line.substring(3);
        }
      }
      await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 1))) {
        await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 1))) {
          found.add(CastDevice(
            name: friendly ?? ptr.domainName.split('.').first,
            host: ip.address.address,
            port: srv.port,
          ));
        }
      }
    }
  } catch (e) {
    debugPrint('discoverCastDevices: $e');
  } finally {
    client.stop();
  }
  return found.toList();
}

/// Emisor Cast mínimo: lanza el receptor multimedia por defecto y le manda una
/// URL para reproducir. Todo el estado de reproducción lo lleva el dispositivo.
///
/// ⚠️ La URL llega al Chromecast: si lleva credenciales Subsonic (`u/t/s`), el
/// dispositivo las ve. Es un token con salt, no la contraseña.
class CastClient {
  CastClient._(this._socket, this.device);

  final SecureSocket _socket;
  final CastDevice device;

  final CastFrameReader _reader = CastCodec.reader();
  final StreamController<CastMessage> _messages =
      StreamController<CastMessage>.broadcast();

  static const _sender = 'sender-0';
  static const _receiver = 'receiver-0';

  Timer? _heartbeat;
  int _requestId = 0;
  String? _transportId;
  int? _mediaSessionId;
  bool _closed = false;

  Stream<CastMessage> get messages => _messages.stream;
  bool get isClosed => _closed;

  static Future<CastClient> connect(CastDevice device,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final socket = await SecureSocket.connect(
      device.host,
      device.port,
      // Los Chromecast usan certificados propios.
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    final client = CastClient._(socket, device);
    client._start();
    return client;
  }

  void _start() {
    _socket.listen(
      (chunk) {
        for (final message in _reader.add(chunk)) {
          _onMessage(message);
        }
      },
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
    _send(CastNamespaces.connection, _receiver, CastPayloads.connect());
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      _send(CastNamespaces.heartbeat, _receiver, CastPayloads.ping());
    });
  }

  void _onMessage(CastMessage m) {
    if (m.namespace == CastNamespaces.heartbeat && m.type == 'PING') {
      _send(CastNamespaces.heartbeat, _receiver, CastPayloads.pong());
      return;
    }
    final json = m.json;
    if (m.namespace == CastNamespaces.receiver &&
        json?['type'] == 'RECEIVER_STATUS') {
      final apps = json?['status']?['applications'];
      if (apps is List && apps.isNotEmpty && apps.first is Map) {
        final id = (apps.first as Map)['transportId'];
        if (id is String) _transportId = id;
      }
    }
    if (m.namespace == CastNamespaces.media &&
        json?['type'] == 'MEDIA_STATUS') {
      final status = json?['status'];
      if (status is List && status.isNotEmpty && status.first is Map) {
        final id = (status.first as Map)['mediaSessionId'];
        if (id is int) _mediaSessionId = id;
      }
    }
    if (!_messages.isClosed) _messages.add(m);
  }

  void _send(String namespace, String destination, String payload) {
    if (_closed) return;
    try {
      _socket.add(CastCodec.encodeFrame(CastMessage(
        source: _sender,
        destination: destination,
        namespace: namespace,
        payload: payload,
      )));
    } catch (_) {
      unawaited(close());
    }
  }

  /// Lanza el receptor multimedia y espera su `transportId`.
  Future<void> _ensureApp() async {
    if (_transportId != null) return;
    _send(
        CastNamespaces.receiver, _receiver, CastPayloads.launch(++_requestId));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_transportId == null) {
      if (_closed || DateTime.now().isAfter(deadline)) {
        throw TimeoutException('El Chromecast no lanzó el receptor');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _send(CastNamespaces.connection, _transportId!, CastPayloads.connect());
  }

  /// Reproduce [url] en el dispositivo.
  Future<void> load({
    required String url,
    required String contentType,
    String? title,
    String? artist,
    String? album,
    String? imageUrl,
    double? durationSeconds,
  }) async {
    await _ensureApp();
    _send(
      CastNamespaces.media,
      _transportId!,
      CastPayloads.load(
        ++_requestId,
        url: url,
        contentType: contentType,
        title: title,
        artist: artist,
        album: album,
        imageUrl: imageUrl,
        durationSeconds: durationSeconds,
      ),
    );
  }

  void _control(String type, {double? currentTime}) {
    final transport = _transportId, session = _mediaSessionId;
    if (transport == null || session == null) return;
    _send(
      CastNamespaces.media,
      transport,
      CastPayloads.mediaControl(type, ++_requestId, session,
          currentTime: currentTime),
    );
  }

  void play() => _control('PLAY');
  void pause() => _control('PAUSE');
  void stop() => _control('STOP');
  void seek(Duration position) =>
      _control('SEEK', currentTime: position.inMilliseconds / 1000);

  void setVolume(double level) => _send(CastNamespaces.receiver, _receiver,
      CastPayloads.setVolume(++_requestId, level));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    try {
      _socket.add(CastCodec.encodeFrame(CastMessage(
        source: _sender,
        destination: _receiver,
        namespace: CastNamespaces.connection,
        payload: CastPayloads.close(),
      )));
      await _socket.flush();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    if (!_messages.isClosed) await _messages.close();
  }
}
