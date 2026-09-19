import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/karaoke_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/album_detail_screen.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';
import 'interactive_artist_text.dart';
import 'server_activity_panel.dart';
import '../utils/app_colors.dart';

/// Menú contextual unificado para pistas/canciones en toda la aplicación.
class TrackContextMenu extends StatelessWidget {
  final Track track;
  final String? playlistId;

  const TrackContextMenu({super.key, required this.track, this.playlistId});

  static void show(BuildContext context, Track track, {String? playlistId}) {
    final theme = context.read<ThemeController>().active;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: theme.bgElevated, width: 1.2),
      ),
      builder: (ctx) => TrackContextMenu(track: track, playlistId: playlistId),
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
                        Wrap(
                          children: [
                            InteractiveArtistText(
                              artistString: track.artist,
                              fontSize: 12,
                            ),
                            Text(
                              ' · ${track.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.textMuted, fontSize: 12),
                            ),
                          ],
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
                if (jam.isHost ||
                    (jam.localParticipant?.canManageQueue ?? false))
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
                if (jam.isHost ||
                    (jam.localParticipant?.canManageQueue ?? false))
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
                if (jam.isGuest &&
                    !(jam.localParticipant?.canManageQueue ?? false))
                  ListTile(
                    enabled: false,
                    leading: Icon(Icons.lock_outline_rounded,
                        color: context.textMuted),
                    title: Text(
                      'La cola está controlada por el anfitrión',
                      style: TextStyle(color: context.textMuted, fontSize: 13),
                    ),
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

              // 1. Añadir a Playlist
              ListTile(
                leading: Icon(Icons.playlist_add_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Añadir a una playlist',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: context.textMuted, size: 20),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddToPlaylistSheet(context, nav, track);
                },
              ),

              // 2. Eliminar de esta playlist
              if (playlistId != null && playlistId!.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.playlist_remove_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Eliminar de esta playlist',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final bg =
                        context.read<ThemeController>().active.bgElevated;
                    Navigator.of(context).pop();
                    try {
                      // Obtener las pistas de la playlist y encontrar el índice
                      final tracks =
                          await nav.getPlaylistTracks(playlistId!);
                      final index =
                          tracks.indexWhere((t) => t.id == track.id);
                      if (index >= 0) {
                        await nav.updatePlaylist(
                          playlistId: playlistId!,
                          songIndexesToRemove: [index],
                        );
                        if (messenger.mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: Text(
                                '"${track.title}" eliminada de la playlist'),
                            backgroundColor: bg,
                          ));
                        }
                      }
                    } catch (e) {
                      if (messenger.mounted) {
                        messenger.showSnackBar(SnackBar(
                          content: Text(e
                              .toString()
                              .replaceFirst('Exception: ', '')),
                          backgroundColor: bg,
                        ));
                      }
                    }
                  },
                ),

              // 3. Guardar en Tus me gusta
              ListTile(
                leading: Icon(
                  isStarred ? Icons.favorite : Icons.favorite_border,
                  color: isStarred ? context.accent : context.textSecondary,
                ),
                title: Text(
                  isStarred
                      ? 'Quitar de Tus me gusta'
                      : 'Guardar en Tus me gusta',
                  style: TextStyle(
                    color: isStarred ? context.accent : context.textPrimary,
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  nav.toggleStar(track);
                  Navigator.of(context).pop();
                },
              ),

              // 4. Añadir a la fila
              if (!jam.inJam)
                ListTile(
                  leading: Icon(Icons.queue_music_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Añadir a la fila',
                    style:
                        TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    final bg =
                        context.read<ThemeController>().active.bgElevated;
                    Navigator.of(context).pop();
                    player.addToQueue(track);
                    messenger.showSnackBar(
                      SnackBar(
                        content:
                            Text('"${track.title}" añadida a la cola'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: bg,
                      ),
                    );
                  },
                ),

              Divider(color: context.bgElevated, height: 1),

              // 5. Apagado automático (sleep timer)
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

              // 6. Ir a radio de la canción
              ListTile(
                leading: Icon(Icons.radio_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Ir a radio de la canción',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Ir a radio de la canción (Próximamente)'),
                    backgroundColor: context.read<ThemeController>().active.bgElevated,
                  ));
                },
              ),

              Divider(color: context.bgElevated, height: 1),

              // 7. Ir al artista
              ListTile(
                leading: Icon(Icons.person_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Ir al artista',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _navigateToArtist(context, nav, track);
                },
              ),

              // 8. Ir al álbum
              ListTile(
                leading: Icon(Icons.album_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Ir al álbum',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                subtitle: Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _navigateToAlbum(context, nav, track);
                },
              ),

              Divider(color: context.bgElevated, height: 1),

              // 9. Compartir con la comunidad
              ListTile(
                leading: Icon(Icons.people_outline_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Compartir con la comunidad',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                onTap: () async {
                  final nav = context.read<NavidromeService>();
                  final messenger = ScaffoldMessenger.of(context);
                  final bg =
                      context.read<ThemeController>().active.bgElevated;
                  Navigator.of(context).pop();
                  // Enviar link de canción al chat de comunidad
                  final msg =
                      '🎵 [TRACK:${track.id}:${track.title}:${track.artist}]';
                  final ok = await nav.addChatMessage(msg);
                  if (ok && context.mounted) {
                    ServerActivityPanel.show(context);
                  } else if (!ok && messenger.mounted) {
                    messenger.showSnackBar(SnackBar(
                      content:
                          const Text('No se pudo compartir en la comunidad'),
                      backgroundColor: bg,
                    ));
                  }
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
                                // Verificar si la canción ya está antes de añadir.
                                try {
                                  final existing =
                                      await nav.getPlaylistTracks(p.id);
                                  final alreadyIn =
                                      existing.any((t) => t.id == track.id);
                                  if (alreadyIn) {
                                    if (messenger.mounted) {
                                      messenger.showSnackBar(SnackBar(
                                        content: Text(
                                            '"${track.title}" ya está en "${p.name}"'),
                                        backgroundColor: bg,
                                      ));
                                    }
                                    return;
                                  }
                                  await nav.updatePlaylist(
                                    playlistId: p.id,
                                    songIdsToAdd: [track.id],
                                  );
                                  if (messenger.mounted) {
                                    messenger.showSnackBar(SnackBar(
                                      content: Text('Añadida a "${p.name}"'),
                                      backgroundColor: bg,
                                    ));
                                  }
                                } catch (e) {
                                  if (messenger.mounted) {
                                    messenger.showSnackBar(SnackBar(
                                      content: Text(e
                                          .toString()
                                          .replaceFirst('Exception: ', '')),
                                      backgroundColor: bg,
                                    ));
                                  }
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

  Future<void> _navigateToArtist(BuildContext context, NavidromeService nav, Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    final bg = context.read<ThemeController>().active.bgElevated;

    try {
      final artists = await nav.getArtists();
      Artist? targetArtist;
      for (final a in artists) {
        if (a['id'] == track.artistId ||
            a['name'].toString().toLowerCase() == track.artist.toLowerCase()) {
          targetArtist = Artist.fromJson(a as Map<String, dynamic>,
              coverArtUrl: a['coverArt'] as String?);
          break;
        }
      }

      if (targetArtist != null && context.mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ArtistScreen(artist: targetArtist!)));
      } else {
        messenger.showSnackBar(SnackBar(
          content: const Text('No se pudo encontrar al artista principal.'),
          backgroundColor: bg,
        ));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Error al buscar al artista.'),
        backgroundColor: bg,
      ));
    }
  }

  Future<void> _navigateToAlbum(BuildContext context, NavidromeService nav, Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    final bg = context.read<ThemeController>().active.bgElevated;

    if (track.albumId == null || track.albumId!.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Esta canción no tiene un álbum asociado.'),
        backgroundColor: bg,
      ));
      return;
    }

    try {
      final album = await nav.getAlbumInfo(track.albumId!);
      if (context.mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: const Text('No se pudo encontrar el álbum.'),
        backgroundColor: bg,
      ));
    }
  }
}
