import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late NavidromeService nav;
  final calls = <String>[];
  late int uploadStatus;
  late bool rejectCreate;
  late bool rejectUpdate;
  List<String>? addedIds;
  List<String>? replacementIds;
  List<String>? removedIndexes;
  late List<String> serverEntries;
  late bool uploaded;
  String? uploadBody;
  String? uploadAuth;
  Map<String, dynamic>? nativeCredentials;
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6X8AAAAASUVORK5CYII=');

  setUp(() async {
    HttpOverrides.global = _RealHttpOverrides();
    calls.clear();
    uploadStatus = 200;
    rejectCreate = false;
    rejectUpdate = false;
    addedIds = null;
    replacementIds = null;
    removedIndexes = null;
    serverEntries = ['primera', 'segunda', 'tercera'];
    uploaded = false;
    uploadBody = null;
    uploadAuth = null;
    nativeCredentials = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      calls.add(path);
      final response = request.response;
      response.headers.contentType = ContentType.json;
      final playlist = {
        'id': 'playlist-1',
        'name': 'Mi playlist',
        'songCount': 0,
        'duration': 0,
        if (uploaded) 'coverArt': 'pl-playlist-1-new',
      };
      if (path == '/music/auth/login') {
        nativeCredentials = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        response.write(jsonEncode({'token': 'test-native-token'}));
      } else if (path == '/music/api/playlist/playlist-1/image') {
        uploadAuth = request.headers.value('X-ND-Authorization');
        final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        uploadBody = latin1.decode(body);
        response.statusCode = uploadStatus;
        uploaded = uploadStatus == 200;
        response.write(jsonEncode({'status': uploaded ? 'ok' : 'failed'}));
      } else {
        final data = <String, dynamic>{'status': 'ok'};
        if (path.endsWith('/updatePlaylist.view')) {
          addedIds = request.uri.queryParametersAll['songIdToAdd'];
          removedIndexes = request.uri.queryParametersAll['songIndexToRemove'];
        }
        if (path.endsWith('/createPlaylist.view')) {
          replacementIds = request.uri.queryParametersAll['songId'];
        }
        if ((path.endsWith('/createPlaylist.view') && rejectCreate) ||
            (path.endsWith('/updatePlaylist.view') && rejectUpdate)) {
          data['status'] = 'failed';
          data['error'] = {'code': 50, 'message': 'Permiso denegado'};
        } else if (path.endsWith('/createPlaylist.view') ||
            path.endsWith('/getPlaylist.view')) {
          data['playlist'] = {
            ...playlist,
            if (path.endsWith('/getPlaylist.view'))
              'entry': [
                for (final id in serverEntries)
                  {'id': id, 'title': id, 'artist': 'A', 'album': 'B'}
              ],
          };
        }
        response.write(jsonEncode({'subsonic-response': data}));
      }
      await response.close();
    });
    nav = NavidromeService();
    await nav.connectByUrl(
        'http://127.0.0.1:${server.port}/music', 'test-user', 'test-password');
  });

  tearDown(() async {
    nav.disconnect();
    nav.dispose();
    await server.close(force: true);
    HttpOverrides.global = null;
  });

  test('PNG uses native image endpoint, MIME and authentication, then reloads',
      () async {
    final playlist = await nav.createPlaylist('Mi playlist',
        coverBytes: png, coverFileName: 'Portada.PNG');
    expect(playlist!.coverArtUrl, contains('pl-playlist-1-new'));
    expect(calls, [
      '/music/rest/ping.view',
      '/music/rest/createPlaylist.view',
      '/music/auth/login',
      '/music/api/playlist/playlist-1/image',
      '/music/rest/getPlaylist.view',
    ]);
    expect(nativeCredentials,
        {'username': 'test-user', 'password': 'test-password'});
    expect(uploadAuth, 'Bearer test-native-token');
    expect(uploadBody, contains('name="image"; filename="Portada.PNG"'));
    expect(uploadBody, contains('content-type: image/png'));
    expect(uploadBody, contains(latin1.decode(png)));
  });

  test('creation without cover keeps standard Subsonic flow', () async {
    expect((await nav.createPlaylist('Mi playlist'))!.id, 'playlist-1');
    expect(calls.where((path) => path.contains('/api/')), isEmpty);
    expect(nativeCredentials, isNull);
  });

  test('HTTP 200 with Subsonic failure is not reported as success', () async {
    rejectCreate = true;
    await expectLater(nav.createPlaylist('Mi playlist'),
        throwsA(predicate((e) => e.toString().contains('Permiso denegado'))));
    expect(nativeCredentials, isNull);
  });

  test('failed image upload preserves playlist and retry uploads only image',
      () async {
    uploadStatus = 403;
    await expectLater(
        nav.createPlaylist('Mi playlist', coverBytes: png),
        throwsA(isA<PlaylistCoverUploadException>()
            .having((e) => e.playlist.id, 'created playlist', 'playlist-1')));
    uploadStatus = 200;
    await nav.uploadPlaylistCover('playlist-1', png);
    expect(
        calls.where((path) => path.endsWith('/createPlaylist.view')).length, 1);
    expect(uploaded, isTrue);
  });

  test('invalid image is rejected before creating a playlist', () async {
    await expectLater(nav.createPlaylist('Mi playlist', coverBytes: [1, 2, 3]),
        throwsArgumentError);
    expect(calls, ['/music/rest/ping.view']);
  });
  test('adding tracks sends repeated IDs and refreshes playlists after success',
      () async {
    await nav
        .updatePlaylist(playlistId: 'playlist-1', songIdsToAdd: ['a', 'b']);
    expect(addedIds, ['a', 'b']);
    expect(nav.playlistVersion, 1);
  });

  test('failed addition does not notify success', () async {
    rejectUpdate = true;
    await expectLater(
      nav.updatePlaylist(playlistId: 'playlist-1', songIdsToAdd: ['a']),
      throwsA(predicate((e) => e.toString().contains('Permiso denegado'))),
    );
    expect(nav.playlistVersion, 0);
  });

  test('reordering refuses a partial copy instead of deleting songs', () async {
    // La pantalla solo veía dos de las tres canciones (copia sin conexión).
    await expectLater(
      nav.reorderPlaylistTracks(
        playlistId: 'playlist-1',
        orderedSongIds: ['segunda', 'primera'],
      ),
      throwsA(predicate((e) => e.toString().contains('no se cargó completa'))),
    );
    expect(replacementIds, isNull);
    expect(nav.playlistVersion, 0);
  });

  test('removing a track uses the server index, not a local copy', () async {
    serverEntries = ['primera', 'segunda', 'tercera'];
    expect(
        await nav.removeTrackFromPlaylist(
            playlistId: 'playlist-1', trackId: 'tercera'),
        isTrue);
    expect(removedIndexes, ['2']);
  });

  test('reordering a playlist replaces entries in the chosen order', () async {
    await nav.reorderPlaylistTracks(
      playlistId: 'playlist-1',
      orderedSongIds: ['tercera', 'primera', 'segunda'],
    );

    expect(replacementIds, ['tercera', 'primera', 'segunda']);
    expect(nav.playlistVersion, 1);
  });
}
