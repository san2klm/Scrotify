import 'dart:async';

import 'crotolink_track_matcher.dart';
import 'navidrome_service.dart';

/// Resultado de resolver una pista remota contra la biblioteca local.
enum CrotoLinkResolveStatus { resolved, unavailable }

class CrotoLinkResolution {
  final CrotoLinkResolveStatus status;
  final Track? track;
  const CrotoLinkResolution.resolved(Track this.track)
      : status = CrotoLinkResolveStatus.resolved;
  const CrotoLinkResolution.unavailable()
      : status = CrotoLinkResolveStatus.unavailable,
        track = null;
  bool get isAvailable => status == CrotoLinkResolveStatus.resolved;
}

/// Busca en *mi* servidor la pista que otro participante tiene en el suyo.
///
/// Orden: 1) mismo `trackId` verificado por metadatos (mismo servidor),
/// 2) MBID/ISRC, 3) título+artista+duración normalizados. Sin coincidencia
/// fiable → `unavailable`. Un error de red NO se cachea ni cuenta como
/// "no disponible": se propaga para que el llamador degrade.
class CrotoLinkTrackResolver {
  final Future<Track?> Function(String id) getSong;
  final Future<List<Track>> Function(String query) searchSongs;

  final Map<String, CrotoLinkResolution> _cache = {};
  final Map<String, Future<CrotoLinkResolution>> _inFlight = {};

  CrotoLinkTrackResolver({required this.getSong, required this.searchSongs});

  /// Resultado ya conocido (sin red), o `null` si aún no se resolvió.
  CrotoLinkResolution? cached(String remoteId) => _cache[remoteId];

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  Future<CrotoLinkResolution> resolve(Track remote) {
    final hit = _cache[remote.id];
    if (hit != null) return Future.value(hit);
    return _inFlight[remote.id] ??= _resolve(remote).then((r) {
      _cache[remote.id] = r;
      return r;
    }).whenComplete(() {
      // Bloque (no `=>`): devolver el propio Future haría que whenComplete
      // esperase por sí mismo.
      _inFlight.remove(remote.id);
    });
  }

  Future<CrotoLinkResolution> _resolve(Track remote) async {
    // 1) Fast path: el mismo ID existe aquí y es la misma canción.
    if (remote.id.isNotEmpty) {
      final same = await getSong(remote.id);
      if (same != null && _isSameRecording(remote, same)) {
        return CrotoLinkResolution.resolved(same);
      }
    }
    // 2-3) Búsqueda por título/artista y emparejado por MBID/ISRC/metadatos.
    final base = normalizeTitle(remote.title);
    final queries = <String>{
      if (base.isNotEmpty) '$base ${remote.artist}'.trim(),
      if (base.isNotEmpty) base,
    };
    final candidates = <String, Track>{};
    for (final q in queries) {
      for (final t in await searchSongs(q)) {
        candidates[t.id] = t;
      }
      final match = pickBestMatch(remote, candidates.values);
      if (match != null) return CrotoLinkResolution.resolved(match.track);
    }
    return const CrotoLinkResolution.unavailable();
  }

  bool _isSameRecording(Track remote, Track local) =>
      pickBestMatch(remote, [local]) != null;

  /// Resuelve [tracks] por lotes cediendo el hilo entre ellos para no bloquear
  /// la UI. [onProgress] se llama tras cada lote.
  Future<void> resolveBatch(
    Iterable<Track> tracks, {
    int batchSize = 4,
    void Function()? onProgress,
    bool Function()? isCancelled,
  }) async {
    final pending = tracks.where((t) => !_cache.containsKey(t.id)).toList();
    for (var i = 0; i < pending.length; i += batchSize) {
      if (isCancelled?.call() ?? false) return;
      final chunk = pending.skip(i).take(batchSize);
      await Future.wait(
          chunk.map((t) => resolve(t).then<void>((_) {}, onError: (_) {})));
      onProgress?.call();
      await Future<void>.delayed(Duration.zero);
    }
  }
}
