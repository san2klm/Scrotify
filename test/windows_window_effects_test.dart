import 'package:crotowave/services/windows_window_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Configura host transparente sin blur y restaura fondo opaco', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const host = MethodChannel('window_manager');
    messenger.setMockMethodCallHandler(host, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(WindowsWindowEffects.channel,
        (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(host, null);
      messenger.setMockMethodCallHandler(WindowsWindowEffects.channel, null);
    });
    await WindowsWindowEffects.apply(
        transparent: true, dark: true, background: Colors.black);
    expect(calls.map((c) => c.method), ['setBackgroundColor', 'setEffects']);
    expect((calls[0].arguments as Map)['backgroundColorA'], 0);
    expect(
        calls[1].arguments, {'transparent': true, 'blur': false, 'dark': true});
    calls.clear();
    await WindowsWindowEffects.apply(
        transparent: false, dark: false, background: Colors.white);
    expect((calls[0].arguments as Map)['backgroundColorA'], 255);
    expect(calls[1].arguments,
        {'transparent': false, 'blur': false, 'dark': false});
    expect(calls.any((c) => c.method == 'setOpacity'), isFalse);
  });
}
