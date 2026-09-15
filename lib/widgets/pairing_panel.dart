import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/pairing_models.dart';
import '../services/pairing_client.dart';
import '../services/pairing_server.dart';

/// Panel del lado PC: muestra el código de emparejamiento, el código QR y
/// el estado en tiempo real para que un teléfono pueda conectarse.
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
              CircularProgressIndicator(strokeWidth: 2.5),
              SizedBox(height: 16),
              Text(
                'Iniciando sesión de emparejamiento...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (status == PairingStatus.paired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.greenAccent, width: 2),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.greenAccent, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                '¡Dispositivo emparejado con éxito!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Las credenciales se transmitieron cifradas al teléfono.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _startPairing,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Generar otro código'),
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
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Listo para emparejar',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Contenedor QR
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: widget.compact ? 160 : 190,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(0),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'O escribe este código en tu teléfono:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),

            // Chips del código 3 + 3
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CodeGroupChip(code: code.substring(0, 3)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('-',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ),
                _CodeGroupChip(code: code.substring(3)),
              ],
            ),
            const SizedBox(height: 12),

            if (widget.server.hostIp != null)
              Text(
                'IP local: ${widget.server.hostIp}:${widget.server.port}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            const SizedBox(height: 16),

            TextButton.icon(
              onPressed: _stopPairing,
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent.withValues(alpha: 0.85),
              ),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancelar emparejamiento'),
            ),
          ],
        ),
      );
    }

    // Estado inicial / expirado / inactivo
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
            border: Border.all(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.qr_code_2_rounded,
              color: Colors.deepPurpleAccent, size: 30),
        ),
        const SizedBox(height: 14),
        const Text(
          'Emparejar con el teléfono',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Genera un código QR y un pin de 6 dígitos para iniciar sesión al instante en tu celular sin volver a escribir la contraseña.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.35),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _startPairing,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.deepPurpleAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.qr_code_rounded, size: 18),
          label: const Text(
            'Generar código de acceso',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _CodeGroupChip extends StatelessWidget {
  final String code;
  const _CodeGroupChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1638),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.deepPurpleAccent.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 4,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// Panel del lado Teléfono: permite ingresar el código de 6 dígitos
/// generado en el PC o escanear el QR con la cámara.
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
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _statusText;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
      _statusText = 'Buscando tu PC en la red local...';
    });

    try {
      // 1. Descubrir el PC por UDP broadcast
      final pc = await PairingClient.findPcByCode(code);
      if (pc == null) {
        throw Exception(
            'No se encontró el PC con ese código en tu red Wi-Fi.\n'
            'Asegúrate de que ambos estén en la misma red Wi-Fi o escanea el QR.');
      }

      if (!mounted) return;
      setState(() {
        _statusText = 'Conectando con ${pc.host}...';
      });

      // 2. Reclamar credenciales cifradas
      final creds = await PairingClient.claim(
        host: pc.host,
        port: pc.port,
        code: pc.code,
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
        const Text(
          'Código de inicio de sesión',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Genera el código en la app de PC (en el login o en Ajustes) e ingrésalo aquí.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 18),

        // Campo del código
        TextField(
          controller: _codeController,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
            fontFamily: 'monospace',
          ),
          inputFormatters: [
            LengthLimitingTextInputFormatter(7),
            _PairCodeInputFormatter(),
          ],
          decoration: InputDecoration(
            hintText: 'XXX-XXX',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              letterSpacing: 8,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Colors.deepPurpleAccent, width: 1.8),
            ),
          ),
          onSubmitted: (_) => _connectWithCode(),
        ),
        const SizedBox(height: 14),

        // Botón Conectar con código
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _loading ? null : _connectWithCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      if (_statusText != null) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _statusText!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  )
                : const Text(
                    'Vincular con este código',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 14),

        // Divisor O
        Row(
          children: [
            Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.1))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('O',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.1))),
          ],
        ),
        const SizedBox(height: 14),

        // Botón Escanear QR
        OutlinedButton.icon(
          onPressed: _loading ? null : _openQrScanner,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
          label: const Text(
            'Escanear código QR',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
        color: Color(0xFF0F0B1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
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
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white70),
                  onPressed: () => _controller.toggleTorch(),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Apunta con la cámara al código QR que aparece en la pantalla de tu PC.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.deepPurpleAccent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
