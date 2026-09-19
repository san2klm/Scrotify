import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lyrics_service.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';

/// Panel lateral de karaoke para pantalla grande.
///
/// No muestra la letra completa: muestra la línea que sigue la canción
/// (anterior atenuada + actual destacada + siguientes).
class LyricsFollowPanel extends StatefulWidget {
  final Track track;

  const LyricsFollowPanel({super.key, required this.track});

  @override
  State<LyricsFollowPanel> createState() => _LyricsFollowPanelState();
}

class _LyricsFollowPanelState extends State<LyricsFollowPanel> {
  Future<LyricsResult?>? _future;
  String? _trackId;

  Future<LyricsResult?> _futureFor(BuildContext context) {
    if (_future == null || _trackId != widget.track.id) {
      _trackId = widget.track.id;
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

  /// Transición fluida compartida: fade + subida leve + escala sutil,
  /// con curvas distintas al entrar/salir para que no se sienta el corte.
  Widget _fluidTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }

  Widget _fluidSwitcher({
    required String keySuffix,
    required Widget child,
    Duration duration = const Duration(milliseconds: 550),
  }) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: _fluidTransition,
      child: KeyedSubtree(
        key: ValueKey('$keySuffix:${widget.track.id}'),
        child: child,
      ),
    );
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
                color: context.textSecondary,
              ),
            ),
          );
        }

        final result = snap.data;
        if (result == null || result.lines.isEmpty) {
          return Center(
            child: Text(
              'Sin letra disponible',
              style:
                  TextStyle(color: context.textSecondary, fontSize: 14),
            ),
          );
        }
        if (result.instrumental) {
          return Center(
            child: Text(
              '♪ Instrumental ♪',
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          );
        }

        // Sin tiempos no se puede seguir: scroll manual como fallback.
        if (!result.synced) {
          return SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              result.plainText,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 15,
                height: 1.8,
              ),
            ),
          );
        }

        return Consumer<PlayerController>(
          builder: (context, player, _) {
            return StreamBuilder<Duration>(
              stream: player.positionStream,
              initialData: player.position,
              builder: (context, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final index = _indexFor(result.lines, pos);

                String prev = '';
                String current = index >= 0
                    ? result.lines[index].text
                    : '♪ ♪ ♪';
                String next1 = (index + 1) < result.lines.length
                    ? result.lines[index + 1].text
                    : '';
                String next2 = (index + 2) < result.lines.length
                    ? result.lines[index + 2].text
                    : '';
                if (index > 0) {
                  prev = result.lines[index - 1].text;
                }

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sourcePill(result.source),
                        const SizedBox(height: 12),
                        if (prev.isNotEmpty)
                          _fluidSwitcher(
                            keySuffix: 'prev:$index',
                            duration:
                                const Duration(milliseconds: 450),
                            child: Text(
                              prev,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.textMuted,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (prev.isNotEmpty)
                          const SizedBox(height: 10),
                        // Línea actual: la que sigue la canción.
                        _fluidSwitcher(
                          keySuffix: 'current:$index',
                          duration:
                              const Duration(milliseconds: 550),
                          child: Text(
                            current,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      if (next1.isNotEmpty)
                        _fluidSwitcher(
                          keySuffix: 'next1:$index',
                          duration:
                              const Duration(milliseconds: 450),
                          child: Text(
                            next1,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (next2.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _fluidSwitcher(
                          keySuffix: 'next2:$index',
                          duration:
                              const Duration(milliseconds: 450),
                          child: Text(
                            next2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textMuted
                                  .withValues(alpha: 0.7),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                      ],
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

  Widget _sourcePill(String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.accent.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        source,
        style: TextStyle(
          color: context.accent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
