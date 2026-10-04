import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Decodificación a PCM mono vía binario `ffmpeg` del sistema.
///
/// Comando utilizado (documentado para el informe final):
/// ```sh
/// ffmpeg -v error -i <input> -ac 1 -ar 8000 -f f32le -acodec pcm_f32le pipe:1
/// ```
/// Salida: stream de float32 little-endian mono a 8000 Hz.
/// Se procesa por chunks (streaming) sin cargar el PCM completo de más.
///
/// Disponibilidad:
/// - Desktop Linux (este entorno): /usr/bin/ffmpeg presente.
/// - Windows/macOS: funciona si ffmpeg está en el PATH.
/// - Android/iOS: sin binario CLI → [isAvailable] es false y el servicio
///   real usa el decodificador WAV puro-Dart o lanza error (nunca sintético).
class FfmpegWaveformDecoder {
  static const int decodeSampleRate = 8000;

  static bool? _cachedAvailable;

  /// True si hay un binario `ffmpeg` ejecutable en el PATH.
  static Future<bool> isAvailable({bool refresh = false}) async {
    if (_cachedAvailable != null && !refresh) return _cachedAvailable!;
    try {
      final result = await Process.run(
        'ffmpeg',
        ['-version'],
      ).timeout(const Duration(seconds: 10));
      _cachedAvailable = result.exitCode == 0;
    } catch (_) {
      _cachedAvailable = false;
    }
    return _cachedAvailable!;
  }

  /// Decodifica el archivo [inputPath] (cualquier formato que ffmpeg soporte:
  /// mp3, ogg, flac, m4a, opus, wav…) a samples mono float32 (-1..1).
  static Future<List<double>> decodeFileToMonoFloat32(
    String inputPath, {
    int sampleRate = decodeSampleRate,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final file = File(inputPath);
    if (!await file.exists()) {
      throw ArgumentError('Audio file not found: $inputPath');
    }
    late Process process;
    try {
      process = await Process.start('ffmpeg', [
        '-v',
        'error',
        '-i',
        inputPath,
        '-ac',
        '1',
        '-ar',
        '$sampleRate',
        '-f',
        'f32le',
        '-acodec',
        'pcm_f32le',
        'pipe:1',
      ]);
    } on ProcessException catch (e) {
      throw StateError('ffmpeg binary not available: $e');
    }

    final outBytes = <int>[];
    final errBuffer = StringBuffer();
    final outDone = Completer<void>();
    final errDone = Completer<void>();

    process.stdout.listen(
      outBytes.addAll,
      onDone: () => outDone.complete(),
      onError: (Object e) => outDone.completeError(e),
      cancelOnError: true,
    );
    process.stderr.transform(const SystemEncoding().decoder).listen(
      errBuffer.write,
      onDone: () => errDone.complete(),
      onError: (Object e) => errDone.completeError(e),
      cancelOnError: true,
    );

    final exited = await process.exitCode.timeout(timeout, onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      throw TimeoutException('ffmpeg decode timed out for $inputPath');
    });
    await Future.wait([outDone.future, errDone.future]);

    if (exited != 0) {
      final err = errBuffer.toString().trim();
      throw StateError(
          'ffmpeg failed (exit $exited) for $inputPath: ${err.isEmpty ? 'unknown error' : err}');
    }
    if (outBytes.isEmpty) {
      final err = errBuffer.toString().trim();
      throw StateError(
          'ffmpeg produced no PCM for $inputPath${err.isEmpty ? '' : ': $err'}');
    }
    return _bytesToFloat32Mono(outBytes);
  }

  /// Escribe [audioBytes] a un temporal y lo decodifica con ffmpeg.
  static Future<List<double>> decodeBytesToMonoFloat32(
    List<int> audioBytes, {
    String extensionHint = '.bin',
    int sampleRate = decodeSampleRate,
  }) async {
    final ext = extensionHint.startsWith('.') ? extensionHint : '.$extensionHint';
    final tmpDir =
        await Directory.systemTemp.createTemp('scrotify_waveform_');
    final tmp = File('${tmpDir.path}/input$ext');
    try {
      await tmp.writeAsBytes(audioBytes, flush: true);
      return await decodeFileToMonoFloat32(tmp.path, sampleRate: sampleRate);
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static List<double> _bytesToFloat32Mono(List<int> bytes) {
    final usable = bytes.length - (bytes.length % 4);
    final bd = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, usable)));
    final count = usable ~/ 4;
    final out = List<double>.filled(count, 0.0);
    for (var i = 0; i < count; i++) {
      out[i] = bd.getFloat32(i * 4, Endian.little).clamp(-1.0, 1.0);
    }
    return out;
  }
}
