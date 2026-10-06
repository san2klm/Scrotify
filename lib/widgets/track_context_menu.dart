import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/karaoke_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/album_detail_screen.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/offline_cache_service.dart';
import '../services/offline_download_manager.dart';
import '../services/local_music_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';
import 'interactive_artist_text.dart';
import 'rating_stars.dart';
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
              const SizedBox(height: 12),
              // Calificación 1 a 5 estrellas (Fase 8)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Puntuación',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    RatingStars(
                      rating: nav.getTrackRating(track.id) != 0
                          ? nav.getTrackRating(track.id)
                          : track.userRating,
                      interactive: true,
                      size: 24,
                      color: context.accent,
                      onRatingChanged: (newRating) {
                        final current = nav.getTrackRating(track.id) != 0
                            ? nav.getTrackRating(track.id)
                            : track.userRating;
                        final targetRating =
                            current == newRating ? 0 : newRating;
                        nav.setRating(track.id, targetRating);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: context.bgElevated, height: 1),
              const SizedBox(height: 8),

              // Acciones Jam (si hay Jam activo)
              if (jam.inJam) ...[
                if (jam.isHost ||
                    (jam.localParticipant?.canManageQueue ?? false)) ...[
                  () {
                    final inJamQueue =
                        jam.queue.any((qi) => qi.track.id == track.id);
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (inJamQueue ? context.accent2 : context.accent)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.speaker_group_rounded,
                            color:
                                inJamQueue ? context.accent2 : context.accent,
                            size: 20),
                      ),
                      title: Text(
                        inJamQueue
                            ? 'Ya está en la cola Jam'
                            : 'Añadir a la cola Jam',
                        style: TextStyle(
                          color: inJamQueue ? context.accent2 : context.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        inJamQueue
                            ? 'Esta pista ya figura en la cola compartida'
                            : 'Compartir con los ${jam.participants.length} oyentes de la sesión',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 11),
                      ),
                      onTap: () {
                        final messenger = ScaffoldMessenger.of(context);
                        final bg =
                            context.read<ThemeController>().active.bgElevated;
                        Navigator.of(context).pop();
                        jam.addTrackToJam(track);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(inJamQueue
                                ? '"${track.title}" ya figuraba en la cola Jam'
                                : (jam.isGuest
                                    ? 'Solicitud enviada para añadir "${track.title}" a la cola Jam'
                                    : '"${track.title}" añadida a la cola Jam')),
                            duration: const Duration(seconds: 2),
                            backgroundColor: bg,
                          ),
                        );
                      },
                    );
                  }(),
                ],
                if (jam.isHost ||
                    (jam.localParticipant?.canManageQueue ?? false))
                  ListTile(
                    leading: Icon(Icons.playlist_play_rounded,
                        color: context.textSecondary),
                    title: Text(
                      'Reproducir siguiente en Jam',
                      style:
                          TextStyle(color: context.textPrimary, fontSize: 14),
                    ),
                    onTap: () {
                      final messenger = ScaffoldMessenger.of(context);
                      final bg =
                          context.read<ThemeController>().active.bgElevated;
                      Navigator.of(context).pop();
                      jam.addTrackToJam(track, playNext: true);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(jam.isGuest
                              ? 'Solicitud enviada para reproducir "${track.title}" a continuación'
                              : '"${track.title}" sonará a continuación en el Jam'),
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
                      final tracks = await nav.getPlaylistTracks(playlistId!);
                      final index = tracks.indexWhere((t) => t.id == track.id);
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
                          content: Text(
                              e.toString().replaceFirst('Exception: ', '')),
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

              // Acción de descarga sin conexión (solo cuando no está en Jam)
              if (!jam.inJam)
                TrackOfflineSection(
                  track: track,
                  serverScope: nav.serverScope,
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
                    ? Icon(Icons.check_rounded, color: context.accent, size: 20)
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
                leading:
                    Icon(Icons.radio_rounded, color: context.textSecondary),
                title: Text(
                  'Ir a radio de la canción',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        const Text('Ir a radio de la canción (Próximamente)'),
                    backgroundColor:
                        context.read<ThemeController>().active.bgElevated,
                  ));
                },
              ),

              Divider(color: context.bgElevated, height: 1),

              // 7. Ir al artista
              ListTile(
                leading:
                    Icon(Icons.person_rounded, color: context.textSecondary),
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
                leading:
                    Icon(Icons.album_rounded, color: context.textSecondary),
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
                  final bg = context.read<ThemeController>().active.bgElevated;
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
            final options =
                <({String label, Duration? duration, bool isEndOfTrack})>[
              (label: 'Desactivado', duration: null, isEndOfTrack: false),
              (label: 'Fin de la canción', duration: null, isEndOfTrack: true),
              (
                label: 'En 5 minutos',
                duration: const Duration(minutes: 5),
                isEndOfTrack: false
              ),
              (
                label: 'En 15 minutos',
                duration: const Duration(minutes: 15),
                isEndOfTrack: false
              ),
              (
                label: 'En 30 minutos',
                duration: const Duration(minutes: 30),
                isEndOfTrack: false
              ),
              (
                label: 'En 45 minutos',
                duration: const Duration(minutes: 45),
                isEndOfTrack: false
              ),
              (
                label: 'En 1 hora',
                duration: const Duration(hours: 1),
                isEndOfTrack: false
              ),
              (
                label: 'En 1 hora y 30 minutos',
                duration: const Duration(minutes: 90),
                isEndOfTrack: false,
              ),
            ];

            bool isSelected(
                ({String label, Duration? duration, bool isEndOfTrack}) opt) {
              if (opt.isEndOfTrack) {
                return player.isSleepTimerEndOfTrack;
              }
              if (opt.duration == null) {
                return !player.hasSleepTimer;
              }
              if (player.isSleepTimerEndOfTrack) return false;
              final rem = player.sleepRemaining;
              if (rem == null) return false;
              // Tolerancia de 2 min para marcar la opción activa.
              return (rem - opt.duration!).abs() < const Duration(minutes: 2);
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
                          style: TextStyle(color: context.accent, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (ctx, i) {
                          final opt = options[i];
                          final selected = isSelected(opt);
                          return ListTile(
                            leading: Icon(
                              opt.duration == null && !opt.isEndOfTrack
                                  ? Icons.timer_off_outlined
                                  : (opt.isEndOfTrack
                                      ? Icons.music_note_rounded
                                      : Icons.timer_outlined),
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
                              final messenger = ScaffoldMessenger.of(context);
                              final bg = context
                                  .read<ThemeController>()
                                  .active
                                  .bgElevated;
                              Navigator.of(context).pop();
                              if (opt.isEndOfTrack) {
                                player.setSleepTimerEndOfTrack();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                        'La música se pausará al terminar la canción actual'),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: bg,
                                  ),
                                );
                              } else if (opt.duration == null) {
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
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.tune_rounded,
                          color: context.textSecondary),
                      title: Text(
                        'Personalizado...',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _showCustomSleepTimerDialog(parentContext, player);
                      },
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

  void _showCustomSleepTimerDialog(
      BuildContext parentContext, PlayerController player) {
    final theme = parentContext.read<ThemeController>().active;
    final controller = TextEditingController(text: '20');
    showDialog<void>(
      context: parentContext,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.bgApp,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.bgElevated),
          ),
          title: Text(
            'Temporizador personalizado',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresa los minutos tras los cuales se pausará la reproducción:',
                style: TextStyle(color: theme.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: TextStyle(color: theme.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Minutos',
                  labelStyle: TextStyle(color: theme.textMuted),
                  suffixText: 'min',
                  suffixStyle: TextStyle(color: theme.accent),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: theme.bgElevated),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: theme.bgElevated),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: theme.accent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancelar', style: TextStyle(color: theme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                final mins = int.tryParse(controller.text.trim());
                if (mins != null && mins > 0) {
                  Navigator.of(ctx).pop();
                  player.setSleepTimer(Duration(minutes: mins));
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(
                      content: Text('La música se pausará en $mins minutos'),
                      backgroundColor: theme.bgElevated,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Programar'),
            ),
          ],
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
                        padding: const EdgeInsets.all(20),
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
                                final messenger = ScaffoldMessenger.of(context);
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

  Future<void> _navigateToArtist(
      BuildContext context, NavidromeService nav, Track track) async {
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
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ArtistScreen(artist: targetArtist!)));
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

  Future<void> _navigateToAlbum(
      BuildContext context, NavidromeService nav, Track track) async {
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

/// Estados de UI para la acción de descarga sin conexión de una pista.
enum TrackOfflineUiState {
  notDownloaded,
  queued,
  downloading,
  paused,
  failed,
  availableOffline,
}

/// Representación del estado resuelto para la acción de descarga sin conexión.
class TrackOfflineActionState {
  final TrackOfflineUiState status;
  final DownloadTask? task;
  final double? progress;
  final String? failureMessage;

  const TrackOfflineActionState({
    required this.status,
    this.task,
    this.progress,
    this.failureMessage,
  });

  /// Resuelve el estado de UI considerando tanto el estado del gestor de descargas
  /// como la verificación real de caché C1.
  ///
  /// Un estado completado en el gestor por sí solo NO se considera prueba de
  /// disponibilidad sin conexión; se requiere [hasVerifiedCache] == true.
  static TrackOfflineActionState resolve({
    required DownloadTask? task,
    required bool hasVerifiedCache,
  }) {
    if (task != null && task.isNonTerminal) {
      switch (task.status) {
        case DownloadTaskStatus.queued:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.queued,
            task: task,
            progress: task.progress,
          );
        case DownloadTaskStatus.downloading:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.downloading,
            task: task,
            progress: task.progress,
          );
        case DownloadTaskStatus.paused:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.paused,
            task: task,
            progress: task.progress,
          );
        case DownloadTaskStatus.failed:
          return TrackOfflineActionState(
            status: TrackOfflineUiState.failed,
            task: task,
            progress: task.progress,
            failureMessage: task.failureMessage,
          );
        case DownloadTaskStatus.completed:
        case DownloadTaskStatus.cancelled:
          break;
      }
    }

    if (hasVerifiedCache) {
      return TrackOfflineActionState(
        status: TrackOfflineUiState.availableOffline,
        task: task,
      );
    }

    // Sin tarea, cancelada, o completada pero sin registro verificado en caché
    return const TrackOfflineActionState(
      status: TrackOfflineUiState.notDownloaded,
    );
  }
}

/// Sección interactiva de acciones y estado de descarga sin conexión para una pista.
class TrackOfflineSection extends StatefulWidget {
  final Track track;
  final String? serverScope;
  final OfflineDownloadManager? downloadManager;
  final OfflineCacheService? cacheService;

  const TrackOfflineSection({
    super.key,
    required this.track,
    this.serverScope,
    this.downloadManager,
    this.cacheService,
  });

  @override
  State<TrackOfflineSection> createState() => _TrackOfflineSectionState();
}

class _TrackOfflineSectionState extends State<TrackOfflineSection> {
  Future<OfflineCacheEntry?>? _lookupFuture;
  DownloadTaskStatus? _lastTaskStatus;
  OfflineCacheService? _cachedService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = widget.cacheService ??
        Provider.of<OfflineCacheService?>(context, listen: false);
    if (service != _cachedService) {
      _cachedService = service;
      _triggerLookup();
    }
  }

  @override
  void didUpdateWidget(TrackOfflineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.serverScope != widget.serverScope ||
        oldWidget.cacheService != widget.cacheService) {
      _cachedService = widget.cacheService ?? _cachedService;
      _triggerLookup();
    }
  }

  void _triggerLookup() {
    final scope = widget.serverScope;
    final service = widget.cacheService ?? _cachedService;
    if (scope != null && scope.trim().isNotEmpty && service != null) {
      _lookupFuture = service.lookup(scope, widget.track.id);
    } else {
      _lookupFuture = Future.value(null);
    }
  }

  Future<void> _handleQueue(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null) return;
    if (serverScope == null || serverScope.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('No hay un servidor conectado para descargar.'),
          backgroundColor: bg,
        ),
      );
      return;
    }

    try {
      final music = Provider.of<LocalMusicService?>(context, listen: false);
      if (music != null) {
        await music.download(manager, track, serverScope);
      } else {
        await manager.queueTrack(track, serverScope: serverScope);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Descarga añadida para "${track.title}"'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al solicitar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handlePause(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.pauseTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al pausar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handleResume(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.resumeTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al reanudar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handleRetry(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.retryTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al reintentar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  Future<void> _handleCancel(
    OfflineDownloadManager? manager,
    String? serverScope,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Provider.of<ThemeController?>(context, listen: false);
    final bg = theme?.active.bgElevated ?? const Color(0xFF282828);

    if (manager == null || serverScope == null || serverScope.trim().isEmpty) {
      return;
    }

    try {
      await manager.cancelTask(serverScope, track.id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Error al cancelar la descarga'),
            duration: const Duration(seconds: 2),
            backgroundColor: bg,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager =
        widget.downloadManager ?? Provider.of<OfflineDownloadManager?>(context);

    if (manager != null) {
      return AnimatedBuilder(
        animation: manager,
        builder: (context, _) => _buildWithManager(context, manager),
      );
    }
    return _buildWithManager(context, null);
  }

  Widget _buildWithManager(
    BuildContext context,
    OfflineDownloadManager? manager,
  ) {
    final scope = widget.serverScope;
    final task = (scope != null && manager != null)
        ? manager.getTask(scope, widget.track.id)
        : null;

    if (task?.status != _lastTaskStatus) {
      if (task?.status == DownloadTaskStatus.completed) {
        _triggerLookup();
      }
      _lastTaskStatus = task?.status;
    }

    return FutureBuilder<OfflineCacheEntry?>(
      future: _lookupFuture,
      builder: (context, snapshot) {
        final hasVerifiedCache = snapshot.data != null;
        final uiState = TrackOfflineActionState.resolve(
          task: task,
          hasVerifiedCache: hasVerifiedCache,
        );

        return _buildActionTiles(context, manager, scope, uiState);
      },
    );
  }

  Widget _buildActionTiles(
    BuildContext context,
    OfflineDownloadManager? manager,
    String? scope,
    TrackOfflineActionState uiState,
  ) {
    final theme = Provider.of<ThemeController?>(context)?.active;
    final accent = theme?.accent ?? Theme.of(context).colorScheme.primary;
    final textPrimary =
        theme?.textPrimary ?? Theme.of(context).colorScheme.onSurface;
    final textSecondary = theme?.textSecondary ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    final textMuted = theme?.textMuted ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);

    switch (uiState.status) {
      case TrackOfflineUiState.notDownloaded:
        return ListTile(
          leading: Icon(Icons.download_rounded, color: textSecondary),
          title: Text(
            'Descargar sin conexión',
            style: TextStyle(color: textPrimary, fontSize: 14),
          ),
          onTap: () => _handleQueue(manager, scope, widget.track),
        );

      case TrackOfflineUiState.queued:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: false,
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textMuted,
                ),
              ),
              title: Text(
                'En cola de descarga',
                style: TextStyle(color: textMuted, fontSize: 14),
              ),
            ),
            ListTile(
              leading: Icon(Icons.pause_circle_outline_rounded,
                  color: textSecondary),
              title: Text(
                'Pausar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handlePause(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.downloading:
        final progress = uiState.progress;
        final progressPercent =
            progress != null ? (progress * 100).toInt() : null;
        final titleText = progressPercent != null
            ? 'Descargando ($progressPercent%)'
            : 'Descargando...';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: false,
              leading: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
              title: Text(
                titleText,
                style: TextStyle(color: textMuted, fontSize: 14),
              ),
            ),
            ListTile(
              leading: Icon(Icons.pause_circle_outline_rounded,
                  color: textSecondary),
              title: Text(
                'Pausar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handlePause(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.paused:
        final progress = uiState.progress;
        final progressPercent =
            progress != null ? (progress * 100).toInt() : null;
        final subtitleText = progressPercent != null
            ? 'Pausada ($progressPercent%)'
            : 'Descarga pausada';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.play_circle_outline_rounded, color: accent),
              title: Text(
                'Reanudar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              subtitle: Text(
                subtitleText,
                style: TextStyle(color: textMuted, fontSize: 11),
              ),
              onTap: () => _handleResume(manager, scope, widget.track),
            ),
            ListTile(
              leading: Icon(Icons.cancel_outlined, color: textSecondary),
              title: Text(
                'Cancelar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handleCancel(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.failed:
        final failureMsg = uiState.failureMessage;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.refresh_rounded, color: accent),
              title: Text(
                'Reintentar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              subtitle: failureMsg != null && failureMsg.isNotEmpty
                  ? Text(
                      failureMsg,
                      style: TextStyle(color: textMuted, fontSize: 11),
                    )
                  : null,
              onTap: () => _handleRetry(manager, scope, widget.track),
            ),
            ListTile(
              leading: Icon(Icons.cancel_outlined, color: textSecondary),
              title: Text(
                'Cancelar descarga',
                style: TextStyle(color: textPrimary, fontSize: 14),
              ),
              onTap: () => _handleCancel(manager, scope, widget.track),
            ),
          ],
        );

      case TrackOfflineUiState.availableOffline:
        return ListTile(
          enabled: false,
          leading: Icon(Icons.check_circle_rounded, color: accent),
          title: Text(
            'Disponible sin conexión',
            style: TextStyle(color: textMuted, fontSize: 14),
          ),
          subtitle: Text(
            'Guardada en este dispositivo',
            style: TextStyle(color: textMuted, fontSize: 11),
          ),
          onTap: null,
        );
    }
  }
}
