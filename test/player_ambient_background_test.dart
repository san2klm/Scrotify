import 'dart:io';
import 'dart:ui' as ui;

import 'package:crotowave/screens/player_screen.dart';
import 'package:crotowave/services/app_theme.dart';
import 'package:crotowave/services/local_music_service.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Cuenta cuántas veces se consulta la portada local (cada consulta es trabajo
/// de resolución que no debe repetirse en cada notificación del reproductor).
class _CountingMusic extends Fake implements LocalMusicService {
  int calls = 0;

  @override
  String? artworkForMetadata(String? scope,
      {String? artist, String? album, String? title}) {
    calls++;
    return null;
  }

  @override
  String? artworkForTrack(String scope, Track track) {
    calls++;
    return null;
  }
}

class _PingNavidrome extends NavidromeService {
  void ping() => notifyListeners();
}

class _ThemeOf extends ThemeController {
  _ThemeOf(this._theme);
  final AppTheme _theme;

  @override
  AppTheme get active => _theme;
}

Future<String> _writePng(WidgetTester tester, Directory dir) async {
  final file = File('${dir.path}/cover.png');
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..color = const Color(0xFFCC3344));
    final image = await recorder.endRecording().toImage(8, 8);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
  return file.uri.toString();
}

Widget _host(
  Widget child, {
  required ThemeController theme,
  LocalMusicService? music,
  NavidromeService? nav,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      Provider<LocalMusicService?>.value(value: music),
      ChangeNotifierProvider<NavidromeService?>.value(value: nav),
    ],
    child: MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    ),
  );
}

Track _track(String? art) => Track(
    id: '1',
    title: 'T',
    artist: 'A',
    album: 'B',
    duration: '10',
    albumArtUrl: art);

AppTheme _themeWhere(bool dark) =>
    AppTheme.fixedThemes.firstWhere((t) => t.isDark == dark);

void main() {
  late Directory tmp;

  // La app también provee estos servicios (Listenable) con Provider simple.
  setUpAll(() => Provider.debugCheckInvalidValueType = null);

  setUp(() => tmp = Directory.systemTemp.createTempSync('ambient_bg_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('la portada borrosa cubre toda la ventana ampliada',
      (tester) async {
    final uri = await _writePng(tester, tmp);
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(
      PlayerAmbientBackground(track: _track(uri)),
      theme: _ThemeOf(_themeWhere(true)),
    ));
    await tester.pump();

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tester.getSize(find.byType(Image)), const Size(1600, 900));
  });

  testWidgets('la resolución de la portada no se repite al reconstruir',
      (tester) async {
    final uri = await _writePng(tester, tmp);
    final music = _CountingMusic();
    final theme = _ThemeOf(_themeWhere(true));

    for (var i = 0; i < 4; i++) {
      // Instancias nuevas pero equivalentes: así llegan en cada notificación.
      await tester.pumpWidget(_host(
        PlayerAmbientBackground(track: _track(uri)),
        theme: theme,
        music: music,
      ));
      await tester.pump();
    }

    expect(music.calls, lessThanOrEqualTo(2),
        reason: 'una sola resolución por pista (artworkForTrack + metadata)');
  });

  testWidgets('una portada guardada sin credenciales se firma con la sesión',
      (tester) async {
    final nav = NavidromeService()
      ..setConnectedForTesting(
          url: 'https://musica.example.invalid',
          username: 'ana',
          password: 'clave');
    addTearDown(nav.dispose);
    const sanitized =
        'https://musica.example.invalid/rest/getCoverArt.view?id=al-1&size=300';

    await tester.pumpWidget(_host(
      PlayerAmbientBackground(track: _track(sanitized)),
      theme: _ThemeOf(_themeWhere(true)),
      nav: nav,
    ));
    await tester.pump();

    final provider = tester.widget<Image>(find.byType(Image)).image;
    final url = ((provider as ResizeImage).imageProvider as NetworkImage).url;
    expect(Uri.parse(url).queryParameters['t'], isNotEmpty);
    tester.takeException(); // la red de tests responde 400: irrelevante aquí
  });

  group('cambio de usuario en el mismo servidor', () {
    const sanitized =
        'https://musica.example.invalid/rest/getCoverArt.view?id=al-1&size=300';

    String shownUser(WidgetTester tester) {
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final url = ((provider as ResizeImage).imageProvider as NetworkImage).url;
      return Uri.parse(url).queryParameters['u']!;
    }

    void connect(NavidromeService nav, String user) =>
        nav.setConnectedForTesting(
            url: 'https://musica.example.invalid',
            username: user,
            password: 'clave');

    testWidgets('al reconstruir la misma pista se firma con el usuario nuevo',
        (tester) async {
      final nav = _PingNavidrome();
      addTearDown(nav.dispose);
      connect(nav, 'ana');
      final theme = _ThemeOf(_themeWhere(true));

      await tester.pumpWidget(_host(
          PlayerAmbientBackground(track: _track(sanitized)),
          theme: theme,
          nav: nav));
      await tester.pump();
      expect(shownUser(tester), 'ana');

      connect(nav, 'bob');
      await tester.pumpWidget(_host(
          PlayerAmbientBackground(track: _track(sanitized)),
          theme: theme,
          nav: nav));
      await tester.pump();

      expect(shownUser(tester), 'bob');
      tester.takeException();
    });

    testWidgets('si solo notifica el servicio también se vuelve a firmar',
        (tester) async {
      final nav = _PingNavidrome();
      addTearDown(nav.dispose);
      connect(nav, 'ana');

      await tester.pumpWidget(_host(
          PlayerAmbientBackground(track: _track(sanitized)),
          theme: _ThemeOf(_themeWhere(true)),
          nav: nav));
      await tester.pump();
      expect(shownUser(tester), 'ana');

      connect(nav, 'bob');
      nav.ping();
      await tester.pump();
      await tester.pump();

      expect(shownUser(tester), 'bob');
      tester.takeException();
    });
  });

  for (final dark in [true, false]) {
    testWidgets(
        'el tinte no oscurece la portada (tema ${dark ? 'oscuro' : 'claro'})',
        (tester) async {
      final uri = await _writePng(tester, tmp);
      await tester.pumpWidget(_host(
        PlayerAmbientBackground(track: _track(uri)),
        theme: _ThemeOf(_themeWhere(dark)),
      ));
      await tester.pump();

      final tint = tester.widget<Image>(find.byType(Image)).color!;
      expect(tint.computeLuminance(), greaterThan(0.9),
          reason: 'modulate con un color oscuro pinta la portada de negro');
    });
  }
}
