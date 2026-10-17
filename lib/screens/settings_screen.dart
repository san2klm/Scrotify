import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/crotolink_models.dart';
import '../services/navidrome_service.dart';
import '../services/remote_crotolink_service.dart';
import '../services/pairing_server.dart';
import '../services/hifi/audio_output_devices.dart';
import '../services/hifi/hifi_coordinator.dart';
import '../services/hifi/hifi_profiles.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import '../services/settings_controller.dart';
import '../services/window_controls.dart';
import '../widgets/diagnostics_panel.dart';
import '../widgets/pairing_panel.dart';
import '../widgets/sync_settings.dart';
import '../widgets/theme_grid.dart';
import '../widgets/local_music_settings.dart';
import 'equalizer_screen.dart';
import 'stats_screen.dart';
import '../utils/app_colors.dart';
import '../utils/app_licenses.dart';
import '../utils/build_info.dart';
import '../utils/responsive.dart';
import '../widgets/material_surface.dart';
import '../widgets/tv_initial_focus.dart';

/// Pantalla de ajustes. Centraliza las preferencias del usuario: calidad de
/// audio según la red, portadas, volumen y cuenta.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
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
      body: ConstrainedContent(
        maxWidth: 1000,
        child: TvInitialFocus(
            child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _menuGroup([
              _menuRow(
                icon: Icons.high_quality_rounded,
                title: 'Audio y calidad',
                subtitle: 'Calidad según la red',
                onTap: () => _openPage('Audio y calidad', _audioPage),
              ),
              _menuRow(
                icon: Icons.play_circle_outline_rounded,
                title: 'Reproducción',
                subtitle: 'Transiciones, volumen y cola',
                onTap: () => _openPage('Reproducción', _playbackPage),
              ),
              _menuRow(
                icon: Icons.equalizer_rounded,
                title: 'Ecualizador',
                subtitle: 'Ajustes de 10 bandas y presets',
                onTap: () => _push(const EqualizerScreen()),
              ),
            ]),
            const SizedBox(height: 16),
            _menuGroup([
              _menuRow(
                icon: Icons.palette_outlined,
                title: 'Apariencia y temas',
                subtitle: 'Portadas y temas de color',
                onTap: () => _openPage('Apariencia y temas', _appearancePage),
              ),
              _menuRow(
                icon: Icons.library_music_outlined,
                title: 'Biblioteca y descargas',
                subtitle: 'Música local y playlists',
                onTap: () => _openPage('Biblioteca y descargas', _libraryPage),
              ),
              _menuRow(
                icon: Icons.podcasts_rounded,
                title: nav.connected
                    ? 'CrotoLink y dispositivos'
                    : 'Servidor CrotoLink',
                subtitle: nav.connected
                    ? 'Servidor CrotoLink y vincular teléfono'
                    : 'Servidor de sesiones grupales',
                onTap: () => _openPage(
                    nav.connected
                        ? 'CrotoLink y dispositivos'
                        : 'Servidor CrotoLink',
                    _crotoLinkPage),
              ),
              _menuRow(
                icon: Icons.insights_rounded,
                title: 'Estadísticas de escucha',
                subtitle: 'Tiempo reproducido y lo más escuchado',
                onTap: () => _push(const StatsScreen()),
              ),
              _menuRow(
                icon: Icons.bug_report_outlined,
                title: 'Diagnóstico',
                subtitle: 'Exportar el registro para reportar un fallo',
                onTap: () => _openPage(
                    'Diagnóstico',
                    (_) => [
                          _sectionTitle('Registro de la app'),
                          _card(children: const [DiagnosticsPanel()]),
                        ]),
              ),
              _menuRow(
                icon: Icons.gavel_rounded,
                title: 'Licencias de código abierto',
                subtitle: 'Licencia de CrotoWave y de las librerías que usa',
                onTap: () => AppLicenses.show(context),
              ),
            ]),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'CrotoWave · ${BuildInfo.label}\n'
                'Cliente de Navidrome (Subsonic API)',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),
          ],
        )),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Categorías
  // ---------------------------------------------------------------------------

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _openPage(
    String title,
    List<Widget> Function(SettingsController settings) children,
  ) {
    _push(_SettingsSubpage(
      title: title,
      children: (settings) => children(settings),
    ));
  }

  List<Widget> _audioPage(SettingsController settings) => [
        _card(children: [
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
          ] else ...[
            const SizedBox(height: 8),
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
        ]),
        _sectionTitle('Fidelidad'),
        _card(children: [
          _choiceTiles<AudioFidelityMode>(
            title: 'Modo de reproducción',
            value: settings.fidelityMode,
            options: const [
              (
                value: AudioFidelityMode.standard,
                label: 'Estándar',
                subtitle: 'Como siempre: sonido seguro y compatible',
              ),
              (
                value: AudioFidelityMode.highFidelity,
                label: 'Alta fidelidad',
                subtitle: 'Archivo original y procesado en coma flotante',
              ),
              (
                value: AudioFidelityMode.bitPerfect,
                label: 'Bit-perfect',
                subtitle: 'Sin procesar: sin ecualizador, crossfade ni '
                    'ReplayGain; volumen fijo al 100 %',
              ),
            ],
            onChanged: settings.setFidelityMode,
          ),
          if (settings.fidelityMode != AudioFidelityMode.standard) ...[
            const SizedBox(height: 8),
            _switchTile(
              title: 'Sin pérdida también con datos móviles',
              subtitle: 'Gasta más datos; si no, se usa Opus con datos móviles',
              value: settings.losslessOnMobileData,
              onChanged: settings.setLosslessOnMobileData,
            ),
          ],
          if (settings.fidelityMode == AudioFidelityMode.bitPerfect &&
              Platform.isLinux)
            const _AlsaOutputPicker(),
          Builder(builder: (context) {
            final notes = context.watch<HifiCoordinator?>()?.plan?.notes ??
                const <String>[];
            if (settings.fidelityMode == AudioFidelityMode.standard ||
                notes.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final note in notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _InfoText(note),
                    ),
                ],
              ),
            );
          }),
        ]),
      ];

  List<Widget> _playbackPage(SettingsController settings) => [
        _sectionTitle('Transiciones'),
        _card(children: [
          _switchTile(
            title: 'Reproducción sin cortes',
            subtitle: 'Evita silencios entre canciones (depende del backend)',
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
                  style: TextStyle(color: context.textPrimary, fontSize: 14)),
              subtitle: Slider(
                value: settings.crossfade.inSeconds.clamp(1, 10).toDouble(),
                min: 1,
                max: 10,
                activeColor: context.accent,
                inactiveColor: context.themeBorder,
                onChanged: (v) =>
                    settings.setCrossfade(Duration(seconds: v.round())),
              ),
              trailing: Text(
                '${settings.crossfade.inSeconds} s',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ]),
        _sectionTitle('Volumen'),
        _card(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Volumen inicial',
                style: TextStyle(color: context.textPrimary, fontSize: 14)),
            subtitle: Slider(
              value: settings.initialVolume,
              activeColor: context.accent,
              inactiveColor: context.themeBorder,
              onChanged: settings.setInitialVolume,
            ),
            trailing: Text(
              '${(settings.initialVolume * 100).round()}%',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          ),
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
                style: TextStyle(color: context.textPrimary, fontSize: 14),
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
                style: TextStyle(color: context.textSecondary, fontSize: 13),
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
        ]),
        _sectionTitle('Cola'),
        _card(children: [
          _switchTile(
            title: 'Eliminar silencios',
            subtitle:
                'Recorta silencios al inicio y final de las canciones usando análisis de waveform',
            value: settings.silenceRemovalEnabled,
            onChanged: settings.setSilenceRemovalEnabled,
          ),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
            _switchTile(
              title: 'Discord Rich Presence',
              subtitle:
                  'Muestra lo que escuchas en tu perfil de Discord (necesita el ID de tu aplicación)',
              value: settings.discordPresence,
              onChanged: settings.setDiscordPresence,
            ),
            if (settings.discordPresence)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextFormField(
                  initialValue: settings.discordClientId,
                  decoration: const InputDecoration(
                    labelText: 'Application ID de Discord',
                    helperText:
                        'portal de desarrolladores de Discord → tu aplicación',
                  ),
                  onFieldSubmitted: settings.setDiscordClientId,
                ),
              ),
          ],
          _switchTile(
            title: 'Color según la carátula',
            subtitle:
                'El color de énfasis de la app sigue a la portada de la canción que suena',
            value: context.watch<ThemeController>().coverAccentEnabled,
            onChanged: (v) =>
                context.read<ThemeController>().setCoverAccentEnabled(v),
          ),
          _switchTile(
            title: 'Guardar la cola en el servidor',
            subtitle:
                'Permite continuar en otro dispositivo; sobrescribe la cola guardada',
            value: settings.syncQueueToServer,
            onChanged: settings.setSyncQueueToServer,
          ),
          ListTile(
            leading: Icon(Icons.restore, color: context.textMuted),
            title: Text('Recuperar la cola guardada',
                style: TextStyle(color: context.textPrimary)),
            subtitle: Text('Continúa lo que dejaste en otro dispositivo',
                style: TextStyle(color: context.textMuted, fontSize: 12)),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final restored =
                  await context.read<PlayerController>().restoreSavedQueue();
              messenger.showSnackBar(SnackBar(
                  content: Text(restored == null
                      ? 'No hay ninguna cola guardada en el servidor.'
                      : 'Cola recuperada (${restored.tracks.length} canciones).')));
            },
          ),
          _switchTile(
            title: 'Fotos de artista de internet',
            subtitle:
                'Busca la foto en TheAudioDB y Deezer; envía el nombre del artista a esos servicios',
            value: settings.thirdPartyArtistImages,
            onChanged: settings.setThirdPartyArtistImages,
          ),
          _switchTile(
            title: 'Mezcla inteligente',
            subtitle:
                'Evita repetir el mismo artista seguido en modo aleatorio',
            value: settings.isSmartMixEnabled,
            onChanged: settings.setSmartMixEnabled,
          ),
        ]),
        if (WindowControls.isDesktop) ...[
          _sectionTitle('Atajos'),
          _card(children: [
            _switchTile(
              title: 'Seguir en segundo plano al cerrar la ventana',
              subtitle:
                  'Al tocar la X, CrotoWave queda en la bandeja del sistema reproduciendo música y respondiendo a los atajos',
              value: settings.closeToTray,
              onChanged: settings.setCloseToTray,
            ),
            _switchTile(
              title: 'Activar atajos de reproducción',
              subtitle:
                  'Permite controlar la reproducción con botones del mouse o teclas del teclado',
              value: settings.mouseControlsEnabled,
              onChanged: settings.setMouseControlsEnabled,
            ),
            if (settings.mouseControlsEnabled) ...[
              _switchTile(
                title: 'Atajos globales (en el escritorio y fuera de la app)',
                subtitle:
                    'Controla la reproducción aunque cierres la ventana, minimices o estés en el escritorio/juegos',
                value: settings.mouseGlobalEnabled,
                onChanged: settings.setMouseGlobalEnabled,
              ),
              _switchTile(
                title: 'Pausar con clic de la rueda (botón central)',
                subtitle:
                    'Funciona en CrotoWave, en el escritorio y en otros programas (en navegadores usa doble clic de rueda o Alt + Rueda para no cerrar pestañas)',
                value: settings.mouseMiddleClickEnabled,
                onChanged: settings.setMouseMiddleClickEnabled,
              ),
              const SizedBox(height: 12),
              Text(
                'Personalizar botones del mouse o teclas',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _ShortcutBindingTile(
                title: 'Reproducir / Pausar tema',
                subtitle:
                    'Elegí qué botón del mouse o tecla usar para pausar y reanudar (doble clic rápido en botón lateral = tema anterior)',
                icon: Icons.play_arrow_rounded,
                binding: settings.playPauseBinding,
                onChange: (newRaw) => settings.setPlayPauseShortcut(newRaw),
              ),
              const SizedBox(height: 8),
              _ShortcutBindingTile(
                title: 'Siguiente tema',
                subtitle:
                    'Elegí qué botón del mouse o tecla usar para pasar a la siguiente canción',
                icon: Icons.skip_next_rounded,
                binding: settings.nextTrackBinding,
                onChange: (newRaw) => settings.setNextTrackShortcut(newRaw),
              ),
              if (settings.playPauseShortcut !=
                      ShortcutBinding.mouseXButton1.raw ||
                  settings.nextTrackShortcut !=
                      ShortcutBinding.mouseXButton2.raw) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: settings.resetShortcutsToDefault,
                    icon: Icon(Icons.restore_rounded,
                        size: 18, color: context.textSecondary),
                    label: Text(
                      'Restaurar atajos por defecto',
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 13),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _InfoText(
                'Atajos activos actualmente:\n'
                '• Reproducir / Pausar tema: ${settings.playPauseBinding.label}\n'
                '• Siguiente tema: ${settings.nextTrackBinding.label}\n'
                '• Alt + Rueda arriba/abajo: Subir o bajar volumen desde cualquier lugar',
              ),
            ],
          ]),
        ],
      ];

  List<Widget> _appearancePage(SettingsController settings) => [
        _card(children: [
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
        ]),
        const SizedBox(height: 12),
        // Temas (.zip estilo Psysonic, carpeta configurable).
        const ThemesSection(),
      ];

  List<Widget> _libraryPage(SettingsController settings) => [
        _sectionTitle('Música local'),
        _card(children: const [LocalMusicSettings()]),
        _sectionTitle('Mis playlists'),
        const _PlaylistsManager(),
      ];

  List<Widget> _crotoLinkPage(SettingsController settings) {
    final nav = context.read<NavidromeService>();
    return [
      _sectionTitle('Servidor CrotoLink'),
      _card(children: [_CrotoLinkServerField(settings: settings)]),
      _sectionTitle('Sincronización'),
      _card(children: const [SyncSettings()]),
      if (nav.connected) ...[
        _sectionTitle('Vincular teléfono'),
        _card(children: [
          PairingSharePanel(
            compact: true,
            server: context.read<PairingServer>(),
            onGetCredentials: () async => nav.currentCredentials,
          ),
        ]),
      ],
    ];
  }

  // ---------------------------------------------------------------------------
  // Menú principal
  // ---------------------------------------------------------------------------

  Widget _menuGroup(List<Widget> rows) {
    return MaterialSurface(
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: context.bgCard,
      child: Column(children: rows),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: context.accent),
      title: Text(title,
          style: TextStyle(color: context.textPrimary, fontSize: 15)),
      subtitle: Text(subtitle,
          style: TextStyle(color: context.textSecondary, fontSize: 13)),
      trailing: Icon(Icons.chevron_right, color: context.textMuted),
      onTap: onTap,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers de UI
  // ---------------------------------------------------------------------------

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Text(
        title,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return MaterialSurface(
      padding: const EdgeInsets.all(16),
      color: context.bgCard,
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
          style: TextStyle(color: context.textSecondary, fontSize: 13)),
      activeTrackColor: context.accent,
      activeThumbColor: context.textPrimary,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _networkBadge(String label, bool mobile) {
    return MaterialSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: context.bgElevated,
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
          Expanded(
              child: Text(
            'Red actual: $label',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          )),
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
        MaterialSurface(
          color: context.bgElevated,
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
                                      color: context.textSecondary,
                                      fontSize: 13)),
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
        MaterialSurface(
          color: context.bgElevated,
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
                                      color: context.textSecondary,
                                      fontSize: 13)),
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
                      image: ResizeImage(
                        NetworkImage(playlist.coverArtUrl!),
                        width: 120,
                      ),
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
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
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
      style: TextStyle(color: context.textSecondary, fontSize: 13, height: 1.4),
    );
  }
}

/// Campo de URL del servidor CrotoLink con validación, prueba de conexión
/// (`GET /health`) y restauración del valor por defecto.
class _CrotoLinkServerField extends StatefulWidget {
  final SettingsController settings;

  const _CrotoLinkServerField({required this.settings});

  @override
  State<_CrotoLinkServerField> createState() => _CrotoLinkServerFieldState();
}

class _CrotoLinkServerFieldState extends State<_CrotoLinkServerField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.settings.crotoLinkServerUrl);
  String? _error;
  String? _info;
  bool _testing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final result = widget.settings.setCrotoLinkServerUrl(_controller.text);
    setState(() {
      _error = result.error;
      _info = result.warning;
      if (result.isValid) _controller.text = result.url!;
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _error = null;
      _info = null;
    });
    final failure =
        await RemoteCrotoLinkService.testConnection(_controller.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (failure == null) {
        _info = 'Conexión correcta.';
      } else {
        _error = failure;
      }
    });
  }

  void _reset() {
    widget.settings.resetCrotoLinkServerUrl();
    setState(() {
      _controller.text = kDefaultRemoteCrotoLinkEndpoint;
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: TextStyle(color: context.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'URL del servidor',
            hintText: kExampleRemoteCrotoLinkEndpoint,
            errorText: _error,
            helperText: _info,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(onPressed: _save, child: const Text('Guardar')),
            OutlinedButton(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'Probando…' : 'Probar conexión'),
            ),
            TextButton(onPressed: _reset, child: const Text('Quitar servidor')),
          ],
        ),
        const SizedBox(height: 8),
        const _InfoText(
            'Servidor para salas CrotoLink remotas, CrotoWave Connect por '
            'internet y sincronización. No hay ninguno por defecto: alojá el '
            'tuyo con el Docker de crotolink-server/ o usá el de alguien de confianza. '
            'Usa wss://; ws:// solo en red local.'),
      ],
    );
  }
}

/// Subpágina de una categoría de ajustes: se reconstruye al cambiar los
/// ajustes o el tema activo.
class _SettingsSubpage extends StatelessWidget {
  const _SettingsSubpage({required this.title, required this.children});

  final String title;
  final List<Widget> Function(SettingsController settings) children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgApp,
      appBar: AppBar(
        backgroundColor: context.bgApp,
        foregroundColor: context.textPrimary,
        elevation: 0,
        title: Text(title),
      ),
      body: Consumer<SettingsController>(
        builder: (context, settings, _) => ConstrainedContent(
          maxWidth: 1000,
          child: TvInitialFocus(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: children(settings),
          )),
        ),
      ),
    );
  }
}

/// Selector de salida ALSA directa (`hw:`) para Bit-perfect en Linux.
class _AlsaOutputPicker extends StatefulWidget {
  const _AlsaOutputPicker();

  @override
  State<_AlsaOutputPicker> createState() => _AlsaOutputPickerState();
}

class _AlsaOutputPickerState extends State<_AlsaOutputPicker> {
  Future<List<AudioOutputDevice>>? _devices;

  Future<List<AudioOutputDevice>> _load() =>
      context.read<HifiCoordinator?>()?.directOutputDevices() ??
      Future.value(const []);

  void _reload() {
    // Con llaves: una flecha devolvería el Future y setState lo rechaza.
    setState(() {
      _devices = _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Primera carga: aún no hay nada pintado, no hace falta setState.
    _devices ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final missing =
        context.watch<HifiCoordinator?>()?.outputDeviceMissing ?? false;
    return FutureBuilder<List<AudioOutputDevice>>(
      future: _devices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const <AudioOutputDevice>[];
        final selected = settings.audioOutputDevice;
        final known = devices.any((d) => d.name == selected);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                // La clave fuerza a reconstruir si cambia la elección externa.
                key: ValueKey('$selected-${devices.length}'),
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Salida directa (ALSA hw:)',
                  helperText: missing
                      ? 'La salida elegida no está conectada: se usa la del sistema.'
                      : 'Elegí tu DAC para bit-perfect real.',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Salida del sistema')),
                  for (final d in devices)
                    DropdownMenuItem<String?>(
                        value: d.name,
                        child: Text(d.description,
                            overflow: TextOverflow.ellipsis)),
                  // Conserva visible una elección cuyo dispositivo no está.
                  if (selected != null && !known)
                    DropdownMenuItem<String?>(
                        value: selected,
                        child: Text('$selected (desconectada)',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: settings.setAudioOutputDevice,
              ),
            ),
            IconButton(
              tooltip: 'Buscar salidas de nuevo',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reload,
            ),
          ]),
        );
      },
    );
  }
}

/// Fila interactiva que muestra el atajo asignado a una acción (ej. Reproducir
/// o Siguiente tema) y permite modificarlo por cualquier botón del mouse o tecla.
class _ShortcutBindingTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final ShortcutBinding binding;
  final ValueChanged<String> onChange;

  const _ShortcutBindingTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.binding,
    required this.onChange,
  });

  IconData get _bindingIcon {
    if (binding.isMouse) return Icons.mouse_rounded;
    if (binding.isKey) return Icons.keyboard_rounded;
    return Icons.block_rounded;
  }

  Future<void> _openCaptureDialog(BuildContext context) async {
    final settings = context.read<SettingsController>();
    settings.setCapturingShortcut(true);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => _ShortcutCaptureDialog(
          actionTitle: title,
          initialBinding: binding,
        ),
      );
      if (result != null && result.isNotEmpty) {
        onChange(result);
      }
    } finally {
      settings.setCapturingShortcut(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      color: context.bgElevated,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: context.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _openCaptureDialog(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.textPrimary,
              side: BorderSide(color: context.accent.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            icon: Icon(_bindingIcon, size: 17, color: context.accent),
            label: Text(
              binding.shortLabel,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo modal para capturar un botón del mouse o una tecla del teclado,
/// o elegir entre las opciones de botones del mouse.
class _ShortcutCaptureDialog extends StatefulWidget {
  final String actionTitle;
  final ShortcutBinding initialBinding;

  const _ShortcutCaptureDialog({
    required this.actionTitle,
    required this.initialBinding,
  });

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  late String _selectedRaw = widget.initialBinding.raw;
  final FocusNode _focusNode = FocusNode();
  bool _justCaptured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectBinding(String raw) {
    setState(() {
      _selectedRaw = raw;
      _justCaptured = true;
    });
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final bound = ShortcutBinding.fromLogicalKey(event.logicalKey);
    if (bound != null) {
      _selectBinding(bound.raw);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if ((event.buttons & kBackMouseButton) != 0) {
      _selectBinding(ShortcutBinding.mouseXButton1.raw);
    } else if ((event.buttons & kForwardMouseButton) != 0) {
      _selectBinding(ShortcutBinding.mouseXButton2.raw);
    } else if ((event.buttons & kMiddleMouseButton) != 0) {
      _selectBinding(ShortcutBinding.mouseMiddle.raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ShortcutBinding(_selectedRaw);
    final presetOptions = [
      (
        binding: ShortcutBinding.mouseXButton1,
        subtitle: 'Botón lateral trasero del mouse (XButton 1)',
        icon: Icons.mouse_rounded,
      ),
      (
        binding: ShortcutBinding.mouseXButton2,
        subtitle: 'Botón lateral delantero del mouse (XButton 2)',
        icon: Icons.mouse_rounded,
      ),
      (
        binding: ShortcutBinding.mouseMiddle,
        subtitle: 'Pulsar la rueda del mouse (Botón central)',
        icon: Icons.mouse_rounded,
      ),
      (
        binding: ShortcutBinding.none,
        subtitle: 'No asignar ningún atajo a esta acción',
        icon: Icons.block_rounded,
      ),
    ];

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        child: AlertDialog(
          backgroundColor: context.bgCard,
          title: Text(
            'Configurar atajo: ${widget.actionTitle}',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    color: context.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _justCaptured
                          ? context.accent
                          : context.themeBorder,
                      width: _justCaptured ? 1.8 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        current.isKey
                            ? Icons.keyboard_alt_rounded
                            : (current.isMouse
                                ? Icons.mouse_rounded
                                : Icons.block_rounded),
                        color: context.accent,
                        size: 30,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        current.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Presioná ahora cualquier TECLA del teclado o BOTÓN del mouse (lateral/rueda) para asignarlo, o elegí una opción abajo:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Opciones de botones del mouse:',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                MaterialSurface(
                  color: context.bgElevated,
                  child: Column(
                    children: [
                      for (final opt in presetOptions)
                        InkWell(
                          onTap: () => _selectBinding(opt.binding.raw),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(
                              children: [
                                Icon(
                                  _selectedRaw == opt.binding.raw
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: _selectedRaw == opt.binding.raw
                                      ? context.accent
                                      : context.themeBorder,
                                  size: 19,
                                ),
                                const SizedBox(width: 10),
                                Icon(opt.icon,
                                    size: 18, color: context.textSecondary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        opt.binding.label,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        opt.subtitle,
                                        style: TextStyle(
                                          color: context.textSecondary,
                                          fontSize: 11.5,
                                        ),
                                      ),
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
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(color: context.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_selectedRaw),
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: Colors.black,
              ),
              child: const Text(
                'Guardar atajo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
