import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:navidrome_client/services/hifi/hifi_coordinator.dart';
import 'package:navidrome_client/services/hifi/hifi_profiles.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/settings_controller.dart';

import 'support/app_fakes.dart';

HifiPlan _plan(AudioFidelityMode mode,
        {HifiPlatform platform = HifiPlatform.linux, bool mpv = true}) =>
    HifiPlanner.plan(
      mode: mode,
      platform: platform,
      network: NetworkKind.wifiOrEthernet,
      mpvEngine: mpv,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HifiCoordinator', () {
    late SettingsController settings;
    late List<HifiPlan> applied;
    late List<bool> eqAllowed;
    late List<(String, String)> mpv;
    late HifiCoordinator coordinator;

    setUp(() {
      settings = SettingsController();
      applied = [];
      eqAllowed = [];
      mpv = [];
      coordinator = HifiCoordinator(
        settings: settings,
        applyToPlayer: (p) async => applied.add(p),
        setEqAllowed: (a) async => eqAllowed.add(a),
        setMpvProperty: (k, v) async => mpv.add((k, v)),
        platform: HifiPlatform.linux,
        mpvEngine: true,
      );
    });

    tearDown(() => coordinator.dispose());

    test('Estándar aplica el plan pero no toca mpv', () async {
      await coordinator.refresh();
      expect(applied.single.mode, AudioFidelityMode.standard);
      expect(eqAllowed, [true]);
      expect(mpv, isEmpty);
    });

    test('Alta fidelidad fija las propiedades de mpv y permite el EQ',
        () async {
      settings.setFidelityMode(AudioFidelityMode.highFidelity);
      await coordinator.refresh();
      expect(eqAllowed.last, isTrue);
      final props = {for (final e in mpv) e.$1: e.$2};
      expect(props['audio-swresample-o'], contains('soxr'));
      expect(props['audio-samplerate'], '0');
    });

    test('Bit-perfect en Linux conserva la salida del sistema sin exclusividad',
        () async {
      settings.setFidelityMode(AudioFidelityMode.bitPerfect);
      await coordinator.refresh();
      expect(applied.last.allowEq, isFalse);
      expect(applied.last.lockVolumeAt100, isTrue);
      expect(eqAllowed.last, isFalse);
      final props = {for (final e in mpv) e.$1: e.$2};
      expect(props.containsKey('ao'), isFalse);
      expect(props['audio-exclusive'], 'no');
      expect(props['af'], '');
      expect(props['volume'], '100');
    });

    test('al volver a Estándar se restauran los valores de mpv', () async {
      settings.setFidelityMode(AudioFidelityMode.highFidelity);
      await coordinator.refresh();
      mpv.clear();
      settings.setFidelityMode(AudioFidelityMode.standard);
      await coordinator.refresh();
      final props = {for (final e in mpv) e.$1: e.$2};
      expect(props['audio-swresample-o'], '');
      expect(props['audio-exclusive'], 'no');
      expect(eqAllowed.last, isTrue);
    });

    test('no repite el trabajo si no cambió nada relevante', () async {
      await coordinator.refresh();
      await coordinator.refresh();
      expect(applied, hasLength(1));
      await coordinator.refresh(force: true);
      expect(applied, hasLength(2));
    });

    test('reacciona a los cambios de Ajustes una vez iniciado', () async {
      coordinator.start();
      await Future<void>.delayed(Duration.zero);
      settings.setFidelityMode(AudioFidelityMode.bitPerfect);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(applied.last.mode, AudioFidelityMode.bitPerfect);
    });
  });

  test('WASAPI y CoreAudio mantienen su salida exclusiva', () {
    for (final platform in [HifiPlatform.windows, HifiPlatform.macos]) {
      final plan = _plan(AudioFidelityMode.bitPerfect, platform: platform);
      expect(plan.mpvProperties['audio-exclusive'], 'yes');
      expect(plan.mpvProperties['ao'],
          platform == HifiPlatform.windows ? 'wasapi' : 'coreaudio');
    }
  });

  group('PlayerController.applyHifi', () {
    late SettingsController settings;
    late FakeNavidrome nav;
    late PlayerController player;

    setUp(() {
      settings = SettingsController();
      nav = FakeNavidrome();
      player = PlayerController(nav, settings);
    });

    tearDown(() => player.dispose());

    test('Bit-perfect fija el volumen al 100 % y lo restaura al salir',
        () async {
      await player.setVolume(0.4);
      expect(player.volume, 0.4);

      await player.applyHifi(_plan(AudioFidelityMode.bitPerfect));
      expect(player.volumeLocked, isTrue);
      expect(player.volume, 1.0);
      await player.setVolume(0.2); // ignorado
      expect(player.volume, 1.0);

      await player.applyHifi(_plan(AudioFidelityMode.standard));
      expect(player.volumeLocked, isFalse);
      expect(player.volume, 0.4);
    });

    test('Alta fidelidad pide el archivo original; Estándar no lo impone',
        () async {
      await player.applyHifi(_plan(AudioFidelityMode.highFidelity));
      expect(nav.hifiStream?.format, 'raw');
      await player.applyHifi(_plan(AudioFidelityMode.standard));
      expect(nav.hifiStream, isNull);
    });
  });

  group('URL de reproducción', () {
    NavidromeService connected() {
      final nav = NavidromeService();
      nav.setConnectedForTesting(
        url: 'https://mock.navidrome.org',
        username: 'u',
        password: 'p',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      return nav;
    }

    test('sin modo de fidelidad usa la calidad de los ajustes', () {
      final nav = connected();
      final lossless = Uri.parse(
          nav.getPlaybackStreamUrl('t1', quality: AudioQuality.lossless));
      expect(lossless.queryParameters.containsKey('format'), isFalse);
      final mp3 = Uri.parse(
          nav.getPlaybackStreamUrl('t1', quality: AudioQuality.high192));
      expect(mp3.queryParameters['format'], 'mp3');
      expect(mp3.queryParameters['maxBitRate'], '192');
    });

    test('con Alta fidelidad pide el original con tamaño conocido', () {
      final nav = connected()..hifiStream = StreamQuality.original;
      final url = Uri.parse(
          nav.getPlaybackStreamUrl('t1', quality: AudioQuality.low96));
      expect(url.queryParameters['format'], 'raw');
      expect(url.queryParameters['maxBitRate'], '0');
      expect(url.queryParameters['estimateContentLength'], 'true');
    });

    test('las descargas no se ven afectadas por el modo de fidelidad', () {
      final nav = connected()..hifiStream = StreamQuality.original;
      final url =
          Uri.parse(nav.getStreamUrl('t1', quality: AudioQuality.high192));
      expect(url.queryParameters['format'], 'mp3');
    });
  });

  test('Track lee frecuencia y profundidad (OpenSubsonic)', () {
    final t = Track.fromJson({
      'id': 'x',
      'title': 'T',
      'samplingRate': 96000,
      'bitDepth': 24,
    });
    expect(t.samplingRate, 96000);
    expect(t.bitDepth, 24);
    expect(t.copyWith(title: 'U').samplingRate, 96000);
  });
}
