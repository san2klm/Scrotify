import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/jam_models.dart';
import '../services/jam_controller.dart';
import '../services/theme_controller.dart';
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
    final theme = context.read<ThemeController>().active;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
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

class _JamDialogState extends State<JamDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _directHostController = TextEditingController();
  final TextEditingController _directPortController =
      TextEditingController(text: '$kJamHostPort');
  final TextEditingController _directPinController = TextEditingController();
  bool _showDirectForm = false;
  bool _directBusy = false;
  String? _directProbeResult;
  String? _directError;
  bool _isCameraActive = false;
  MobileScannerController? _scannerController;
  JamMode _selectedMode = JamMode.partySpeaker;
  bool _isPublicSession = true;
  bool _allowGuestControls = true;
  bool _allowGuestQueueManage = true;
  int _maxParticipants = 0;

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
    _directHostController.dispose();
    _directPortController.dispose();
    _directPinController.dispose();
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

  /// Muestra el código en su propio diálogo para no reducir la lista ni los
  /// controles de la sesión principal al ampliarlo.
  Future<void> _showQrDialog(String qrUri) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = (MediaQuery.sizeOf(dialogContext).width - 96)
            .clamp(180.0, 300.0)
            .toDouble();
        return Dialog(
          backgroundColor: context.bgApp,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: context.bgElevated, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Escanear código Jam',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(Icons.close_rounded, color: context.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.textPrimary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: qrUri,
                    version: QrVersions.auto,
                    size: size,
                    backgroundColor: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Abrí Scrotify y elegí “Escanear QR” para unirte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Alternativa al radar para routers que aíslan clientes Wi‑Fi o bloquean
  /// broadcast UDP. El anfitrión puede compartir la dirección LAN que aparece
  /// debajo de su PIN.
  Future<void> _showDirectConnectDialog(JamController jam) async {
    final messenger = ScaffoldMessenger.of(context);
    final dangerColor = context.danger;
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '$kJamHostPort');
    final pinController = TextEditingController(text: _pinController.text);
    String? dialogError;
    String? probeResult;
    bool busy = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> runProbe() async {
              final port = int.tryParse(portController.text.trim());
              if (port == null) {
                setDialogState(() {
                  probeResult = 'Puerto inválido.';
                });
                return;
              }
              setDialogState(() {
                busy = true;
                probeResult = 'Probando…';
              });
              final result = await jam.testHostReachable(
                hostController.text.trim(),
                port,
              );
              if (dialogContext.mounted) {
                setDialogState(() {
                  busy = false;
                  probeResult = result;
                });
              }
            }

            Future<void> runConnect() async {
              final port = int.tryParse(portController.text.trim());
              if (port == null) {
                setDialogState(() {
                  dialogError = 'Puerto inválido.';
                });
                return;
              }
              setDialogState(() {
                busy = true;
                dialogError = null;
              });
              final ok = await jam.joinSession(
                host: hostController.text.trim(),
                port: port,
                pin: pinController.text.trim(),
              );
              if (!dialogContext.mounted) return;
              if (ok) {
                Navigator.of(dialogContext).pop();
              } else {
                final reason = jam.lastJoinError ??
                    'No se pudo conectar. Revisá IP, puerto, PIN y que ambos equipos estén en la misma red.';
                setDialogState(() {
                  busy = false;
                  dialogError = reason;
                });
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(reason),
                    backgroundColor: dangerColor,
                  ),
                );
              }
            }

            return AlertDialog(
              backgroundColor: context.bgApp,
              title: Text(
                'Conectar por IP local',
                style: TextStyle(color: context.textPrimary, fontSize: 17),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ingresá la dirección LAN que muestra el anfitrión. La cuenta de Navidrome no conecta: la Jam es directa entre equipos.',
                      style: TextStyle(color: context.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hostController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'IP del anfitrión',
                        hintText: 'Ej. 192.168.1.35',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Puerto'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pinController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'PIN Jam'),
                    ),
                    if (probeResult != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        probeResult!,
                        style: TextStyle(
                          color: probeResult!.startsWith('OK')
                              ? Colors.green
                              : context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (dialogError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        dialogError!,
                        style: TextStyle(color: dangerColor, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      busy ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: busy ? null : runProbe,
                  child: const Text('Probar'),
                ),
                FilledButton(
                  onPressed: busy ? null : runConnect,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conectar'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      hostController.dispose();
      portController.dispose();
      pinController.dispose();
    }
  }

  /// Formulario inline (sin popup) para conexión directa. Evita el problema
  /// del diálogo anidado que en Linux/escritorio a veces no se muestra.
  Widget _buildDirectConnectForm(JamController jam) {
    Future<void> runProbe() async {
      final port = int.tryParse(_directPortController.text.trim());
      if (port == null) {
        setState(() => _directProbeResult = 'Puerto inválido.');
        return;
      }
      setState(() {
        _directBusy = true;
        _directProbeResult = 'Probando…';
      });
      final result = await jam.testHostReachable(
        _directHostController.text.trim(),
        port,
      );
      if (mounted) {
        setState(() {
          _directBusy = false;
          _directProbeResult = result;
        });
      }
    }

    Future<void> runConnect() async {
      final port = int.tryParse(_directPortController.text.trim());
      if (port == null) {
        setState(() => _directError = 'Puerto inválido.');
        return;
      }
      setState(() {
        _directBusy = true;
        _directError = null;
      });
      final ok = await jam.joinSession(
        host: _directHostController.text.trim(),
        port: port,
        pin: _directPinController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _directBusy = false);
      if (!ok) {
        final reason = jam.lastJoinError ?? 'No se pudo conectar.';
        setState(() => _directError = reason);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason), backgroundColor: context.danger),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _directHostController,
            keyboardType: TextInputType.url,
            style: TextStyle(color: context.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'IP del anfitrión',
              hintText: 'Ej. 192.168.1.75',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _directPortController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Puerto',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _directPinController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'PIN Jam',
                    hintText: 'Ej. 3GE68W',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          if (_directProbeResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _directProbeResult!,
              style: TextStyle(
                color: _directProbeResult!.startsWith('OK')
                    ? Colors.green
                    : context.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (_directError != null) ...[
            const SizedBox(height: 8),
            Text(
              _directError!,
              style: TextStyle(color: context.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _directBusy ? null : runProbe,
                  child: const Text('Probar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _directBusy ? null : runConnect,
                  child: _directBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conectar'),
                ),
              ),
            ],
          ),
        ],
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
                        isHost
                            ? 'Tu Sesión Jam'
                            : 'Jam de ${session?.hostName ?? "Anfitrión"}',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
                  onTap: () => _showQrDialog(jam.qrUri!),
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
                    if (isHost && jam.hostIp != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: '${jam.hostIp}:${jam.port}'),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('IP del host copiada al portapapeles'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Text(
                            jam.allHostIpsFormatted != null
                                ? 'LAN: ${jam.allHostIpsFormatted}:${jam.port} (tocá para copiar)'
                                : 'LAN: ${jam.hostIp}:${jam.port}',
                            style: TextStyle(
                              color: context.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
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
                        style:
                            TextStyle(color: context.textMuted, fontSize: 10.5),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Permitir a invitados gestionar la cola',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            value: jam.allowGuestQueueManage,
            activeTrackColor: context.accent,
            onChanged: (val) =>
                jam.updateJamSettings(allowGuestQueueManage: val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Sesión pública',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            subtitle: Text(
              jam.isPublic
                  ? 'Visible en el radar y servidor'
                  : 'Sólo accesible por PIN o QR',
              style: TextStyle(color: context.textMuted, fontSize: 10.5),
            ),
            value: jam.isPublic,
            activeTrackColor: context.accent,
            onChanged: (val) => jam.updateJamSettings(isPublic: val),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Límite de participantes',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
              ),
              DropdownButton<int>(
                value: jam.maxParticipants,
                dropdownColor: context.bgElevated,
                underline: const SizedBox(),
                icon: Icon(Icons.arrow_drop_down, color: context.textMuted),
                style: TextStyle(color: context.textPrimary, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Sin límite')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 5, child: Text('5')),
                  DropdownMenuItem(value: 10, child: Text('10')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    jam.updateJamSettings(maxParticipants: value);
                  }
                },
              ),
            ],
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
              final isMe =
                  p.id == jam.localParticipant?.id || (isHost && p.isHost);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                              style: TextStyle(
                                  color: context.accent, fontSize: 11),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            labelStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
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
                  'Configura quién puede encontrar y controlar la sesión. Las sesiones privadas sólo se unen con PIN o QR.',
                  style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 11.5,
                      height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameController,
                  maxLength: 48,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'Nombre del anfitrión (opcional)',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<JamMode>(
                  initialValue: _selectedMode,
                  dropdownColor: context.bgElevated,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Modo de reproducción',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: JamMode.partySpeaker,
                      child: Text('Altavoz de fiesta (audio sólo en host)'),
                    ),
                    DropdownMenuItem(
                      value: JamMode.synchronizedListening,
                      child: Text('Escucha sincronizada'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => _selectedMode = mode);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Sesión pública',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  subtitle: Text(
                    _isPublicSession
                        ? 'Aparece en el radar de la red y del servidor'
                        : 'Sólo se puede unir con PIN o QR',
                    style: TextStyle(color: context.textMuted, fontSize: 10.5),
                  ),
                  value: _isPublicSession,
                  activeTrackColor: context.accent,
                  onChanged: (value) =>
                      setState(() => _isPublicSession = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Permitir controles de reproducción',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  value: _allowGuestControls,
                  activeTrackColor: context.accent,
                  onChanged: (value) =>
                      setState(() => _allowGuestControls = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Permitir gestionar la cola',
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 12)),
                  value: _allowGuestQueueManage,
                  activeTrackColor: context.accent,
                  onChanged: (value) =>
                      setState(() => _allowGuestQueueManage = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _maxParticipants,
                  dropdownColor: context.bgElevated,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Límite de participantes',
                    labelStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.bgElevated),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Sin límite')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 5, child: Text('5')),
                    DropdownMenuItem(value: 10, child: Text('10')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _maxParticipants = value);
                  },
                ),
                const SizedBox(height: 16),

                // Botón Iniciar
                FilledButton.icon(
                  onPressed: () async {
                    await jam.startHostSession(
                      mode: _selectedMode,
                      isPublic: _isPublicSession,
                      allowGuestControls: _allowGuestControls,
                      allowGuestQueueManage: _allowGuestQueueManage,
                      maxParticipants: _maxParticipants,
                      customName: _nameController.text,
                    );
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
                        content: Text(
                            'No se pudo encontrar la sesión Jam con ese PIN'),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Unirse',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              // En escritorio el diálogo anidado a veces no se muestra;
              // por eso el formulario va inline y el diálogo queda como respaldo.
              setState(() {
                _showDirectForm = !_showDirectForm;
                if (_showDirectForm && _directPinController.text.isEmpty) {
                  _directPinController.text = _pinController.text;
                }
              });
            },
            icon: const Icon(Icons.lan_rounded, size: 16),
            label: const Text('Conectar por IP local'),
            style: TextButton.styleFrom(
              foregroundColor: context.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        if (_showDirectForm) _buildDirectConnectForm(jam),
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
                          color: context.textPrimary.withValues(alpha: 0.15),
                          size: 40),
                      const SizedBox(height: 8),
                      Text(
                        jam.isScanningRadar
                            ? 'Buscando sesiones en la red y servidor...'
                            : 'No se encontraron sesiones Jam en la red o servidor',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 12),
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
                                    content:
                                        Text('Error al conectarse a la sesión'),
                                    backgroundColor: context.danger,
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  context.accent.withValues(alpha: 0.2),
                              foregroundColor: context.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Entrar',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold)),
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
              style: TextStyle(
                  color: context.textPrimary, fontWeight: FontWeight.bold),
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
                          content:
                              Text('Código QR inválido o sesión inaccesible'),
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
