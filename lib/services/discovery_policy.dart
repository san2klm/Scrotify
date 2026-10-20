import 'dart:math' as math;

import 'listening_stats_service.dart';
import 'navidrome_service.dart';

/// A playable recommendation retaining the original Navidrome track ID.
class DiscoveryCandidate {
  const DiscoveryCandidate({required this.track, this.reason = ''});
  final Track track;
  final String reason;
}

final Map<String, String> _textCache = <String, String>{};
final Map<String, String> _titleCache = <String, String>{};
final Map<String, String> _artistCache = <String, String>{};

final RegExp _diacriticsRe = RegExp(r'[\u0300-\u036f]');
final RegExp _apostropheRe = RegExp("['’]");
final RegExp _nonAlnumUnicodeRe = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _remasterBracketRe = RegExp(
    r'[\(\[][^\)\]]*(?:remaster|deluxe|anniversary|bonus|radio edit|album version)[^\)\]]*[\)\]]');
final RegExp _remasterDashRe = RegExp(
    r'\s*[-–—:]\s*(?:\d{4}\s+)?(?:remaster|deluxe|anniversary|radio edit|album version).*$');
final RegExp _remasterWordRe =
    RegExp(r'\b(?:remastered?|remastering)\b(?:\s+\d{4})?');
final RegExp _featBracketRe =
    RegExp(r'[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]');
final RegExp _featSuffixRe =
    RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
final RegExp _nonAlnumAsciiRe = RegExp('[^A-Z0-9]');

String discoveryText(String value) {
  final cached = _textCache[value];
  if (cached != null) return cached;
  if (_textCache.length > 4096) _textCache.clear();
  var text = value.toLowerCase().replaceAll(_diacriticsRe, '');
  const groups = {
    'a': 'áàäâãåā',
    'e': 'éèëêē',
    'i': 'íìïîī',
    'o': 'óòöôõøō',
    'u': 'úùüûū',
    'n': 'ñ',
    'c': 'ç',
    'y': 'ýÿ',
  };
  groups.forEach((replacement, letters) {
    for (var i = 0; i < letters.length; i++) {
      text = text.replaceAll(letters[i], replacement);
    }
  });
  final result = text
      .replaceAll('ß', 'ss')
      .replaceAll(_apostropheRe, '')
      .replaceAll('&', ' and ')
      .replaceAll(_nonAlnumUnicodeRe, ' ')
      .trim();
  return _textCache[value] = result;
}

String discoveryTitle(String value) {
  final cached = _titleCache[value];
  if (cached != null) return cached;
  if (_titleCache.length > 4096) _titleCache.clear();
  var title = value.toLowerCase();
  // Treat rereleases and remasters as the same song, retaining meaningful
  // parentheticals (e.g. part numbers) instead of stripping every suffix.
  title = title.replaceAll(_remasterBracketRe, '');
  title = title.replaceAll(_remasterDashRe, '');
  title = title.replaceAll(_remasterWordRe, '');
  title = title.replaceAll(_featBracketRe, '');
  return _titleCache[value] = discoveryText(title);
}

String discoveryArtist(String value) {
  final cached = _artistCache[value];
  if (cached != null) return cached;
  if (_artistCache.length > 4096) _artistCache.clear();
  return _artistCache[value] =
      discoveryText(value.replaceAll(_featSuffixRe, ''));
}

String _recordingKey(Track track) =>
    '${discoveryArtist(track.artist)}|${discoveryTitle(track.title)}';
String _isrc(String value) =>
    value.toUpperCase().replaceAll(_nonAlnumAsciiRe, '');

class DiscoveryLibraryIndex {
  DiscoveryLibraryIndex(Iterable<Track> tracks) {
    for (final track in tracks) {
      songs.add(_recordingKey(track));
      if (track.mbid?.isNotEmpty == true) mbids.add(track.mbid!.toLowerCase());
      if (track.isrc?.isNotEmpty == true) isrcs.add(_isrc(track.isrc!));
      artists.add(discoveryText(track.artist));
      albums
          .add('${discoveryText(track.artist)}|${discoveryTitle(track.album)}');
    }
  }
  final songs = <String>{};
  final mbids = <String>{};
  final isrcs = <String>{};
  final artists = <String>{};
  final albums = <String>{};
  bool contains(Track track) =>
      songs.contains(_recordingKey(track)) ||
      (track.mbid != null && mbids.contains(track.mbid!.toLowerCase())) ||
      (track.isrc != null && isrcs.contains(_isrc(track.isrc!)));
  bool containsAlbum(Album album) => albums.contains(
      '${discoveryText(album.artist)}|${discoveryTitle(album.title)}');
  bool containsArtist(Artist artist) =>
      artists.contains(discoveryText(artist.name));
}

class DiscoveryTaste {
  DiscoveryTaste._(this.artistWeights, this.genreWeights);
  final Map<String, double> artistWeights;
  final Map<String, double> genreWeights;
  List<String> get artists => _sorted(artistWeights);
  List<String> get genres => _sorted(genreWeights);
  static List<String> _sorted(Map<String, double> weights) =>
      weights.keys.toList()
        ..sort((a, b) {
          final score = weights[b]!.compareTo(weights[a]!);
          return score != 0 ? score : a.compareTo(b);
        });

  factory DiscoveryTaste.from(
      {required List<Track> library,
      required Iterable<ListeningEvent> events,
      required DateTime now,
      bool Function(String id)? isStarred}) {
    final artists = <String, double>{};
    final genres = <String, double>{};
    void add(Map<String, double> weights, String? name, double score) {
      if (name == null ||
          name.trim().isEmpty ||
          ['unknown', 'desconocido', 'various artists']
              .contains(discoveryText(name))) {
        return;
      }
      final clean = name.trim();
      weights[clean] = (weights[clean] ?? 0) + score;
    }

    for (final track in library) {
      // A large discography cannot drown out actual listening behaviour.
      final current = artists[track.artist] ?? 0;
      final base = current < 2 ? 0.1 : 0.0;
      final score = base +
          track.userRating * 0.3 +
          ((isStarred?.call(track.id) ?? false) ? 1.5 : 0);
      add(artists, track.artist, score);
      add(genres, track.genre, base * 0.2);
    }
    for (final event in events) {
      final age = math.max(0, now.difference(event.timestamp).inDays);
      final score = (3 * math.pow(0.5, age / 60)).toDouble();
      add(artists, event.artist, score);
      add(genres, event.genre, score);
    }
    return DiscoveryTaste._(artists, genres);
  }
}

List<DiscoveryCandidate> recommendNavidromeTracks({
  required List<Track> library,
  required Iterable<ListeningEvent> events,
  required DateTime now,
  bool Function(String id)? isStarred,
  int limit = 20,
}) {
  if (limit <= 0) return const [];
  final history = events.toList();
  final taste = DiscoveryTaste.from(
      library: library, events: history, now: now, isStarred: isStarred);
  final artists = <String, double>{
    for (final e in taste.artistWeights.entries)
      discoveryArtist(e.key): e.value,
  };
  final genres = <String, double>{
    for (final e in taste.genreWeights.entries) discoveryText(e.key): e.value,
  };
  final plays = <String, int>{};
  final lastPlayed = <String, DateTime>{};
  for (final event in history) {
    plays[event.trackId] = (plays[event.trackId] ?? 0) + 1;
    final last = lastPlayed[event.trackId];
    if (last == null || event.timestamp.isAfter(last)) {
      lastPlayed[event.trackId] = event.timestamp;
    }
  }
  double score(Track track) {
    final artist = artists[discoveryArtist(track.artist)] ?? 0;
    final genre = genres[discoveryText(track.genre ?? '')] ?? 0;
    final last = lastPlayed[track.id];
    final recentlyPlayed = last != null && now.difference(last).inDays < 7;
    return 2 * math.log(1 + artist) +
        2 * math.log(1 + genre) +
        math.log(1 + (plays[track.id] ?? 0)) * 0.5 +
        ((isStarred?.call(track.id) ?? false) ? 1 : 0) +
        track.userRating * 0.2 +
        (plays.containsKey(track.id) ? 0 : 1.5) -
        (recentlyPlayed ? 4 : 0);
  }

  final pool = library
      .where(
          (track) => track.id.isNotEmpty && !track.id.startsWith('discovery:'))
      .toList();
  final scores = {for (final track in pool) track.id: score(track)};
  pool.sort((a, b) {
    final result = scores[b.id]!.compareTo(scores[a.id]!);
    return result != 0 ? result : a.id.compareTo(b.id);
  });
  // Deduplicate once before selecting, keeping selection O(limit * catalogue)
  // even for libraries containing many duplicate editions.
  final indexed = DiscoveryLibraryIndex(const []);
  final indexedIds = <String>{};
  pool.removeWhere((track) {
    if (!indexedIds.add(track.id) || indexed.contains(track)) return true;
    indexed.songs.add(_recordingKey(track));
    if (track.mbid?.isNotEmpty == true) {
      indexed.mbids.add(track.mbid!.toLowerCase());
    }
    if (track.isrc?.isNotEmpty == true) indexed.isrcs.add(_isrc(track.isrc!));
    return false;
  });
  final selected = <DiscoveryCandidate>[];
  final seen = DiscoveryLibraryIndex(const []);
  final seenIds = <String>{};
  final counts = <String, int>{};
  // Soft diversity penalty: still fill the section for small libraries.
  while (pool.isNotEmpty && selected.length < limit) {
    var best = 0;
    double adjusted(Track t) =>
        scores[t.id]! - (counts[discoveryArtist(t.artist)] ?? 0) * 2;
    for (var i = 1; i < pool.length; i++) {
      if (adjusted(pool[i]) > adjusted(pool[best])) best = i;
    }
    final track = pool.removeAt(best);
    if (!seenIds.add(track.id) || seen.contains(track)) continue;
    seen.songs.add(_recordingKey(track));
    if (track.mbid?.isNotEmpty == true) {
      seen.mbids.add(track.mbid!.toLowerCase());
    }
    if (track.isrc?.isNotEmpty == true) seen.isrcs.add(_isrc(track.isrc!));
    final artist = discoveryArtist(track.artist);
    counts[artist] = (counts[artist] ?? 0) + 1;
    selected.add(DiscoveryCandidate(
        track: track,
        reason: history.any((e) => discoveryArtist(e.artist) == artist)
            ? 'Por tus escuchas de ${track.artist}'
            : 'De tu biblioteca de Navidrome'));
  }
  return List.unmodifiable(selected);
}
