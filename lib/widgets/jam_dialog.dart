import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/jam_models.dart';
import '../services/jam_controller.dart';
import 'cover_art.dart';
import '../utils/app_colors.dart';

/// Modal / Diálogo interactivo para gestionar o unirse a una sesión Jam.
class JamDialog extends StatefulWidget {
  const JamDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const JamDialog(),
    );
  }

  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: context.bgElevated, width: 1.2),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: const FractionallySizedBox(
          heightFactor: 0.88,
          child: JamDialog(),
        ),
      ),
    );
  }

  @override
  State<JamDialog> createState() => _JamDialogState();
}

class _JamDialogState extends State<JamDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _showQrLarge = false;
  bool _isCameraActive = false;
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final jam = context.read<JamController>();
      if (!jam.inJam) {
        jam.scanRadar();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pinController.dispose();
    _nameController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamController>();
    final isDesktop = MediaQuery.of(context).size.width >= 700;

    return Dialog(
      backgroundColor: context.bgApp,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40 : 16,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: context.bgElevated, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 540 : 420,
          maxHeight: 680,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: jam.inJam ? _buildActiveJamView(jam) : _buildIdleJamView(jam),
        ),
      ),
    );
  }

  // ===========================================================================
  // VISTA: SESIÓN ACTIVA (HOST O GUEST)
  // ===========================================================================
  Widget _buildActiveJamView(JamController jam) {
    final session = jam.session;
    final isHost = jam.isHost;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.speaker_group_rounded,
                  color: context.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isHost ? 'Tu Sesión Jam' : 'Jam de ${session?.hostName ?? "Anfitrión"}',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isHost
                              ? context.accent.withValues(alpha: 0.2)
                              : context.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isHost ? 'ANFITRIÓN' : 'INVITADO',
                          style: TextStyle(
                            color: isHost ? context.accent : context.accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${jam.participants.length} participante${jam.participants.length == 1 ? "" : "s"} conectado${jam.participants.length == 1 ? "" : "s"}',
                    style: TextStyle(color: context.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: context.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tarjeta de Código PIN y QR
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.bgElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.bgElevated),
          ),
          child: Row(
            children: [
              // Botón QR
              if (jam.qrUri != null)
                GestureDetector(
                  onTap: () => setState(() => _showQrLarge = !_showQrLarge),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.textPrimary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: jam.qrUri!,
                      version: QrVersions.auto,
                      size: 46,
                      backgroundColor: context.textPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CÓDIGO DE ACCESO',
                      style: TextStyle(
                        color: context.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      jam.currentCodeFormatted ?? '---',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar código',
                icon: Icon(Icons.copy_rounded, color: context.accent, size: 20),
                onPressed: () {
                  final code = session?.pinCode ?? jam.currentCodeFormatted;
                  if (code != null) {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Código Jam copiado al portapapeles'),
                        duration: Duration(seconds: 2),
                        backgroundColor: context.bgElevated,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),

        // QR Desplegable Grande si se tocó el icono
        if (_showQrLarge && jam.qrUri != null) ...[
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.textPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: jam.qrUri!,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: context.textPrimary,
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Selector de Modo (Solo configurable por el Host)
        if (isHost) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.bgElevated),
            ),
            child: Row(
              children: [
                Icon(
                  jam.mode == JamMode.partySpeaker
                      ? Icons.speaker_rounded
                      : Icons.headphones_rounded,
                  color: context.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jam.mode == JamMode.partySpeaker
                            ? 'Modo Altavoz de Fiesta'
                            : 'Modo Escucha Sincronizada',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        jam.mode == JamMode.partySpeaker
                            ? 'El audio suena sólo en el Host'
                            : 'El audio suena en todos los dispositivos',
                        style: TextStyle(color: context.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                DropdownButton<JamMode>(
                  value: jam.mode,
                  dropdownColor: context.bgElevated,
                  underline: const SizedBox(),
                  icon: Icon(Icons.arrow_drop_down, color: context.textMuted),
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  items: const [
                    DropdownMenuItem(
                      value: JamMode.partySpeaker,
                      child: Text('Altavoz'),
                    ),
                    DropdownMenuItem(
                      value: JamMode.synchronizedListening,
                      child: Text('Sincronizado'),
                    ),
                  ],
                  onChanged: (newMode) {
                    if (newMode != null) {
                      jam.updateJamSettings(mode: newMode);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Permisos de invitados
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Permitir a invitados controlar reproducción',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            value: jam.allowGuestControls,
            activeTrackColor: context.accent,
            onChanged: (val) => jam.updateJamSettings(allowGuestControls: val),
          ),
        ],

        const SizedBox(height: 8),

        // Lista de Participantes
        Text(
          'PARTICIPANTES EN LA SESIÓN',
          style: TextStyle(
            color: context.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: jam.participants.length,
            itemBuilder: (ctx, i) {
              final p = jam.participants[i];
              final isMe = p.id == jam.localParticipant?.id ||
                  (isHost && p.isHost);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(p.avatarColorValue),
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(Tú)',
                              style: TextStyle(color: context.accent, fontSize: 11),
                            ),
                          ],
                          if (p.isHost) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.star_rounded,
                                color: context.warning, size: 14),
                          ],
                        ],
                      ),
                    ),
                    if (isHost && !p.isHost)
                      IconButton(
                        tooltip: 'Expulsar participante',
                        icon: Icon(Icons.remove_circle_outline,
                            color: context.danger, size: 18),
                        onPressed: () => jam.kickParticipant(p.id),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // Botón de Salir o Terminar
        FilledButton.tonalIcon(
          onPressed: () async {
            await jam.leaveOrEndSession();
            if (mounted) Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: isHost
                ? context.danger.withValues(alpha: 0.18)
                : context.bgElevated,
            foregroundColor: isHost ? context.danger : context.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(
            isHost ? Icons.power_settings_new_rounded : Icons.logout_rounded,
            size: 18,
          ),
          label: Text(
            isHost ? 'Finalizar Sesión Jam' : 'Salir del Jam',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // VISTA: SIN SESIÓN ACTIVA (CREAR O UNIRSE)
  // ===========================================================================
  Widget _buildIdleJamView(JamController jam) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.speaker_group_rounded,
                  color: context.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scrotify Jam',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Escucha en grupo y comparte la cola en tiempo real',
                    style: TextStyle(color: context.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: context.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Pestañas Crear / Unirse
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: context.bgElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: context.accent2,
              borderRadius: BorderRadius.circular(10),
            ),
            dividerColor: Colors.transparent,
            labelColor: context.textPrimary,
            unselectedLabelColor: context.textMuted,
            labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Iniciar Jam'),
              Tab(text: 'Unirse a Jam'),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Flexible(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStartJamTab(jam),
              _buildJoinJamTab(jam),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña 1: Iniciar Sesión Jam
  // ---------------------------------------------------------------------------
  Widget _buildStartJamTab(JamController jam) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.bgElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.bgElevated),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_tethering_rounded,
                        color: context.accent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Conexión Local y en Servidor',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Inicia una sesión colaborativa. Tus amigos en la misma red Wi-Fi o conectados a tu servidor Navidrome podrán detectarte por radar, ver tu sesión en vivo, escanear tu QR o ingresar tu PIN.',
                  style: TextStyle(color: context.textSecondary, fontSize: 11.5, height: 1.4),
                ),
                const SizedBox(height: 16),

                // Botón Iniciar
                FilledButton.icon(
                  onPressed: () async {
                    await jam.startHostSession();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accent2,
                    foregroundColor: context.onAccent2,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text(
                    'Iniciar Sesión Jam en este equipo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña 2: Unirse a un Jam (Radar / PIN / QR)
  // ---------------------------------------------------------------------------
  Widget _buildJoinJamTab(JamController jam) {
    if (_isCameraActive) {
      return _buildCameraScanner(jam);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ingreso Rápido por PIN
        Row(
          children: [
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.bgElevated),
                ),
                child: TextField(
                  controller: _pinController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 14,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: 'PIN (ej: AB3-4EF)',
                    hintStyle: TextStyle(
                      color: context.textMuted,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Escanear QR con cámara',
              style: IconButton.styleFrom(
                backgroundColor: context.bgElevated,
                foregroundColor: context.accent,
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              onPressed: () {
                setState(() => _isCameraActive = true);
              },
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final pin = _pinController.text.trim();
                if (pin.length >= 6) {
                  final ok = await jam.joinByPin(pin);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('No se pudo encontrar la sesión Jam con ese PIN'),
                        backgroundColor: context.danger,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: context.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Unirse', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Radar en Red Local y Servidor
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SESIONES ACTIVAS (RADAR & SERVIDOR)',
              style: TextStyle(
                color: context.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: jam.isScanningRadar
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.accent),
                    )
                  : Icon(Icons.refresh_rounded,
                      color: context.accent, size: 18),
              onPressed: jam.isScanningRadar ? null : jam.scanRadar,
            ),
          ],
        ),
        const SizedBox(height: 6),

        Expanded(
          child: jam.discoveredSessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar_rounded,
                          color: context.textPrimary.withValues(alpha: 0.15), size: 40),
                      const SizedBox(height: 8),
                      Text(
                        jam.isScanningRadar
                            ? 'Buscando sesiones en la red y servidor...'
                            : 'No se encontraron sesiones Jam en la red o servidor',
                        style: TextStyle(color: context.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: jam.discoveredSessions.length,
                  itemBuilder: (ctx, i) {
                    final d = jam.discoveredSessions[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.bgElevated),
                      ),
                      child: Row(
                        children: [
                          CoverArt(
                            url: d.albumArtUrl,
                            width: 40,
                            height: 40,
                            borderRadius: 8,
                            fallbackIcon: Icons.speaker_group,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.sessionTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Host: ${d.hostName} · ${d.participantCount} oyente${d.participantCount == 1 ? "" : "s"}',
                                  style: TextStyle(
                                    color: context.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () async {
                              final ok = await jam.joinDiscovered(d);
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error al conectarse a la sesión'),
                                    backgroundColor: context.danger,
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: context.accent.withValues(alpha: 0.2),
                              foregroundColor: context.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Entrar',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Lector de Cámara para Código QR
  // ---------------------------------------------------------------------------
  Widget _buildCameraScanner(JamController jam) {
    _scannerController ??= MobileScannerController();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Escanea el QR del Anfitrión',
              style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: Icon(Icons.close, color: context.textSecondary),
              onPressed: () {
                _scannerController?.stop();
                setState(() => _isCameraActive = false);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MobileScanner(
              controller: _scannerController,
              onDetect: (capture) async {
                final barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final raw = barcode.rawValue;
                  if (raw != null && raw.startsWith('scrotify://jam')) {
                    _scannerController?.stop();
                    setState(() => _isCameraActive = false);
                    final ok = await jam.joinByQr(raw);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Código QR inválido o sesión inaccesible'),
                          backgroundColor: context.danger,
                        ),
                      );
                    }
                    break;
                  }
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
