import 'navidrome_service.dart';

/// Representa un grupo de canciones que se consideran duplicadas entre sí.
class DuplicateGroup {
  final String canonicalKey;
  final String canonicalArtist;
  final String canonicalTitle;
  final List<Track> tracks;
  final List<int> indices;

  const DuplicateGroup({
    required this.canonicalKey,
    required this.canonicalArtist,
    required this.canonicalTitle,
    required this.tracks,
    required this.indices,
  });

  /// La canción "original" o principal que se conservará.
  Track get primaryTrack => tracks.first;

  /// Las copias duplicadas que se sugiere eliminar.
  List<Track> get duplicatesToRemove => tracks.sublist(1);

  /// Los índices en la lista original de las copias que se sugiere eliminar.
  List<int> get indicesToRemove => indices.sublist(1);
}

/// Detector inteligente de canciones duplicadas en playlists, colas y colecciones.
class DuplicateDetector {
  static final RegExp _diacriticsRe = RegExp(r'[\u0300-\u036f]');
  static final RegExp _apostropheRe = RegExp("['’]");
  static final RegExp _nonAlnumUnicodeRe =
      RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final RegExp _remasterBracketRe = RegExp(
      r'[\(\[][^\)\]]*(?:remaster|deluxe|anniversary|bonus|radio edit|album version|version|edit|mono|stereo)[^\)\]]*[\)\]]',
      caseSensitive: false);
  static final RegExp _remasterDashRe = RegExp(
      r'\s*[-–—:]\s*(?:\d{4}\s+)?(?:remaster|deluxe|anniversary|radio edit|album version|bonus).*$',
      caseSensitive: false);
  static final RegExp _remasterWordRe =
      RegExp(r'\b(?:remastered?|remastering)\b(?:\s+\d{4})?', caseSensitive: false);
  static final RegExp _featBracketRe =
      RegExp(r'[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]', caseSensitive: false);
  static final RegExp _featSuffixRe =
      RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
  static final RegExp _leadingTheRe =
      RegExp(r'^the\s+', caseSensitive: false);

  /// Normaliza texto para comparación insensata a mayúsculas, tildes y símbolos.
  static String normalizeText(String value) {
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
    return text
        .replaceAll('ß', 'ss')
        .replaceAll(_apostropheRe, '')
        .replaceAll('&', ' and ')
        .replaceAll(_nonAlnumUnicodeRe, ' ')
        .trim();
  }

  /// Normaliza el título de una canción eliminando remasters, sufijos y colaboradores.
  static String normalizeTitle(String value) {
    var title = value.toLowerCase();
    title = title.replaceAll(_remasterBracketRe, '');
    title = title.replaceAll(_remasterDashRe, '');
    title = title.replaceAll(_remasterWordRe, '');
    title = title.replaceAll(_featBracketRe, '');
    return normalizeText(title);
  }

  /// Normaliza el nombre del artista eliminando prefijos "The" y colaboradores.
  static String normalizeArtist(String value) {
    var artist = value.replaceAll(_featSuffixRe, '').trim();
    artist = artist.replaceAll(_leadingTheRe, '').trim();
    return normalizeText(artist);
  }

  /// Genera una clave canónica para agrupar canciones equivalentes.
  static String canonicalKeyFor(Track track, {required bool matchMetadata}) {
    if (!matchMetadata) {
      return track.id;
    }
    final artist = normalizeArtist(track.artist);
    final title = normalizeTitle(track.title);
    return '$artist|$title';
  }

  /// Encuentra todos los grupos de canciones duplicadas en una lista de pistas.
  ///
  /// Si [matchMetadata] es true (por defecto), agrupa tanto por coincidencia de
  /// artista + título normalizado como por ID.
  /// Si es false, agrupa estrictamente por ID idéntico.
  static List<DuplicateGroup> findDuplicates(
    List<Track> tracks, {
    bool matchMetadata = true,
  }) {
    if (tracks.length <= 1) return const [];

    final groups = <String, ({
      String canonicalArtist,
      String canonicalTitle,
      List<Track> tracks,
      List<int> indices,
    })>{};

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final key = canonicalKeyFor(track, matchMetadata: matchMetadata);
      final artist = normalizeArtist(track.artist);
      final title = normalizeTitle(track.title);

      final entry = groups.putIfAbsent(
        key,
        () => (
          canonicalArtist: artist,
          canonicalTitle: title,
          tracks: <Track>[],
          indices: <int>[],
        ),
      );
      entry.tracks.add(track);
      entry.indices.add(i);
    }

    final duplicates = <DuplicateGroup>[];
    for (final entry in groups.entries) {
      if (entry.value.tracks.length > 1) {
        duplicates.add(
          DuplicateGroup(
            canonicalKey: entry.key,
            canonicalArtist: entry.value.canonicalArtist,
            canonicalTitle: entry.value.canonicalTitle,
            tracks: entry.value.tracks,
            indices: entry.value.indices,
          ),
        );
      }
    }

    return duplicates;
  }

  /// Devuelve el conjunto de índices que deben eliminarse para dejar la lista
  /// sin canciones duplicadas (conservando la primera aparición de cada una).
  static Set<int> findDuplicateIndicesToRemove(
    List<Track> tracks, {
    bool matchMetadata = true,
  }) {
    final duplicates = findDuplicates(tracks, matchMetadata: matchMetadata);
    final indicesToRemove = <int>{};
    for (final group in duplicates) {
      indicesToRemove.addAll(group.indicesToRemove);
    }
    return indicesToRemove;
  }

  /// Devuelve una nueva lista de pistas conservando únicamente la primera aparición
  /// de cada pista única.
  static List<Track> deduplicate(
    List<Track> tracks, {
    bool matchMetadata = true,
  }) {
    if (tracks.length <= 1) return List.of(tracks);
    final seen = <String>{};
    final result = <Track>[];

    for (final track in tracks) {
      final key = canonicalKeyFor(track, matchMetadata: matchMetadata);
      if (seen.add(key)) {
        result.add(track);
      }
    }

    return result;
  }
}
