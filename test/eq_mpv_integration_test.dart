import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:crotowave/services/eq/eq_mpv_setup.dart';
import 'package:crotowave/services/hifi/hifi_coordinator.dart';
import 'package:crotowave/services/hifi/hifi_profiles.dart';
import 'package:crotowave/services/eq/eq_presets.dart';
import 'package:crotowave/services/equalizer_service.dart';

/// WAV estéreo de 16 bits con un tono de 440 Hz.
Uint8List _tone(int seconds) {
  const rate = 44100;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 4);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 4, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 4, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 4, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (8000 * math.sin(2 * math.pi * 440 * i / rate)).round();
    data.setInt16(44 + i * 4, v, Endian.little);
    data.setInt16(46 + i * 4, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Prueba con el motor mpv real (libmpv del sistema). Se omite si no existe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final libmpv = ['/usr/lib/libmpv.so', '/usr/lib/x86_64-linux-gnu/libmpv.so']
      .where((p) => File(p).existsSync())
      .firstOrNull;

  test('el ecualizador llega al filtro af de mpv y no rompe la reproducción',
      () async {
    // `pitch` instala su propio `af` (scaletempo) y pisaría el del ecualizador.
    JustAudioMediaKit.pitch = false;
    JustAudioMediaKit.ensureInitialized(libmpv: libmpv);
    final dir = await Directory.systemTemp.createTemp('crotowave-eq-mpv-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/tono.wav')..writeAsBytesSync(_tone(4));

    final eq = EqualizerService(storageDir: dir);
    addTearDown(eq.dispose);
    // just_audio crea el motor al cargar la primera pista.
    JustAudioMediaKit.onPlayerReady = () => eq.reapply();
    await eq.attachBackend(createDesktopEqBackend());
    await eq.selectProfile(EqPresets.simple[1]); // «Más graves»

    final player = AudioPlayer();
    addTearDown(player.dispose);
    await player.setFilePath(file.path);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final mpv = JustAudioMediaKit.mpvPlayers.first.platform as NativePlayer;
    final on = await mpv.getProperty('af');
    expect(on, contains('bass=f=105.0'));
    expect(on, contains('alimiter'));

    await eq.setEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await mpv.getProperty('af'), isNot(contains('bass')));

    await eq.setEnabled(true);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(player.position, greaterThan(Duration.zero));
  },
      skip: libmpv == null ? 'libmpv no está instalada' : false,
      timeout: const Timeout(Duration(seconds: 60)));

  test('mpv acepta todas las propiedades de los modos de fidelidad', () async {
    JustAudioMediaKit.pitch = false;
    JustAudioMediaKit.ensureInitialized(libmpv: libmpv);
    final dir = await Directory.systemTemp.createTemp('crotowave-hifi-mpv-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/tono.wav')..writeAsBytesSync(_tone(2));
    final player = AudioPlayer();
    addTearDown(player.dispose);
    await player.setFilePath(file.path);
    final mpv = JustAudioMediaKit.mpvPlayers.first.platform as NativePlayer;

    for (final mode in AudioFidelityMode.values) {
      final plan = HifiPlanner.plan(
        mode: mode,
        platform: HifiPlatform.linux,
        network: NetworkKind.wifiOrEthernet,
        mpvEngine: true,
      );
      final props = {
        ...HifiCoordinator.mpvDefaults,
        for (final e in plan.mpvProperties.entries)
          if (!plan.mpvInitOnly.contains(e.key)) e.key: e.value,
      };
      for (final e in props.entries) {
        // Una propiedad inexistente lanzaría: así se detecta una versión de mpv incompatible.
        await mpv.setProperty(e.key, e.value);
      }
    }
    await mpv.setProperty('af', '');
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(player.position, greaterThan(Duration.zero));
  },
      skip: libmpv == null ? 'libmpv no está instalada' : false,
      timeout: const Timeout(Duration(seconds: 60)));
}
