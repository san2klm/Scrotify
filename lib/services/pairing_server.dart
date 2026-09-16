import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/pairing_models.dart';
import '../utils/crypto_helper.dart';

/// Servidor de emparejamiento LAN que corre en el PC.
///
/// Expone:
/// - `GET /pair/status` → estado actual
/// - `POST /pair/claim` → móvil reclama el código con su clave pública
/// - Beacon UDP (puerto [kPairingDiscoveryPort]) para descubrimiento automático
///   por código y escaneo de radar de dispositivos en la misma red Wi-Fi.
class PairingServer {
  static const int _defaultTtlSeconds = 300; // 5 min

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _expiryTimer;

  String? _hostIp;
  List<String> _allLocalIps = [];
  int _port = 0;
  PairCode? _currentCode;
  DateTime? _expiresAt;
  PairingStatus _status = PairingStatus.idle;
  String? _serverUrl; // URL del servidor Navidrome a compartir
  String? _username;
  String? _password;
  String _deviceName = '';
  SimpleKeyPair? _ephemeralKeyPair; // clave efímera del PC para este emparejamiento
  final _statusController = StreamController<PairingStatus>.broadcast();

  /// Stream del estado para la UI.
  Stream<PairingStatus> get statusStream => _statusController.stream;
  PairingStatus get status => _status;
  String? get hostIp => _hostIp;
  List<String> get allLocalIps => _allLocalIps;
  int get port => _port;
  String get deviceName => _deviceName;
  String? get currentCode => _currentCode?.value;
  String? get currentCodeFormatted => _currentCode?.formatted;
  String? get qrDataUri => _currentCode != null && _hostIp != null
      ? QrData(host: _hostIp!, port: _port, code: _currentCode!.value).toUri()
      : null;
  int get remainingSeconds => _expiresAt != null
      ? (_expiresAt!.difference(DateTime.now()).inSeconds)
          .clamp(0, _defaultTtlSeconds)
      : 0;
  bool get isActive => _status == PairingStatus.waiting;

  /// Inicia el servidor de emparejamiento con las credenciales del servidor Navidrome.
  Future<void> start({
    required String serverUrl,
    required String username,
    required String password,
    String? customDeviceName,
    int ttlSeconds = _defaultTtlSeconds,
  }) async {
    await stop(); // limpiar cualquier instancia previa

    _serverUrl = serverUrl;
    _username = username;
    _password = password;
    _deviceName = customDeviceName ?? _getDefaultDeviceName();

    // Generar código y clave efímera
    _currentCode = PairCode.generate();
    _ephemeralKeyPair = await generateKeyPair();
    _expiresAt = DateTime.now().add(Duration(seconds: ttlSeconds));
    _status = PairingStatus.waiting;
    _statusController.add(_status);

    // Bind a puerto efímero en todas las interfaces
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    _allLocalIps = await _getAllLocalIps();
    _hostIp = _allLocalIps.isNotEmpty ? _allLocalIps.first : '127.0.0.1';
    debugPrint(
        'PairingServer listening on $_hostIp:$_port (device: $_deviceName, code: ${_currentCode?.value})');

    // Rutas HTTP
    _server!.listen(_handleRequest);

    // Timer de expiración
    _expiryTimer = Timer(Duration(seconds: ttlSeconds), _expire);

    // Iniciar beacon de descubrimiento UDP
    await _startDiscoveryBeacon();
  }

  String _getDefaultDeviceName() {
    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty) return host;
    } catch (_) {}
    if (Platform.isLinux) return 'PC Linux';
    if (Platform.isWindows) return 'PC Windows';
    if (Platform.isMacOS) return 'Mac';
    return 'Computadora';
  }

  /// Detiene el servidor y limpia estado.
  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;

    _stopDiscoveryBeacon();

    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (_) {}
      _server = null;
    }

    if (_status != PairingStatus.idle) {
      _status = PairingStatus.idle;
      _statusController.add(_status);
    }
    _currentCode = null;
    _expiresAt = null;
    _ephemeralKeyPair = null;
    _serverUrl = null;
    _username = null;
    _password = null;
    _hostIp = null;
    _allLocalIps = [];
    _port = 0;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final path = req.uri.path;
    debugPrint('PairingServer: ${req.method} $path');

    try {
      if (path == '/pair/status' && req.method == 'GET') {
        await _handleStatus(req);
      } else if (path == '/pair/claim' && req.method == 'POST') {
        await _handleClaim(req);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (e) {
      debugPrint('PairingServer error: $e');
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.write('{"error": "Internal server error"}');
      await req.response.close();
    }
  }

  Future<void> _handleStatus(HttpRequest req) async {
    final body = jsonEncode({
      'deviceName': _deviceName,
      'serverUrl': _serverUrl,
      'status': _status.name,
      'code': _currentCode?.value,
      'expiresIn': remainingSeconds,
    });
    req.response.headers.contentType = ContentType.json;
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _handleClaim(HttpRequest req) async {
    if (_status != PairingStatus.waiting || _currentCode == null) {
      req.response.statusCode = HttpStatus.gone;
      req.response.write('{"error": "No active pairing session"}');
      await req.response.close();
      return;
    }

    // Leer body
    final content = await utf8.decoder.bind(req).join();
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write('{"error": "Invalid JSON"}');
      await req.response.close();
      return;
    }

    final request = PairClaimRequest.fromJson(json);

    // Validar código
    if (request.code.toUpperCase() != _currentCode!.value) {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.write('{"error": "Invalid code"}');
      await req.response.close();
      return;
    }

    // Validar clave pública (32 bytes = 43-44 chars base64url)
    if (request.publicKey.length < 40) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write('{"error": "Invalid public key"}');
      await req.response.close();
      return;
    }

    // Cifrar credenciales con sealed box
    final credentials = PairCredentials(
      url: _serverUrl!,
      username: _username!,
      password: _password!,
    );
    final plaintext = utf8.encode(jsonEncode(credentials.toJson()));

    final responseMap = await sealEncrypt(
      ephemeralKeyPair: _ephemeralKeyPair!,
      recipientPublicKey: SimplePublicKey(
        base64Url.decode(request.publicKey),
        type: KeyPairType.x25519,
      ),
      plaintext: Uint8List.fromList(plaintext),
    );

    // Responder primero
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(responseMap));
    await req.response.close();

    // Luego marcar como emparejado y detener servidor tras un breve respiro
    _status = PairingStatus.paired;
    _statusController.add(_status);
    _expiryTimer?.cancel();
    _stopDiscoveryBeacon();

    // Detener completamente en segundo plano tras 500ms para asegurar el flush HTTP
    Future.delayed(const Duration(milliseconds: 500), () => stop());
  }

  void _expire() {
    if (_status == PairingStatus.waiting) {
      _status = PairingStatus.expired;
      _statusController.add(_status);
    }
    stop();
  }

  Future<List<String>> _getAllLocalIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254.') &&
              !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    if (ips.isEmpty) ips.add('127.0.0.1');
    return ips;
  }

  // ---------------------------------------------------------------------------
  // Beacon UDP para descubrimiento automático en la red local
  // ---------------------------------------------------------------------------
  Future<void> _startDiscoveryBeacon() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kPairingDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket?.receive();
          if (dg == null) return;
          _handleDiscoveryDatagram(dg);
        }
      });
      debugPrint('PairingServer: discovery beacon bound on port $kPairingDiscoveryPort');
    } catch (e) {
      debugPrint('PairingServer: discovery beacon failed to bind: $e');
    }
  }

  void _handleDiscoveryDatagram(Datagram dg) {
    if (_status != PairingStatus.waiting || _currentCode == null) return;

    try {
      final text = utf8.decode(dg.data);
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['app'] != kPairingDiscoveryAppTag) return;

      final op = json['op'] as String?;

      // 1. Búsqueda específica por código
      if (op == 'find') {
        final requestedCode = (json['code'] as String?)?.toUpperCase();
        if (requestedCode == _currentCode!.value) {
          final responsePayload = jsonEncode({
            'app': kPairingDiscoveryAppTag,
            'op': 'here',
            'code': _currentCode!.value,
            'port': _port,
            'host': _hostIp,
            'deviceName': _deviceName,
            'serverUrl': _serverUrl,
            'expiresIn': remainingSeconds,
          });
          final bytes = utf8.encode(responsePayload);
          _discoverySocket?.send(bytes, dg.address, dg.port);
          debugPrint(
              'PairingServer: replied to code match query from ${dg.address.address}:${dg.port}');
        }
      }
      // 2. Escaneo de radar / presencia en LAN
      else if (op == 'discover') {
        final responsePayload = jsonEncode({
          'app': kPairingDiscoveryAppTag,
          'op': 'presence',
          'deviceName': _deviceName,
          'serverUrl': _serverUrl,
          'port': _port,
          'host': _hostIp,
          'expiresIn': remainingSeconds,
        });
        final bytes = utf8.encode(responsePayload);
        _discoverySocket?.send(bytes, dg.address, dg.port);
        debugPrint(
            'PairingServer: replied to presence discovery from ${dg.address.address}:${dg.port}');
      }
    } catch (_) {}
  }

  void _stopDiscoveryBeacon() {
    try {
      _discoverySocket?.close();
    } catch (_) {}
    _discoverySocket = null;
  }
}
