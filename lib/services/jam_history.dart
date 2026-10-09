import '../models/jam_models.dart';
import 'navidrome_service.dart';

/// Pista que sonó en la Jam y quién la añadió.
class JamHistoryEntry {
  final Track track;
  final JamParticipant? addedBy;
  final DateTime playedAt;

  const JamHistoryEntry({
    required this.track,
    required this.addedBy,
    required this.playedAt,
  });
}

/// Resumen de fin de sesión (mini-Wrapped).
class JamHistorySummary {
  final int trackCount;
  final Duration totalDuration;
  final String? topContributor;
  final int topContributorCount;
  final Track? mostVoted;
  final int mostVotes;

  const JamHistorySummary({
    required this.trackCount,
    required this.totalDuration,
    this.topContributor,
    this.topContributorCount = 0,
    this.mostVoted,
    this.mostVotes = 0,
  });
}

/// Historial de la Jam, en RAM del host (el servidor no guarda nada).
class JamHistory {
  /// Una pista cuenta si sonó al menos esto…
  static const Duration minListened = Duration(seconds: 30);

  /// …o al menos esta fracción de su duración (mismo criterio que stats).
  static const double minFraction = 0.5;

  final List<JamHistoryEntry> _entries = [];
  final Map<String, int> _votesByTrack = {};

  List<JamHistoryEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  /// Decide si una pista con [listened] reproducido de [total] cuenta.
  static bool qualifies(Duration listened, Duration? total) {
    if (listened >= minListened) return true;
    if (total == null || total <= Duration.zero) return false;
    return listened.inMilliseconds >= total.inMilliseconds * minFraction;
  }

  /// Registra [track] si [listened] cumple el umbral. Devuelve si se añadió.
  bool record(
    Track track,
    JamParticipant? addedBy, {
    required Duration listened,
    Duration? total,
    DateTime? now,
    int votes = 0,
  }) {
    if (!qualifies(listened, total)) return false;
    _entries.add(JamHistoryEntry(
      track: track,
      addedBy: addedBy,
      playedAt: now ?? DateTime.now(),
    ));
    if (votes != 0) _votesByTrack[track.id] = votes;
    return true;
  }

  List<JamHistoryEntry> byParticipant(String participantId) =>
      _entries.where((e) => e.addedBy?.id == participantId).toList();

  void clear() {
    _entries.clear();
    _votesByTrack.clear();
  }

  JamHistorySummary summary() {
    final counts = <String, int>{};
    var totalMs = 0;
    for (final e in _entries) {
      final name = e.addedBy?.name;
      if (name != null) counts[name] = (counts[name] ?? 0) + 1;
      totalMs += (parseTrackDuration(e.track.duration)?.inMilliseconds ?? 0);
    }
    String? top;
    var topCount = 0;
    counts.forEach((name, n) {
      if (n > topCount) {
        top = name;
        topCount = n;
      }
    });
    Track? voted;
    var votes = 0;
    for (final e in _entries) {
      final v = _votesByTrack[e.track.id] ?? 0;
      if (v > votes) {
        votes = v;
        voted = e.track;
      }
    }
    return JamHistorySummary(
      trackCount: _entries.length,
      totalDuration: Duration(milliseconds: totalMs),
      topContributor: top,
      topContributorCount: topCount,
      mostVoted: voted,
      mostVotes: votes,
    );
  }
}

/// Historial del invitado: el host no lo envía, así que lo construye cada
/// invitado observando el estado sincronizado de la sala (pista actual,
/// posición y cola). Solo incluye lo que sonó desde que entró.
class JamGuestHistoryTracker {
  JamGuestHistoryTracker(this.history);

  final JamHistory history;

  /// Cuántas pistas de la cola se recuerdan para saber quién las añadió.
  static const _maxRemembered = 300;

  final Map<String, JamParticipant> _addedByTrack = {};
  Track? _track;
  JamParticipant? _addedBy;
  int _startMs = 0;
  int _maxMs = 0;

  int get rememberedCount => _addedByTrack.length;

  /// Anota quién añadió cada pista de la cola (el estado remoto no lo trae para
  /// la pista actual). Conserva las más recientes.
  void rememberQueue(Iterable<JamQueueItem> queue) {
    for (final item in queue) {
      final by = item.addedBy;
      if (by == null) continue;
      _addedByTrack.remove(item.track.id); // reinsertar = más reciente
      _addedByTrack[item.track.id] = by;
    }
    while (_addedByTrack.length > _maxRemembered) {
      _addedByTrack.remove(_addedByTrack.keys.first);
    }
  }

  /// Observa el estado actual de la sala.
  void observe({
    required Track? track,
    JamParticipant? addedBy,
    required int positionMs,
  }) {
    if (track?.id != _track?.id) {
      _close();
      if (track != null) {
        _track = track;
        _addedBy = addedBy ?? _addedByTrack[track.id];
        _startMs = positionMs;
        _maxMs = positionMs;
      }
      return;
    }
    if (track == null) return;
    if (positionMs > _maxMs) _maxMs = positionMs;
    _addedBy ??= addedBy ?? _addedByTrack[track.id];
  }

  /// Cierra la pista en curso (al salir de la sala o terminar la sesión).
  void finalize() => _close();

  /// Olvida lo observado (nueva sala); no toca el historial ya guardado.
  void reset() {
    _track = null;
    _addedBy = null;
    _startMs = 0;
    _maxMs = 0;
    _addedByTrack.clear();
  }

  void _close() {
    final track = _track;
    if (track == null) return;
    _track = null;
    final heard = _maxMs > _startMs ? _maxMs - _startMs : 0;
    history.record(
      track,
      _addedBy,
      listened: Duration(milliseconds: heard),
      total: parseTrackDuration(track.duration),
    );
    _addedBy = null;
  }
}

/// `Track.duration` llega como segundos ("215") o como "m:ss".
Duration? parseTrackDuration(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final secs = int.tryParse(text);
  if (secs != null) return Duration(seconds: secs);
  final parts = text.split(':');
  if (parts.length == 2 || parts.length == 3) {
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    final n = nums.cast<int>();
    return parts.length == 2
        ? Duration(minutes: n[0], seconds: n[1])
        : Duration(hours: n[0], minutes: n[1], seconds: n[2]);
  }
  return null;
}
