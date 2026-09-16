import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/pairing_models.dart';
import '../services/pairing_client.dart';
import '../services/pairing_server.dart';

// =============================================================================
// LADO PC: PairingSharePanel (AMOLED)
// =============================================================================

/// Panel del lado PC con diseño optimizado para pantallas AMOLED (negros puros y acentos neón).
class PairingSharePanel extends StatefulWidget {
  final PairingServer server;
  final Future<({String url, String username, String password})?> Function()
      onGetCredentials;
  final VoidCallback? onPaired;
  final bool compact;

  const PairingSharePanel({
    super.key,
    required this.server,
    required this.onGetCredentials,
    this.onPaired,
    this.compact = false,
  });

  @override
  State<PairingSharePanel> createState() => _PairingSharePanelState();
}

class _PairingSharePanelState extends State<PairingSharePanel> {
  Timer? _ticker;
  bool _starting = false;
  String? _errorMessage;
  StreamSubscription<PairingStatus>? _statusSub;

  @override
  void initState() {
    super.initState();
    _listenStatus();
    if (widget.server.isActive) {
      _startTicker();
    }
  }

  void _listenStatus() {
    _statusSub = widget.server.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {});
      if (status == PairingStatus.paired) {
        _ticker?.cancel();
        widget.onPaired?.call();
      } else if (status == PairingStatus.expired ||
          status == PairingStatus.idle) {
        _ticker?.cancel();
      }
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!widget.server.isActive) {
        _ticker?.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _startPairing() async {
    setState(() {
      _starting = true;
      _errorMessage = null;
    });

    try {
      final creds = await widget.onGetCredentials();
      if (creds == null) {
        throw Exception(
            'Ingresa primero los datos del servidor (URL, usuario y contraseña)');
      }

      await widget.server.start(
        serverUrl: creds.url,
        username: creds.username,
        password: creds.password,
      );
      _startTicker();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopPairing() async {
    _ticker?.cancel();
    await widget.server.stop();
    if (mounted) setState(() {});
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1B1428),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 8),
            Text(
              '$label copiado al portapapeles',
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.server.status;

    if (_starting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA855F7)),
              SizedBox(height: 14),
              Text(
                'Iniciando sesión segura...',
                style: TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
            ],
          ),
        ),
      );
    }

    if (status == PairingStatus.paired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.8),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Color(0xFF10B981), size: 32),
              ),
              const SizedBox(height: 14),
              const Text(
                '¡Teléfono emparejado!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Las credenciales se transmitieron cifradas con éxito.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _startPairing,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF2A2A35)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Generar otro código', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ),
      );
    }

    if (status == PairingStatus.waiting && widget.server.currentCode != null) {
      final code = widget.server.currentCode!;
      final qrData = widget.server.qrDataUri ?? '';
      final seconds = widget.server.remainingSeconds;
      final minutes = seconds ~/ 60;
      final remSec = seconds % 60;
      final timeStr =
          '$minutes:${remSec.toString().padLeft(2, '0')}';

      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Listo para vincular (${widget.server.deviceName})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 13, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Contenedor QR AMOLED
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: widget.compact ? 150 : 175,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 14),

            const Text(
              'O escribe este código en tu teléfono:',
              style: TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
            const SizedBox(height: 8),

            // Chips del código 3 + 3 con opción de copiar
            GestureDetector(
              onTap: () => _copyToClipboard(code, 'Código $code'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AmoledCodeGroupChip(code: code.substring(0, 3)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('-',
                        style: TextStyle(
                            color: Colors.white30,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ),
                  _AmoledCodeGroupChip(code: code.substring(3)),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Copiar código',
                    icon: const Icon(Icons.copy_rounded,
                        size: 16, color: Colors.white54),
                    onPressed: () => _copyToClipboard(code, 'Código $code'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (widget.server.allLocalIps.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: widget.server.allLocalIps.map((ip) {
                  return GestureDetector(
                    onTap: () => _copyToClipboard(
                        '$ip:${widget.server.port}', 'IP $ip:${widget.server.port}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070709),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF1E1E28)),
                      ),
                      child: Text(
                        'IP: $ip:${widget.server.port}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _startPairing,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                  ),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Regenerar', style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _stopPairing,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent.withValues(alpha: 0.8),
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Estado inicial / inactivo
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF140E24),
            border: Border.all(
                color: const Color(0xFFA855F7).withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.qr_code_2_rounded,
              color: Color(0xFFA855F7), size: 28),
        ),
        const SizedBox(height: 12),
        const Text(
          'Emparejar con el teléfono',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Genera un código QR y un pin seguro para que tu teléfono pueda conectarse automáticamente sin escribir la contraseña.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.25)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _startPairing,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.qr_code_rounded, size: 17),
          label: const Text(
            'Generar código de acceso',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _AmoledCodeGroupChip extends StatelessWidget {
  final String code;
  const _AmoledCodeGroupChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFA855F7),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFA855F7).withValues(alpha: 0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 3,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// =============================================================================
// LADO TELÉFONO: PairingJoinPanel (AMOLED)
// =============================================================================

/// Panel del teléfono optimizado para AMOLED:
/// - Pestaña 1: 📡 Radar Wi-Fi de computadoras
/// - Pestaña 2: 🔢 Código PIN
/// - Botón: 📷 Escanear QR
/// - Desplegable: 🌐 Conexión Manual por IP
class PairingJoinPanel extends StatefulWidget {
  final Future<void> Function(PairCredentials creds) onCredentialsReceived;

  const PairingJoinPanel({
    super.key,
    required this.onCredentialsReceived,
  });

  @override
  State<PairingJoinPanel> createState() => _PairingJoinPanelState();
}

class _PairingJoinPanelState extends State<PairingJoinPanel> {
  int _activeTab = 0; // 0 = Radar LAN, 1 = Código

  // Radar LAN
  List<DiscoveredPc> _nearbyDevices = [];
  bool _scanningLan = false;

  // Código
  final _codeController = TextEditingController();

  // Manual IP
  bool _showManualIp = false;
  final _manualHostController = TextEditingController();
  final _manualPortController = TextEditingController();
  final _manualCodeController = TextEditingController();

  bool _loading = false;
  String? _statusText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scanLanDevices();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _manualHostController.dispose();
    _manualPortController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  Future<void> _scanLanDevices() async {
    if (_scanningLan) return;
    setState(() {
      _scanningLan = true;
      _errorMessage = null;
    });

    try {
      final devices = await PairingClient.discoverPcs(
        timeout: const Duration(seconds: 3),
      );
      if (mounted) {
        setState(() {
          _nearbyDevices = devices;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _scanningLan = false);
    }
  }

  Future<void> _connectToDiscoveredDevice(DiscoveredPc pc) async {
    String? code = pc.code;

    if (code == null || code.isEmpty) {
      code = await _promptForCodeDialog(pc.deviceName);
      if (code == null || code.isEmpty) return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Conectando con ${pc.deviceName} (${pc.host})...';
    });

    try {
      final creds = await PairingClient.claim(
        host: pc.host,
        port: pc.port,
        code: code,
      );

      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });

      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<String?> _promptForCodeDialog(String deviceName) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E0E12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E1E28)),
        ),
        title: Row(
          children: [
            const Icon(Icons.laptop_mac_rounded, color: Color(0xFFA855F7), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Código de $deviceName',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa el código que aparece en la pantalla de esa computadora:',
              style: TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(7),
                _PairCodeInputFormatter(),
              ],
              decoration: InputDecoration(
                hintText: 'XXX-XXX',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2), letterSpacing: 4),
                filled: true,
                fillColor: const Color(0xFF060608),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF22222E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFA855F7), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            ),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectWithCode() async {
    final raw = _codeController.text;
    final code = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Ingresa el código de 6 caracteres';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Buscando computadora en la red Wi-Fi...';
    });

    try {
      final pc = await PairingClient.findPcByCode(code);
      if (pc == null) {
        throw Exception(
            'No se encontró el PC con ese código en tu red Wi-Fi.\n'
            'Asegúrate de estar en la misma red o prueba con el escáner QR.');
      }

      if (!mounted) return;
      setState(() {
        _statusText = 'Conectando con ${pc.deviceName} (${pc.host})...';
      });

      final creds = await PairingClient.claim(
        host: pc.host,
        port: pc.port,
        code: pc.code ?? code,
      );

      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });

      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<void> _connectManualIp() async {
    final host = _manualHostController.text.trim();
    final port = int.tryParse(_manualPortController.text.trim());
    final code = _manualCodeController.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (host.isEmpty || port == null || port <= 0 || code.length != 6) {
      setState(() {
        _errorMessage = 'Ingresa IP/Host, Puerto válido y Código de 6 letras';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Conectando a $host:$port...';
    });

    try {
      final creds = await PairingClient.claim(
        host: host,
        port: port,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });
      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  Future<void> _openQrScanner() async {
    final scannedUri = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QrScannerSheet(),
    );

    if (scannedUri == null || !mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _statusText = 'Reclamando credenciales desde el QR...';
    });

    try {
      final creds = await PairingClient.claimFromQr(scannedUri);
      if (!mounted) return;
      setState(() {
        _statusText = 'Iniciando sesión en Navidrome...';
      });
      await widget.onCredentialsReceived(creds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sub-selector AMOLED
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF060608),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E1E28)),
          ),
          child: Row(
            children: [
              _buildSubTab(0, Icons.wifi_tethering_rounded, 'Radar Wi-Fi'),
              _buildSubTab(1, Icons.pin_outlined, 'Código PIN'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_activeTab == 0)
          _buildRadarSection()
        else
          _buildCodeSection(),

        const SizedBox(height: 14),

        // Botón Escanear QR
        OutlinedButton.icon(
          onPressed: _loading ? null : _openQrScanner,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF2A2A38)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded,
              size: 19, color: Color(0xFFA855F7)),
          label: const Text(
            'Escanear código QR con la cámara',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),

        // Desplegable conexión manual por IP
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showManualIp = !_showManualIp),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            icon: Icon(
              _showManualIp
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
            ),
            label: Text(
              _showManualIp
                  ? 'Ocultar conexión por IP'
                  : 'Conexión manual por IP',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ),

        if (_showManualIp) ...[
          const SizedBox(height: 6),
          _buildManualIpSection(),
        ],

        if (_loading && _statusText != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: Color(0xFFA855F7)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _statusText!,
                  style: const TextStyle(
                      color: Color(0xFFA855F7), fontSize: 12),
                ),
              ),
            ],
          ),
        ],

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubTab(int index, IconData icon, String label) {
    final isSelected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1C132E) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.4),
                    width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: isSelected
                      ? const Color(0xFFA855F7)
                      : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sección Radar LAN AMOLED
  // ---------------------------------------------------------------------------
  Widget _buildRadarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Dispositivos en tu red Wi-Fi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Volver a escanear',
              icon: _scanningLan
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.8, color: Color(0xFFA855F7)),
                    )
                  : const Icon(Icons.refresh, size: 17, color: Colors.white54),
              onPressed: _scanningLan ? null : _scanLanDevices,
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Computadoras con Scrotify listas para emparejar:',
          style: TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
        const SizedBox(height: 10),

        if (_nearbyDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF070709),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E1E28)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    _scanningLan
                        ? Icons.radar_rounded
                        : Icons.devices_other_rounded,
                    size: 28,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scanningLan
                        ? 'Buscando computadoras en la red...'
                        : 'No se encontraron computadoras emitiendo',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Toca "Generar código" en tu PC o usa la pestaña "Código PIN".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white30, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          )
        else
          ..._nearbyDevices.map((pc) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF070709),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1B122C),
                      border: Border.all(
                          color: const Color(0xFFA855F7).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.laptop_rounded,
                        color: Color(0xFFA855F7), size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pc.deviceName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          '${pc.host}:${pc.port}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ? null : () => _connectToDiscoveredDevice(pc),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Vincular', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sección Código PIN AMOLED
  // ---------------------------------------------------------------------------
  Widget _buildCodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Código de inicio de sesión',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Ingresa el código que aparece en tu computadora:',
          style: TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _codeController,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 6,
            fontFamily: 'monospace',
          ),
          inputFormatters: [
            LengthLimitingTextInputFormatter(7),
            _PairCodeInputFormatter(),
          ],
          decoration: InputDecoration(
            hintText: 'XXX-XXX',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.15),
              letterSpacing: 6,
            ),
            filled: true,
            fillColor: const Color(0xFF070709),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E1E28)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E1E28)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFFA855F7), width: 1.5),
            ),
          ),
          onSubmitted: (_) => _connectWithCode(),
        ),
        const SizedBox(height: 12),

        ElevatedButton(
          onPressed: _loading ? null : _connectWithCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text(
            'Vincular con este código',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sección Manual por IP AMOLED
  // ---------------------------------------------------------------------------
  Widget _buildManualIpSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF070709),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Conexión directa por dirección IP',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 7,
                child: TextField(
                  controller: _manualHostController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'IP del PC',
                    labelStyle:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                    hintText: '192.168.1.50',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2), fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF000000),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E1E28)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _manualPortController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Puerto',
                    labelStyle:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                    hintText: '54321',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2), fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF000000),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E1E28)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _manualCodeController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, letterSpacing: 2),
            inputFormatters: [
              LengthLimitingTextInputFormatter(7),
              _PairCodeInputFormatter(),
            ],
            decoration: InputDecoration(
              labelText: 'Código de 6 letras',
              labelStyle:
                  const TextStyle(color: Colors.white54, fontSize: 11),
              hintText: 'ABC-DEF',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2), fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF000000),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E1E28)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _connectManualIp,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.link_rounded, size: 15),
            label: const Text('Conectar por IP', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Formateador automático que añade el guion en la posición 3: "ABCDEF" → "ABC-DEF"
class _PairCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final clean =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length > 6) {
      return oldValue;
    }

    String formatted = clean;
    if (clean.length > 3) {
      formatted = '${clean.substring(0, 3)}-${clean.substring(3)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// =============================================================================
// Modal con escáner de cámara QR AMOLED
// =============================================================================

/// Modal con escáner de cámara para leer el código QR del PC.
class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({super.key});

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.startsWith('scrotify://pair')) {
        _handled = true;
        Navigator.of(context).pop(value);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF22222E), width: 1.2)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                const Text(
                  'Escanear código QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white70, size: 20),
                  onPressed: () => _controller.toggleTorch(),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Apunta con la cámara al código QR que aparece en la pantalla de tu PC.',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFA855F7),
                            width: 2.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
