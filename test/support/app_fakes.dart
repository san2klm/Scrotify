import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:navidrome_client/models/jam_models.dart';
import 'package:navidrome_client/services/connect/connect_protocol.dart';
import 'package:navidrome_client/services/connect/connect_service.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/waveform_service.dart';

class FakeNavidrome extends NavidromeService {
  final queries = <String>[];

  @override
  Future<List<Track>> getTracks({
    String? artist,
    String? album,
    int limit = 500,
    int offset = 0,
  }) async =>
      [];

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
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  Duration get position => Duration.zero;
  @override
  bool get karaokeMode => false;
  @override
  WaveformData? get waveformData => null;
  @override
  double get volume => 0.7;
  @override
  List<MostPlayedItem> get mostPlayed => [];
  @override
  List<Track> get recentlyPlayed => [];
  @override
  String get mostPlayedSignature => '';
  @override
  String get recentlyPlayedSignature => '';

  @override
  bool get hasSleepTimer => false;
  @override
  bool get vocalReduction => false;
  @override
  bool get hasTrack => false;
  @override
  bool get isWaveformLoading => false;
  @override
  bool get gapless => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class IdleJam extends ChangeNotifier implements JamController {
  @override
  JamRole get role => JamRole.none;

  @override
  bool get inJam => false;

  @override
  bool get isHost => false;

  @override
  bool get isGuest => false;

  @override
  JamParticipant? get localParticipant => null;

  @override
  List<JamQueueItem> get jamQueue => const [];

  @override
  List<JamQueueItem> get queue => const [];

  @override
  bool isTrackInJamQueue(String trackId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Puerto de Connect sin reproductor, para pantallas que solo necesitan el
/// servicio presente.
class IdleConnectPort extends ChangeNotifier implements ConnectPlayerPort {
  @override
  String? get scope => null;
  @override
  Map<String, dynamic>? snapshot() => null;
  @override
  ConnectTransfer? exportTransfer() => null;
  @override
  Future<void> adopt(ConnectTransfer transfer) async {}
  @override
  Future<void> apply(
      String command, num? value, Map<String, dynamic> data) async {}
  @override
  Future<void> pauseLocal() async {}
}

ConnectService idleConnectService() => ConnectService(
      port: IdleConnectPort(),
      selfId: 'test-device',
      transportsFor: (_) => const [],
    );
