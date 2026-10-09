// Recorrido de humo de Ajustes: monta SettingsScreen con los mismos
// proveedores que lib/main.dart (incluido un HifiCoordinator real) por encima
// del MaterialApp —las subpantallas se abren con Navigator.push—, entra en cada
// subpantalla, toca cada opción y vuelve, sin excepciones en ningún paso.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/screens/settings_screen.dart';
import 'package:navidrome_client/services/app_theme.dart';
import 'package:navidrome_client/services/connect/connect_service.dart';
import 'package:navidrome_client/services/equalizer_service.dart';
import 'package:navidrome_client/services/hifi/audio_output_devices.dart';
import 'package:navidrome_client/services/hifi/hifi_coordinator.dart';
import 'package:navidrome_client/services/hifi/hifi_profiles.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/listening_stats_service.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/settings_controller.dart';
import 'package:navidrome_client/services/sync/sync_service.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:provider/provider.dart';

import 'support/app_fakes.dart';

class _Themes extends ThemeController {
  @override
  AppTheme get active => AppTheme.fixedThemes.first;
  @override
  String get activeId => active.id;
  @override
  List<AppTheme> get themes => AppTheme.fixedThemes;
  @override
  String get themesDir => '/tmp/temas';
  @override
  bool get loading => false;
  @override
  Future<void> rescan() async {}
}

class _Nav extends FakeNavidrome {
  @override
  Future<List<Playlist>> getPlaylists() async => [];
  @override
  Future<int?> getServerSongCount() async => 0;
}

/// Biblioteca local mínima: lo que lee la sección «Música local» de Ajustes.
class _Music extends ChangeNotifier implements LocalMusicService {
  @override
  String? get folderPath => '/storage/emulated/0/Music/Scrotify';
  @override
  bool get scanning => false;
  @override
  LocalScanProgress? get scanProgress => null;
  @override
  bool get lastScanCancelled => false;
  @override
  int get recoveredByLastScan => 0;
  @override
  int get unidentifiedByLastScan => 0;
  @override
  bool get recoveryUnavailable => false;
  @override
  int count(String? scope) => 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> rescan(
      {bool requestAccess = true,
      String? serverScope,
      Future<List<Track>> Function()? catalogLoader}) async {}
  @override
  void cancelScan() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stats extends ChangeNotifier implements ListeningStatsService {
  @override
  Duration getTotalListeningDuration({String? serverScope}) =>
      const Duration(hours: 1);
  @override
  int getTotalPlayCount({String? serverScope}) => 3;
  @override
  List<TrackStat> getTopTracks({int limit = 10, String? serverScope}) => [];
  @override
  List<ArtistStat> getTopArtists({int limit = 10, String? serverScope}) => [];
  @override
  List<GenreStat> getTopGenres({int limit = 10, String? serverScope}) => [];
  @override
  List<TimeSeriesPoint> getDailyListening(
          {int days = 7, String? serverScope}) =>
      [];
  @override
  List<TimeSeriesPoint> getWeeklyListening(
          {int weeks = 4, String? serverScope}) =>
      [];
  @override
  List<TimeSeriesPoint> getMonthlyListening(
          {int months = 6, String? serverScope}) =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AudioOutputDevice dev(String name, [String? description]) =>
    AudioOutputDevice(name, description ?? 'Salida $name');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsController settings;
  late HifiCoordinator hifi;
  var devices = <AudioOutputDevice>[];
  var listCalls = 0;

  late LocalMusicService music;

  Future<void> pumpSettings(WidgetTester tester) async {
    music = _Music();
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    settings = SettingsController();
    hifi = HifiCoordinator(
      settings: settings,
      applyToPlayer: (_) async {},
      setEqAllowed: (_) async {},
      setMpvProperty: (_, __) async {},
      listOutputDevices: () async {
        listCalls++;
        return devices;
      },
      platform: HifiPlatform.linux,
      mpvEngine: true,
    );
    final sync = SyncService(
      dataDir: () async => Directory.systemTemp,
      themeImportsDir: () async => Directory.systemTemp,
      serverBase: () => null,
      readKey: () async => null,
      writeKey: (_) async {},
    );
    hifi.start(); // como en main.dart
    addTearDown(hifi.dispose);
    addTearDown(sync.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>(create: (_) => _Themes()),
        ChangeNotifierProvider<NavidromeService>(create: (_) => _Nav()),
        ChangeNotifierProvider<PlayerController>(create: (_) => IdlePlayer()),
        ChangeNotifierProvider<ConnectService>(
            create: (_) => idleConnectService()),
        ChangeNotifierProvider<JamController>(create: (_) => IdleJam()),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<LocalMusicService>.value(value: music),
        ChangeNotifierProvider<HifiCoordinator>.value(value: hifi),
        ChangeNotifierProvider<SyncService>.value(value: sync),
        ChangeNotifierProvider<EqualizerService>(
            create: (_) => EqualizerService()),
        ChangeNotifierProvider<ListeningStatsService>(create: (_) => _Stats()),
      ],
      child: MaterialApp(
        theme: AppTheme.fixedThemes.first.toThemeData(),
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  void noErrors(WidgetTester tester, String where) =>
      expect(tester.takeException(), isNull, reason: where);

  Future<void> open(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
    noErrors(tester, 'abrir $title');
  }

  Future<void> back(WidgetTester tester, String from) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
    noErrors(tester, 'volver desde $from');
  }

  /// Activa y desactiva cada interruptor, toca cada opción de radio, mueve cada
  /// deslizador. Devuelve cuántos controles tocó.
  Future<int> exerciseControls(WidgetTester tester, String page) async {
    var touched = 0;
    final switches = find.byType(Switch).evaluate().length;
    for (var i = 0; i < switches; i++) {
      for (var round = 0; round < 2; round++) {
        final finder = find.byType(Switch).at(i);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        noErrors(tester, '$page: interruptor $i, vez ${round + 1}');
        touched++;
      }
    }
    final radios = find.byIcon(Icons.radio_button_off).evaluate().length;
    for (var i = 0; i < radios; i++) {
      final finder = find.byIcon(Icons.radio_button_off);
      if (finder.evaluate().length <= i) break; // la página cambió de forma
      await tester.ensureVisible(finder.at(i));
      await tester.pumpAndSettle();
      await tester.tap(finder.at(i));
      await tester.pumpAndSettle();
      noErrors(tester, '$page: opción $i');
      touched++;
    }
    final sliders = find.byType(Slider).evaluate().length;
    for (var i = 0; i < sliders; i++) {
      final finder = find.byType(Slider).at(i);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.drag(finder, const Offset(40, 0));
      await tester.pumpAndSettle();
      await tester.drag(finder, const Offset(-80, 0));
      await tester.pumpAndSettle();
      noErrors(tester, '$page: deslizador $i');
      touched++;
    }
    return touched;
  }

  group('menú principal', () {
    for (final page in [
      'Audio y calidad',
      'Reproducción',
      'Apariencia y temas',
      'Biblioteca y descargas',
      'Servidor Jam',
    ]) {
      testWidgets('$page: abrir, tocar todo y volver', (tester) async {
        await pumpSettings(tester);
        await open(tester, page);
        final touched = await exerciseControls(tester, page);
        if (!const {
          'Servidor Jam',
          'Apariencia y temas',
          'Biblioteca y descargas'
        }.contains(page)) {
          expect(touched, greaterThan(0),
              reason: '$page debería tener controles');
        }
        await back(tester, page);
        expect(find.text('Audio y calidad'), findsOneWidget);
      });
    }

    testWidgets('Ecualizador y Estadísticas: abrir y volver', (tester) async {
      await pumpSettings(tester);
      for (final page in ['Ecualizador', 'Estadísticas de escucha']) {
        await open(tester, page);
        await back(tester, page);
      }
    });

    testWidgets('recorrido completo seguido, dos vueltas', (tester) async {
      await pumpSettings(tester);
      for (var lap = 0; lap < 2; lap++) {
        for (final page in [
          'Audio y calidad',
          'Reproducción',
          'Apariencia y temas',
          'Biblioteca y descargas',
          'Servidor Jam',
        ]) {
          await open(tester, page);
          await exerciseControls(tester, page);
          await back(tester, page);
        }
      }
    });
  });

  group('modos de fidelidad', () {
    for (final entry in {
      'Estándar': AudioFidelityMode.standard,
      'Alta fidelidad': AudioFidelityMode.highFidelity,
      'Bit-perfect': AudioFidelityMode.bitPerfect,
    }.entries) {
      testWidgets('elegir ${entry.key} no rompe la pantalla', (tester) async {
        await pumpSettings(tester);
        await open(tester, 'Audio y calidad');
        // Primero otro modo, para que el cambio sea real.
        final other = entry.value == AudioFidelityMode.standard
            ? 'Alta fidelidad'
            : 'Estándar';
        await tester.ensureVisible(find.text(other));
        await tester.tap(find.text(other));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        noErrors(tester, 'modo ${entry.key}');
        expect(settings.fidelityMode, entry.value);
        await back(tester, 'Audio y calidad');
      });
    }

    testWidgets('pasar por los tres modos seguidos, de ida y vuelta',
        (tester) async {
      await pumpSettings(tester);
      await open(tester, 'Audio y calidad');
      for (final label in [
        'Bit-perfect',
        'Alta fidelidad',
        'Estándar',
        'Bit-perfect',
        'Estándar',
        'Alta fidelidad',
        'Bit-perfect',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        noErrors(tester, 'modo $label');
      }
    });
  });

  group('selector de salida ALSA', () {
    Future<void> openBitPerfect(WidgetTester tester) async {
      await pumpSettings(tester);
      await open(tester, 'Audio y calidad');
      await tester.ensureVisible(find.text('Bit-perfect'));
      await tester.tap(find.text('Bit-perfect'));
      await tester.pumpAndSettle();
      noErrors(tester, 'Bit-perfect');
    }

    Finder picker() => find.byType(DropdownButtonFormField<String?>);

    Future<void> openMenu(WidgetTester tester) async {
      await tester.ensureVisible(picker());
      await tester.pumpAndSettle();
      await tester.tap(picker());
      await tester.pumpAndSettle();
      noErrors(tester, 'abrir el desplegable');
    }

    setUp(() {
      devices = [];
      listCalls = 0;
    });

    testWidgets('sin salidas: solo «Salida del sistema»', (tester) async {
      devices = [];
      await openBitPerfect(tester);
      expect(picker(), findsOneWidget);
      await openMenu(tester);
      expect(find.text('Salida del sistema'), findsWidgets);
      expect(find.textContaining('Salida alsa'), findsNothing);
    }, skip: !Platform.isLinux);

    testWidgets('una salida: se puede elegir y deja de ser la del sistema',
        (tester) async {
      devices = [dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC')];
      await openBitPerfect(tester);
      await openMenu(tester);
      await tester.tap(find.text('USB DAC').last);
      await tester.pumpAndSettle();
      noErrors(tester, 'elegir la salida');
      expect(settings.audioOutputDevice, 'alsa/hw:CARD=DAC,DEV=0');
    }, skip: !Platform.isLinux);

    testWidgets('varias salidas: elegir una, otra y volver a la del sistema',
        (tester) async {
      devices = [
        dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC'),
        dev('alsa/hw:CARD=Generic,DEV=3', 'HDMI 0'),
        dev('alsa/hw:CARD=Generic,DEV=7', 'HDMI 1'),
      ];
      await openBitPerfect(tester);
      for (final entry in {
        'HDMI 0': 'alsa/hw:CARD=Generic,DEV=3',
        'USB DAC': 'alsa/hw:CARD=DAC,DEV=0',
        'HDMI 1': 'alsa/hw:CARD=Generic,DEV=7',
      }.entries) {
        await openMenu(tester);
        await tester.tap(find.text(entry.key).last);
        await tester.pumpAndSettle();
        noErrors(tester, 'elegir ${entry.key}');
        expect(settings.audioOutputDevice, entry.value);
      }
      await openMenu(tester);
      await tester.tap(find.text('Salida del sistema').last);
      await tester.pumpAndSettle();
      noErrors(tester, 'volver a la salida del sistema');
      expect(settings.audioOutputDevice, isNull);
    }, skip: !Platform.isLinux);

    testWidgets('una salida elegida que ya no está se muestra desconectada',
        (tester) async {
      devices = [dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC')];
      await pumpSettings(tester);
      settings.setAudioOutputDevice('alsa/hw:CARD=Vieja,DEV=0');
      await open(tester, 'Audio y calidad');
      await tester.ensureVisible(find.text('Bit-perfect'));
      await tester.tap(find.text('Bit-perfect'));
      await tester.pumpAndSettle();
      noErrors(tester, 'Bit-perfect con una salida ausente');
      expect(find.textContaining('(desconectada)'), findsWidgets);
      expect(hifi.outputDeviceMissing, isTrue);
      expect(find.textContaining('no está conectada'), findsOneWidget);
      await openMenu(tester);
      await tester.tap(find.text('USB DAC').last);
      await tester.pumpAndSettle();
      noErrors(tester, 'cambiar a una salida presente');
      expect(settings.audioOutputDevice, 'alsa/hw:CARD=DAC,DEV=0');
    }, skip: !Platform.isLinux);

    testWidgets('nombres repetidos en la lista no rompen el desplegable',
        (tester) async {
      devices = [
        dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC'),
        dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC (otra vez)'),
        dev('alsa/hw:CARD=Generic,DEV=3', 'HDMI 0'),
      ];
      await openBitPerfect(tester);
      await openMenu(tester);
      await tester.tap(find.text('HDMI 0').last);
      await tester.pumpAndSettle();
      noErrors(tester, 'elegir con nombres repetidos');
      expect(settings.audioOutputDevice, 'alsa/hw:CARD=Generic,DEV=3');
    }, skip: !Platform.isLinux);

    testWidgets('una salida repetida y elegida tampoco rompe', (tester) async {
      devices = [
        dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC'),
        dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC (otra vez)'),
      ];
      await pumpSettings(tester);
      settings.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      await open(tester, 'Audio y calidad');
      await tester.ensureVisible(find.text('Bit-perfect'));
      await tester.tap(find.text('Bit-perfect'));
      await tester.pumpAndSettle();
      noErrors(tester, 'elegida y repetida');
    }, skip: !Platform.isLinux);

    testWidgets(
        '«Buscar salidas de nuevo» vuelve a leer la lista y se puede '
        'elegir lo nuevo', (tester) async {
      devices = [];
      await openBitPerfect(tester);
      final before = listCalls;

      devices = [dev('alsa/hw:CARD=Nueva,DEV=0', 'DAC recién conectado')];
      await tester.ensureVisible(find.byTooltip('Buscar salidas de nuevo'));
      await tester.tap(find.byTooltip('Buscar salidas de nuevo'));
      await tester.pumpAndSettle();
      noErrors(tester, 'buscar salidas de nuevo');
      expect(listCalls, greaterThan(before));

      await openMenu(tester);
      await tester.tap(find.text('DAC recién conectado').last);
      await tester.pumpAndSettle();
      noErrors(tester, 'elegir la salida nueva');
      expect(settings.audioOutputDevice, 'alsa/hw:CARD=Nueva,DEV=0');
    }, skip: !Platform.isLinux);

    testWidgets('buscar varias veces seguidas y con la lista vacía',
        (tester) async {
      devices = [dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC')];
      await openBitPerfect(tester);
      for (var i = 0; i < 3; i++) {
        devices = i.isEven ? [] : [dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC')];
        await tester.tap(find.byTooltip('Buscar salidas de nuevo'));
        await tester.pumpAndSettle();
        noErrors(tester, 'búsqueda $i');
      }
    }, skip: !Platform.isLinux);

    testWidgets('el selector solo aparece en Bit-perfect', (tester) async {
      devices = [dev('alsa/hw:CARD=DAC,DEV=0', 'USB DAC')];
      await pumpSettings(tester);
      await open(tester, 'Audio y calidad');
      expect(picker(), findsNothing);
      await tester.ensureVisible(find.text('Bit-perfect'));
      await tester.tap(find.text('Bit-perfect'));
      await tester.pumpAndSettle();
      expect(picker(), findsOneWidget);
      await tester.ensureVisible(find.text('Alta fidelidad'));
      await tester.tap(find.text('Alta fidelidad'));
      await tester.pumpAndSettle();
      expect(picker(), findsNothing);
      noErrors(tester, 'salir de Bit-perfect');
    }, skip: !Platform.isLinux);
  });
}
