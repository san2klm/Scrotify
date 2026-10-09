part of 'navidrome_service.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String? albumArtUrl;
  final int playCount;
  final String? suffix;
  final String? artistId;
  final String? albumId;
  final String? genre;
  final DateTime? createdAt;
  final ReplayGainMetadata? replayGain;
  final int userRating;

  /// Identificadores/metadatos para emparejar la pista entre servidores
  /// distintos (Jam). Opcionales: OpenSubsonic los expone si están etiquetados.
  final String? mbid;
  final String? isrc;
  final int? trackNumber;

  /// Frecuencia (Hz) y profundidad (bits) del archivo original, si el servidor
  /// las informa (OpenSubsonic). El modo Bit-perfect las necesita.
  final int? samplingRate;
  final int? bitDepth;

  int get rating => userRating;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.albumArtUrl,
    this.playCount = 0,
    this.suffix,
    this.artistId,
    this.albumId,
    this.genre,
    this.createdAt,
    this.replayGain,
    this.userRating = 0,
    this.mbid,
    this.isrc,
    this.trackNumber,
    this.samplingRate,
    this.bitDepth,
  });

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? duration,
    String? albumArtUrl,
    int? playCount,
    String? suffix,
    String? artistId,
    String? albumId,
    String? genre,
    DateTime? createdAt,
    ReplayGainMetadata? replayGain,
    int? userRating,
    String? mbid,
    String? isrc,
    int? trackNumber,
    int? samplingRate,
    int? bitDepth,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      playCount: playCount ?? this.playCount,
      suffix: suffix ?? this.suffix,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      genre: genre ?? this.genre,
      createdAt: createdAt ?? this.createdAt,
      replayGain: replayGain ?? this.replayGain,
      userRating: userRating ?? this.userRating,
      mbid: mbid ?? this.mbid,
      isrc: isrc ?? this.isrc,
      trackNumber: trackNumber ?? this.trackNumber,
      samplingRate: samplingRate ?? this.samplingRate,
      bitDepth: bitDepth ?? this.bitDepth,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json, {String? albumArtUrl}) {
    final rawDuration = json['duration'];
    final duration = rawDuration is num
        ? rawDuration.toString()
        : (rawDuration as String? ?? '');

    final coverArt = albumArtUrl ?? json['coverArt'] as String?;

    DateTime? createdAt;
    final rawCreated = json['created'] ?? json['createdAt'];
    if (rawCreated != null) {
      createdAt = DateTime.tryParse(rawCreated.toString());
    }

    ReplayGainMetadata? replayGain;
    final rawRg = json['replayGain'];
    if (rawRg is Map) {
      final parsed = ReplayGainMetadata.fromJson(rawRg.cast<String, dynamic>());
      if (!parsed.isEmpty) {
        replayGain = parsed;
      }
    } else if (json.containsKey('trackGain') ||
        json.containsKey('albumGain') ||
        json.containsKey('trackPeak') ||
        json.containsKey('albumPeak') ||
        json.containsKey('baseGain') ||
        json.containsKey('fallbackGain')) {
      final parsed = ReplayGainMetadata.fromJson(json);
      if (!parsed.isEmpty) {
        replayGain = parsed;
      }
    }

    final rating = (json['userRating'] as num?)?.toInt() ??
        (json['rating'] as num?)?.toInt() ??
        0;

    return Track(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      album: (json['album'] as String?) ?? 'Unknown',
      duration: duration,
      albumArtUrl: coverArt,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      suffix: json['suffix'] as String?,
      artistId: json['artistId'] as String?,
      albumId: json['albumId'] as String?,
      genre: json['genre'] as String?,
      createdAt: createdAt,
      replayGain: replayGain,
      userRating: rating,
      mbid: (json['musicBrainzId'] ?? json['mbid']) as String?,
      isrc: _firstIsrc(json['isrc']),
      trackNumber: (json['track'] ?? json['trackNumber']) is num
          ? ((json['track'] ?? json['trackNumber']) as num).toInt()
          : null,
      samplingRate: (json['samplingRate'] as num?)?.toInt(),
      bitDepth: (json['bitDepth'] as num?)?.toInt(),
    );
  }

  /// OpenSubsonic devuelve `isrc` como lista; nuestro protocolo, como texto.
  static String? _firstIsrc(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return raw;
    if (raw is List && raw.isNotEmpty && raw.first is String) {
      return raw.first as String;
    }
    return null;
  }
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? coverArtUrl;
  final int trackCount;
  final int year;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArtUrl,
    required this.trackCount,
    required this.year,
  });

  factory Album.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Album(
      id: (json['id'] as String?) ?? '',
      title:
          (json['name'] as String?) ?? (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
      trackCount: (json['songCount'] as num?)?.toInt() ??
          (json['trackCount'] as num?)?.toInt() ??
          0,
      year: (json['year'] as num?)?.toInt() ?? 0,
    );
  }
}

class Artist {
  final String id;
  final String name;
  final String? coverArtUrl;

  Artist({required this.id, required this.name, this.coverArtUrl});

  factory Artist.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Artist(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final String? coverArtUrl;
  final int songCount;
  final int duration;
  final String? owner;
  final bool public;

  Playlist({
    required this.id,
    required this.name,
    this.coverArtUrl,
    required this.songCount,
    required this.duration,
    this.owner,
    this.public = false,
  });

  factory Playlist.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Playlist(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      owner: json['owner'] as String?,
      public: json['public'] == true,
    );
  }
}

/// La playlist ya existe aunque su portada no haya podido guardarse.
class PlaylistCoverUploadException implements Exception {
  final Playlist playlist;
  final Object cause;

  PlaylistCoverUploadException(this.playlist, this.cause);

  @override
  String toString() => 'La playlist se creó, pero la portada no se guardó. '
      '${cause.toString().replaceFirst('Exception: ', '')}';
}

class SearchResults {
  final List<Track> songs;
  final List<Album> albums;
  final List<Artist> artists;

  SearchResults({
    required this.songs,
    required this.albums,
    required this.artists,
  });

  bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Registro de lo que un usuario está escuchando en el servidor Navidrome en tiempo real.
class NowPlayingEntry {
  final String username;
  final Track track;
  final int minutesAgo;
  final int? playerId;

  NowPlayingEntry({
    required this.username,
    required this.track,
    required this.minutesAgo,
    this.playerId,
  });

  factory NowPlayingEntry.fromJson(
      Map<String, dynamic> json, String? albumArtUrl) {
    return NowPlayingEntry(
      username: (json['username'] as String?) ?? 'Usuario',
      track: Track.fromJson(json, albumArtUrl: albumArtUrl),
      minutesAgo: (json['minutesAgo'] as num?)?.toInt() ?? 0,
      playerId: (json['playerId'] as num?)?.toInt(),
    );
  }
}

/// Mensaje en el chat comunitario del servidor Navidrome.
class ChatMessage {
  final String username;
  final DateTime time;
  final String message;

  ChatMessage({
    required this.username,
    required this.time,
    required this.message,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawTime = json['time'];
    DateTime time;
    if (rawTime is num) {
      time = DateTime.fromMillisecondsSinceEpoch(rawTime.toInt());
    } else if (rawTime is String) {
      final parsed = int.tryParse(rawTime);
      time = parsed != null
          ? DateTime.fromMillisecondsSinceEpoch(parsed)
          : (DateTime.tryParse(rawTime) ?? DateTime.now());
    } else {
      time = DateTime.now();
    }

    return ChatMessage(
      username: (json['username'] as String?) ?? 'Usuario',
      time: time,
      message: (json['message'] as String?) ?? '',
    );
  }
}

/// Línea de letra estructurada (OpenSubsonic).
class LyricLineData {
  final int startMs;
  final String text;

  const LyricLineData({required this.startMs, required this.text});
}

/// Bloque de letra estructurada devuelto por `getLyricsBySongId`.
class StructuredLyricBlock {
  final bool synced;
  final String lang;
  final List<LyricLineData> lines;

  const StructuredLyricBlock({
    required this.synced,
    required this.lang,
    required this.lines,
  });
}
