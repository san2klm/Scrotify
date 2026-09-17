import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';

class FakeNavidrome extends NavidromeService {
  final queries = <String>[];

  @override
  Future<List<Track>> getTracks({String? musicFolderId}) async => [];

  @override
  Future<List<Playlist>> getPlaylists() async => [];

  @override
  Future<List<dynamic>> getArtists() async => [];

  @override
  Future<List<Album>> getAlbums(
          {String type = 'newest', int limit = 50, int offset = 0}) async =>
      [];

  @override
  Future<SearchResults> search(String query) async {
    queries.add(query);
    return SearchResults(songs: [], albums: [], artists: []);
  }
}

class IdlePlayer extends ChangeNotifier implements PlayerController {
  @override
  Track? get currentTrack => null;
  @override
  bool get playing => false;
  @override
  bool get shuffleEnabled => false;
  @override
  LoopMode get repeatMode => LoopMode.off;
  @override
  Duration? get duration => null;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  double get volume => 0.7;
  @override
  List<MostPlayedItem> get mostPlayed => [];
  @override
  List<Track> get recentlyPlayed => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class IdleJam extends ChangeNotifier implements JamController {
  @override
  bool get inJam => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
