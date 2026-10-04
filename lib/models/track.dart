class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String? albumArtUrl;
  final int playCount;
  final String? artistId;
  final String? albumId;
  final String? genre;
  final DateTime? createdAt;
  final int? rating;
  final int? year;
  final String? trackNumber;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.albumArtUrl,
    this.playCount = 0,
    this.artistId,
    this.albumId,
    this.genre,
    this.createdAt,
    this.rating,
    this.year,
    this.trackNumber,
  });

  factory Track.fromJson(Map<String, dynamic> json, {String? albumArtUrl}) {
    final rawDuration = json['duration'];
    final duration = rawDuration is num
        ? rawDuration.toString()
        : (rawDuration as String? ?? '');
    return Track(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      album: (json['album'] as String?) ?? 'Unknown',
      duration: duration,
      albumArtUrl: albumArtUrl ?? json['coverArt'] as String?,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      artistId: json['artistId'] as String?,
      albumId: json['albumId'] as String?,
      genre: json['genre'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      rating: (json['rating'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      trackNumber: json['track'] as String?,
    );
  }

  Track copyWith({int? rating}) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      albumArtUrl: albumArtUrl,
      playCount: playCount,
      artistId: artistId,
      albumId: albumId,
      genre: genre,
      createdAt: createdAt,
      rating: rating ?? this.rating,
      year: year,
      trackNumber: trackNumber,
    );
  }
}
