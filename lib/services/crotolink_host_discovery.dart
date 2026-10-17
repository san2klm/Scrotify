part of 'crotolink_host_service.dart';

/// Descubrimiento en la red local: baliza UDP, presencia y direcciones de difusión.
mixin _CrotoLinkHostDiscovery on _CrotoLinkHostBase {
  // ---------------------------------------------------------------------------
  // Beacon UDP para Radar en Red Local
  // ---------------------------------------------------------------------------
  Future<void> _startDiscoveryBeacon() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kCrotoLinkDiscoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _discoverySocket!.broadcastEnabled = true;
      final multicastGroup = InternetAddress(kCrotoLinkDiscoveryMulticastGroup);
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      if (interfaces.isEmpty) {
        _discoverySocket!.joinMulticast(multicastGroup);
      } else {
        for (final interface in interfaces) {
          try {
            _discoverySocket!.joinMulticast(multicastGroup, interface);
          } catch (e) {
            debugPrint(
              'CrotoLinkHostService: No se pudo unir al multicast en ${interface.name}: $e',
            );
          }
        }
      }
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket?.receive();
          if (dg != null) {
            _handleDiscoveryDatagram(dg);
          }
        }
      });

      // Cachear direcciones de difusión para no llamar NetworkInterface.list en cada ciclo
      await _updateCachedBroadcastAddresses();

      // Ráfaga inmediata de tres pulsos al inicio
      _broadcastPresence();
      _discoveryBurstTimers.add(Timer(const Duration(milliseconds: 250), () {
        _broadcastPresence();
      }));
      _discoveryBurstTimers.add(Timer(const Duration(milliseconds: 500), () {
        _broadcastPresence();
      }));

      // Anuncio periódico a ritmo constante de 8 segundos sin NetworkInterface.list
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        _broadcastPresence();
      });
      debugPrint(
          'CrotoLinkHostService: Discovery beacon bound on port $kCrotoLinkDiscoveryPort');
    } catch (e) {
      debugPrint('CrotoLinkHostService: Discovery beacon failed to bind: $e');
    }
  }

  Future<void> _updateCachedBroadcastAddresses() async {
    final targets = <InternetAddress>[
      InternetAddress.loopbackIPv4,
      InternetAddress('255.255.255.255'),
      InternetAddress(kCrotoLinkDiscoveryMulticastGroup),
    ];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            try {
              targets.add(
                InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
              );
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint(
          'CrotoLinkHostService: no se pudieron listar las interfaces de red: $e');
    }
    _cachedBroadcastAddresses = targets;
  }

  /// Payload de presencia con IP principal y respaldo (segunda interfaz).
  Map<String, dynamic> _presencePayload() {
    final hasFallback = _allLocalIps.length > 1;
    return {
      'tag': kCrotoLinkDiscoveryAppTag,
      'op': 'crotolink_presence',
      'host': _hostIp,
      'port': _port,
      'transport': 'wss',
      'tlsFingerprint': _tlsIdentity?.fingerprintSha256,
      'pin': _pinCode!.value,
      'sessionTitle': 'CrotoLink de $_hostName',
      'hostName': _hostName,
      'participantCount': _participants.length + 1,
      'currentTrackTitle': _currentTrackTitle,
      'currentTrackArtist': _currentTrackArtist,
      'albumArtUrl': _albumArtUrl,
      'mode': _mode.name,
      'isPublic': _isPublic,
      'hasPassword': roomPassword?.isNotEmpty == true,
      if (hasFallback)
        'remoteHost': _allLocalIps.firstWhere((address) => address != _hostIp),
      if (hasFallback) 'remotePort': _port,
    };
  }

  /// Envía presencia a las direcciones de destino cacheadas (loopback, broadcast, multicast, subred).
  void _broadcastPresence() {
    if (_server == null ||
        _pinCode == null ||
        _tlsIdentity == null ||
        !_isPublic) {
      return;
    }
    final socket = _discoverySocket;
    if (socket == null) return;
    try {
      final bytes = utf8.encode(jsonEncode(_presencePayload()));
      for (final target in _cachedBroadcastAddresses) {
        try {
          socket.send(bytes, target, kCrotoLinkDiscoveryPort);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _handleDiscoveryDatagram(Datagram dg) {
    if (_server == null || _pinCode == null) return;

    try {
      final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (msg['tag'] != kCrotoLinkDiscoveryAppTag) return;

      final op = msg['op'] as String?;
      final pin = msg['pin'] as String?;

      bool shouldReply = false;
      if (op == 'discover_crotolink') {
        shouldReply = _isPublic;
      } else if (op == 'find_crotolink' && pin != null) {
        shouldReply = pin.toUpperCase() == _pinCode!.value;
      }

      if (shouldReply) {
        final reply = jsonEncode(_presencePayload());

        _discoverySocket?.send(
          utf8.encode(reply),
          dg.address,
          dg.port,
        );
      }
    } catch (_) {}
  }

  Future<List<String>> _getAllLocalIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      // NetworkInterface.list no garantiza orden. Wi‑Fi/Ethernet deben ir
      // antes que VPN, Docker o adaptadores virtuales, porque la primera IP se
      // codifica en el QR.
      interfaces.sort(
        (a, b) => _interfacePriority(a.name).compareTo(
          _interfacePriority(b.name),
        ),
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
    } catch (e) {
      debugPrint(
          'CrotoLinkHostService: no se pudieron obtener las IP locales: $e');
    }
    if (ips.isEmpty) ips.add('127.0.0.1');
    return ips;
  }

  int _interfacePriority(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('wlan') ||
        normalized.contains('wifi') ||
        normalized.startsWith('wl') ||
        normalized.startsWith('eth') ||
        normalized.startsWith('enp') ||
        normalized.startsWith('eno') ||
        normalized.startsWith('enx') ||
        normalized == 'en0') {
      return 0;
    }
    if (normalized.contains('docker') ||
        normalized.contains('vbox') ||
        normalized.contains('vmnet') ||
        normalized.contains('virbr') ||
        normalized.startsWith('br-') ||
        normalized.startsWith('tun') ||
        normalized.startsWith('tap') ||
        normalized.startsWith('ppp') ||
        normalized.contains('tailscale') ||
        normalized.contains('zerotier')) {
      return 2;
    }
    return 1;
  }
}
