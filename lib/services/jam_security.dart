/// Comparación en tiempo constante (evita filtrar la contraseña por tiempos).
bool constantTimeEquals(String a, String b) {
  var diff = a.length ^ b.length;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Limita los intentos fallidos de unión a una Jam LAN: tras [maxFailures]
/// dentro de [window] bloquea nuevos intentos hasta que los fallos caduquen.
class JamFailureBlocker {
  final int maxFailures;
  final Duration window;
  final List<int> _failuresMs = [];

  JamFailureBlocker({this.maxFailures = 10, this.window = const Duration(minutes: 1)});

  void _prune(int now) =>
      _failuresMs.removeWhere((t) => now - t >= window.inMilliseconds);

  bool isBlocked([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _prune(now);
    return _failuresMs.length >= maxFailures;
  }

  void recordFailure([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _prune(now);
    _failuresMs.add(now);
  }

  void reset() => _failuresMs.clear();
}
