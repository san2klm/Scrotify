import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/desktop_media_keys.dart';
import 'package:crotowave/services/player_controller.dart';

class _Player extends Fake implements PlayerController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Windows media keys send valid native codes and non-null modifiers',
      () async {
    if (!Platform.isWindows) return;
    const channel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');
    const events =
        MethodChannel('dev.leanflutter.plugins/hotkey_manager_event');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final codes = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'register') {
        final args = call.arguments as Map;
        expect(args['modifiers'], isEmpty);
        codes.add(args['keyCode'] as int);
      }
      return true;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final keys = DesktopMediaKeys(_Player());
    try {
      await keys.start();
      expect(codes, [0xB3, 0xB0, 0xB1]);
    } finally {
      await keys.stop();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
