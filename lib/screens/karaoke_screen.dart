import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lyrics_service.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/cover_fallback_service.dart';
import '../services/local_music_service.dart';
import '../utils/app_colors.dart';
import '../widgets/cover_art.dart';

/// Pantalla inmersiva de Modo Karaoke: letra de gran tamaño sincronizada
/// con efecto de avance y control de reducción de voz (en Desktop).
class KaraokeScreen extends StatefulWidget {
  const KaraokeScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const KaraokeScreen(),
      ),
    );
  }

  @override
  State<KaraokeScreen> createState() => _KaraokeScreenState();
}

class _KaraokeScreenState extends State<KaraokeScreen> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int _lastIndex = -1;
  double? _dragValue;
  Future<LyricsResult?>? _future;
  String? _trackId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = Provider.of<PlayerController>(context, listen: false);
      if (PlayerController.isVocalReductionSupported && !player.karaokeMode) {
        player.setKaraokeMode(true);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<LyricsResult?> _futureFor(BuildContext context, Track track) {
    if (_future == null || _trackId != track.id) {
      _trackId = track.id;
      _lastIndex = -1;
      final nav = Provider.of<NavidromeService>(context, listen: false);
      _future = LyricsService.fetch(nav: nav, track: track);
    }
    return _future!;
  }

  int _indexFor(List<LyricLine> lines, Duration pos) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (pos >= lines[i].start) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _scrollToIndex(int index) {
    if (!_scroll.hasClients || index < 0 || index == _lastIndex) return;
    _lastIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final key = _itemKeys[index];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.45,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) {
          return Scaffold(
            backgroundColor: context.bgApp,
            body: Center(
              child: Text(
                'No hay ninguna canción en reproducción',
                style: TextStyle(color: context.textSecondary),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: context.bgDeep,
          body: Stack(
            children: [
              // Fondo ambiental desenfocado
              Positioned.fill(
                child: FutureBuilder<String?>(
                  future: () async {
                    final nav = context.read<NavidromeService?>();
                    final local = context
                        .read<LocalMusicService?>()
                        ?.artworkForMetadata(nav?.serverScope,
                            artist: track.artist,
                            album: track.album,
                            title: track.title);
                    if (local != null) return Uri.file(local).toString();
                    if (nav?.offlineMode == true &&
                        Uri.tryParse(track.albumArtUrl ?? '')?.scheme !=
                            'file') {
                      return null;
                    }
                    if (track.albumArtUrl != null &&
                        track.albumArtUrl!.isNotEmpty) {
                      return track.albumArtUrl;
                    }
                    if (track.artist.isNotEmpty ||
                        track.album.isNotEmpty ||
                        track.title.isNotEmpty) {
                      return CoverFallbackService.instance.findCover(
                        artist: track.artist,
                        album: track.album,
                        title: track.title,
                        size: 300,
                      );
                    }
                    return null;
                  }(),
                  builder: (context, snapshot) {
                    final url = snapshot.data;
                    if (url == null || url.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return RepaintBoundary(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                        child: Image(
                          image: ResizeImage(CoverArt.imageProvider(url),
                              width: 128),
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          color: context.textPrimary.withValues(alpha: 0.18),
                          colorBlendMode: BlendMode.modulate,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // Barra superior
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: 'Cerrar',
                            icon: Icon(Icons.close_rounded,
                                color: context.textPrimary, size: 28),
                            onPressed: () {
                              if (PlayerController.isVocalReductionSupported &&
                                  player.karaokeMode) {
                                player.setKaraokeMode(false);
                              }
                              Navigator.of(context).pop();
                            },
                          ),
                          Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mic_external_on_rounded,
                                      color: context.accent, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'MODO KARAOKE',
                                    style: TextStyle(
                                      color: context.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${track.title} · ${track.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          // Botón reductor de voz (solo Desktop)
                          if (PlayerController.isVocalReductionSupported)
                            IconButton(
                              tooltip: player.vocalReduction
                                  ? 'Voz reducida (activo)'
                                  : 'Voz original',
                              icon: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: player.vocalReduction
                                      ? context.accent.withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: player.vocalReduction
                                        ? context.accent
                                        : context.themeBorder,
                                  ),
                                ),
                                child: Icon(
                                  player.vocalReduction
                                      ? Icons.voice_over_off_rounded
                                      : Icons.record_voice_over_rounded,
                                  color: player.vocalReduction
                                      ? context.accent
                                      : context.textMuted,
                                  size: 20,
                                ),
                              ),
                              onPressed: player.toggleVocalReduction,
                            )
                          else
                            const SizedBox(width: 48),
                        ],
                      ),
                    ),

                    // Área central con letra en grande
                    Expanded(
                      child: FutureBuilder<LyricsResult?>(
                        future: _futureFor(context, track),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.accent,
                              ),
                            );
                          }
                          final result = snap.data;
                          if (result == null || result.lines.isEmpty) {
                            return Center(
                              child: Text(
                                'No se encontró letra disponible para esta canción',
                                style: TextStyle(
                                    color: context.textSecondary, fontSize: 16),
                              ),
                            );
                          }
                          if (result.instrumental) {
                            return Center(
                              child: Text(
                                '♪ Pista Instrumental ♪',
                                style: TextStyle(
                                  color: context.accent,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }

                          return StreamBuilder<Duration>(
                            stream: player.positionStream,
                            initialData: player.position,
                            builder: (context, posSnap) {
                              final pos = posSnap.data ?? Duration.zero;
                              final index = _indexFor(result.lines, pos);
                              _scrollToIndex(index);

                              return ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 80),
                                itemCount: result.lines.length,
                                itemBuilder: (context, i) {
                                  final active = i == index;
                                  final past = i < index;
                                  return Padding(
                                    key: _itemKeys.putIfAbsent(
                                        i, () => GlobalKey()),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: AnimatedDefaultTextStyle(
                                      duration:
                                          const Duration(milliseconds: 250),
                                      style: TextStyle(
                                        color: active
                                            ? context.accent
                                            : past
                                                ? Colors.white
                                                    .withValues(alpha: 0.35)
                                                : Colors.white
                                                    .withValues(alpha: 0.8),
                                        fontSize: active ? 32 : 22,
                                        fontWeight: active
                                            ? FontWeight.w900
                                            : FontWeight.w600,
                                        height: 1.3,
                                        shadows: active
                                            ? [
                                                Shadow(
                                                  color: context.accent
                                                      .withValues(alpha: 0.5),
                                                  blurRadius: 16,
                                                )
                                              ]
                                            : const [
                                                Shadow(
                                                  color: Colors.black54,
                                                  blurRadius: 4,
                                                )
                                              ],
                                      ),
                                      child: Text(
                                        result.lines[i].text,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // Barra de progreso y controles inferiores
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Column(
                        children: [
                          StreamBuilder<Duration>(
                            stream: player.positionStream,
                            builder: (context, snapshot) {
                              final trackTime = Duration(
                                  seconds: int.tryParse(
                                          player.currentTrack?.duration ??
                                              '') ??
                                      0);
                              final duration = player.duration ?? trackTime;
                              final position = snapshot.data ?? Duration.zero;
                              final maxMs = duration.inMilliseconds == 0
                                  ? 1.0
                                  : duration.inMilliseconds.toDouble();
                              final currentMs = (_dragValue ??
                                      position.inMilliseconds.toDouble())
                                  .clamp(0.0, maxMs);

                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      activeTrackColor: context.accent,
                                      inactiveTrackColor:
                                          context.waveformUnplayed,
                                      thumbColor: context.accent,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 5),
                                      overlayColor: context.accentDim,
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: maxMs,
                                      value: currentMs,
                                      onChanged: (v) =>
                                          setState(() => _dragValue = v),
                                      onChangeEnd: (v) async {
                                        await player.seek(
                                            Duration(milliseconds: v.round()));
                                        if (mounted) {
                                          setState(() => _dragValue = null);
                                        }
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _format(Duration(
                                              milliseconds: currentMs.round())),
                                          style: TextStyle(
                                              color: context.textSecondary,
                                              fontSize: 11),
                                        ),
                                        Text(
                                          _format(duration),
                                          style: TextStyle(
                                              color: context.textSecondary,
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Anterior',
                                icon: Icon(Icons.skip_previous_rounded,
                                    color: context.textPrimary, size: 30),
                                onPressed: player.skipPrevious,
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                tooltip: 'Pausar / Reproducir',
                                iconSize: 52,
                                icon: Icon(
                                  player.playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_filled_rounded,
                                  color: context.accent,
                                ),
                                onPressed: player.togglePlay,
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                tooltip: 'Siguiente',
                                icon: Icon(Icons.skip_next_rounded,
                                    color: context.textPrimary, size: 30),
                                onPressed: player.skipNext,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
