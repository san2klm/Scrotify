// Salidas de audio de mpv (propiedad `audio-device-list`).
//
// En Linux solo las salidas ALSA `hw:` hablan directamente con la tarjeta, sin
// mezclador ni remuestreo del sistema: son las únicas que permiten bit-perfect
// real. PipeWire, PulseAudio, `default` o `plughw:` mezclan o convierten.

import 'dart:convert';

class AudioOutputDevice {
  const AudioOutputDevice(this.name, this.description);

  /// Identificador de mpv (`alsa/hw:CARD=DAC,DEV=0`).
  final String name;
  final String description;

  bool get isDirectHardware => isValidDirectDevice(name);
}

final _directDevice = RegExp(r'^alsa/hw:[A-Za-z0-9_=,.:+-]{1,120}$');

/// `true` si [name] es una salida ALSA `hw:` con caracteres seguros para
/// pasarla a mpv.
bool isValidDirectDevice(String? name) =>
    name != null && _directDevice.hasMatch(name);

/// Interpreta el JSON de `audio-device-list`; devuelve vacío ante cualquier
/// entrada inesperada.
List<AudioOutputDevice> parseAudioDeviceList(Object? raw) {
  try {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! List) return const [];
    return [
      for (final entry in data)
        if (entry is Map && entry['name'] is String)
          AudioOutputDevice(
            entry['name'] as String,
            entry['description'] is String
                ? entry['description'] as String
                : entry['name'] as String,
          ),
    ];
  } catch (_) {
    return const [];
  }
}

List<AudioOutputDevice> directHardwareDevices(
        Iterable<AudioOutputDevice> devices) =>
    [
      for (final d in devices)
        if (d.isDirectHardware) d
    ];
