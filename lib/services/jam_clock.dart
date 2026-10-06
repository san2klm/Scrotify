/// Umbrales de corrección de deriva (ms) y ajuste de velocidad.
const int kJamDriftIgnoreMs = 50;
const int kJamDriftSeekMs = 450;
const double kJamDriftSpeedDelta = 0.02;
const int kJamClockSamples = 5;
const Duration kJamClockResync = Duration(seconds: 60);

/// Muestra de un intercambio `time_ping`/`time_pong`.
class JamClockSample {
  final int rttMs;

  /// `referencia ≈ local + offsetMs`.
  final int offsetMs;

  const JamClockSample(this.rttMs, this.offsetMs);

  /// [sentAt]/[receivedAt]: reloj local al enviar/recibir; [serverNow]: hora
  /// de referencia en el pong. Se asume trayecto simétrico (rtt/2).
  factory JamClockSample.fromExchange({
    required int sentAt,
    required int receivedAt,
    required int serverNow,
  }) {
    final rtt = receivedAt - sentAt;
    return JamClockSample(rtt, serverNow + rtt ~/ 2 - receivedAt);
  }
}

/// Estimador de offset tipo NTP: guarda las últimas muestras y devuelve la
/// mediana de las de menor RTT (las menos afectadas por jitter).
class ClockOffsetEstimator {
  final int maxSamples;
  final int bestCount;
  final List<JamClockSample> _samples = [];

  ClockOffsetEstimator({this.maxSamples = 12, this.bestCount = 5});

  int get sampleCount => _samples.length;
  bool get isReady => _samples.isNotEmpty;

  void add(JamClockSample sample) {
    if (sample.rttMs < 0) return; // reloj local retrocedió: descartar
    _samples.add(sample);
    if (_samples.length > maxSamples) _samples.removeAt(0);
  }

  void clear() => _samples.clear();

  /// Offset estimado (ms) o `null` sin muestras.
  int? get offsetMs {
    if (_samples.isEmpty) return null;
    final best = [..._samples]..sort((a, b) => a.rttMs.compareTo(b.rttMs));
    final used = best.take(bestCount).map((s) => s.offsetMs).toList()..sort();
    final mid = used.length ~/ 2;
    return used.length.isOdd ? used[mid] : (used[mid - 1] + used[mid]) ~/ 2;
  }

  /// Hora de referencia equivalente a [localMs] (o [localMs] sin muestras).
  int toReference(int localMs) => localMs + (offsetMs ?? 0);

  /// Instante local equivalente a la hora de referencia [refMs].
  int toLocal(int refMs) => refMs - (offsetMs ?? 0);
}

enum JamDriftAction { none, nudge, seek }

/// Decisión de corrección para una deriva con signo (`objetivo − actual`:
/// positivo = vamos atrasados).
class JamDriftDecision {
  final JamDriftAction action;

  /// Velocidad a aplicar (1.0 = normal).
  final double speed;

  const JamDriftDecision(this.action, this.speed);
}

/// Pura y testeable. [currentSpeed] da histéresis: una vez ajustando, se
/// mantiene hasta que la deriva baje de la mitad del umbral.
JamDriftDecision decideDriftCorrection(
  int driftMs, {
  double currentSpeed = 1.0,
}) {
  final abs = driftMs.abs();
  if (abs > kJamDriftSeekMs) return const JamDriftDecision(JamDriftAction.seek, 1.0);
  final nudging = currentSpeed != 1.0;
  final threshold = nudging ? kJamDriftIgnoreMs ~/ 2 : kJamDriftIgnoreMs;
  if (abs <= threshold) return const JamDriftDecision(JamDriftAction.none, 1.0);
  return JamDriftDecision(
    JamDriftAction.nudge,
    driftMs > 0 ? 1.0 + kJamDriftSpeedDelta : 1.0 - kJamDriftSpeedDelta,
  );
}
