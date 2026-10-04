class Album {
  final String id;
  final String title;
  final String artist;
  final String? coverArtUrl;
  final int trackCount;
  final int year;
  final String? genre;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArtUrl,
    required this.trackCount,
    required this.year,
    this.genre,
  });

  factory Album.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Album(
      id: (json['id'] as String?) ?? '',
      title: (json['name'] as String?) ?? (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
      trackCount: (json['songCount'] as num?)?.toInt() ?? (json['trackCount'] as num?)?.toInt() ?? 0,
      year: (json['year'] as num?)?.toInt() ?? 0,
      genre: json['genre'] as String?,
    );
  }
}
