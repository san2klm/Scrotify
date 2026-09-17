import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/karaoke_screen.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';
import '../utils/app_colors.dart';

/// Menú contextual unificado para pistas/canciones en toda la aplicación.
class TrackContextMenu extends StatelessWidget {
  final Track track;

  const TrackContextMenu({super.key, required this.track});

  static void show(BuildContext context, Track track) {
    // NOTA: no usar context.bgApp aquí (usa watch y revienta fuera del build).
    final theme = context.read<ThemeController>().active;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
      ),
      builder: (ctx) => TrackContextMenu(track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    final player = context.watch<PlayerController>();
    final jam = context.watch<JamController>();
    final isStarred = nav.isStarred(track.id);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.themeBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Cabecera de la pista
              Row(
                children: [
                  CoverArt(
                    url: track.albumArtUrl,
                    artist: track.artist,
                    album: track.album,
                    title: track.title,
                    width: 48,
                    height: 48,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${track.artist} · ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isStarred ? Icons.favorite : Icons.favorite_border,
                      color: isStarred ? context.accent : context.textSecondary,
                    ),
                    onPressed: () => nav.toggleStar(track),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: context.bgElevated, height: 1),
              const SizedBox(height: 8),

              // Acciones Jam (si hay Jam activo)
              if (jam.inJam) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.speaker_group_rounded,
                        color: context.accent, size: 20),
                  ),
                  title: Text(
                    'Añadir a la cola Jam',
                    style: TextStyle(
                      color: context.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'Compartir con los ${jam.participants.length} oyentes de la sesión',
                    style: TextStyle(color: context.textMuted, fontSize: 11),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    final bg =
                        context.read<ThemeController>().active.bgElevated;
                    Navigator.of(context).pop();
                    jam.addTrackToJam(track);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('"${track.title}" añadida a la cola Jam'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: bg,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.playlist_play_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Reproducir siguiente en Jam',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    final bg =
                        context.read<ThemeController>().active.bgElevated;
                    Navigator.of(context).pop();
                    jam.addTrackToJam(track, playNext: true);
                    messenger.showSnackBar(
                      SnackBar(
                        content:
                            Text('"${track.title}" sonará a continuación en el Jam'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: bg,
                      ),
                    );
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded,
                      color: context.accent, size: 24),
                  title: Text(
                    'Reproducir ahora',
                    style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    player.playQueue([track], startIndex: 0);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.queue_music_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Añadir a la cola',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    final bg =
                        context.read<ThemeController>().active.bgElevated;
                    Navigator.of(context).pop();
                    player.addToQueue(track);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('"${track.title}" añadida a la cola'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: bg,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.playlist_play_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Reproducir siguiente',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    final bg =
                        context.read<ThemeController>().active.bgElevated;
                    Navigator.of(context).pop();
                    player.addNextInQueue(track);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('"${track.title}" sonará a continuación'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: bg,
                      ),
                    );
                  },
                ),
              ],

              // Añadir a Playlist
              ListTile(
                leading: Icon(Icons.playlist_add_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Añadir a una playlist',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddToPlaylistSheet(context, nav, track);
                },
              ),

              Divider(color: context.bgElevated, height: 1),

              // Modo Karaoke
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.mic_external_on_rounded,
                    color: context.accent,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Modo Karaoke',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  PlayerController.isVocalReductionSupported
                      ? 'Letra grande y reducción de voz'
                      : 'Letra sincronizada a pantalla completa',
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: context.textMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  KaraokeScreen.open(context);
                },
              ),

              // Apagado automático (sleep timer)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: player.hasSleepTimer
                        ? context.accent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.timer_outlined,
                    color: player.hasSleepTimer
                        ? context.accent
                        : context.textSecondary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Apagado automático',
                  style: TextStyle(
                    color: player.hasSleepTimer
                        ? context.accent
                        : context.textPrimary,
                    fontSize: 14,
                    fontWeight: player.hasSleepTimer
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  player.hasSleepTimer ? player.sleepLabel : 'Desactivado',
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
                trailing: player.hasSleepTimer
                    ? Icon(Icons.check_rounded,
                        color: context.accent, size: 20)
                    : Icon(Icons.chevron_right_rounded,
                        color: context.textMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  _showSleepTimerSheet(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSleepTimerSheet(BuildContext parentContext) {
    // Leer tema con read (fuera del build no se puede usar watch).
    final theme = parentContext.read<ThemeController>().active;
    showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
      ),
      builder: (ctx) {
        return Consumer<PlayerController>(
          builder: (context, player, _) {
            final options = <({String label, Duration? duration})>[
              (label: 'Desactivado', duration: null),
              (label: 'En 5 minutos', duration: const Duration(minutes: 5)),
              (label: 'En 10 minutos', duration: const Duration(minutes: 10)),
              (label: 'En 15 minutos', duration: const Duration(minutes: 15)),
              (label: 'En 30 minutos', duration: const Duration(minutes: 30)),
              (label: 'En 45 minutos', duration: const Duration(minutes: 45)),
              (label: 'En 1 hora', duration: const Duration(hours: 1)),
              (
                label: 'En 1 hora y 30 minutos',
                duration: const Duration(minutes: 90)
              ),
            ];

            bool isSelected(Duration? d) {
              if (d == null) return !player.hasSleepTimer;
              final rem = player.sleepRemaining;
              if (rem == null) return false;
              // Tolerancia de 2 min para marcar la opción activa.
              return (rem - d).abs() < const Duration(minutes: 2);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.themeBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer_outlined,
                            color: context.accent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Apagado automático',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (player.hasSleepTimer)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          player.sleepLabel,
                          style: TextStyle(
                              color: context.accent, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (ctx, i) {
                          final opt = options[i];
                          final selected = isSelected(opt.duration);
                          return ListTile(
                            leading: Icon(
                              opt.duration == null
                                  ? Icons.timer_off_outlined
                                  : Icons.timer_outlined,
                              color: selected
                                  ? context.accent
                                  : context.textSecondary,
                            ),
                            title: Text(
                              opt.label,
                              style: TextStyle(
                                color: selected
                                    ? context.accent
                                    : context.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check_rounded,
                                    color: context.accent, size: 20)
                                : null,
                            onTap: () {
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              final bg = context
                                  .read<ThemeController>()
                                  .active
                                  .bgElevated;
                              Navigator.of(context).pop();
                              if (opt.duration == null) {
                                player.cancelSleepTimer();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                        'Apagado automático desactivado'),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: bg,
                                  ),
                                );
                              } else {
                                player.setSleepTimer(opt.duration!);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'La música se pausará ${opt.label.toLowerCase()}'),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: bg,
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddToPlaylistSheet(
      BuildContext parentContext, NavidromeService nav, Track track) {
    final theme = parentContext.read<ThemeController>().active;
    showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
      ),
      builder: (ctx) {
        return FutureBuilder<List<Playlist>>(
          future: nav.getPlaylists(),
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? <Playlist>[];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.themeBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Añadir a Playlist',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (playlists.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No tienes playlists creadas',
                          style: TextStyle(color: context.textMuted),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: playlists.length,
                          itemBuilder: (ctx, i) {
                            final p = playlists[i];
                            return ListTile(
                              leading: Icon(Icons.playlist_play,
                                  color: context.accent),
                              title: Text(p.name,
                                  style: TextStyle(color: context.textPrimary)),
                              subtitle: Text('${p.songCount} canciones',
                                  style: TextStyle(
                                      color: context.textMuted, fontSize: 11)),
                              onTap: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                final bg = context
                                    .read<ThemeController>()
                                    .active
                                    .bgElevated;
                                Navigator.of(context).pop();
                                String message;
                                try {
                                  await nav.updatePlaylist(
                                    playlistId: p.id,
                                    songIdsToAdd: [track.id],
                                  );
                                  message = 'Añadida a "${p.name}"';
                                } catch (e) {
                                  message = e.toString().replaceFirst('Exception: ', '');
                                }
                                if (messenger.mounted) {
                                  messenger.showSnackBar(SnackBar(
                                    content: Text(message),
                                    backgroundColor: bg,
                                  ));
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
