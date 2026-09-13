import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';

class PlayerScreen extends StatefulWidget {
  final List<Track> tracks;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.tracks,
    required this.initialIndex,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late AudioPlayer _player;
  int? _currentTrackIndex; // Índice en la playlist (puede ser reordenada por shuffle)

  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  LoopMode _repeatMode = LoopMode.off;

  // Historial de canciones para navegación precisa
  final List<int> _playHistory = [];
  int _historyPosition = -1;

  // Valor temporal mientras el usuario arrastra el thumb de progreso
  double? _dragValue;

  Track? get _track {
    if (_currentTrackIndex == null ||
        _currentTrackIndex! < 0 ||
        _currentTrackIndex! >= widget.tracks.length) {
      return null;
    }
    return widget.tracks[_currentTrackIndex!];
  }

  @override
  void initState() {
    super.initState();
    _currentTrackIndex = widget.initialIndex;
    _player = AudioPlayer();

    // Inicializar historial con la canción actual
    _playHistory.add(widget.initialIndex);
    _historyPosition = 0;

    _listenPlayer();
    _setupPlaylist();
  }

  void _addToPlayHistory(int trackIndex) {
    // Eliminar el futuro si estamos en medio del historial (ramificación)
    if (_historyPosition < _playHistory.length - 1) {
      _playHistory.removeRange(_historyPosition + 1, _playHistory.length);
    }

    // Agregar nueva canción al historial
    _playHistory.add(trackIndex);
    _historyPosition++;
  }

  void _listenPlayer() {
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing &&
            state.processingState != ProcessingState.completed;
      });
    });

    // Escuchar cambios de índice para actualizar el historial y UI
    _player.currentIndexStream.listen((idx) {
      if (idx == null || idx < 0 || idx >= widget.tracks.length) return;

      if (!mounted) return;

      final previousIndex = _currentTrackIndex;

      // Solo agregar al historial si es una canción diferente y no estamos en shuffle
      // (con shuffle, just_audio maneja el orden internamente)
      if (!_shuffleEnabled && previousIndex != idx) {
        _addToPlayHistory(idx);
      }

      setState(() {
        _currentTrackIndex = idx;
      });
    });
  }

  Future<void> _setupPlaylist() async {
    final service = context.read<NavidromeService>();
    final sources = widget.tracks
        .map((t) => AudioSource.uri(Uri.parse(service.getStreamUrl(t.id))))
        .toList();

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: _currentTrackIndex!,
    );
    await _player.setLoopMode(_repeatMode);
    await _player.setShuffleModeEnabled(_shuffleEnabled);
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _skipNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  Future<void> _skipPrevious() async {
    // Con shuffle activado, usar el método nativo que respeta el orden aleatorio
    if (_shuffleEnabled && _player.hasPrevious) {
      await _player.seekToPrevious();
    } else if (!_shuffleEnabled && _historyPosition > 0) {
      // Sin shuffle, volver al historial de reproducción
      _historyPosition--;
      final previousIndex = _playHistory[_historyPosition];
      await _player.seek(Duration.zero, index: previousIndex);
      setState(() {
        _currentTrackIndex = previousIndex;
      });
    } else {
      // Si no hay canciones anteriores, volver al inicio de la actual
      await _player.seek(Duration.zero);
    }
  }

  Future<void> _toggleShuffle() async {
    setState(() {
      _shuffleEnabled = !_shuffleEnabled;
    });

    await _player.setShuffleModeEnabled(_shuffleEnabled);
  }

  Future<void> _toggleRepeat() async {
    _repeatMode = switch (_repeatMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(_repeatMode);
    setState(() {});
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _showContextMenu() {
    final track = _track;
    if (track == null) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Añadir a una playlist',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border, color: Colors.white),
                title: const Text('Añadir a favoritos',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline, color: Colors.white),
                title: Text('Ir al artista · ${track.artist}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.album_outlined, color: Colors.white),
                title: Text('Ir al álbum · ${track.album}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: Colors.white),
                title: const Text('Compartir',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;

    // Si no hay track disponible, mostrar pantalla de carga
    if (track == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          _buildAmbientBackground(track),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: track.albumArtUrl != null
                              ? Image.network(
                                  track.albumArtUrl!,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.grey.shade800,
                                  child: const Icon(Icons.music_note,
                                      size: 60, color: Colors.grey),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Marquee(
                    text: track.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildProgressBar(),
                  const SizedBox(height: 8),
                  _buildControls(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientBackground(Track track) {
    return Positioned.fill(
      child: track.albumArtUrl == null
          ? const SizedBox.shrink()
          : ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Image.network(
                track.albumArtUrl!,
                fit: BoxFit.cover,
                color: Colors.white.withAlpha(70),
                colorBlendMode: BlendMode.modulate,
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Colors.white, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.white),
          onPressed: _showContextMenu,
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snapshot) {
        final trackDuration = _track != null
            ? Duration(seconds: int.tryParse(_track!.duration) ?? 0)
            : Duration.zero;
        final duration = _player.duration ?? trackDuration;
        final position = snapshot.data ?? Duration.zero;

        final maxMs = duration.inMilliseconds == 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final currentMs =
            (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);

        return Column(
          children: [
            SliderTheme(
              data: const SliderThemeData(
                trackHeight: 3,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayColor: Colors.white10,
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                max: maxMs,
                value: currentMs,
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) async {
                  await _player.seek(Duration(milliseconds: v.round()));
                  if (mounted) setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(Duration(milliseconds: currentMs.round())),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    _format(duration),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle,
            size: 22,
            color: _shuffleEnabled ? Colors.greenAccent : Colors.white,
          ),
          onPressed: _toggleShuffle,
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous,
              color: Colors.white, size: 34),
          onPressed: _skipPrevious,
        ),
        IconButton(
          iconSize: 60,
          icon: Icon(
            _isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            color: Colors.white,
          ),
          onPressed: _togglePlay,
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white, size: 34),
          onPressed: _skipNext,
        ),
        IconButton(
          icon: Icon(
            _repeatMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
            size: 22,
            color: _repeatMode != LoopMode.off
                ? Colors.greenAccent
                : Colors.white,
          ),
          onPressed: _toggleRepeat,
        ),
      ],
    );
  }
}

class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _Marquee({required this.text, required this.style});

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final textWidth = painter.width;
        if (textWidth <= constraints.maxWidth) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: widget.style,
          );
        }

        const gap = 60.0;
        final oneItem = textWidth + gap;

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final offset = _controller.value * oneItem;
              return Transform.translate(
                offset: Offset(-offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: widget.style),
                    const SizedBox(width: gap),
                    Text(widget.text, style: widget.style),
                    const SizedBox(width: gap),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}