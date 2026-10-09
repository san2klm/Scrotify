// Conexión del ecualizador con el motor mpv de escritorio.
//
// just_audio_media_kit crea un reproductor mpv por cada AudioPlayer de just_audio
// (A y B del crossfade). Las propiedades se fijan en TODOS los que existan: así
// el crossfade nunca mezcla una pista ecualizada con otra sin ecualizar.

import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';

import '../hifi/audio_output_devices.dart';
import 'eq_backends.dart';

/// Fija la propiedad mpv [name] en todos los reproductores activos.
Future<void> setMpvProperty(String name, String value) async {
  for (final player in JustAudioMediaKit.mpvPlayers) {
    final platform = player.platform;
    if (platform is! NativePlayer) continue;
    try {
      await platform.setProperty(name, value);
    } catch (e) {
      debugPrint('mpv: no se pudo fijar $name ($e)');
    }
  }
}

/// Salidas de audio que mpv ve ahora (`audio-device-list`), leídas del primer
/// reproductor activo; vacío si todavía no hay ninguno.
Future<List<AudioOutputDevice>> listMpvOutputDevices() async {
  for (final player in JustAudioMediaKit.mpvPlayers) {
    final platform = player.platform;
    if (platform is! NativePlayer) continue;
    try {
      return parseAudioDeviceList(
          await platform.getProperty('audio-device-list'));
    } catch (e) {
      debugPrint('mpv: no se pudo leer audio-device-list ($e)');
    }
  }
  return const [];
}

/// Backend de ecualizador para escritorio (Linux, Windows y macOS).
MpvEqBackend createDesktopEqBackend() => MpvEqBackend([setMpvProperty]);
