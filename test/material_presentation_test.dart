import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/screens/album_detail_screen.dart';
import 'package:navidrome_client/screens/equalizer_screen.dart';
import 'package:navidrome_client/screens/liked_songs_screen.dart';
import 'package:navidrome_client/screens/playlist_detail_screen.dart';
import 'package:navidrome_client/screens/settings_screen.dart';
import 'package:navidrome_client/screens/stats_screen.dart';
import 'package:navidrome_client/services/app_theme.dart';
import 'package:navidrome_client/services/equalizer_service.dart';
import 'package:navidrome_client/services/connect/connect_service.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/listening_stats_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/settings_controller.dart';
import 'package:navidrome_client/services/sync/sync_service.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/utils/tv_mode.dart';
import 'package:navidrome_client/widgets/theme_grid.dart';

import 'support/app_fakes.dart';

final _track = Track(
    id: 'cancion',
    title: 'Una canción con un título muy largo',
    artist: 'Un artista con un nombre extenso',
    album: 'Álbum',
    duration: '240');
final _album = Album(
    id: 'album',
    title: _track.title,
    artist: _track.artist,
    trackCount: 1,
    year: 2026);
final _playlist = Playlist(
    id: 'lista',
    name: 'Una playlist con un nombre muy largo',
    songCount: 1,
    duration: 240);

AppTheme _imported() {
  final archive = Archive();
  for (final entry in {
    'manifest.json': jsonEncode({
      'id': 'prueba-material',
      'name': 'Tema importado con nombre largo',
      'version': '1.0.0',
      'mode': 'light'
    }),
    'theme.css': ':root { --bg-app: #f6f0e8; --bg-card: #ffffff; '
        '--text-primary: #252525; --text-secondary: #454545; --accent: #73409a; }',
  }.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return AppTheme.fromZipBytes(ZipEncoder().encode(archive),
      sourceZipPath: '/tmp/prueba-material.zip')!;
}

class _Themes extends ThemeController {
  _Themes(this.current, this.imported);
  AppTheme current;
  final AppTheme imported;
  int rescans = 0;
  String? deleted;
  @override
  AppTheme get active => current;
  @override
  String get activeId => current.id;
  @override
  List<AppTheme> get themes => [...AppTheme.fixedThemes, imported];
  @override
  String get themesDir =>
      '/carpeta/con/un/nombre/muy/largo/para/los/temas/de/scrotify';
  @override
  bool get loading => false;
  @override
  Future<void> selectTheme(String id) async {
    current = themes.firstWhere((t) => t.id == id);
    notifyListeners();
  }

  @override
  Future<void> rescan() async {
    rescans++;
  }

  @override
  Future<void> deleteTheme(String id) async {
    deleted = id;
  }
}

class _Library extends FakeNavidrome {
  @override
  Future<List<Track>> getAlbumTracks(String albumId) async => [_track];
  @override
  Future<List<Track>> getPlaylistTracks(String playlistId) async => [_track];
  @override
  Future<List<Track>> getStarred() async => [_track];
}

class _Stats extends ChangeNotifier implements ListeningStatsService {
  @override
  Duration getTotalListeningDuration({String? serverScope}) =>
      const Duration(hours: 2);
  @override
  int getTotalPlayCount({String? serverScope}) => 12;
  @override
  List<TrackStat> getTopTracks({int limit = 10, String? serverScope}) => [
        TrackStat(
            trackId: _track.id,
            title: _track.title,
            artist: _track.artist,
            album: _track.album,
            playCount: 12,
            totalDuration: const Duration(hours: 2))
      ];
  @override
  List<ArtistStat> getTopArtists({int limit = 10, String? serverScope}) => [
        ArtistStat(
            name: _track.artist,
            playCount: 12,
            totalDuration: const Duration(hours: 2))
      ];
  @override
  List<GenreStat> getTopGenres({int limit = 10, String? serverScope}) => [
        const GenreStat(
            name: 'Rock', playCount: 12, totalDuration: Duration(hours: 2))
      ];
  @override
  List<TimeSeriesPoint> getDailyListening(
          {int days = 7, String? serverScope}) =>
      List.generate(
          days,
          (i) => TimeSeriesPoint(
              label: 'D${i + 1}',
              date: DateTime(2026, 10, i + 1),
              duration: Duration(minutes: i * 5),
              playCount: i));
  @override
  List<TimeSeriesPoint> getWeeklyListening(
          {int weeks = 4, String? serverScope}) =>
      getDailyListening(days: weeks);
  @override
  List<TimeSeriesPoint> getMonthlyListening(
          {int months = 6, String? serverScope}) =>
      getDailyListening(days: months);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget screen, _Themes themes,
    Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themes),
        ChangeNotifierProvider<NavidromeService>(create: (_) => _Library()),
        ChangeNotifierProvider<PlayerController>(create: (_) => IdlePlayer()),
        ChangeNotifierProvider<ConnectService>(
            create: (_) => idleConnectService()),
        ChangeNotifierProvider<JamController>(create: (_) => IdleJam()),
        ChangeNotifierProvider<SettingsController>(
            create: (_) => SettingsController()),
        ChangeNotifierProvider<SyncService>(
            create: (_) => SyncService(
                  dataDir: () async => Directory.systemTemp,
                  themeImportsDir: () async => Directory.systemTemp,
                  serverBase: () => null,
                  readKey: () async => null,
                  writeKey: (_) async {},
                )),
        ChangeNotifierProvider<EqualizerService>(
            create: (_) => EqualizerService()),
        ChangeNotifierProvider<ListeningStatsService>(create: (_) => _Stats()),
      ],
      child: Consumer<ThemeController>(
          builder: (context, controller, _) => MaterialApp(
                theme: controller.active.toThemeData(),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true),
                    child: child!),
                home: RepaintBoundary(
                    key: const ValueKey('captura-material'), child: screen),
              ))));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Capturas opcionales con las fuentes del SDK; las pruebas normales usan Ahem.
    if (Platform.environment['SCROTIFY_UI_CAPTURE'] != '1') return;
    final fontDir = Platform.environment['SCROTIFY_UI_FONT_DIR'];
    if (fontDir == null) return;
    for (final entry in {
      'Ahem': 'Roboto-Regular.ttf',
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf'
    }.entries) {
      final bytes = await File('$fontDir/${entry.value}').readAsBytes();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  final imported = _imported();
  final themes = [AppTheme.fixedThemes[0], AppTheme.fixedThemes[1], imported];
  for (final entry in <String, String>{
    'Audio y calidad': 'Detectar red automáticamente',
    'Reproducción': 'Crossfade',
    'Apariencia y temas': 'Resolución de portadas',
    'Servidor Jam': 'Servidor Jam',
  }.entries) {
    testWidgets('ajustes: categoría ${entry.key} abre su subpantalla',
        (tester) async {
      await _pump(tester, const SettingsScreen(), _Themes(themes[0], imported),
          const Size(375, 812), 1.5);
      await tester.ensureVisible(find.text(entry.key).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(entry.value), findsWidgets);
    });
  }
  testWidgets(
      'ajustes: activar Bit-perfect no rompe la subpantalla ni al volver',
      (tester) async {
    await _pump(tester, const SettingsScreen(), _Themes(themes[0], imported),
        const Size(1100, 800), 1);
    await tester.tap(find.text('Audio y calidad').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Bit-perfect'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bit-perfect'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (Platform.isLinux) {
      // El selector de salida ALSA solo existe en Linux.
      await tester.scrollUntilVisible(
          find.byTooltip('Buscar salidas de nuevo'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.ensureVisible(find.byTooltip('Buscar salidas de nuevo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Buscar salidas de nuevo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Salida del sistema'), findsOneWidget);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reproducción'), findsWidgets);
  });

  group('Android TV con el control remoto', () {
    tearDown(() => TvMode.debugSet(false));

    bool focusedHasText(String text) {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return false;
      var found = false;
      void visit(Element element) {
        final widget = element.widget;
        if (widget is Text && widget.data == text) found = true;
        if (!found) element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
      return found;
    }

    testWidgets('Ajustes empieza en la primera categoría, no en la barra',
        (tester) async {
      TvMode.debugSet(true);
      await _pump(tester, const SettingsScreen(), _Themes(themes[0], imported),
          const Size(1920, 1080), 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(focusedHasText('Audio y calidad'), isTrue);
    });

    testWidgets('con las flechas se recorren todas las categorías y se vuelve',
        (tester) async {
      TvMode.debugSet(true);
      await _pump(tester, const SettingsScreen(), _Themes(themes[0], imported),
          const Size(1920, 1080), 1);
      await tester.pump(const Duration(milliseconds: 250));

      final visited = <String>[];
      for (final title in [
        'Audio y calidad',
        'Reproducción',
        'Ecualizador',
        'Apariencia y temas',
        'Biblioteca y descargas',
        'Servidor Jam',
        'Estadísticas de escucha',
      ]) {
        expect(focusedHasText(title), isTrue, reason: 'debía estar en $title');
        visited.add(title);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(visited, hasLength(7));
      expect(tester.takeException(), isNull);

      // Y hacia arriba se llega otra vez a la primera sin quedar atrapado.
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(focusedHasText('Audio y calidad'), isTrue);
    });

    testWidgets('OK abre una categoría y Atrás vuelve a la lista',
        (tester) async {
      TvMode.debugSet(true);
      await _pump(tester, const SettingsScreen(), _Themes(themes[0], imported),
          const Size(1920, 1080), 1);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // Reproducción
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Crossfade'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Crossfade'), findsNothing);
      expect(find.text('Reproducción'), findsOneWidget);
    });

    testWidgets('dentro de una subpágina las flechas pasan por los ajustes',
        (tester) async {
      TvMode.debugSet(true);
      await _pump(tester, const SettingsScreen(), _Themes(themes[0], imported),
          const Size(1920, 1080), 1);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.sendKeyEvent(LogicalKeyboardKey.select); // Audio y calidad
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);

      final seen = <FocusNode>{};
      for (var i = 0; i < 25; i++) {
        final node = FocusManager.instance.primaryFocus;
        if (node != null) seen.add(node);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(seen.length, greaterThan(3),
          reason: 'el foco debe avanzar por varios controles');
      expect(tester.takeException(), isNull);
    });
  });

  for (final theme in themes) {
    test('Material respeta los tokens del tema ${theme.id}', () {
      final data = theme.toThemeData();
      expect(data.colorScheme.onSurface, theme.textPrimary);
      expect(data.colorScheme.surfaceContainerLow, theme.bgCard);
      expect(data.colorScheme.onPrimary, theme.textOnAccent);
      expect(data.dialogTheme.backgroundColor, theme.modalBg);
      expect(data.popupMenuTheme.color, theme.menuBg);
    });
    for (final screen in <String, Widget>{
      'temas':
          const Scaffold(body: SingleChildScrollView(child: ThemesSection())),
      'ajustes': const SettingsScreen(),
      'estadisticas': const StatsScreen(),
      'ecualizador': const EqualizerScreen(),
      'album': AlbumDetailScreen(album: _album),
      'playlist': PlaylistDetailScreen(playlist: _playlist),
      'favoritos': const LikedSongsScreen(),
    }.entries) {
      for (final size in [const Size(375, 812), const Size(1280, 800)]) {
        for (final scale in [1.0, 1.5]) {
          testWidgets('${screen.key}: ${theme.id}, $size, texto $scale',
              (tester) async {
            await _pump(
                tester, screen.value, _Themes(theme, imported), size, scale);
            expect(tester.takeException(), isNull);
            if (screen.key == 'ajustes') {
              expect(find.text('Cuenta y Perfiles'), findsNothing);
              expect(find.text('Gestionar perfiles de servidor'), findsNothing);
            }
            if (Platform.environment['SCROTIFY_UI_CAPTURE'] == '1' &&
                scale == 1 &&
                size.width == 375 &&
                ['temas', 'estadisticas', 'playlist'].contains(screen.key)) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('captura-material')));
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('/tmp/scrotify-${screen.key}-${theme.id}.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          });
        }
      }
    }
  }
  testWidgets('Temas conserva selección, reescaneo y confirmación de borrado',
      (tester) async {
    final themes = _Themes(imported, imported);
    await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: ThemesSection())),
        themes,
        const Size(1280, 800),
        1);
    await tester.tap(find.text('Reescanear'));
    expect(themes.rescans, 1);
    await tester.tap(find.byTooltip('Borrar ${imported.name}'));
    await tester.pumpAndSettle();
    expect(find.text('¿Borrar tema?'), findsOneWidget);
    expect(themes.deleted, isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(themes.deleted, isNull);
    await tester.tap(find.byTooltip('Borrar ${imported.name}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(themes.deleted, imported.id);
    final list = find.byType(ListView).first;
    await tester.drag(list, const Offset(1800, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppTheme.fixedThemes.first.name));
    await tester.pumpAndSettle();
    expect(themes.activeId, AppTheme.fixedThemes.first.id);
    expect(tester.takeException(), isNull);
  });
}
