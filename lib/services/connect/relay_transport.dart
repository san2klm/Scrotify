import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'connect_account.dart';
import 'connect_protocol.dart';
import 'connect_transport.dart';

/// Conecta con el servidor Jam (`connect_join` / `connect_send`) para ver y
/// controlar los dispositivos del mismo usuario de Navidrome, también fuera de
/// la red local. El servidor verifica al usuario con Navidrome y solo reenvía
/// blobs cifrados.
class RelayTransport implements ConnectTransport {
  RelayTransport({
    required this.account,
    required this.serverUrl,
    required this.selfId,
    required this.selfName,
    required this.selfKind,
    WebSocketChannel Function(Uri uri)? connect,
    this.retryDelay = const Duration(seconds: 5),
  }) : _connect = connect ?? WebSocketChannel.connect;

  final ConnectAccount account;
  final Uri serverUrl;
  final String selfId;
  final String selfName;
  final ConnectKind selfKind;
  final Duration retryDelay;
  final WebSocketChannel Function(Uri uri) _connect;

  final _devices = StreamController<List<ConnectDevice>>.broadcast();
  final _messages = StreamController<({String from, String blob})>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _running = false;
  bool _joined = false;
  Set<String> _known = {};
  String? _problem;

  @override
  Stream<List<ConnectDevice>> get devices => _devices.stream;

  @override
  Stream<({String from, String blob})> get messages => _messages.stream;

  @override
  String? get problem => _problem;

  @override
  bool canReach(String deviceId) => _joined && _known.contains(deviceId);

  @override
  Future<void> start() async {
    _running = true;
    _open();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _joined = false;
    _known = {};
    _devices.add(const []);
  }

  void _open() {
    if (!_running) return;
    try {
      final channel = _connect(serverUrl);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
      final auth = account.authToken();
      channel.sink.add(jsonEncode({
        'action': 'connect_join',
        'user': account.user,
        'token': auth.token,
        'salt': auth.salt,
        'deviceId': selfId,
        'name': selfName,
        'kind': selfKind.name,
      }));
    } catch (error) {
      debugPrint('connect/relay: $error');
      _onClosed();
    }
  }

  void _onClosed() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_joined || _known.isNotEmpty) {
      _joined = false;
      _known = {};
      _devices.add(const []);
    }
    if (!_running) return;
    _problem ??= 'Sin conexión con el servidor Jam.';
    _retry?.cancel();
    _retry = Timer(retryDelay, _open);
  }

  void _onData(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      if (data['status'] == 'connect_joined' ||
          data['event'] == 'connect_devices') {
        _joined = true;
        _problem = null;
        _publish(data['devices'] as List? ?? const []);
      } else if (data['status'] == 'connect_error') {
        _problem = data['message'] as String? ?? 'El servidor rechazó Connect.';
        _devices.add(const []);
      } else if (data['event'] == 'connect_msg') {
        final from = data['from'];
        final blob = data['blob'];
        if (from is String && blob is String) {
          _messages.add((from: from, blob: blob));
        }
      }
    } catch (_) {
      // Trama ajena o malformada: se ignora.
    }
  }

  void _publish(List<dynamic> raw) {
    final devices = <ConnectDevice>[
      for (final d in raw)
        if (d is Map && d['deviceId'] is String && d['deviceId'] != selfId)
          ConnectDevice(
            id: d['deviceId'] as String,
            name: (d['name'] as String?) ?? 'Dispositivo',
            kind: connectKindFrom(d['kind'] as String?),
            viaRelay: true,
          ),
    ];
    _known = {for (final d in devices) d.id};
    _devices.add(devices);
  }

  @override
  Future<void> send(String? deviceId, String blob) async {
    if (!_joined) return;
    _channel?.sink.add(jsonEncode(
        {'action': 'connect_send', 'to': deviceId ?? '*', 'blob': blob}));
  }
}
