import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Una escucha pendiente de informar al servidor, con su hora original.
class PendingScrobble {
  final String trackId;
  final int timeMs;

  const PendingScrobble(this.trackId, this.timeMs);

  Map<String, dynamic> toJson() => {'id': trackId, 'time': timeMs};
}

/// Cola persistente de scrobbles: las escuchas hechas sin conexión (o cuyo
/// envío falló) se guardan en disco y se envían en orden al reconectar, con la
/// hora en que ocurrieron.
class ScrobbleQueue {
  ScrobbleQueue(this.file, {this.maxItems = 5000});

  final File file;
  final int maxItems;

  final List<PendingScrobble> _items = [];
  bool _loaded = false;
  Future<void> _write = Future.value();
  bool _flushing = false;

  int get length => _items.length;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final time = entry['time'];
        if (id is String && id.isNotEmpty && time is num) {
          _items.add(PendingScrobble(id, time.toInt()));
        }
      }
    } catch (_) {
      // Archivo dañado: se empieza con una cola vacía.
    }
  }

  Future<void> add(String trackId, int timeMs) async {
    await _ensureLoaded();
    _items.add(PendingScrobble(trackId, timeMs));
    if (_items.length > maxItems) {
      _items.removeRange(0, _items.length - maxItems);
    }
    await _persist();
  }

  /// Envía las pendientes en orden con [send]; se detiene en el primer fallo
  /// y conserva lo que no se pudo enviar. Devuelve cuántas se enviaron.
  Future<int> flush(Future<bool> Function(PendingScrobble item) send) async {
    await _ensureLoaded();
    if (_flushing || _items.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      while (_items.isNotEmpty) {
        final item = _items.first;
        final ok = await send(item);
        if (!ok) break;
        _items.removeAt(0);
        sent++;
      }
    } finally {
      _flushing = false;
      if (sent > 0) await _persist();
    }
    return sent;
  }

  /// Escritura atómica (`.tmp` + rename), serializada.
  Future<void> _persist() {
    final contents = jsonEncode(_items.map((e) => e.toJson()).toList());
    _write = _write.catchError((Object _) {}).then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(contents, flush: true);
        await temp.rename(file.path);
      } catch (_) {}
    });
    return _write;
  }
}
