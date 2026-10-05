import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lyrics_service.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';

/// Letra sobre la portada con blur.
///
/// Prioridad de fuente (gestionada por [LyricsService]):
/// local de Navidrome > LRCLIB.
///
/// - Si la letra es sincronizada, resalta la línea actual según la posición
///   de reproducción y hace auto-scroll.
/// - Si es texto plano, la muestra centrada con scroll manual.
/// - Muestra una píldora con la fuente (Navidrome / LRCLIB).
class LyricsOverlay extends StatefulWidget {
  final Track track;

  const LyricsOverlay({super.key, required this.track});

  @override
  State<LyricsOverlay> createState() => _LyricsOverlayState();
}

class _LyricsOverlayState extends State<LyricsOverlay> {
  Future<LyricsResult?>? _future;
  String? _trackId;
  final ScrollController _scroll = ScrollController();
  int _lastIndex = -1;

  /// Índice actual según la posición de reproducción.
  int _currentIndex = -1;

  /// Claves por línea para centrar la activa justo en el medio
  /// con `Scrollable.ensureVisible`, sin depender de alturas estimadas.
  final Map<int, GlobalKey> _itemKeys = {};

  /// Seguimiento automático. Se pausa al tocar/arrastrar la letra y
  /// se reanuda a los 4s de dejarla quieta.
  bool _followEnabled = true;
  Timer? _resumeTimer;

  /// Evita que el scroll programado (animateTo) se confunda con gesto manual.
  bool _programmatic = false;

  /// Segundos quieto antes de volver a sincronizar.
  static const _resyncDelay = Duration(seconds: 4);

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<LyricsResult?> _futureFor(BuildContext context) {
    if (_future == null || _trackId != widget.track.id) {
      _trackId = widget.track.id;
      _lastIndex = -1;
      _currentIndex = -1;
      _followEnabled = true;
      _resumeTimer?.cancel();
      final nav = Provider.of<NavidromeService>(context, listen: false);
      _future = LyricsService.fetch(nav: nav, track: widget.track);
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

  void _maybeScrollTo(int index, {bool force = false}) {
    if (!_scroll.hasClients || index < 0) return;
    if (!force && (!_followEnabled || index == _lastIndex)) return;
    _lastIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // 1) Intento exacto: centra la línea activa en el medio,
      //    funcione la altura que funcione cada línea.
      final key = _itemKeys[index];
      final ctx = key?.currentContext;
      if (ctx != null) {
        _programmatic = true;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ).then((_) {
          _programmatic = false;
        }).catchError((_) {
          _programmatic = false;
        });
        return;
      }
      // 2) Fallback si la línea aún no está construida: salto estimado
      //    también centrado en el viewport.
      double viewport = 400;
      try {
        viewport = _scroll.position.viewportDimension;
      } catch (_) {}
      const lineHeight = 40.0;
      final max = _scroll.position.maxScrollExtent;
      final target =
          (index * lineHeight - viewport / 2 + lineHeight / 2).clamp(0.0, max);
      _programmatic = true;
      _scroll
          .animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      )
          .then((_) {
        _programmatic = false;
      }).catchError((_) {
        _programmatic = false;
      });
    });
  }

  void _pauseFollow() {
    if (_programmatic) return;
    _resumeTimer?.cancel();
    if (_followEnabled && mounted) {
      setState(() => _followEnabled = false);
    }
  }

  void _scheduleResume() {
    if (_programmatic) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resyncDelay, _resumeFollow);
  }

  void _resumeFollow() {
    if (!mounted) return;
    _resumeTimer?.cancel();
    setState(() => _followEnabled = true);
    // Fuerza el scroll aunque el índice no haya cambiado mientras leías.
    final idx = _currentIndex;
    _lastIndex = -1;
    _maybeScrollTo(idx, force: true);
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (_programmatic) return false;
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _pauseFollow();
    } else if (n is ScrollUpdateNotification) {
      _pauseFollow();
    } else if (n is ScrollEndNotification) {
      _scheduleResume();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsResult?>(
      future: _futureFor(context),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.textPrimary,
              ),
            ),
          );
        }

        final result = snap.data;
        if (result == null) {
          return _empty('Sin letra disponible');
        }
        if (result.instrumental) {
          return _frame(
            source: result.source,
            child: const Center(
              child: Text(
                '♪ Instrumental ♪',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        if (result.lines.isEmpty) {
          return _empty('Sin letra disponible', source: result.source);
        }

        if (!result.synced) {
          return _frame(
            source: result.source,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
              child: Text(
                result.plainText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.7,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
            ),
          );
        }

        // Sincronizada: resalta la línea actual y hace auto-scroll.
        return Consumer<PlayerController>(
          builder: (context, player, _) {
            return StreamBuilder<Duration>(
              stream: player.positionStream,
              initialData: player.position,
              builder: (context, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final index = _indexFor(result.lines, pos);
                _currentIndex = index;
                _maybeScrollTo(index);
                return _frame(
                  source: result.source,
                  paused: !_followEnabled,
                  onResume: _resumeFollow,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, top: 64, bottom: 120),
                      itemCount: result.lines.length,
                      itemBuilder: (context, i) {
                        final active = i == index;
                        final past = i < index;
                        return Padding(
                          key: _itemKeys.putIfAbsent(i, () => GlobalKey()),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            result.lines[i].text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: active
                                  ? context.accent
                                  : past
                                      ? Colors.white.withValues(alpha: 0.55)
                                      : Colors.white.withValues(alpha: 0.85),
                              fontSize: active ? 21 : 15,
                              fontWeight:
                                  active ? FontWeight.bold : FontWeight.normal,
                              height: 1.45,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 6)
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _frame({
    required String source,
    required Widget child,
    bool paused = false,
    VoidCallback? onResume,
  }) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                source,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        if (paused)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onResume,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.bgElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: context.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync, color: context.textPrimary, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Toca para sincronizar',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _empty(String text, {String? source}) {
    return Stack(
      children: [
        Center(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        if (source != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(source,
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ),
          ),
      ],
    );
  }
}
