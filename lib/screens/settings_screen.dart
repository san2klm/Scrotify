import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/pairing_server.dart';
import '../services/playlist_importer.dart';
import '../services/secure_storage.dart';
import '../services/settings_controller.dart';
import '../widgets/pairing_panel.dart';
import '../widgets/theme_grid.dart';
import 'equalizer_screen.dart';
import 'login_screen.dart';
import 'server_profiles_screen.dart';
import 'stats_screen.dart';
import '../utils/app_colors.dart';

/// Pantalla de ajustes. Centraliza las preferencias del usuario: calidad de
/// audio según la red, portadas, volumen y cuenta.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();

    return Scaffold(
      backgroundColor: context.bgApp,
      appBar: AppBar(
        backgroundColor: context.bgApp,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: const Text('Ajustes'),
      ),
      body: Consumer<SettingsController>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---------------------------------------------------------------
              // Calidad de audio
              // ---------------------------------------------------------------
              _sectionTitle('Calidad de audio'),
              _card(
                children: [
                  _switchTile(
                    title: 'Detectar red automáticamente',
                    subtitle:
                        'Usa una calidad distinta según estés en casa o en datos móviles',
                    value: settings.autoSwitch,
                    onChanged: settings.setAutoSwitch,
                  ),
                  if (settings.autoSwitch) ...[
                    _networkBadge(settings.networkLabel, settings.isMobileData),
                    const SizedBox(height: 12),
                    _qualitySelector(
                      title: 'En casa (WiFi / conexión fija)',
                      current: settings.wifiQuality,
                      onChanged: settings.setWifiQuality,
                    ),
                    const SizedBox(height: 12),
                    _qualitySelector(
                      title: 'En datos móviles',
                      current: settings.mobileQuality,
                      onChanged: settings.setMobileQuality,
                    ),
                  ] else
                    const SizedBox(height: 8),
                  if (!settings.autoSwitch) ...[
                    _qualitySelector(
                      title: 'Calidad de audio',
                      current: settings.wifiQuality,
                      onChanged: settings.setWifiQuality,
                    ),
                  ],
                  const SizedBox(height: 12),
                  const _InfoText(
                    'Sin pérdida transmite el archivo original (FLAC). '
                    'Las demás opciones se transcodifican a MP3 en el servidor, '
                    'ahorrando datos móviles.',
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // Reproducción
              // ---------------------------------------------------------------
              _sectionTitle('Reproducción'),
              _card(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Volumen inicial',
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 14)),
                    subtitle: Slider(
                      value: settings.initialVolume,
                      activeColor: context.accent,
                      inactiveColor: context.themeBorder,
                      onChanged: settings.setInitialVolume,
                    ),
                    trailing: Text(
                      '${(settings.initialVolume * 100).round()}%',
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 13),
                    ),
                  ),
                  _switchTile(
                    title: 'Reproducción sin cortes',
                    subtitle:
                        'Evita silencios entre canciones (depende del backend)',
                    value: settings.gapless,
                    onChanged: settings.setGapless,
                  ),
                  const SizedBox(height: 8),
                  _switchTile(
                    title: 'Crossfade',
                    subtitle:
                        'Funde el final de una canción con el inicio de la siguiente',
                    value: settings.crossfade > Duration.zero,
                    onChanged: (enabled) => settings.setCrossfade(
                      enabled ? const Duration(seconds: 5) : Duration.zero,
                    ),
                  ),
                  if (settings.crossfade > Duration.zero) ...[
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Duración del fundido',
                          style: TextStyle(
                              color: context.textPrimary, fontSize: 14)),
                      subtitle: Slider(
                        value: settings.crossfade.inSeconds
                            .clamp(1, 10)
                            .toDouble(),
                        min: 1,
                        max: 10,
                        activeColor: context.accent,
                        inactiveColor: context.themeBorder,
                        onChanged: (v) =>
                            settings.setCrossfade(Duration(seconds: v.round())),
                      ),
                      trailing: Text(
                        '${settings.crossfade.inSeconds} s',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _choiceTiles<ReplayGainMode>(
                    title: 'Normalización de volumen (ReplayGain)',
                    value: settings.replayGainMode,
                    options: const [
                      (
                        value: ReplayGainMode.off,
                        label: 'Desactivado',
                        subtitle: 'Sin normalización de volumen',
                      ),
                      (
                        value: ReplayGainMode.track,
                        label: 'Pista (Track)',
                        subtitle: 'Normaliza cada pista individualmente',
                      ),
                      (
                        value: ReplayGainMode.album,
                        label: 'Álbum (Album)',
                        subtitle: 'Preserva la dinámica del álbum completo',
                      ),
                    ],
                    onChanged: settings.setReplayGainMode,
                  ),
                  if (settings.replayGainMode != ReplayGainMode.off) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Preamplificador (Preamp)',
                        style:
                            TextStyle(color: context.textPrimary, fontSize: 14),
                      ),
                      subtitle: Slider(
                        value: settings.replayGainPreamp.clamp(-12.0, 12.0),
                        min: -12.0,
                        max: 12.0,
                        divisions: 48,
                        activeColor: context.accent,
                        inactiveColor: context.themeBorder,
                        onChanged: settings.setReplayGainPreamp,
                      ),
                      trailing: Text(
                        '${settings.replayGainPreamp > 0 ? '+' : ''}${settings.replayGainPreamp.toStringAsFixed(1)} dB',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 13),
                      ),
                    ),
                    _switchTile(
                      title: 'Evitar distorsión (Prevent clipping)',
                      subtitle:
                          'Atenúa la ganancia si el pico de la pista superaría 0 dBFS',
                      value: settings.replayGainPreventClipping,
                      onChanged: settings.setReplayGainPreventClipping,
                    ),
                    const SizedBox(height: 4),
                    const _InfoText(
                      'ReplayGain opera únicamente por atenuación (≤ 0 dB) en este '
                      'reproductor para evitar distorsión digital.',
                    ),
                  ],
                  const SizedBox(height: 8),
                  _switchTile(
                    title: 'Eliminar silencios',
                    subtitle:
                        'Recorta silencios al inicio y final de las canciones usando análisis de waveform',
                    value: settings.silenceRemovalEnabled,
                    onChanged: settings.setSilenceRemovalEnabled,
                  ),
                  _switchTile(
                    title: 'Mezcla inteligente',
                    subtitle:
                        'Evita repetir el mismo artista seguido en modo aleatorio',
                    value: settings.isSmartMixEnabled,
                    onChanged: settings.setSmartMixEnabled,
                  ),
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.equalizer_rounded,
                        color: context.textSecondary),
                    title: Text('Ecualizador',
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      'Ajustes de 10 bandas y presets',
                      style: TextStyle(color: context.textMuted, fontSize: 12),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: context.textMuted),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EqualizerScreen()),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.insights_rounded,
                        color: context.textSecondary),
                    title: Text('Estadísticas de escucha',
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      'Tiempo reproducido, canciones y artistas más escuchados',
                      style: TextStyle(color: context.textMuted, fontSize: 12),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: context.textMuted),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StatsScreen()),
                      );
                    },
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // Interfaz
              // ---------------------------------------------------------------
              _sectionTitle('Interfaz'),
              _card(
                children: [
                  _choiceTiles<int>(
                    title: 'Resolución de portadas',
                    value: settings.coverArtSize,
                    options: const [
                      (
                        value: 600,
                        label: 'Alta',
                        subtitle: 'Portadas nítidas · más datos'
                      ),
                      (value: 300, label: 'Baja', subtitle: 'Ahorra datos'),
                    ],
                    onChanged: settings.setCoverArtSize,
                  ),
                  const SizedBox(height: 8),
                  const _InfoText(
                    'La nueva resolución se aplica al volver a cargar el contenido.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Temas (.zip estilo Psysonic, carpeta configurable).
              const ThemesSection(),

              // ---------------------------------------------------------------
              // Playlists (importar)
              // ---------------------------------------------------------------
              _sectionTitle('Playlists'),
              _card(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.upload_file, color: context.textSecondary),
                    title: Text('Importar playlist',
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      'Desde CSV, M3U/M3U8, PLS o TXT',
                      style: TextStyle(color: context.textMuted, fontSize: 12),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: context.textMuted),
                    onTap: _importing ? null : _pickAndImport,
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // Playlists (gestionar/borrar)
              // ---------------------------------------------------------------
              _sectionTitle('Mis playlists'),
              const _PlaylistsManager(),

              // ---------------------------------------------------------------
              // Cuenta y Perfiles
              // ---------------------------------------------------------------
              _sectionTitle('Cuenta y Perfiles'),
              _card(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.switch_account_outlined,
                        color: context.textSecondary),
                    title: Text('Gestionar perfiles de servidor',
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 14)),
                    subtitle: Text(
                      nav.connected
                          ? '${nav.username} en ${nav.serverUrl}'
                          : 'Sin conexión',
                      style: TextStyle(color: context.textMuted, fontSize: 12),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: context.textMuted),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ServerProfilesScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.danger,
                        side: BorderSide(color: context.danger),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Cerrar sesión plana'),
                      onPressed: () => _confirmLogout(context),
                    ),
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // Vincular con el teléfono
              // ---------------------------------------------------------------
              if (nav.connected) ...[
                _sectionTitle('Vincular teléfono'),
                _card(
                  children: [
                    PairingSharePanel(
                      compact: true,
                      server: context.read<PairingServer>(),
                      onGetCredentials: () async => nav.currentCredentials,
                    ),
                  ],
                ),
              ],

              // ---------------------------------------------------------------
              // Acerca de
              // ---------------------------------------------------------------
              _sectionTitle('Acerca de'),
              _card(
                children: const [
                  _InfoText(
                    'Scrotify — cliente de Navidrome (Subsonic API)\n'
                    'v1.0.0',
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Importar playlist
  // ---------------------------------------------------------------------------

  Future<void> _pickAndImport() async {
    const xType = XTypeGroup(
      label: 'Playlists',
      extensions: ['csv', 'm3u', 'm3u8', 'pls', 'txt'],
    );

    final xFile = await openFile(acceptedTypeGroups: [xType]);
    if (xFile == null) return;

    final bytes = await xFile.readAsBytes();
    // UTF-8 real (y sin BOM): String.fromCharCodes rompía acentos y eñes.
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\uFEFF')) content = content.substring(1);

    final parsed = PlaylistImporter.parseFile(xFile.name, content);
    if (parsed.tracks.isEmpty) {
      if (!mounted) return;
      _showError('El archivo no contiene canciones reconocibles.');
      return;
    }

    final defaultName = parsed.suggestedName ??
        xFile.name.split('.').first.replaceAll(RegExp(r'[_\-]+'), ' ').trim();

    if (!mounted) return;
    final nav = context.read<NavidromeService>();

    // Playlists existentes para poder agregar a una de ellas.
    var existing = <Playlist>[];
    try {
      existing = await nav.getPlaylists();
    } catch (_) {}
    if (!mounted) return;

    final target = await showDialog<_ImportTarget>(
      context: context,
      builder: (_) => _ImportTargetDialog(
        trackCount: parsed.tracks.length,
        defaultName: defaultName,
        existing: existing,
      ),
    );
    if (target == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final outcome = await showDialog<_ImportOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ImportProgressDialog(
          tracks: parsed.tracks,
          nav: nav,
          target: target,
        ),
      );

      if (!mounted || outcome == null || outcome.cancelled) return;
      if (outcome.error != null) {
        _showError(outcome.error!);
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (_) => _ImportResultDialog(result: outcome.result!),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('Error al importar',
            style: TextStyle(color: context.textPrimary)),
        content: Text(msg, style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: context.danger)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final nav = context.read<NavidromeService>();
    final server = context.read<PairingServer>();
    final navigator = Navigator.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('¿Cerrar sesión?',
            style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Se eliminarán las credenciales guardadas en este dispositivo y volverás a la pantalla de inicio de sesión.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                Text('Cerrar sesión', style: TextStyle(color: context.danger)),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      await server.stop();
      await SecureStorage.clearCredentials();
      nav.disconnect();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers de UI
  // ---------------------------------------------------------------------------

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title,
          style: TextStyle(color: context.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(color: context.textMuted, fontSize: 12)),
      activeTrackColor: context.accent,
      activeThumbColor: context.textPrimary,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _networkBadge(String label, bool mobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.bgElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mobile ? context.warning : context.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Red actual: $label',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _qualitySelector({
    required String title,
    required AudioQuality current,
    required ValueChanged<AudioQuality> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: context.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.bgElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final q in AudioQuality.values)
                InkWell(
                  onTap: () => onChanged(q),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          q == current
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: q == current
                              ? context.accent
                              : context.themeBorder,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.label,
                                  style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 14)),
                              Text(q.subtitle,
                                  style: TextStyle(
                                      color: context.textMuted, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (q == AudioQuality.lossless)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'FLAC',
                              style: TextStyle(
                                color: context.accent.withValues(alpha: 0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _choiceTiles<T>({
    required String title,
    required T value,
    required List<({T value, String label, String subtitle})> options,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: context.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.bgElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final opt in options)
                InkWell(
                  onTap: () => onChanged(opt.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          opt.value == value
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: opt.value == value
                              ? context.accent
                              : context.themeBorder,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opt.label,
                                  style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 14)),
                              Text(opt.subtitle,
                                  style: TextStyle(
                                      color: context.textMuted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Destino elegido para la importación: playlist nueva o ya existente.
class _ImportTarget {
  final String? newName;
  final Playlist? existing;

  const _ImportTarget.create(String this.newName) : existing = null;
  const _ImportTarget.existing(Playlist this.existing) : newName = null;
}

class _ImportOutcome {
  final PlaylistImportResult? result;
  final String? error;
  final bool cancelled;

  const _ImportOutcome.done(PlaylistImportResult this.result)
      : error = null,
        cancelled = false;
  const _ImportOutcome.failed(String this.error)
      : result = null,
        cancelled = false;
  const _ImportOutcome.cancelled()
      : result = null,
        error = null,
        cancelled = true;
}

class _ImportTargetDialog extends StatefulWidget {
  final int trackCount;
  final String defaultName;
  final List<Playlist> existing;

  const _ImportTargetDialog({
    required this.trackCount,
    required this.defaultName,
    required this.existing,
  });

  @override
  State<_ImportTargetDialog> createState() => _ImportTargetDialogState();
}

class _ImportTargetDialogState extends State<_ImportTargetDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.defaultName);
  bool _useExisting = false;
  Playlist? _selected;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _useExisting ? _selected != null : _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_useExisting
        ? _ImportTarget.existing(_selected!)
        : _ImportTarget.create(_name.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text('Importar playlist',
          style: TextStyle(color: context.textPrimary)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.trackCount} canciones detectadas',
              style: TextStyle(color: context.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Nueva')),
                ButtonSegment(
                  value: true,
                  label: const Text('Existente'),
                  enabled: widget.existing.isNotEmpty,
                ),
              ],
              selected: {_useExisting},
              onSelectionChanged: (v) => setState(() => _useExisting = v.first),
            ),
            const SizedBox(height: 12),
            if (!_useExisting)
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Nombre de la playlist',
                  labelStyle: TextStyle(color: context.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.textMuted)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.accent)),
                ),
              )
            else
              DropdownButtonFormField<Playlist>(
                initialValue: _selected,
                isExpanded: true,
                dropdownColor: context.bgCard,
                hint: Text('Elegí una playlist',
                    style: TextStyle(color: context.textSecondary)),
                style: TextStyle(color: context.textPrimary),
                items: [
                  for (final p in widget.existing)
                    DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (${p.songCount})',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (p) => setState(() => _selected = p),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              Text('Cancelar', style: TextStyle(color: context.textSecondary)),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text('Importar',
              style: TextStyle(
                  color: _canSubmit ? context.accent : context.textMuted)),
        ),
      ],
    );
  }
}

/// Ejecuta la importación y muestra el porcentaje de avance. Se cierra solo
/// al terminar, devolviendo un [_ImportOutcome].
class _ImportProgressDialog extends StatefulWidget {
  final List<ImportTrack> tracks;
  final NavidromeService nav;
  final _ImportTarget target;

  const _ImportProgressDialog({
    required this.tracks,
    required this.nav,
    required this.target,
  });

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<_ImportProgressDialog> {
  late final ValueNotifier<PlaylistImportProgress> _progress = ValueNotifier(
    PlaylistImportProgress(
        done: 0, total: widget.tracks.length, matched: 0, notFound: 0),
  );
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _progress.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    _ImportOutcome outcome;
    try {
      final result = await PlaylistImporter.import(
        tracks: widget.tracks,
        nav: widget.nav,
        name: widget.target.newName,
        existingPlaylistId: widget.target.existing?.id,
        existingPlaylistName: widget.target.existing?.name,
        isCancelled: () => _cancelRequested,
        onProgress: (p) {
          if (mounted) _progress.value = p;
        },
      );
      outcome = _ImportOutcome.done(result);
    } on PlaylistImportCancelled {
      outcome = const _ImportOutcome.cancelled();
    } catch (e) {
      outcome = _ImportOutcome.failed(
          e.toString().replaceFirst(RegExp(r'^(Exception|StateError): '), ''));
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: context.bgCard,
        title:
            Text('Importando…', style: TextStyle(color: context.textPrimary)),
        content: SizedBox(
          width: 320,
          child: ValueListenableBuilder<PlaylistImportProgress>(
            valueListenable: _progress,
            builder: (context, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    '${p.percent}%',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: p.fraction,
                  color: context.accent,
                  backgroundColor: context.textMuted.withValues(alpha: 0.25),
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Text(
                  '${p.done} de ${p.total} canciones revisadas',
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.matched} encontradas · ${p.notFound} no encontradas',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _cancelRequested = true),
            child: Text(_cancelRequested ? 'Cancelando…' : 'Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Pantalla de finalización de la importación. Muestra cuántas canciones se
/// importaron y cuántas no (los totales), la lista de las que faltan y un botón
/// para exportar un CSV con ellas.
class _ImportResultDialog extends StatefulWidget {
  final PlaylistImportResult result;

  const _ImportResultDialog({required this.result});

  @override
  State<_ImportResultDialog> createState() => _ImportResultDialogState();
}

class _ImportResultDialogState extends State<_ImportResultDialog> {
  bool _savingCsv = false;

  Future<void> _exportCsv() async {
    final result = widget.result;
    final safeName = result.name
            .replaceAll(RegExp(r'[^\w\s\-áéíóúüñÁÉÍÓÚÜÑ]'), '')
            .trim()
            .isEmpty
        ? 'playlist'
        : result.name
            .replaceAll(RegExp(r'[^\w\s\-áéíóúüñÁÉÍÓÚÜÑ]'), '')
            .trim()
            .replaceAll(' ', '_');

    setState(() => _savingCsv = true);
    try {
      final csv = PlaylistImporter.tracksToCsv(result.unmatched);
      final fileName = '${safeName}_faltantes.csv';

      File? file;
      var copiedToClipboard = false;
      final isDesktop =
          Platform.isLinux || Platform.isWindows || Platform.isMacOS;
      if (isDesktop) {
        final location = await getSaveLocation(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'CSV', extensions: ['csv']),
          ],
          suggestedName: fileName,
        );
        if (location == null) return; // usuario canceló el guardado
        file = File(location.path);
        if (!file.path.toLowerCase().endsWith('.csv')) {
          file = File('${file.path}.csv');
        }
      } else {
        // Android/iOS no tienen diálogo "Guardar como": se guarda en la
        // carpeta de la app y además se copia al portapapeles para poder
        // pegarlo/enviarlo directamente.
        final dir = Platform.isAndroid
            ? (await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory())
            : await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$fileName');
        await Clipboard.setData(ClipboardData(text: csv));
        copiedToClipboard = true;
      }
      // BOM para que Excel abra bien los acentos.
      await file.writeAsString('\uFEFF$csv');

      if (!mounted) return;
      _snack(copiedToClipboard
          ? 'CSV guardado en ${file.path} y copiado al portapapeles'
          : 'CSV guardado en ${file.path}');
    } catch (e) {
      if (!mounted) return;
      _snack('No se pudo guardar el CSV: $e');
    } finally {
      if (mounted) setState(() => _savingCsv = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: context.textPrimary)),
        backgroundColor: context.bgCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final total = result.matched + result.unmatched.length;

    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text(
        !result.playlistTouched
            ? 'No se importó nada'
            : result.toExisting
                ? 'Agregadas a "${result.name}"'
                : 'Playlist "${result.name}" creada',
        style: TextStyle(color: context.textPrimary),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$total canciones en total:',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.check_circle, color: context.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  result.alreadyInPlaylist > 0
                      ? '${result.added} agregadas (${result.alreadyInPlaylist} ya estaban en la playlist)'
                      : '${result.matched} importadas',
                  style: TextStyle(color: context.accent, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  result.hasUnmatched
                      ? Icons.error_outline
                      : Icons.check_circle,
                  color: result.hasUnmatched ? context.warning : context.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  result.hasUnmatched
                      ? '${result.unmatched.length} no encontradas'
                      : 'Todas las canciones fueron importadas',
                  style: TextStyle(
                    color:
                        result.hasUnmatched ? context.warning : context.accent,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            if (result.hasUnmatched) ...[
              const SizedBox(height: 14),
              Text(
                'Canciones que faltan (${result.unmatched.length}):',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: result.unmatched.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final t = result.unmatched[i];
                    return Text(
                      t.display,
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 12),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _savingCsv ? null : _exportCsv,
                icon: _savingCsv
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.warning,
                        ),
                      )
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: Text(
                  _savingCsv ? 'Guardando…' : 'Exportar CSV de las que faltan',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.warning,
                  side: BorderSide(color: context.warning),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK', style: TextStyle(color: context.accent)),
        ),
      ],
    );
  }
}

/// Widget que lista las playlists del usuario y permite borrarlas.
class _PlaylistsManager extends StatelessWidget {
  const _PlaylistsManager();

  @override
  Widget build(BuildContext context) {
    return Consumer<NavidromeService>(
      builder: (context, nav, _) {
        return FutureBuilder<List<Playlist>>(
          future: nav.getPlaylists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: context.accent),
                ),
              );
            }
            if (snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No tienes playlists creadas.',
                  style: TextStyle(color: context.textMuted),
                ),
              );
            }
            final playlists = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final playlist in playlists)
                  _PlaylistTile(playlist: playlist),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;

  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.bgElevated,
              borderRadius: BorderRadius.circular(4),
              image: playlist.coverArtUrl != null
                  ? DecorationImage(
                      image: NetworkImage(playlist.coverArtUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: playlist.coverArtUrl == null
                ? Icon(Icons.queue_music, color: context.textMuted, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                Text(
                  '${playlist.songCount} canciones',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: context.danger, size: 20),
            onPressed: () => _confirmDelete(context, playlist),
            tooltip: 'Eliminar playlist',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Playlist playlist) async {
    final nav = context.read<NavidromeService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('¿Eliminar playlist?',
            style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Se borrará "${playlist.name}" permanentemente.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Eliminar', style: TextStyle(color: context.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await nav.deletePlaylist(playlist.id);
      nav.bumpPlaylists();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist eliminada',
              style: TextStyle(color: context.textPrimary)),
          backgroundColor: context.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: TextStyle(color: context.danger)),
          backgroundColor: context.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _InfoText extends StatelessWidget {
  final String text;

  const _InfoText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: context.textMuted, fontSize: 12, height: 1.4),
    );
  }
}
