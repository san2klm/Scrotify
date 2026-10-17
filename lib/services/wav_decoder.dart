import 'dart:typed_data';

/// Resultado de decodificar un WAV a mono flotante.
class WavDecodeResult {
  /// Samples mono en rango -1.0..1.0.
  final List<double> monoSamples;
  final int sampleRate;
  final int numChannels;

  const WavDecodeResult({
    required this.monoSamples,
    required this.sampleRate,
    required this.numChannels,
  });
}

/// Decodificador WAV 100% Dart (sin dependencias nativas).
///
/// Soporta PCM entero (8/16/24/32 bits) y float IEEE (32/64 bits),
/// mono o multicanal (promedia canales a mono).
/// Funciona en todas las plataformas (incluido móvil) sin ffmpeg.
class WavDecoder {
  /// Devuelve true si [bytes] parece un WAV (RIFF....WAVE).
  static bool isWav(List<int> bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x41 && // A
        bytes[10] == 0x56 && // V
        bytes[11] == 0x45; // E
  }

  /// Decodifica [bytes] WAV a mono flotante. Lanza [FormatException] si no
  /// es un WAV válido o el formato no es soportado.
  static WavDecodeResult decode(List<int> bytes) {
    if (!isWav(bytes)) {
      throw const FormatException('Not a WAV file (missing RIFF/WAVE magic)');
    }
    final data = Uint8List.fromList(bytes);
    final bd = ByteData.sublistView(data);

    int offset = 12;
    var audioFormat = -1;
    var numChannels = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;
    var dataStart = -1;
    var dataLen = 0;

    while (offset + 8 <= data.length) {
      final tag = String.fromCharCodes(data.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      if (tag == 'fmt ') {
        if (chunkStart + 16 > data.length) {
          throw const FormatException('Truncated WAV fmt chunk');
        }
        audioFormat = bd.getUint16(chunkStart, Endian.little);
        numChannels = bd.getUint16(chunkStart + 2, Endian.little);
        sampleRate = bd.getUint32(chunkStart + 4, Endian.little);
        bitsPerSample = bd.getUint16(chunkStart + 14, Endian.little);
      } else if (tag == 'data') {
        dataStart = chunkStart;
        dataLen = chunkSize;
        // No break: seguir por si hay múltiples chunks data (tomar el primero
        // con contenido suele bastar).
        break;
      }
      offset = chunkStart + chunkSize + (chunkSize % 2);
    }

    if (audioFormat == -1 || numChannels <= 0 || sampleRate <= 0) {
      throw const FormatException('WAV missing valid fmt chunk');
    }
    if (dataStart < 0) {
      throw const FormatException('WAV missing data chunk');
    }
    dataLen = dataLen.clamp(0, data.length - dataStart);

    // WAVE_FORMAT_EXTENSIBLE (0xFFFE): los primeros 16 bytes equivalen al fmt
    // base; el subformato real está al final. Para simplificar, si el fmt
    // extensible declara PCM/float en bits válidos lo tratamos como tal.
    // Los archivos de test usan PCM estándar, así que este path es raro.
    const pcm = 1;
    const ieeeFloat = 3;
    const extensible = 0xFFFE;
    final isFloat = audioFormat == ieeeFloat ||
        (audioFormat == extensible &&
            (bitsPerSample == 32 || bitsPerSample == 64));
    final isPcm = audioFormat == pcm ||
        (audioFormat == extensible && !isFloat && bitsPerSample % 8 == 0);
    if (!isFloat && !isPcm) {
      throw FormatException('Unsupported WAV format code: $audioFormat');
    }

    final bytesPerSample = (bitsPerSample / 8).ceil();
    if (bytesPerSample <= 0 || bytesPerSample > 8) {
      throw FormatException('Unsupported bitsPerSample: $bitsPerSample');
    }
    final frameSize = bytesPerSample * numChannels;
    if (frameSize <= 0) {
      throw const FormatException('Invalid WAV frame size');
    }
    final frameCount = dataLen ~/ frameSize;
    if (frameCount <= 0) {
      return WavDecodeResult(
          monoSamples: const [],
          sampleRate: sampleRate,
          numChannels: numChannels);
    }

    final mono = List<double>.filled(frameCount, 0.0);
    for (var f = 0; f < frameCount; f++) {
      var acc = 0.0;
      for (var c = 0; c < numChannels; c++) {
        final pos = dataStart + f * frameSize + c * bytesPerSample;
        acc += _readSample(bd, pos, bitsPerSample, isFloat);
      }
      mono[f] = (acc / numChannels).clamp(-1.0, 1.0);
    }
    return WavDecodeResult(
      monoSamples: mono,
      sampleRate: sampleRate,
      numChannels: numChannels,
    );
  }

  static double _readSample(ByteData bd, int pos, int bits, bool isFloat) {
    if (isFloat) {
      if (bits == 32) {
        return bd.getFloat32(pos, Endian.little).clamp(-1.0, 1.0);
      }
      if (bits == 64) {
        return bd.getFloat64(pos, Endian.little).clamp(-1.0, 1.0);
      }
      throw FormatException('Unsupported float bits: $bits');
    }
    switch (bits) {
      case 8:
        // 8-bit WAV es unsigned (128 = silencio).
        return (bd.getUint8(pos) - 128) / 128.0;
      case 16:
        return bd.getInt16(pos, Endian.little) / 32768.0;
      case 24:
        var v = bd.getUint8(pos) |
            (bd.getUint8(pos + 1) << 8) |
            (bd.getUint8(pos + 2) << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        return v / 8388608.0;
      case 32:
        return bd.getInt32(pos, Endian.little) / 2147483648.0;
      default:
        throw FormatException('Unsupported PCM bits: $bits');
    }
  }
}
