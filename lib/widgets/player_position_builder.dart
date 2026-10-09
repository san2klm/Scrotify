import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/player_controller.dart';
import '../utils/app_visibility.dart';

/// Reconstruye [builder] con la posición de reproducción a alta frecuencia.
///
/// Por qué existe: en Android, just_audio emite `positionStream` ~1 vez por
/// segundo; en una barra angosta eso se percibe como congelada (menos de
/// 1 px por tick) y "salta" al pausar/recibir un evento. Este widget no
/// depende de la frecuencia del backend: re-ancla con cada evento y, entre
/// eventos, avanza en pasos de [tick] mientras [PlayerController.playing]
/// sea true. En pausa no avanza: la barra queda quieta, como debe ser.
class PlayerPositionBuilder extends StatefulWidget {
  final PlayerController player;

  /// Duración actual: solo se usa para no estimar más allá del final.
  final Duration duration;

  /// Paso de avance entre eventos del backend.
  final Duration tick;

  final Widget Function(BuildContext context, Duration position) builder;

  const PlayerPositionBuilder({
    super.key,
    required this.player,
    required this.duration,
    required this.builder,
    this.tick = const Duration(milliseconds: 250),
  });

  /// Avanza [current] un [step] si [playing]; si no, lo deja quieto.
  /// Limita a [0, duration]. Visible para tests.
  static Duration advance({
    required Duration current,
    required Duration step,
    required bool playing,
    Duration? duration,
  }) {
    if (!playing) return current;
    var next = current + step;
    if (next < Duration.zero) next = Duration.zero;
    if (duration != null && next > duration) next = duration;
    return next;
  }

  @override
  State<PlayerPositionBuilder> createState() => _PlayerPositionBuilderState();
}

class _PlayerPositionBuilderState extends State<PlayerPositionBuilder> {
  StreamSubscription<Duration>? _sub;
  bool _subscribedKaraoke = false;
  Duration _displayed = Duration.zero;
  Timer? _ticker;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _displayed = _safePosition();
    _subscribe();
    _ticker = Timer.periodic(widget.tick, (_) {
      // Con la app oculta nadie ve la barra: no se redibuja.
      if (!isAppVisible) {
        _hidden = true;
        return;
      }
      _ensureSubscription();
      if (_hidden) {
        // De vuelta: partir de la posición real, no de la última estimada.
        _hidden = false;
        if (mounted) setState(() => _displayed = _safePosition());
        return;
      }
      if (mounted && _safePlaying()) {
        setState(() {
          _displayed = PlayerPositionBuilder.advance(
            current: _displayed,
            step: widget.tick,
            playing: true,
            duration: widget.duration,
          );
        });
      }
    });
  }

  Duration _safePosition() {
    try {
      return widget.player.position;
    } catch (_) {
      return _displayed;
    }
  }

  bool _safePlaying() {
    try {
      return widget.player.playing;
    } catch (_) {
      return false;
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = null;
    // Lecturas defensivas: un player incompleto (fakes de test) no debe
    // romper la UI; en ese caso la barra queda congelada en cero, igual
    // que antes de este widget.
    try {
      _subscribedKaraoke = widget.player.karaokeMode;
    } catch (_) {}
    try {
      _displayed = widget.player.position;
    } catch (_) {}
    try {
      _sub = widget.player.positionStream.listen((pos) {
        _displayed = pos;
        if (mounted && isAppVisible) setState(() {});
      });
    } catch (_) {}
  }

  void _ensureSubscription() {
    // El stream cambia al alternar el modo karaoke: re-suscribir entonces.
    try {
      if (_subscribedKaraoke != widget.player.karaokeMode) {
        _subscribe();
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant PlayerPositionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _subscribe();
    } else {
      _ensureSubscription();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _displayed);
  }
}
