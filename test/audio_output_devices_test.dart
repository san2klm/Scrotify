import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/hifi/audio_output_devices.dart';
import 'package:crotowave/services/hifi/hifi_coordinator.dart';
import 'package:crotowave/services/hifi/hifi_profiles.dart';
import 'package:crotowave/services/settings_controller.dart';

const _list = [
  {'name': 'auto', 'description': 'Autoselect device'},
  {'name': 'pipewire', 'description': 'Default (PipeWire)'},
  {'name': 'alsa/default', 'description': 'Default Audio Device'},
  {'name': 'alsa/plughw:CARD=Generic,DEV=0', 'description': 'HDA (plug)'},
  {'name': 'alsa/hw:CARD=DAC,DEV=0', 'description': 'USB DAC, USB Audio'},
  {'name': 'alsa/hw:CARD=Generic,DEV=3', 'description': 'HDA HDMI 0'},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseAudioDeviceList', () {
    test('lee el JSON de audio-device-list de mpv', () {
      final devices = parseAudioDeviceList(jsonEncode(_list));
      expect(devices, hasLength(6));
      expect(devices.first.name, 'auto');
      expect(devices[4].description, 'USB DAC, USB Audio');
    });

    test('solo ofrece como bit-perfect las salidas hw: directas', () {
      final direct =
          directHardwareDevices(parseAudioDeviceList(jsonEncode(_list)));
      expect(direct.map((d) => d.name),
          ['alsa/hw:CARD=DAC,DEV=0', 'alsa/hw:CARD=Generic,DEV=3']);
    });

    test('un nombre repetido solo aparece una vez (la primera descripción)',
        () {
      final direct = directHardwareDevices(const [
        AudioOutputDevice('alsa/hw:CARD=DAC,DEV=0', 'USB DAC'),
        AudioOutputDevice('alsa/hw:CARD=DAC,DEV=0', 'USB DAC (otra vez)'),
        AudioOutputDevice('alsa/hw:CARD=Generic,DEV=3', 'HDMI'),
      ]);
      expect(direct.map((d) => d.name),
          ['alsa/hw:CARD=DAC,DEV=0', 'alsa/hw:CARD=Generic,DEV=3']);
      expect(direct.first.description, 'USB DAC');
    });

    test('entradas inválidas o ajenas se ignoran sin lanzar', () {
      expect(parseAudioDeviceList(null), isEmpty);
      expect(parseAudioDeviceList('no es json'), isEmpty);
      expect(parseAudioDeviceList('{"a":1}'), isEmpty);
      final devices = parseAudioDeviceList(jsonEncode([
        {'name': 5},
        'texto',
        {'name': 'alsa/hw:CARD=X,DEV=0'},
        {'description': 'sin nombre'},
      ]));
      expect(devices.map((d) => d.name), ['alsa/hw:CARD=X,DEV=0']);
      expect(devices.single.description, 'alsa/hw:CARD=X,DEV=0');
    });
  });

  group('isValidDirectDevice', () {
    test('acepta nombres ALSA hw: razonables', () {
      expect(isValidDirectDevice('alsa/hw:CARD=DAC,DEV=0'), isTrue);
      expect(isValidDirectDevice('alsa/hw:1,0'), isTrue);
    });
    test('rechaza lo que no sea hw: o lleve caracteres peligrosos', () {
      expect(isValidDirectDevice('alsa/plughw:CARD=X'), isFalse);
      expect(isValidDirectDevice('pipewire'), isFalse);
      expect(isValidDirectDevice('alsa/hw:X;rm -rf'), isFalse);
      expect(isValidDirectDevice('alsa/hw:X\nY'), isFalse);
      expect(isValidDirectDevice(''), isFalse);
      expect(isValidDirectDevice(null), isFalse);
    });
  });

  group('HifiPlanner con salida elegida', () {
    HifiPlan plan(AudioFidelityMode mode,
            {String? device, HifiPlatform platform = HifiPlatform.linux}) =>
        HifiPlanner.plan(
            mode: mode,
            platform: platform,
            network: NetworkKind.wifiOrEthernet,
            mpvEngine: true,
            outputDevice: device);

    test('Linux bit-perfect con hw: fija audio-device', () {
      final p =
          plan(AudioFidelityMode.bitPerfect, device: 'alsa/hw:CARD=DAC,DEV=0');
      expect(p.mpvProperties['audio-device'], 'alsa/hw:CARD=DAC,DEV=0');
      expect(p.mpvProperties['audio-exclusive'], 'no');
      expect(p.notes.join(' '), contains('ALSA'));
    });

    test('sin dispositivo se conserva la salida del sistema', () {
      final p = plan(AudioFidelityMode.bitPerfect);
      expect(p.mpvProperties.containsKey('audio-device'), isFalse);
      expect(p.mpvProperties['audio-exclusive'], 'no');
    });

    test('un dispositivo inválido se ignora', () {
      final p = plan(AudioFidelityMode.bitPerfect, device: 'pipewire');
      expect(p.mpvProperties.containsKey('audio-device'), isFalse);
    });

    test('fuera de bit-perfect o de Linux la elección no se aplica', () {
      expect(
          plan(AudioFidelityMode.highFidelity, device: 'alsa/hw:CARD=DAC,DEV=0')
              .mpvProperties
              .containsKey('audio-device'),
          isFalse);
      expect(
          plan(AudioFidelityMode.bitPerfect,
                  device: 'alsa/hw:CARD=DAC,DEV=0',
                  platform: HifiPlatform.windows)
              .mpvProperties
              .containsKey('audio-device'),
          isFalse);
    });
  });

  group('HifiCoordinator y salida ALSA', () {
    late SettingsController settings;
    late List<(String, String)> mpv;
    late List<AudioOutputDevice> present;
    late HifiCoordinator coordinator;

    setUp(() {
      settings = SettingsController()
        ..setFidelityMode(AudioFidelityMode.bitPerfect);
      mpv = [];
      present = parseAudioDeviceList(jsonEncode(_list));
      coordinator = HifiCoordinator(
        settings: settings,
        applyToPlayer: (_) async {},
        setEqAllowed: (_) async {},
        setMpvProperty: (k, v) async => mpv.add((k, v)),
        listOutputDevices: () async => present,
        platform: HifiPlatform.linux,
        mpvEngine: true,
      );
    });
    tearDown(() => coordinator.dispose());

    String? lastDevice() =>
        mpv.where((e) => e.$1 == 'audio-device').lastOrNull?.$2;

    test('aplica la salida elegida si existe', () async {
      settings.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      await coordinator.refresh();
      expect(lastDevice(), 'alsa/hw:CARD=DAC,DEV=0');
      expect(coordinator.outputDeviceMissing, isFalse);
    });

    test('si el dispositivo se desconecta vuelve a auto y avisa', () async {
      settings.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      await coordinator.refresh();
      expect(lastDevice(), 'alsa/hw:CARD=DAC,DEV=0');

      present = present.where((d) => !d.name.contains('DAC')).toList();
      await coordinator.refresh(force: true);
      expect(lastDevice(), 'auto');
      expect(coordinator.outputDeviceMissing, isTrue);
      expect(coordinator.plan!.notes.join(' '), contains('no está disponible'));
    });

    test('si ya no estaba al arrancar solo avisa, sin tocar mpv', () async {
      settings.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      present = present.where((d) => !d.name.contains('DAC')).toList();
      await coordinator.refresh();
      expect(lastDevice(), isNull);
      expect(coordinator.outputDeviceMissing, isTrue);
      expect(
          coordinator.plan!.mpvProperties.containsKey('audio-device'), isFalse);
    });

    test('al salir de bit-perfect se restaura la salida automática', () async {
      settings.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      await coordinator.refresh();
      mpv.clear();
      settings.setFidelityMode(AudioFidelityMode.highFidelity);
      await coordinator.refresh();
      expect(lastDevice(), 'auto');
    });

    test('sin elección no toca audio-device', () async {
      await coordinator.refresh();
      expect(lastDevice(), isNull);
    });

    test('cambiar de dispositivo lo reaplica', () async {
      settings.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      await coordinator.refresh();
      settings.setAudioOutputDevice('alsa/hw:CARD=Generic,DEV=3');
      await coordinator.refresh();
      expect(lastDevice(), 'alsa/hw:CARD=Generic,DEV=3');
    });
  });

  group('SettingsController.audioOutputDevice', () {
    test('solo acepta salidas hw: válidas', () {
      final s = SettingsController();
      s.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      expect(s.audioOutputDevice, 'alsa/hw:CARD=DAC,DEV=0');
      s.setAudioOutputDevice('pipewire');
      expect(s.audioOutputDevice, isNull);
      s.setAudioOutputDevice('alsa/hw:CARD=DAC,DEV=0');
      s.setAudioOutputDevice(null);
      expect(s.audioOutputDevice, isNull);
    });
  });
}
