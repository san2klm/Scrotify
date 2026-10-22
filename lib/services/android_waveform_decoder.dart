import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'waveform_service.dart';

/// Función que atiende una llamada al canal. Permite inyectar un doble en
/// tests sin registrar un handler global del binding.
typedef AndroidWaveformHandler = Future<Object?> Function(MethodCall call);

/// Puente Dart hacia `AndroidWaveformPlugin.kt` (canal `crotowave/waveform`).
///
/// El análisis (MediaExtractor + MediaCodec, RMS*0.75 + pico*0.25 y
/// normalización) ocurre íntegramente en Kotlin; por el canal solo viajan la
/// ruta local, los parámetros y, de vuelta, `bins` amplitudes finitas 0..1.
/// Nunca se envían URLs, credenciales ni PCM.
///
/// Contrato:
/// - `decode {jobId, path, bins (16..2048), durationUs > 0}` → `DoubleArray`.
/// - `cancel {jobId}` → detiene el trabajo pendiente o en curso.
/// - Errores nativos: `unsupported`, `timeout`, `cancelled`, `decode_failed`,
///   `invalid_arguments`; aquí se traducen a [WaveformDecodeException] con
///   mensajes que nunca reproducen el texto nativo.
class AndroidWaveformDecoder {
  static const String channelName = 'crotowave/waveform';
  static const int minBins = 16;
  static const int maxBins = 2048;

  /// Algo por encima del plazo nativo (120 s): si el lado nativo no responde
  /// nunca, el Future termina igualmente.
  static const Duration _dartTimeout = Duration(seconds: 130);

  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  static const Set<String> _knownExtensions = {
    'mp3', 'flac', 'ogg', 'oga', 'opus', 'm4a', 'mp4', 'aac', 'wav', 'mka',
    'amr', 'mid', //
  };

  static int _jobCounter = 0;

  final bool isSupported;
  final AndroidWaveformHandler _handler;
  final Future<Directory> Function() _tempDirProvider;

  /// Trabajos con una llamada nativa viva en este proceso Dart. Acotado: cada
  /// entrada se elimina al terminar la llamada, de modo que una cancelación
  /// nunca deja marcas permanentes.
  final Set<String> _active = <String>{};
  final Set<String> _abortRequested = <String>{};

  /// [isSupported] por defecto es `Platform.isAndroid`. [handler] sustituye
  /// al canal real (tests). [tempDirProvider] elige dónde crear los temporales
  /// del audio ya descargado (por defecto el directorio temporal privado de la
  /// app).
  AndroidWaveformDecoder({
    bool? isSupported,
    AndroidWaveformHandler? handler,
    Future<Directory> Function()? tempDirProvider,
  })  : isSupported = isSupported ?? (!kIsWeb && Platform.isAndroid),
        _handler = handler ??
            ((call) => _defaultChannel.invokeMethod<Object?>(
                call.method, call.arguments)),
        _tempDirProvider =
            tempDirProvider ?? (() async => Directory.systemTemp);

  /// Identificador único de trabajo (sin información de la pista ni de la URL).
  static String newJobId() =>
      'wf-${DateTime.now().microsecondsSinceEpoch}-${_jobCounter++}';

  /// Analiza el archivo local [path] y devuelve exactamente [bins] amplitudes.
  Future<List<double>> decodeFile(
    String path, {
    required Duration duration,
    required int bins,
    String? jobId,
  }) async {
    final id = jobId ?? newJobId();
    _validate(path, duration, bins);
    _active.add(id);
    try {
      return await _invokeDecode(id, path, duration, bins);
    } finally {
      _active.remove(id);
      _abortRequested.remove(id);
    }
  }

  /// Escribe [bytes] (audio ya descargado) en un temporal privado con una
  /// extensión válida, lo analiza por ruta y borra el temporal siempre.
  Future<List<double>> decodeBytes(
    List<int> bytes, {
    required Duration duration,
    required int bins,
    String? fileNameHint,
    String? jobId,
  }) async {
    final id = jobId ?? newJobId();
    if (bytes.isEmpty) {
      throw const WaveformDecodeException('Empty audio bytes');
    }
    if (!isSupported) {
      throw const WaveformDecodeException(
          'Native waveform decoder is not available on this platform',
          kind: WaveformFailure.unsupported);
    }
    if (duration.inMicroseconds <= 0 || bins < minBins || bins > maxBins) {
      throw const WaveformDecodeException('Invalid waveform arguments');
    }
    _active.add(id);
    Directory? dir;
    try {
      final root = await _tempDirProvider();
      dir = await root.createTemp('crotowave_waveform_');
      final file =
          File('${dir.path}/input${_extensionFor(bytes, fileNameHint)}');
      await file.writeAsBytes(bytes, flush: true);
      if (_abortRequested.contains(id)) throw _cancelled();
      return await _invokeDecode(id, file.path, duration, bins);
    } on FileSystemException {
      throw const WaveformDecodeException(
          'Could not prepare the audio for analysis');
    } finally {
      _active.remove(id);
      _abortRequested.remove(id);
      final d = dir;
      if (d != null) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Cancela el trabajo [jobId]. Nunca lanza: si ya terminó o el canal falla,
  /// no hay nada más que cancelar.
  Future<void> cancel(String jobId) async {
    if (_active.contains(jobId)) _abortRequested.add(jobId);
    try {
      await _handler(MethodCall('cancel', {'jobId': jobId}));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------

  Future<List<double>> _invokeDecode(
    String jobId,
    String path,
    Duration duration,
    int bins,
  ) async {
    final Object? raw;
    try {
      raw = await _handler(MethodCall('decode', {
        'jobId': jobId,
        'path': path,
        'bins': bins,
        'durationUs': duration.inMicroseconds,
      })).timeout(_dartTimeout);
    } on TimeoutException {
      unawaited(cancel(jobId));
      throw const WaveformDecodeException('Audio analysis timed out',
          kind: WaveformFailure.timeout);
    } on PlatformException catch (e) {
      throw _fromPlatform(e.code);
    } on MissingPluginException {
      throw const WaveformDecodeException(
          'Native waveform decoder is not registered',
          kind: WaveformFailure.unsupported);
    }
    if (_abortRequested.contains(jobId)) throw _cancelled();
    return _parse(raw, bins);
  }

  void _validate(String path, Duration duration, int bins) {
    if (!isSupported) {
      throw const WaveformDecodeException(
          'Native waveform decoder is not available on this platform',
          kind: WaveformFailure.unsupported);
    }
    if (path.isEmpty || !path.startsWith('/') || path.contains('://')) {
      throw const WaveformDecodeException(
          'Native waveform decoder only accepts absolute local paths');
    }
    if (duration.inMicroseconds <= 0) {
      throw const WaveformDecodeException('Duration must be positive');
    }
    if (bins < minBins || bins > maxBins) {
      throw const WaveformDecodeException('Bin count out of range');
    }
  }

  static WaveformDecodeException _cancelled() =>
      const WaveformDecodeException('Audio analysis cancelled',
          kind: WaveformFailure.cancelled);

  static WaveformDecodeException _fromPlatform(String code) {
    // El mensaje nativo se descarta a propósito: podría contener rutas.
    return switch (code) {
      'unsupported' => const WaveformDecodeException(
          'Audio format not supported by this device',
          kind: WaveformFailure.unsupported),
      'timeout' => const WaveformDecodeException('Audio analysis timed out',
          kind: WaveformFailure.timeout),
      'cancelled' => _cancelled(),
      'invalid_arguments' =>
        const WaveformDecodeException('Invalid arguments for audio analysis'),
      _ => const WaveformDecodeException('Native audio decode failed'),
    };
  }

  static List<double> _parse(Object? raw, int bins) {
    if (raw is! List || raw.length != bins) {
      throw const WaveformDecodeException(
          'Native decoder returned an unexpected result');
    }
    final out = List<double>.filled(bins, 0.0);
    for (var i = 0; i < bins; i++) {
      final v = raw[i];
      if (v is! num) {
        throw const WaveformDecodeException(
            'Native decoder returned a non-numeric amplitude');
      }
      final d = v.toDouble();
      if (!d.isFinite || d < 0.0 || d > 1.0) {
        throw const WaveformDecodeException(
            'Native decoder returned an out-of-range amplitude');
      }
      out[i] = d;
    }
    return out;
  }

  /// Extensión del temporal: primero por firma del contenido (la URL de
  /// Subsonic `stream.view` no la trae), luego por el nombre si es conocida.
  static String _extensionFor(List<int> b, String? hint) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (b[i + k] != sig[k]) return false;
      }
      return true;
    }

    if (at(0, [0x49, 0x44, 0x33])) return '.mp3'; // ID3
    if (at(0, [0x66, 0x4C, 0x61, 0x43])) return '.flac'; // fLaC
    if (at(0, [0x4F, 0x67, 0x67, 0x53])) return '.ogg'; // OggS
    if (at(0, [0x52, 0x49, 0x46, 0x46])) return '.wav'; // RIFF
    if (at(4, [0x66, 0x74, 0x79, 0x70])) return '.m4a'; // ftyp
    if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
      return '.mp3'; // sync de frame MPEG
    }
    if (hint != null) {
      final clean = hint.split('?').first.split('/').last;
      final dot = clean.lastIndexOf('.');
      if (dot >= 0) {
        final ext = clean.substring(dot + 1).toLowerCase();
        if (_knownExtensions.contains(ext)) return '.$ext';
      }
    }
    return '.bin';
  }
}
