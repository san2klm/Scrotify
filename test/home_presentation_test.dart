import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:crotowave/screens/home_screen.dart';
import 'package:crotowave/screens/mobile_home_screen.dart';
import 'package:crotowave/services/app_theme.dart';
import 'package:crotowave/services/connect/connect_service.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/utils/tv_mode.dart';
import 'package:crotowave/widgets/global_top_bar.dart';

import 'support/app_fakes.dart';

final _track = Track(
  id: 'prueba',
  title: 'Una canción con un título muy largo para comprobar la distribución',
  artist: 'Artista con un nombre extenso',
  album: 'Álbum de prueba',
  duration: '240',
);

class _Biblioteca extends FakeNavidrome {
  @override
  Future<List<Track>> getTracks(
          {String? artist,
          String? album,
          int limit = 500,
          int offset = 0}) async =>
      [_track];
  @override
  Future<List<Track>> getRecentlyAddedTracks({int limit = 20}) async =>
      [_track];
  @override
  Future<List<String>> getGenres() async => [];
  @override
  Future<List<Album>> getAlbums(
          {String type = 'newest', int limit = 50, int offset = 0}) async =>
      [
        Album(
            id: 'album',
            title: _track.title,
            artist: _track.artist,
            trackCount: 1,
            year: 2026)
      ];
  @override
  Future<List<dynamic>> getArtists() async => [
        {'id': 'artista', 'name': _track.artist},
      ];
}

class _Reproductor extends IdlePlayer {
  @override
  List<MostPlayedItem> get mostPlayed => [MostPlayedItem.track(_track)];
  @override
  List<Track> get recentlyPlayed => [_track];
}

class _Tema extends ThemeController {
  _Tema(this.tema);
  final AppTheme tema;
  @override
  AppTheme get active => tema;
}

AppTheme _temaImportado() {
  final archive = Archive();
  for (final entry in {
    'manifest.json': jsonEncode({
      'id': 'prueba-importada',
      'name': 'Prueba',
      'version': '1.0.0',
      'mode': 'light'
    }),
    'theme.css': ':root { --bg-app: #f6f0e8; --bg-card: #ffffff; '
        '--text-primary: #252525; --text-secondary: #454545; --accent: #73409a; }',
  }.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return AppTheme.fromZipBytes(ZipEncoder().encode(archive))!;
}

void main() {
  final temas = [
    AppTheme.fixedThemes.firstWhere((t) => t.id == 'mocha'),
    AppTheme.fixedThemes.firstWhere((t) => t.id == 'latte'),
    _temaImportado(),
  ];
  for (final tema in temas) {
    for (final size in [
      const Size(375, 812),
      const Size(667, 375),
      const Size(720, 480),
      const Size(1440, 900)
    ]) {
      for (final escala in [1.0, 1.5]) {
        testWidgets('Inicio con contenido: ${tema.id}, $size, texto $escala',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<NavidromeService>(
                  create: (_) => _Biblioteca()),
              ChangeNotifierProvider<PlayerController>(
                  create: (_) => _Reproductor()),
              ChangeNotifierProvider<ThemeController>(
                  create: (_) => _Tema(tema)),
              ChangeNotifierProvider<ConnectService>(
                  create: (_) => idleConnectService()),
              ChangeNotifierProvider<CrotoLinkController>(
                  create: (_) => IdleCrotoLink()),
            ],
            child: MaterialApp(
                theme: tema.toThemeData(),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(escala)),
                    child: child!),
                home: size.width < 700
                    ? const MobileHomeScreen()
                    : const HomeScreen()),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Recomendados para ti'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        });
      }
    }
  }

  testWidgets('En una tele el foco inicial cae en el contenido, no en la barra',
      (tester) async {
    TvMode.debugSet(true);
    addTearDown(() => TvMode.debugSet(false));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tema = temas.first;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NavidromeService>(create: (_) => _Biblioteca()),
        ChangeNotifierProvider<PlayerController>(create: (_) => _Reproductor()),
        ChangeNotifierProvider<ThemeController>(create: (_) => _Tema(tema)),
        ChangeNotifierProvider<ConnectService>(
            create: (_) => idleConnectService()),
        ChangeNotifierProvider<CrotoLinkController>(
            create: (_) => IdleCrotoLink()),
      ],
      child: MaterialApp(theme: tema.toThemeData(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(focused, isNot(isA<FocusScopeNode>()),
        reason: 'debe haber un elemento concreto enfocado, no solo el ámbito');
    expect(
        focused!.context!.findAncestorWidgetOfExactType<GlobalTopBar>(), isNull,
        reason: 'el foco no debe quedarse en la barra superior');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
