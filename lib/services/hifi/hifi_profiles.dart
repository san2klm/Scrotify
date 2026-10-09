// Modos de alta fidelidad de Scrotify, por plataforma.
//
//   Estándar       → lo que hay hoy: sonido seguro y compatible en todo.
//   Alta fidelidad → stream sin transcodificar, procesado en float, remuestreo
//                    SoXr de alta precisión. Permite EQ, ReplayGain y crossfade.
//   Bit-perfect    → los bytes del FLAC llegan intactos al DAC: sin EQ, sin
//                    ReplayGain, sin crossfade, volumen digital al 100 % y
//                    salida exclusiva cuando el sistema lo permite.
//
// Este archivo NO toca el reproductor: produce un `HifiPlan` (datos puros) que
// PlayerController aplica. Así es testeable y la UI puede mostrar qué hará.

import '../../models/eq_models.dart';

enum AudioFidelityMode { standard, highFidelity, bitPerfect }

enum HifiPlatform { linux, windows, macos, android, ios }

enum NetworkKind { wifiOrEthernet, mobile, offline }

/// Parámetros de `stream.view` (Subsonic 1.16.1 / Navidrome).
class StreamQuality {
  /// `raw` = original sin transcodificar (Navidrome); null = lo decide el server.
  final String? format;

  /// 0 = sin límite.
  final int maxBitRate;
  const StreamQuality({this.format, this.maxBitRate = 0});

  static const original = StreamQuality(format: 'raw', maxBitRate: 0);

  Map<String, String> toQuery() => {
        if (format != null) 'format': format!,
        'maxBitRate': '$maxBitRate',
        // Navidrome: permite que el reproductor conozca el tamaño y haga seek
        // instantáneo también en streams transcodificados.
        'estimateContentLength': 'true',
      };

  String get label => format == 'raw'
      ? 'Original (sin pérdida)'
      : '${format ?? 'auto'} ${maxBitRate == 0 ? '' : '$maxBitRate kbps'}'
          .trim();
}

class HifiPlan {
  final AudioFidelityMode mode;
  final StreamQuality stream;

  /// Propiedades mpv a fijar en AMBOS reproductores A/B (sólo motor mpv).
  /// Las marcadas en [mpvInitOnly] requieren recrear el player (p. ej. `ao`).
  final Map<String, String> mpvProperties;
  final Set<String> mpvInitOnly;

  final bool allowEq;
  final bool allowReplayGain;
  final bool allowCrossfade;
  final bool lockVolumeAt100;

  /// Activar el mezclador bit-perfect USB nativo (Android 14+).
  final bool requestAndroidBitPerfect;

  /// Pedir a iOS que la sesión de audio use la frecuencia de la pista.
  final bool matchIosSampleRate;

  /// Explicaciones honestas para mostrar en Ajustes.
  final List<String> notes;

  const HifiPlan({
    required this.mode,
    required this.stream,
    this.mpvProperties = const {},
    this.mpvInitOnly = const {},
    this.allowEq = true,
    this.allowReplayGain = true,
    this.allowCrossfade = true,
    this.lockVolumeAt100 = false,
    this.requestAndroidBitPerfect = false,
    this.matchIosSampleRate = false,
    this.notes = const [],
  });
}

class HifiPlanner {
  /// Calidad cuando NO estamos en modo alta fidelidad o en datos móviles.
  static StreamQuality qualityFor(NetworkKind net, {required int mobileKbps}) =>
      switch (net) {
        NetworkKind.mobile =>
          StreamQuality(format: 'opus', maxBitRate: mobileKbps),
        _ => StreamQuality.original,
      };

  static HifiPlan plan({
    required AudioFidelityMode mode,
    required HifiPlatform platform,
    required NetworkKind network,
    required bool mpvEngine,
    int mobileKbps = 192,
    bool allowLosslessOnMobileData = false,
  }) {
    final notes = <String>[];

    // ── Calidad del stream ──
    var stream = qualityFor(network, mobileKbps: mobileKbps);
    if (mode != AudioFidelityMode.standard &&
        (network != NetworkKind.mobile || allowLosslessOnMobileData)) {
      stream = StreamQuality.original;
    } else if (mode != AudioFidelityMode.standard) {
      notes.add('Estás en datos móviles: se usa ${stream.label}. Activá '
          '"Sin pérdida también con datos móviles" para forzar el original.');
    }

    // ── Propiedades mpv comunes ──
    final mpv = <String, String>{};
    final initOnly = <String>{};
    if (mpvEngine) {
      mpv['gapless-audio'] = 'weak';
      mpv['volume-max'] = '100'; // nunca amplificar digitalmente > 0 dB
      mpv['replaygain'] = 'no'; // ReplayGain lo calcula Scrotify, no mpv
      if (mode != AudioFidelityMode.standard) {
        // Remuestreo de calidad de estudio cuando el dispositivo lo exige.
        mpv['audio-swresample-o'] = 'resampler=soxr,precision=28';
        mpv['audio-pitch-correction'] = 'no';
        mpv['audio-buffer'] = '0.5';
        mpv['audio-normalize-downmix'] = 'yes';
        // 0 = conservar la frecuencia de la pista (44.1/48/96/192 kHz).
        mpv['audio-samplerate'] = '0';
      }
    }

    switch (mode) {
      case AudioFidelityMode.standard:
        return HifiPlan(
          mode: mode,
          stream: stream,
          mpvProperties: mpv,
          notes: notes,
        );

      case AudioFidelityMode.highFidelity:
        notes.add('El ecualizador y ReplayGain se procesan en coma flotante de '
            '32/64 bits con preamp automático: no hay recorte digital.');
        if (platform == HifiPlatform.ios && !mpvEngine) {
          notes.add(
              'En iOS, la sesión de audio se ajusta a la frecuencia de cada pista.');
        }
        if (platform == HifiPlatform.android && !mpvEngine) {
          notes.add(
              'Android mezcla a 48 kHz: las pistas de 44.1 kHz se remuestrean '
              'en el sistema. Para salida intacta usá Bit-perfect con un DAC USB.');
        }
        return HifiPlan(
          mode: mode,
          stream: stream,
          mpvProperties: mpv,
          matchIosSampleRate: platform == HifiPlatform.ios,
          notes: notes,
        );

      case AudioFidelityMode.bitPerfect:
        if (mpvEngine) {
          mpv['af'] = ''; // ningún filtro
          mpv['volume'] = '100';
          mpv['audio-exclusive'] = 'yes';
          switch (platform) {
            case HifiPlatform.windows:
              mpv['ao'] = 'wasapi';
              initOnly.add('ao');
              notes
                  .add('Salida WASAPI exclusiva: Windows deja de mezclar otros '
                      'sonidos mientras Scrotify reproduce.');
            case HifiPlatform.macos:
              mpv['ao'] = 'coreaudio';
              // Cambia el formato físico del DAC a la frecuencia de cada pista.
              mpv['coreaudio-change-physical-format'] = 'yes';
              initOnly.add('ao');
              notes.add(
                  'CoreAudio en modo exclusivo (hog mode) con cambio automático '
                  'de frecuencia del DAC.');
            case HifiPlatform.linux:
              // La salida actual la elige el sistema. Pedir exclusividad a
              // PipeWire puede dejar el stream sin destino (p. ej. Bluetooth)
              // y consumir la pista rápidamente sin emitir sonido.
              mpv['audio-exclusive'] = 'no';
              notes.add(
                  'En Linux se conserva la salida del sistema, incluido Bluetooth, '
                  'sin pedir exclusividad a PipeWire. Se desactiva el procesado '
                  'de Scrotify, pero la salida compartida o Bluetooth no garantiza '
                  'bit-perfect real. Para eso hace falta una salida ALSA hw: '
                  'directa a un DAC compatible; esta app aún no permite elegirla.');
            case HifiPlatform.android:
            case HifiPlatform.ios:
              break;
          }
        }
        if (platform == HifiPlatform.android) {
          notes.add('Bit-perfect en Android requiere Android 14+ y un DAC USB. '
              'Con Bluetooth o el parlante interno se usa Alta fidelidad.');
        }
        if (platform == HifiPlatform.ios) {
          notes.add(
              'iOS no expone salida exclusiva: se iguala la frecuencia de la '
              'sesión a la de la pista y se desactiva todo procesamiento.');
        }
        notes.add(
            'El ecualizador, ReplayGain, crossfade y el control de volumen '
            'digital se desactivan. Regulá el volumen desde tu DAC o amplificador.');
        return HifiPlan(
          mode: mode,
          stream: stream,
          mpvProperties: mpv,
          mpvInitOnly: initOnly,
          allowEq: false,
          allowReplayGain: false,
          allowCrossfade: false,
          lockVolumeAt100: true,
          requestAndroidBitPerfect: platform == HifiPlatform.android,
          matchIosSampleRate: platform == HifiPlatform.ios,
          notes: notes,
        );
    }
  }

  /// Ayuda a la UI: explica por qué el EQ está deshabilitado.
  static String? eqBlockedReason(HifiPlan plan, EqProfile active) => plan
              .allowEq ||
          active.isFlat
      ? null
      : 'El ecualizador está en pausa porque el modo Bit-perfect envía el audio '
          'sin modificar. Cambiá a "Alta fidelidad" para usarlo.';
}
