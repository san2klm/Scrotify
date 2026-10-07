import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/pairing_models.dart';
import '../services/pairing_client.dart';
import '../services/pairing_server.dart';
import '../utils/app_colors.dart';
import '../utils/tv_mode.dart';
import 'material_surface.dart';
import 'pairing_qr_code.dart';

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
      if (!mounted) {
        _ticker?.cancel();
        return;
      }
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
      if (!mounted) return;
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
        backgroundColor: context.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: context.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              '$label copiado al portapapeles',
              style: TextStyle(color: context.textPrimary, fontSize: 12.5),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2, color: context.accent),
              const SizedBox(height: 14),
              Text(
                'Iniciando sesión segura...',
                style: TextStyle(color: context.textSecondary, fontSize: 12.5),
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
                  color: context.accent.withValues(alpha: 0.12),
                  border: Border.all(color: context.accent, width: 1.8),
                ),
                child:
                    Icon(Icons.check_rounded, color: context.accent, size: 32),
              ),
              const SizedBox(height: 14),
              Text(
                '¡Teléfono emparejado!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Las credenciales se transmitieron cifradas con éxito.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _startPairing,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textSecondary,
                  side: BorderSide(color: context.bgElevated),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Generar otro código',
                    style: TextStyle(fontSize: 12.5)),
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
      final timeStr = '$minutes:${remSec.toString().padLeft(2, '0')}';

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
                  decoration: BoxDecoration(
                    color: context.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Listo para vincular (${widget.server.deviceName})',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                MaterialSurface(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: context.bgCard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 13, color: context.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: context.textPrimary,
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
                    color: context.accent.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: PairingQrCode(
                data: qrData,
                size: widget.compact ? 150 : 175,
              ),
            ),
            const SizedBox(height: 14),

            Text(
              'QR temporal por relay gratuito de ntfy.sh',
              style: TextStyle(color: context.textSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 3),
            Text(
              'Las credenciales viajan cifradas de punta a punta.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textMuted, fontSize: 10.5),
            ),
            const SizedBox(height: 8),

            // Chips del código 3 + 3 con opción de copiar
            GestureDetector(
              onTap: () => _copyToClipboard(code, 'Código $code'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AmoledCodeGroupChip(code: code.substring(0, 3)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text('-',
                        style: TextStyle(
                            color: context.textMuted,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ),
                  _AmoledCodeGroupChip(code: code.substring(3)),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Copiar código',
                    icon: Icon(Icons.copy_rounded,
                        size: 16, color: context.textMuted),
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
                    onTap: () => _copyToClipboard('$ip:${widget.server.port}',
                        'IP $ip:${widget.server.port}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.bgApp,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.bgElevated),
                      ),
                      child: Text(
                        'IP: $ip:${widget.server.port}',
                        style: TextStyle(
                          color: context.textMuted,
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
                    foregroundColor: context.textSecondary,
                  ),
                  icon: const Icon(Icons.refresh, size: 14),
                  label:
                      const Text('Regenerar', style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _stopPairing,
                  style: TextButton.styleFrom(
                    foregroundColor: context.danger.withValues(alpha: 0.8),
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label:
                      const Text('Cancelar', style: TextStyle(fontSize: 11.5)),
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
            color: context.bgElevated,
            border: Border.all(color: context.accent.withValues(alpha: 0.3)),
          ),
          child: Icon(Icons.qr_code_2_rounded, color: context.accent, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          'Emparejar con el teléfono',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Genera un código QR y un pin seguro para que tu teléfono pueda conectarse automáticamente sin escribir la contraseña.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textMuted, fontSize: 12, height: 1.3),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.danger.withValues(alpha: 0.25)),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: context.danger, fontSize: 11.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _startPairing,
          style: FilledButton.styleFrom(
            backgroundColor: context.accent2,
            foregroundColor: context.onAccent2,
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
        color: context.bgApp,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.accent,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: context.accent.withValues(alpha: 0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        code,
        style: TextStyle(
          color: context.textPrimary,
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
  final bool autoOpenScanner;

  const PairingJoinPanel({
    super.key,
    required this.onCredentialsReceived,
    this.autoOpenScanner = false,
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
    if (widget.autoOpenScanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) {
          unawaited(_openQrScanner());
        }
      });
    }
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
        backgroundColor: context.bgApp,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.bgElevated),
        ),
        title: Row(
          children: [
            Icon(Icons.laptop_mac_rounded, color: context.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Código de $deviceName',
                style: TextStyle(color: context.textPrimary, fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa el código que aparece en la pantalla de esa computadora:',
              style: TextStyle(color: context.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.textPrimary,
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
                    color: context.textPrimary.withValues(alpha: 0.2),
                    letterSpacing: 4),
                filled: true,
                fillColor: context.bgApp,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.bgElevated),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.accent, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accent2,
              foregroundColor: context.onAccent2,
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
        throw Exception('No se encontró el PC con ese código en tu red Wi-Fi.\n'
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
            color: context.bgApp,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.bgElevated),
          ),
          child: Row(
            children: [
              _buildSubTab(0, Icons.wifi_tethering_rounded, 'Radar Wi-Fi'),
              _buildSubTab(1, Icons.pin_outlined, 'Código PIN'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_activeTab == 0) _buildRadarSection() else _buildCodeSection(),

        const SizedBox(height: 14),

        // Botón Escanear QR (una tele no tiene cámara)
        if (!TvMode.isTv)
          OutlinedButton.icon(
            onPressed: _loading ? null : _openQrScanner,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.textPrimary,
              side: BorderSide(color: context.bgElevated),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(Icons.qr_code_scanner_rounded,
                size: 19, color: context.accent),
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
              foregroundColor: context.textMuted,
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
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: context.accent),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _statusText!,
                  style: TextStyle(color: context.accent, fontSize: 12),
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
              color: context.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.danger.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: context.danger, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: context.danger, fontSize: 11.5),
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
            color: isSelected ? context.bgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: context.accent.withValues(alpha: 0.4), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: isSelected ? context.accent : context.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? context.textPrimary : context.textMuted,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
            Text(
              'Dispositivos en tu red Wi-Fi',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Volver a escanear',
              icon: _scanningLan
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.8, color: context.accent),
                    )
                  : Icon(Icons.refresh, size: 17, color: context.textMuted),
              onPressed: _scanningLan ? null : _scanLanDevices,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Computadoras con Scrotify listas para emparejar:',
          style: TextStyle(color: context.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 10),
        if (_nearbyDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.bgApp,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.bgElevated),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    _scanningLan
                        ? Icons.radar_rounded
                        : Icons.devices_other_rounded,
                    size: 28,
                    color: context.themeBorder,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scanningLan
                        ? 'Buscando computadoras en la red...'
                        : 'No se encontraron computadoras emitiendo',
                    style: TextStyle(color: context.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca "Generar código" en tu PC o usa la pestaña "Código PIN".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textMuted, fontSize: 10.5),
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
                color: context.bgApp,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.accent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.bgElevated,
                      border: Border.all(
                          color: context.accent.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.laptop_rounded,
                        color: context.accent, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pc.deviceName,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          '${pc.host}:${pc.port}',
                          style: TextStyle(
                            color: context.textMuted,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _loading ? null : () => _connectToDiscoveredDevice(pc),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.accent2,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Vincular',
                        style: TextStyle(fontSize: 11.5)),
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
        Text(
          'Código de inicio de sesión',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Ingresa el código que aparece en tu computadora:',
          style: TextStyle(color: context.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.textPrimary,
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
              color: context.textPrimary.withValues(alpha: 0.15),
              letterSpacing: 6,
            ),
            filled: true,
            fillColor: context.bgApp,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.bgElevated),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.bgElevated),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.accent, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _connectWithCode(),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _loading ? null : _connectWithCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.accent2,
            foregroundColor: context.onAccent2,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        color: context.bgApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.bgElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Conexión directa por dirección IP',
            style: TextStyle(
              color: context.textPrimary,
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
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'IP del PC',
                    labelStyle:
                        TextStyle(color: context.textMuted, fontSize: 11),
                    hintText: '192.168.1.50',
                    hintStyle: TextStyle(
                        color: context.textPrimary.withValues(alpha: 0.2),
                        fontSize: 11),
                    filled: true,
                    fillColor: context.bgApp,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.bgElevated),
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
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Puerto',
                    labelStyle:
                        TextStyle(color: context.textMuted, fontSize: 11),
                    hintText: '54321',
                    hintStyle: TextStyle(
                        color: context.textPrimary.withValues(alpha: 0.2),
                        fontSize: 11),
                    filled: true,
                    fillColor: context.bgApp,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.bgElevated),
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
            style: TextStyle(
                color: context.textPrimary, fontSize: 12, letterSpacing: 2),
            inputFormatters: [
              LengthLimitingTextInputFormatter(7),
              _PairCodeInputFormatter(),
            ],
            decoration: InputDecoration(
              labelText: 'Código de 6 letras',
              labelStyle: TextStyle(color: context.textMuted, fontSize: 11),
              hintText: 'ABC-DEF',
              hintStyle: TextStyle(
                  color: context.textPrimary.withValues(alpha: 0.2),
                  fontSize: 11),
              filled: true,
              fillColor: context.bgApp,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.bgElevated),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _connectManualIp,
            style: FilledButton.styleFrom(
              backgroundColor: context.accent2,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.link_rounded, size: 15),
            label:
                const Text('Conectar por IP', style: TextStyle(fontSize: 12)),
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

class _QrScannerSheetState extends State<QrScannerSheet>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _handled = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startScanner());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startScanner());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_controller.stop());
        return;
    }
  }

  Future<void> _startScanner() async {
    if (!mounted) return;
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) {
        setState(() {
          _startError = 'No se pudo iniciar la cámara en este dispositivo.';
        });
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } on MobileScannerException {
      // La cámara todavía no está lista o el dispositivo no tiene linterna.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.startsWith('scrotify://pair')) {
        _handled = true;
        unawaited(_controller.stop());
        Navigator.of(context).pop(value);
        break;
      }
    }
  }

  String _cameraErrorMessage(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Permite el acceso a la cámara para escanear el código QR.';
    }
    if (error.errorCode == MobileScannerErrorCode.unsupported) {
      return 'Este dispositivo no tiene una cámara compatible.';
    }
    return 'No se pudo iniciar la cámara. Cierra e intenta abrir el escáner otra vez.';
  }

  Widget _buildCameraProblem(BuildContext context, String message) {
    return ColoredBox(
      color: context.bgDeep,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, color: context.warning, size: 34),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar escáner'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPlaceholder(BuildContext context) {
    return ColoredBox(
      color: context.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: context.accent, strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              'Solicitando acceso a la cámara...',
              style: TextStyle(color: context.textMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: context.bgApp,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: context.bgElevated, width: 1.2)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.themeBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Text(
                  'Escanear código QR',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder: (context, state, _) => IconButton(
                    tooltip: 'Linterna',
                    icon: Icon(
                      state.torchState == TorchState.on
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: context.textSecondary,
                      size: 20,
                    ),
                    onPressed: state.isRunning &&
                            state.torchState != TorchState.unavailable
                        ? _toggleTorch
                        : null,
                  ),
                ),
                IconButton(
                  icon:
                      Icon(Icons.close, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Apunta con la cámara al código QR que aparece en la pantalla de tu PC.',
              style: TextStyle(color: context.textMuted, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _startError == null
                    ? MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        placeholderBuilder: (context, _) =>
                            _buildCameraPlaceholder(context),
                        errorBuilder: (context, error, _) =>
                            _buildCameraProblem(
                                context, _cameraErrorMessage(error)),
                        overlayBuilder: (context, _) => Center(
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: context.accent,
                                width: 2.2,
                              ),
                            ),
                          ),
                        ),
                      )
                    : _buildCameraProblem(context, _startError!),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
