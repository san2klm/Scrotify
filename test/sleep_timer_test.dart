import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/settings_controller.dart';

import 'support/app_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerController Sleep Timer Tests', () {
    late SettingsController settings;
    late FakeNavidrome navService;
    late PlayerController player;

    setUp(() {
      settings = SettingsController();
      navService = FakeNavidrome();
      player = PlayerController(navService, settings);
    });

    tearDown(() {
      player.cancelSleepTimer(silent: true);
      player.dispose();
    });

    test('initial state has no sleep timer', () {
      expect(player.hasSleepTimer, isFalse);
      expect(player.isSleepTimerEndOfTrack, isFalse);
      expect(player.sleepEndsAt, isNull);
      expect(player.sleepRemaining, isNull);
      expect(player.sleepLabel, 'Desactivado');
    });

    test('setSleepTimer with duration configures timer properly', () {
      player.setSleepTimer(const Duration(minutes: 30));

      expect(player.hasSleepTimer, isTrue);
      expect(player.isSleepTimerEndOfTrack, isFalse);
      expect(player.sleepEndsAt, isNotNull);
      expect(player.sleepRemaining!.inMinutes, inInclusiveRange(29, 30));
      expect(player.sleepLabel, anyOf('Apagar en 30 min', 'Apagar en 29 min'));
    });

    test('cancelSleepTimer clears all timer state', () {
      player.setSleepTimer(const Duration(minutes: 15));
      expect(player.hasSleepTimer, isTrue);

      player.cancelSleepTimer();

      expect(player.hasSleepTimer, isFalse);
      expect(player.isSleepTimerEndOfTrack, isFalse);
      expect(player.sleepEndsAt, isNull);
      expect(player.sleepRemaining, isNull);
      expect(player.sleepLabel, 'Desactivado');
    });

    test('setSleepTimerEndOfTrack sets end of track timer', () {
      player.setSleepTimerEndOfTrack();

      expect(player.hasSleepTimer, isTrue);
      expect(player.isSleepTimerEndOfTrack, isTrue);
      expect(player.sleepEndsAt, isNull);
      expect(player.sleepLabel, contains('Fin de la canción'));
    });

    test('setting duration sleep timer cancels previous end of track timer',
        () {
      player.setSleepTimerEndOfTrack();
      expect(player.isSleepTimerEndOfTrack, isTrue);

      player.setSleepTimer(const Duration(minutes: 45));
      expect(player.isSleepTimerEndOfTrack, isFalse);
      expect(player.hasSleepTimer, isTrue);
      expect(player.sleepRemaining!.inMinutes, inInclusiveRange(44, 45));
    });

    test('setting end of track timer cancels previous duration timer', () {
      player.setSleepTimer(const Duration(minutes: 15));
      expect(player.sleepEndsAt, isNotNull);

      player.setSleepTimerEndOfTrack();
      expect(player.sleepEndsAt, isNull);
      expect(player.isSleepTimerEndOfTrack, isTrue);
      expect(player.hasSleepTimer, isTrue);
    });
  });
}
