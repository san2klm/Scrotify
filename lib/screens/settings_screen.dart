import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/pairing_server.dart';
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
