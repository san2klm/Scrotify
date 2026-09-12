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
  late int _currentIndex;

  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  LoopMode _repeatMode = LoopMode.off;

  Track get _track => widget.tracks[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _player = AudioPlayer();
    _listenPlayer();
    _setupPlaylist();
  }

  void _listenPlayer() {
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying =
            state.playing && state.processingState != ProcessingState.completed;
      });
    });

    _player.currentIndexStream.listen((idx) {
      if (idx != null && idx != _currentIndex && mounted) {
        setState(() => _currentIndex = idx);
      }
    });
  }

  Future<void> _setupPlaylist() async {
    final service = context.read<NavidromeService>();
    final sources = widget.tracks
        .map((t) => AudioSource.uri(Uri.parse(service.getStreamUrl(t.id))))
        .toList();

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: _currentIndex,
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
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> _toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    await _player.setShuffleModeEnabled(_shuffleEnabled);
    setState(() {});
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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialDuration = Duration(seconds: int.tryParse(_track.duration) ?? 0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              SizedBox(
                height: 240,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _track.albumArtUrl != null
                        ? Image.network(
                            _track.albumArtUrl!,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.music_note,
                            size: 60, color: Colors.grey),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                _track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 24),

              Row(
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
                    icon: const Icon(Icons.skip_next,
                        color: Colors.white, size: 34),
                    onPressed: _skipNext,
                  ),
                  IconButton(
                    icon: Icon(
                      _repeatMode == LoopMode.one
                          ? Icons.repeat_one
                          : Icons.repeat,
                      size: 22,
                      color: _repeatMode != LoopMode.off
                          ? Colors.greenAccent
                          : Colors.white,
                    ),
                    onPressed: _toggleRepeat,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snapshot) {
                  final duration = _player.duration ?? initialDuration;
                  final position = snapshot.data ?? Duration.zero;
                  final progress = duration.inMilliseconds == 0
                      ? 0.0
                      : (position.inMilliseconds / duration.inMilliseconds)
                          .clamp(0.0, 1.0);

                  return Column(
                    children: [
                      _Waveform(progress: progress, barCount: 44, height: 40),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _format(position),
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
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  final double progress;
  final int barCount;
  final double height;

  const _Waveform({
    required this.progress,
    required this.barCount,
    required this.height,
  });

  static const _barHeights = <double>[
    0.40, 0.70, 0.50, 0.90, 0.60, 0.80, 0.40, 1.00, 0.55, 0.75,
    0.35, 0.85, 0.60, 0.45, 0.70, 0.90, 0.50, 0.65, 0.80, 0.40,
    0.95, 0.55, 0.70, 0.50, 0.60, 0.85, 0.45, 0.70, 0.60, 0.40,
    0.80, 0.55, 0.90, 0.65, 0.50, 0.75, 0.60, 0.85, 0.45, 0.70,
    0.55, 0.60, 0.80, 0.50,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < barCount; i++)
            Container(
              width: 3,
              height: height * _barHeights[i % _barHeights.length],
              decoration: BoxDecoration(
                color: (i / barCount) <= progress ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}