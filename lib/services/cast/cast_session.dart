import 'dart:async';

import 'package:flutter/foundation.dart';

import '../navidrome_service.dart';
import 'cast_client.dart';
import 'cast_protocol.dart';

/// Sesión de transmisión a un Chromecast: una sola a la vez.
class CastSession extends ChangeNotifier {
  CastSession._();

  static final CastSession instance = CastSession._();

  CastClient? _client;
  CastDevice? _device;
  Track? _track;

  CastDevice? get device => _device;
  Track? get track => _track;
  bool get isCasting => _client != null && !(_client!.isClosed);

  /// Transmite [track] a [device]; sustituye cualquier sesión anterior.
  Future<void> cast(
    CastDevice device,
    Track track, {
    required String streamUrl,
    String? imageUrl,
  }) async {
    await stop();
    final client = await CastClient.connect(device);
    _client = client;
    _device = device;
    _track = track;
    unawaited(client.messages.drain<void>().whenComplete(() {
      if (identical(_client, client)) {
        _client = null;
        _device = null;
        _track = null;
        notifyListeners();
      }
    }));
    await client.load(
      url: streamUrl,
      contentType: castContentTypeFor(track.suffix),
      title: track.title,
      artist: track.artist,
      album: track.album,
      imageUrl: imageUrl,
      durationSeconds: double.tryParse(track.duration),
    );
    notifyListeners();
  }

  void pause() => _client?.pause();
  void resume() => _client?.play();

  Future<void> stop() async {
    final client = _client;
    _client = null;
    _device = null;
    _track = null;
    if (client != null) {
      client.stop();
      await client.close();
    }
    notifyListeners();
  }
}
