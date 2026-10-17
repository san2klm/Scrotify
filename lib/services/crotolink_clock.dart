/// Umbrales de corrección de deriva (ms) y ajuste de velocidad.
const int kCrotoLinkDriftIgnoreMs = 50;
const int kCrotoLinkDriftSeekMs = 450;
const double kCrotoLinkDriftSpeedDelta = 0.02;
const int kCrotoLinkClockSamples = 5;
const Duration kCrotoLinkClockResync = Duration(seconds: 60);

final Stopwatch _crotoLinkMonotonic = Stopwatch()..start();

/// Milisegundos de un reloj monótono (no salta con cambios de hora ni NTP).
/// Se usa para medir el RTT; el reloj de pared solo para el offset.
int crotoLinkMonotonicMs() => _crotoLinkMonotonic.elapsedMilliseconds;

/// Muestra de un intercambio `time_ping`/`time_pong`.
class CrotoLinkClockSample {
  final int rttMs;

  /// `referencia ≈ local + offsetMs`.
  final int offsetMs;

  const CrotoLinkClockSample(this.rttMs, this.offsetMs);

  /// [sentAt]/[receivedAt]: reloj local al enviar/recibir; [serverNow]: hora
  /// de referencia en el pong. Se asume trayecto simétrico (rtt/2).
  ///
  /// [sentAt] y [receivedAt] deben venir del mismo reloj (idealmente
  /// [crotoLinkMonotonicMs]); [receivedWallMs] es la hora de pared al recibir y se
  /// usa solo para el offset (por defecto, [receivedAt]).
  factory CrotoLinkClockSample.fromExchange({
    required int sentAt,
    required int receivedAt,
    required int serverNow,
    int? receivedWallMs,
  }) {
    final rtt = receivedAt - sentAt;
    return CrotoLinkClockSample(
        rtt, serverNow + rtt ~/ 2 - (receivedWallMs ?? receivedAt));
  }
}

/// Estimador de offset tipo NTP: guarda las últimas muestras y devuelve la
/// mediana de las de menor RTT (las menos afectadas por jitter).
class ClockOffsetEstimator {
  final int maxSamples;
  final int bestCount;
  final List<CrotoLinkClockSample> _samples = [];

  ClockOffsetEstimator({this.maxSamples = 12, this.bestCount = 5});

  int get sampleCount => _samples.length;
  bool get isReady => _samples.isNotEmpty;

  void add(CrotoLinkClockSample sample) {
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

enum CrotoLinkDriftAction { none, nudge, seek }

/// Decisión de corrección para una deriva con signo (`objetivo − actual`:
/// positivo = vamos atrasados).
class CrotoLinkDriftDecision {
  final CrotoLinkDriftAction action;

  /// Velocidad a aplicar (1.0 = normal).
  final double speed;

  const CrotoLinkDriftDecision(this.action, this.speed);
}

/// Pura y testeable. [currentSpeed] da histéresis: una vez ajustando, se
/// mantiene hasta que la deriva baje de la mitad del umbral.
CrotoLinkDriftDecision decideDriftCorrection(
  int driftMs, {
  double currentSpeed = 1.0,
}) {
  final abs = driftMs.abs();
  if (abs > kCrotoLinkDriftSeekMs) {
    return const CrotoLinkDriftDecision(CrotoLinkDriftAction.seek, 1.0);
  }
  final nudging = currentSpeed != 1.0;
  final threshold =
      nudging ? kCrotoLinkDriftIgnoreMs ~/ 2 : kCrotoLinkDriftIgnoreMs;
  if (abs <= threshold) {
    return const CrotoLinkDriftDecision(CrotoLinkDriftAction.none, 1.0);
  }
  return CrotoLinkDriftDecision(
    CrotoLinkDriftAction.nudge,
    driftMs > 0
        ? 1.0 + kCrotoLinkDriftSpeedDelta
        : 1.0 - kCrotoLinkDriftSpeedDelta,
  );
}
