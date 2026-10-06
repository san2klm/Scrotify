import '../services/navidrome_service.dart';
import 'jam_history.dart' show parseTrackDuration;

/// Emparejamiento de pistas por metadatos (lógica pura). Sirve para que dos
/// personas con servidores Navidrome distintos escuchen lo mismo.

const int kJamMatchDurationToleranceSec = 3;

const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
};

String _stripAccents(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

// Grupos entre () o [] que solo informan de la edición, no de la grabación.
final _noiseGroup = RegExp(
  r'[\(\[][^\)\]]*\b(feat|ft|featuring|with|remaster(ed)?|mono|stereo|deluxe|bonus|expanded|anniversary|version)\b[^\)\]]*[\)\]]',
);
final _dashNoise = RegExp(
  r'\s[-–]\s.*\b(remaster(ed)?|mono|stereo|deluxe|version|\d{4})\b.*$',
);
final _trailingFeat = RegExp(r'\s(feat|ft|featuring)\.?\s.*$');

/// Título comparable: sin acentos/mayúsculas ni ruido de edición; conserva
/// marcas que cambian la grabación (live, acoustic, remix, instrumental).
String normalizeTitle(String title) {
  var t = _stripAccents(title.toLowerCase());
  t = t.replaceAll(_noiseGroup, ' ');
  t = t.replaceAll(_dashNoise, '');
  t = t.replaceAll(_trailingFeat, '');
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

final _artistSplit = RegExp(
  r'\s*(?:,|;|&|/|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b|\band\b)\s*',
);

/// Conjunto de artistas normalizados ("A feat. B & C" → {a, b, c}).
Set<String> normalizeArtists(String artist) {
  final a = _stripAccents(artist.toLowerCase());
  return a
      .split(_artistSplit)
      .map((p) => p.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toSet();
}

bool _sameArtists(String a, String b) {
  final x = normalizeArtists(a);
  final y = normalizeArtists(b);
  if (x.isEmpty || y.isEmpty) return false;
  // Coinciden si comparten el artista principal (primer nombre) o uno contiene
  // al otro por completo; "Queen" vs "Queen & David Bowie" cuenta.
  return x.intersection(y).isNotEmpty && (x.containsAll(y) || y.containsAll(x));
}

int? _seconds(Track t) => parseTrackDuration(t.duration)?.inSeconds;

enum JamMatchKind { mbid, isrc, metadata }

class JamMatch {
  final Track track;
  final JamMatchKind kind;
  const JamMatch(this.track, this.kind);
}

bool _eq(String? a, String? b) =>
    a != null && b != null && a.isNotEmpty && a.toLowerCase() == b.toLowerCase();

/// ¿[candidate] es la misma grabación que [remote] por título+artista+duración?
bool metadataMatches(Track remote, Track candidate) {
  if (normalizeTitle(remote.title) != normalizeTitle(candidate.title)) {
    return false;
  }
  if (!_sameArtists(remote.artist, candidate.artist)) return false;
  final a = _seconds(remote);
  final b = _seconds(candidate);
  if (a != null && b != null && a > 0 && b > 0) {
    return (a - b).abs() <= kJamMatchDurationToleranceSec;
  }
  return true;
}

/// Elige el mejor candidato local para [remote]: MBID > ISRC > metadatos
/// (a igualdad, mismo álbum y menor diferencia de duración). `null` = no hay
/// coincidencia fiable.
JamMatch? pickBestMatch(Track remote, Iterable<Track> candidates) {
  final list = candidates.toList();
  for (final c in list) {
    if (_eq(remote.mbid, c.mbid)) return JamMatch(c, JamMatchKind.mbid);
  }
  for (final c in list) {
    if (_eq(remote.isrc, c.isrc)) return JamMatch(c, JamMatchKind.isrc);
  }
  final ok = list.where((c) => metadataMatches(remote, c)).toList();
  if (ok.isEmpty) return null;
  final rd = _seconds(remote);
  int score(Track c) {
    var s = 0;
    if (normalizeTitle(remote.album) == normalizeTitle(c.album)) s -= 1000;
    final cd = _seconds(c);
    if (rd != null && cd != null) s += (rd - cd).abs();
    return s;
  }
  ok.sort((a, b) => score(a).compareTo(score(b)));
  return JamMatch(ok.first, JamMatchKind.metadata);
}
