import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/playlist_importer.dart';
import '../services/settings_controller.dart';
import 'login_screen.dart';

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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: Colors.white,
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
                    title: const Text('Volumen inicial',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Slider(
                      value: settings.initialVolume,
                      activeColor: Colors.greenAccent,
                      inactiveColor: Colors.white24,
                      onChanged: settings.setInitialVolume,
                    ),
                    trailing: Text(
                      '${(settings.initialVolume * 100).round()}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  _switchTile(
                    title: 'Reproducción sin cortes',
                    subtitle: 'Evita silencios entre canciones (depende del backend)',
                    value: settings.gapless,
                    onChanged: settings.setGapless,
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
                      (value: 600, label: 'Alta', subtitle: 'Portadas nítidas · más datos'),
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

              // ---------------------------------------------------------------
              // Playlists (importar)
              // ---------------------------------------------------------------
              _sectionTitle('Playlists'),
              _card(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file, color: Colors.white70),
                    title: const Text('Importar playlist',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text(
                      'Desde CSV, M3U/M3U8, PLS o TXT',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: _importing ? null : _pickAndImport,
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // Playlists (gestionar/borrar)
              // ---------------------------------------------------------------
              _sectionTitle('Mis playlists'),
              _PlaylistsManager(),

              // ---------------------------------------------------------------
              // Cuenta
              // ---------------------------------------------------------------
              _sectionTitle('Cuenta'),
              _card(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dns_outlined, color: Colors.white70),
                    title: Text(
                      nav.serverUrl ?? 'Sin conexión',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      nav.connected ? 'Conectado' : 'Desconectado',
                      style: TextStyle(
                        color: nav.connected ? Colors.greenAccent : Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Cerrar sesión'),
                      onPressed: () => _confirmLogout(context),
                    ),
                  ),
                ],
              ),

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
    final xType = XTypeGroup(
      label: 'Playlists',
      extensions: ['csv', 'm3u', 'm3u8', 'pls', 'txt'],
    );

    final xFile = await openFile(acceptedTypeGroups: [xType]);
    if (xFile == null) return;

    final bytes = await xFile.readAsBytes();
    final content = String.fromCharCodes(bytes);

    final parsed = PlaylistImporter.parseFile(xFile.name, content);
    if (parsed.tracks.isEmpty) {
      if (!mounted) return;
      _showError('El archivo no contiene canciones reconocibles.');
      return;
    }

    final defaultName = parsed.suggestedName ??
        xFile.name.split('.').first.replaceAll(RegExp(r'[_\-]+'), ' ').trim();

    final controller = TextEditingController(text: defaultName);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('Importar playlist',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${parsed.tracks.length} canciones detectadas',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nombre de la playlist',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.greenAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Importar', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final name = controller.text.trim();
    if (name.isEmpty) {
      _showError('El nombre no puede estar vacío.');
      return;
    }

    setState(() => _importing = true);

    final nav = context.read<NavidromeService>();
    try {
      final result = await showDialog<PlaylistImportResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ImportingDialog(
          future: PlaylistImporter.import(name: name, tracks: parsed.tracks, nav: nav),
        ),
      );

      if (!mounted || result == null) return;

      if (result.hasUnmatched) {
        await _showResult(result);
      } else {
        _showSnack('Playlist "$name" creada (${result.matched} canciones)');
      }
    } on Exception catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showResult(PlaylistImportResult result) async {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Text(
          'Playlist "${result.name}" creada',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se agregaron ${result.matched} canciones.',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                'No se encontraron ${result.unmatched.length} canciones:',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: result.unmatched.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final t = result.unmatched[i];
                    return Text(
                      t.display,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('Error al importar',
            style: TextStyle(color: Colors.white)),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1F1F1F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final nav = context.read<NavidromeService>();
    final navigator = Navigator.of(context);
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('¿Cerrar sesión?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Volverás a la pantalla de inicio de sesión.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar sesión',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true) return;
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
        style: const TextStyle(
          color: Colors.white,
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
        color: const Color(0xFF1F1F1F),
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
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      activeTrackColor: Colors.greenAccent,
      activeThumbColor: Colors.white,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _networkBadge(String label, bool mobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mobile ? Colors.orangeAccent : Colors.greenAccent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Red actual: $label',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final q in AudioQuality.values)
                InkWell(
                  onTap: () => onChanged(q),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          q == current
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: q == current
                              ? Colors.greenAccent
                              : Colors.white24,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.label,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              Text(q.subtitle,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (q == AudioQuality.lossless)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'FLAC',
                              style: TextStyle(
                                color: Colors.greenAccent.withValues(alpha: 0.8),
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
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final opt in options)
                InkWell(
                  onTap: () => onChanged(opt.value),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          opt.value == value
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: opt.value == value
                              ? Colors.greenAccent
                              : Colors.white24,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opt.label,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              Text(opt.subtitle,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
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

class _ImportingDialog extends StatelessWidget {
  final Future<PlaylistImportResult> future;

  const _ImportingDialog({required this.future});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F1F1F),
      title: const Text('Importando…', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.greenAccent),
          const SizedBox(height: 16),
          const Text(
            'Buscando canciones en tu biblioteca…',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
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
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.greenAccent),
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No tienes playlists creadas.',
                  style: TextStyle(color: Colors.white54),
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
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(4),
              image: playlist.coverArtUrl != null
                  ? DecorationImage(
                      image: NetworkImage(playlist.coverArtUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: playlist.coverArtUrl == null
                ? const Icon(Icons.queue_music, color: Colors.white54, size: 20)
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
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  '${playlist.songCount} canciones',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
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
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('¿Eliminar playlist?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Se borrará "${playlist.name}" permanentemente.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
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
          content: Text('Playlist eliminada', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.redAccent)),
          backgroundColor: const Color(0xFF1F1F1F),
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
      style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
    );
  }
}