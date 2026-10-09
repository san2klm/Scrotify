import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:navidrome_client/services/hifi/audio_output_devices.dart';
import 'package:navidrome_client/services/hifi/hifi_coordinator.dart';
import 'package:navidrome_client/services/hifi/hifi_profiles.dart';

/// WAV silencioso: permite verificar la salida real sin emitir un tono.
Uint8List _silence() {
  const frames = 44100 * 8;
  final data = ByteData(44 + frames * 4);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 44100 * 4, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * 4, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Linux mantiene audio y reloj real en el modo sin procesado', () async {
    JustAudioMediaKit.pitch = false;
    JustAudioMediaKit.ensureInitialized();
    final temp = await Directory.systemTemp.createTemp('scrotify-hifi-linux-');
    final audio = File('${temp.path}/silencio.wav');
    await audio.writeAsBytes(_silence());
    final player = AudioPlayer();
    addTearDown(() async {
      await player.dispose();
      await temp.delete(recursive: true);
    });
    await player.setFilePath(audio.path);
    final mpv = JustAudioMediaKit.mpvPlayers.last.platform as NativePlayer;
    final plan = HifiPlanner.plan(
        mode: AudioFidelityMode.bitPerfect,
        platform: HifiPlatform.linux,
        network: NetworkKind.wifiOrEthernet,
        mpvEngine: true);
    for (final entry
        in {...HifiCoordinator.mpvDefaults, ...plan.mpvProperties}.entries) {
      await mpv.setProperty(entry.key, entry.value);
    }
    final errors = <Object>[];
    unawaited(player.play().catchError((Object error) {
      errors.add(error);
    }));
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(errors, isEmpty);
    expect(await mpv.getProperty('audio-exclusive'), 'no');
    expect(await mpv.getProperty('current-ao'), isNot('null'));
    expect(player.processingState, isNot(ProcessingState.completed));
    expect(player.position.inMilliseconds, inInclusiveRange(200, 3000));
    await player.pause();
  },
      skip: !Platform.isLinux ||
              Platform.environment['SCROTIFY_AUDIO_INTEGRATION'] != '1'
          ? 'Requiere Linux con salida de audio y SCROTIFY_AUDIO_INTEGRATION=1.'
          : false,
      timeout: const Timeout(Duration(seconds: 30)));

  test('libmpv lista salidas que el selector sabe interpretar', () async {
    JustAudioMediaKit.pitch = false;
    JustAudioMediaKit.ensureInitialized();
    final player = AudioPlayer();
    addTearDown(player.dispose);
    final temp = await Directory.systemTemp.createTemp('scrotify-hifi-dev-');
    addTearDown(() => temp.delete(recursive: true));
    final audio = File('${temp.path}/silencio.wav');
    await audio.writeAsBytes(_silence());
    await player.setFilePath(audio.path);
    final mpv = JustAudioMediaKit.mpvPlayers.last.platform as NativePlayer;
    final devices =
        parseAudioDeviceList(await mpv.getProperty('audio-device-list'));
    expect(devices.map((d) => d.name), contains('auto'));
    // Volver a "auto" es siempre válido y no rompe la reproducción.
    await mpv.setProperty('audio-device', 'auto');
    expect(await mpv.getProperty('audio-device'), 'auto');
    for (final d in directHardwareDevices(devices)) {
      expect(isValidDirectDevice(d.name), isTrue, reason: d.name);
    }
  },
      skip: !Platform.isLinux ||
              Platform.environment['SCROTIFY_AUDIO_INTEGRATION'] != '1'
          ? 'Requiere Linux con salida de audio y SCROTIFY_AUDIO_INTEGRATION=1.'
          : false,
      timeout: const Timeout(Duration(seconds: 30)));
}
