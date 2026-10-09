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

part 'pairing_qr_scanner.dart';

part 'pairing_join_panel.dart';

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
            InkWell(
              borderRadius: BorderRadius.circular(8),
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
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
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
