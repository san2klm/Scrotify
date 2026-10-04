/// Utilidades puras para formateo de tiempos de reproducción y tiempo restante.
library;

/// Formatea una duración de reproducción como `m:ss` (o `h:mm:ss` si es de 1 hora o más).
///
/// Si [duration] es nulo o menor/igual a cero, retorna `'0:00'`.
/// Los segundos siempre tienen relleno a 2 dígitos (`00`-`59`).
/// Si la duración es de 1 hora o más, los minutos también se rellenan a 2 dígitos.
String formatPlaybackTime(Duration? duration) {
  if (duration == null || duration <= Duration.zero) {
    return '0:00';
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final secondsPadded = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    final minutesPadded = minutes.toString().padLeft(2, '0');
    return '$hours:$minutesPadded:$secondsPadded';
  }

  return '${duration.inMinutes}:$secondsPadded';
}

/// Alias para [formatPlaybackTime].
String formatElapsed(Duration? duration) => formatPlaybackTime(duration);

/// Calcula el tiempo restante como `max(duration - position, Duration.zero)`.
///
/// Si [duration] es nulo o <= cero, retorna [Duration.zero].
/// Si [position] es nulo o negativo, se interpreta como [Duration.zero].
/// Si [position] iguala o sobrepasa a [duration], retorna [Duration.zero].
Duration calculateRemainingDuration(Duration? position, Duration? duration) {
  if (duration == null || duration <= Duration.zero) {
    return Duration.zero;
  }
  final effectivePosition =
      (position == null || position.isNegative) ? Duration.zero : position;
  final remaining = duration - effectivePosition;
  return remaining.isNegative ? Duration.zero : remaining;
}

/// Formatea el tiempo restante de reproducción como `-m:ss` (o `-h:mm:ss`).
///
/// El tiempo restante se calcula como `max(duration - position, Duration.zero)`.
/// Siempre se antepone un signo `-` explícito deliberado.
/// Duraciones agotadas, sobrepasadas, nulas o en cero retornan de forma segura `'-0:00'`.
String formatRemainingPlaybackTime(Duration? position, Duration? duration) {
  final remaining = calculateRemainingDuration(position, duration);
  return '-${formatPlaybackTime(remaining)}';
}

/// Alias para [formatRemainingPlaybackTime].
String formatRemaining(Duration? position, Duration? duration) =>
    formatRemainingPlaybackTime(position, duration);

/// Clase utilitaria con métodos estáticos para formateo de tiempos.
abstract final class PlaybackTime {
  /// Formatea la duración transcurrida como `m:ss` (o `h:mm:ss`).
  static String formatElapsed(Duration? duration) =>
      formatPlaybackTime(duration);

  /// Alias de [formatElapsed].
  static String format(Duration? duration) => formatPlaybackTime(duration);

  /// Calcula la duración restante como `max(duration - position, Duration.zero)`.
  static Duration remaining(Duration? position, Duration? duration) =>
      calculateRemainingDuration(position, duration);

  /// Formatea la duración restante como `-m:ss` (o `-h:mm:ss`).
  static String formatRemaining(Duration? position, Duration? duration) =>
      formatRemainingPlaybackTime(position, duration);
}
