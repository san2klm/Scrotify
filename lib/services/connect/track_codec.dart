import '../../models/crotolink_models.dart' show sanitizeArtUrl;
import '../navidrome_service.dart';

/// `Track` ⇄ JSON para los mensajes de Connect (subconjunto que basta para
/// mostrar y reproducir; sin metadatos pesados).
Map<String, dynamic> trackToConnectJson(Track t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'duration': t.duration,
      'albumArtUrl': sanitizeArtUrl(t.albumArtUrl),
      'suffix': t.suffix,
      'artistId': t.artistId,
      'albumId': t.albumId,
      'genre': t.genre,
      'trackNumber': t.trackNumber,
      'samplingRate': t.samplingRate,
      'bitDepth': t.bitDepth,
    }..removeWhere((_, v) => v == null); // mensajes más cortos

Track trackFromConnectJson(Map<String, dynamic> json) =>
    Track.fromJson(json, albumArtUrl: json['albumArtUrl'] as String?);
