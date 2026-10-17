import '../models/crotolink_models.dart';

/// Lógica pura (sin red ni reproductor) de ordenación de la cola CrotoLink.
/// El host la aplica sobre su cola; el relay solo reenvía.

/// Reordena [items] según [mode]. Los ítems `pinned` conservan su orden
/// relativo y van primero; el resto se ordena según el modo. El resultado es
/// estable: no depende de nada más que de los datos de entrada.
List<CrotoLinkQueueItem> orderQueue(
  List<CrotoLinkQueueItem> items, {
  required CrotoLinkQueueMode mode,
  int fairTurnsPerPerson = 1,
}) {
  final pinned = items.where((i) => i.pinned).toList();
  final rest = items.where((i) => !i.pinned).toList();
  final ordered = switch (mode) {
    CrotoLinkQueueMode.fairTurns => _fairTurns(rest, fairTurnsPerPerson),
    CrotoLinkQueueMode.voting => _byVotes(rest),
    _ => rest,
  };
  return [...pinned, ...ordered];
}

/// Intercala por participante en bloques de [perPerson], respetando el orden
/// de llegada de cada uno. Los participantes se turnan en el orden de su
/// primera aparición.
List<CrotoLinkQueueItem> _fairTurns(
    List<CrotoLinkQueueItem> items, int perPerson) {
  final block = perPerson < 1 ? 1 : perPerson;
  final order = <String>[];
  final byPerson = <String, List<CrotoLinkQueueItem>>{};
  for (final item in items) {
    final key = item.addedBy?.id ?? '';
    if (!byPerson.containsKey(key)) order.add(key);
    byPerson.putIfAbsent(key, () => []).add(item);
  }
  final cursor = {for (final k in order) k: 0};
  final out = <CrotoLinkQueueItem>[];
  while (out.length < items.length) {
    for (final key in order) {
      final list = byPerson[key]!;
      var taken = 0;
      while (taken < block && cursor[key]! < list.length) {
        out.add(list[cursor[key]!]);
        cursor[key] = cursor[key]! + 1;
        taken++;
      }
    }
  }
  return out;
}

/// Más votos primero; empate por antigüedad (`addedAt`), luego por posición.
List<CrotoLinkQueueItem> _byVotes(List<CrotoLinkQueueItem> items) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final byVotes = b.$2.votes.compareTo(a.$2.votes);
    if (byVotes != 0) return byVotes;
    final byTime = a.$2.addedAt.compareTo(b.$2.addedAt);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Registro de votos: un voto por participante e ítem (−1, 0 quita, +1).
class CrotoLinkVoteBook {
  final Map<String, Map<String, int>> _votes = {};

  /// Devuelve `true` si el voto cambió algo.
  bool vote(String itemId, String participantId, int value) {
    final v = value.clamp(-1, 1);
    final current = _votes[itemId]?[participantId] ?? 0;
    if (current == v) return false;
    if (v == 0) {
      _votes[itemId]?.remove(participantId);
      if (_votes[itemId]?.isEmpty ?? false) _votes.remove(itemId);
    } else {
      _votes.putIfAbsent(itemId, () => {})[participantId] = v;
    }
    return true;
  }

  int total(String itemId) =>
      (_votes[itemId]?.values ?? const <int>[]).fold(0, (a, b) => a + b);

  int myVote(String itemId, String participantId) =>
      _votes[itemId]?[participantId] ?? 0;

  void removeItem(String itemId) => _votes.remove(itemId);

  /// Elimina los votos de un participante que se va (opcional).
  void removeParticipant(String participantId) {
    for (final m in _votes.values) {
      m.remove(participantId);
    }
    _votes.removeWhere((_, m) => m.isEmpty);
  }

  void clear() => _votes.clear();
}

/// Plan de reordenación: lista de movimientos `(from, to)` sobre una lista de
/// ids que la transforma en [target]. Sirve para aplicar el orden deseado al
/// reproductor con `reorderQueue` sin reconstruirlo (no toca la pista actual).
List<(int, int)> reorderMoves(List<String> current, List<String> target) {
  final work = List<String>.of(current);
  final moves = <(int, int)>[];
  for (var i = 0; i < target.length && i < work.length; i++) {
    if (work[i] == target[i]) continue;
    final from = work.indexOf(target[i], i);
    if (from < 0) continue;
    final id = work.removeAt(from);
    work.insert(i, id);
    moves.add((from, i));
  }
  return moves;
}
