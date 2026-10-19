import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'diagnostics_log.dart' show redactSecrets;
import 'ffmpeg_waveform_decoder.dart';
import 'pcm_waveform_analyzer.dart';
import 'wav_decoder.dart';
import 'waveform_service.dart';

/// Servicio REAL de waveform: la forma deriva del audio real de cada pista.
///
/// Pipeline:
/// ```
/// archivo real de audio
///   → decodificación (WAV puro-Dart, o ffmpeg para mp3/ogg/flac/m4a/…)
///   → PCM / samples reales mono float
///   → ventanas temporales
///   → RMS / peak / envelope (rms*0.75 + peak*0.25)
///   → normalización
///   → ~2048 bins (según duración: 1 bin / 50 ms, clamp 16..2048)
///   → caché v2 en disco
///   → downsampling según ancho (en el painter)
///   → CustomPainter / barra de progreso
/// ```
///
/// - El `trackId` SOLO forma parte de la clave de caché, nunca de la forma.
/// - PROHIBIDO: `Random`, `hashCode` para amplitud, `trackId` para amplitud,
///   `sin`/`cos`, ruido o curvas inventadas.
/// - Sin fallback sintético en producción: si el audio no puede analizarse se
///   lanza [WaveformDecodeException] y la UI muestra estado neutro.
class AudioWaveformService implements WaveformService {
  /// Versión del formato de caché. v2 invalida la caché sintética anterior.
  static const int cacheVersion = 2;
  static const String _cacheDirName = 'waveform_cache_v2';
  static const int _maxDownloadBytes = 30 * 1024 * 1024;
  static const Duration _maxDownloadTime = Duration(seconds: 90);

  /// Análisis simultáneos como máximo: descargar y decodificar es caro y el
  /// usuario puede saltar de pista rápido.
  static final _Gate _analysisGate = _Gate(2);

  final http.Client _http;
  final Directory? cacheDirOverride;

  /// Cargas en curso por (origen, pista): las peticiones repetidas comparten
  /// el mismo trabajo en lugar de descargar y analizar otra vez.
  final Map<String, Future<WaveformData>> _inFlight = {};

  AudioWaveformService({http.Client? httpClient, this.cacheDirOverride})
      : _http = httpClient ?? http.Client();

  // -------------------------------------------------------------------------
  // API de producción (WaveformService)
  // -------------------------------------------------------------------------

  /// [streamUrl] es el audio a ANALIZAR: archivo local descargado o un stream
  /// liviano (no hace falta el lossless de reproducción para una envolvente).
  @override
  Future<WaveformData> getWaveform(
    String trackId,
    String streamUrl,
    Duration duration,
  ) async {
    if (trackId.isEmpty) {
      throw ArgumentError('trackId must not be empty');
    }
    if (duration.inMilliseconds <= 0) {
      throw ArgumentError('duration must be positive');
    }
    final source = streamUrl.trim();
    final scope = await _sourceScope(source);
    final key = '$scope|$trackId|${duration.inMilliseconds}';
    // Bloque, no flecha: whenComplete espera al Future que devuelva el callback
    // y `remove` devolvería este mismo (autoespera).
    return _inFlight[key] ??=
        _load(trackId, source, scope, duration).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<WaveformData> _load(
    String trackId,
    String source,
    String scope,
    Duration duration,
  ) async {
    // 1. Caché por (origen, trackId): rápido + offline. El JSON guarda el
    //    fingerprint del audio analizado para trazabilidad.
    final cached = await _loadTrackCache(trackId, scope);
    if (cached != null && _durationMatches(cached.duration, duration)) {
      return cached;
    }

    return _analysisGate.run(() async {
      // 2. Decodificar + analizar el audio real (fuera del isolate de UI).
      final bins = PcmWaveformAnalyzer.targetBinsForDuration(duration);
      final List<double> amplitudes;
      final String fingerprint;
      final localPath = _localPath(source);
      if (localPath != null) {
        final local = await _analyzeLocalFile(localPath, bins, duration, scope);
        amplitudes = local.amplitudes;
        fingerprint = local.fingerprint;
      } else {
        final resolved = await _downloadAudio(source);
        amplitudes = await analyzeAudioBytes(
          resolved.bytes,
          duration: duration,
          fileNameHint: resolved.fileNameHint,
        );
        fingerprint = await _fingerprintInIsolate(resolved.bytes);
      }

      final data = WaveformData(
        trackId: trackId,
        duration: duration,
        amplitudes: amplitudes,
      );
      await _saveTrackCache(trackId, scope, data,
          audioFingerprint: fingerprint);
      return data;
    });
  }

  /// Ruta local si [source] es `file://` o una ruta absoluta; si no, null.
  static String? _localPath(String source) {
    if (source.startsWith('file://')) return Uri.parse(source).toFilePath();
    if (source.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source)) {
      return source;
    }
    return null;
  }

  /// Identidad estable de la FUENTE, para la clave de caché (junto al trackId):
  /// - local: ruta canónica + tamaño + fecha de modificación;
  /// - remoto: origen + ruta del endpoint + usuario (`u`). Nunca `s`/`t`
  ///   (cambian en cada sesión) ni el `id`, que ya es el trackId.
  static Future<String> _sourceScope(String source) async {
    final localPath = _localPath(source);
    if (localPath != null) {
      final file = File(localPath);
      if (!await file.exists()) {
        throw WaveformDecodeException('Audio file not found: $localPath');
      }
      var canonical = file.absolute.path;
      try {
        canonical = await file.resolveSymbolicLinks();
      } catch (_) {}
      final stat = await file.stat();
      return _digest(
          'file|$canonical|${stat.size}|${stat.modified.millisecondsSinceEpoch}');
    }
    try {
      final uri = Uri.parse(source);
      return _digest('http|${uri.scheme}://${uri.host}:${uri.port}|${uri.path}'
          '|${uri.queryParameters['u'] ?? ''}');
    } catch (_) {
      return 'remote';
    }
  }

  static String _digest(String text) =>
      sha1.convert(utf8.encode(text)).toString().substring(0, 16);

  /// Un archivo local se decodifica por ruta con ffmpeg (sin tope de tamaño ni
  /// copiarlo a memoria). Sin ffmpeg (Android/iOS) solo hay WAV pequeño.
  Future<({List<double> amplitudes, String fingerprint})> _analyzeLocalFile(
    String path,
    int bins,
    Duration duration,
    String fingerprint,
  ) async {
    if (!await FfmpegWaveformDecoder.isAvailable()) {
      final read = await _readLocalFile(path);
      final amplitudes = await analyzeAudioBytes(read.bytes,
          duration: duration, fileNameHint: read.fileNameHint);
      return (amplitudes: amplitudes, fingerprint: fingerprint);
    }
    try {
      final pcm = await FfmpegWaveformDecoder.decodeFileToPcmBytes(path);
      return (
        amplitudes: await _analyzePcmInIsolate(pcm, bins),
        fingerprint: fingerprint
      );
    } on WaveformDecodeException {
      rethrow;
    } catch (e) {
      throw WaveformDecodeException(
          'Audio decode failed: ${redactSecrets(e.toString())}');
    }
  }

  // -------------------------------------------------------------------------
  // API de laboratorio / tests (bytes y archivos locales)
  // -------------------------------------------------------------------------

  /// Analiza bytes de audio en memoria. La caché se clavea por CONTENIDO
  /// (huella del audio), de modo que el mismo trackId con audio distinto
  /// produce waveforms distintas (prueba A) y audios idénticos con distinto
  /// trackId producen waveforms equivalentes (prueba B).
  Future<WaveformData> getWaveformForBytes(
    String trackId,
    List<int> audioBytes, {
    required Duration duration,
    String? fileNameHint,
  }) async {
    if (audioBytes.isEmpty) {
      throw const WaveformDecodeException('Empty audio bytes');
    }
    final fingerprint = contentFingerprint(audioBytes);
    final cached =
        await _loadBytesCache(trackId: trackId, fingerprint: fingerprint);
    if (cached != null) {
      return cached;
    }
    final amplitudes = await analyzeAudioBytes(
      audioBytes,
      duration: duration,
      fileNameHint: fileNameHint,
    );
    final data = WaveformData(
      trackId: trackId,
      duration: duration,
      amplitudes: amplitudes,
    );
    await _saveBytesCache(
        trackId: trackId, fingerprint: fingerprint, data: data);
    return data;
  }

  /// Analiza un archivo local de audio real.
  Future<WaveformData> getWaveformForFile(
    String trackId,
    String filePath, {
    required Duration duration,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw WaveformDecodeException('Audio file not found: $filePath');
    }
    final bytes = await file.readAsBytes();
    return getWaveformForBytes(
      trackId,
      bytes,
      duration: duration,
      fileNameHint: filePath,
    );
  }

  // -------------------------------------------------------------------------
  // Núcleo: bytes → amplitudes (puro contenido)
  // -------------------------------------------------------------------------

  /// Decodifica bytes de audio y devuelve amplitudes normalizadas 0..1.
  ///
  /// - WAV → [WavDecoder] puro-Dart (todas las plataformas, sin ffmpeg).
  /// - Otros (mp3/ogg/flac/m4a/…) → [FfmpegWaveformDecoder] (desktop).
  static Future<List<double>> analyzeAudioBytes(
    List<int> audioBytes, {
    required Duration duration,
    String? fileNameHint,
  }) async {
    final bins = PcmWaveformAnalyzer.targetBinsForDuration(duration);
    final List<double> amplitudes;
    if (WavDecoder.isWav(audioBytes)) {
      final result = await _analyzeWavInIsolate(audioBytes, bins);
      final error = result.error;
      if (error != null) throw WaveformDecodeException(error);
      amplitudes = result.amplitudes;
    } else {
      final available = await FfmpegWaveformDecoder.isAvailable();
      if (!available) {
        throw const WaveformDecodeException(
          'Non-WAV audio requires the ffmpeg binary, which is not available '
          'on this platform. Decode on desktop or provide WAV audio.',
          kind: WaveformFailure.unsupported,
        );
      }
      final pcm = await FfmpegWaveformDecoder.decodeBytesToPcmBytes(
        audioBytes,
        extensionHint: _extensionHint(fileNameHint),
      );
      amplitudes = await _analyzePcmInIsolate(pcm, bins);
    }
    if (amplitudes.isEmpty) {
      throw const WaveformDecodeException('Decoded PCM is empty');
    }
    return amplitudes;
  }

  // El trabajo pesado (decodificar WAV, recorrer millones de muestras, sha1)
  // corre en un isolate aparte para no congelar la UI. Son estáticos para que
  // el closure no capture el servicio (cliente HTTP, etc.).

  static Future<({List<double> amplitudes, String? error})>
      _analyzeWavInIsolate(List<int> wav, int bins) => Isolate.run(() {
            try {
              final mono = WavDecoder.decode(wav).monoSamples;
              if (mono.isEmpty) return (amplitudes: <double>[], error: null);
              return (
                amplitudes: PcmWaveformAnalyzer.analyzeMonoFloat32(mono, bins),
                error: null
              );
            } on WaveformDecodeException catch (e) {
              return (amplitudes: <double>[], error: e.message);
            }
          });

  static Future<List<double>> _analyzePcmInIsolate(Uint8List pcm, int bins) =>
      Isolate.run(() => PcmWaveformAnalyzer.analyzeMonoFloat32(
          FfmpegWaveformDecoder.pcmBytesToFloat32(pcm), bins));

  static Future<String> _fingerprintInIsolate(List<int> bytes) =>
      Isolate.run(() => contentFingerprint(bytes));

  /// Huella estable del CONTENIDO de audio (sha1 hex). Solo para caché.
  static String contentFingerprint(List<int> audioBytes) {
    return sha1.convert(audioBytes).toString().substring(0, 16);
  }

  // -------------------------------------------------------------------------
  // Descarga del audio (http/https)
  // -------------------------------------------------------------------------

  Future<({List<int> bytes, String? fileNameHint})> _downloadAudio(
      String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const WaveformDecodeException('Empty stream URL');
    }
    // URL remota (stream Navidrome con auth por query).
    try {
      final streamed = await _http
          .send(http.Request('GET', Uri.parse(trimmed)))
          .timeout(const Duration(seconds: 25));
      if (streamed.statusCode != 200) {
        await _discard(streamed);
        throw WaveformDecodeException(
            'Audio download failed: HTTP ${streamed.statusCode}',
            kind: WaveformFailure.network);
      }
      // Cortar por Content-Length ANTES de bajar nada a memoria.
      final declared = streamed.contentLength;
      if (declared != null && declared > _maxDownloadBytes) {
        await _discard(streamed);
        throw const WaveformDecodeException(
            'Audio file too large for waveform analysis',
            kind: WaveformFailure.tooLarge);
      }
      final builder = BytesBuilder(copy: false);
      final elapsed = Stopwatch()..start();
      await for (final chunk
          in streamed.stream.timeout(const Duration(seconds: 25))) {
        builder.add(chunk);
        if (builder.length > _maxDownloadBytes) {
          throw const WaveformDecodeException(
              'Audio file too large for waveform analysis',
              kind: WaveformFailure.tooLarge);
        }
        // Un stream sin fin que sigue enviando datos no vence el timeout de
        // inactividad: acotar también el tiempo total.
        if (elapsed.elapsed > _maxDownloadTime) {
          throw const WaveformDecodeException('Audio download timed out',
              kind: WaveformFailure.timeout);
        }
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        throw const WaveformDecodeException('Downloaded audio is empty');
      }
      return (
        bytes: bytes,
        fileNameHint: _fileNameFromUrl(trimmed),
      );
    } on TimeoutException {
      throw const WaveformDecodeException('Audio download timed out',
          kind: WaveformFailure.timeout);
    } on WaveformDecodeException {
      rethrow;
    } catch (e) {
      // El error de http incluye la URI con u/t/s: nunca debe llegar al log.
      throw WaveformDecodeException(
          'Audio download failed: ${redactSecrets(e.toString())}',
          kind: WaveformFailure.network);
    }
  }

  /// Cancela el cuerpo de una respuesta rechazada: sin esto el socket queda
  /// con datos pendientes hasta que el servidor cierre.
  static Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } catch (_) {}
  }

  Future<({List<int> bytes, String? fileNameHint})> _readLocalFile(
      String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw WaveformDecodeException('Audio file not found: $path');
    }
    // Comprobar el tamaño ANTES de leer: el límite protege la RAM.
    if (await file.length() > _maxDownloadBytes) {
      throw const WaveformDecodeException(
          'Audio file too large for waveform analysis',
          kind: WaveformFailure.tooLarge);
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const WaveformDecodeException('Audio file is empty');
    }
    return (bytes: bytes, fileNameHint: path);
  }

  // -------------------------------------------------------------------------
  // Caché v2 en disco
  // -------------------------------------------------------------------------

  Future<Directory?> _cacheDir() async {
    try {
      if (cacheDirOverride != null) {
        if (!await cacheDirOverride!.exists()) {
          await cacheDirOverride!.create(recursive: true);
        }
        return cacheDirOverride;
      }
      final docs = await getAppDataDirectory();
      final dir = Directory('${docs.path}/$_cacheDirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null; // Sin caché (tests sin plugins): se re-analiza.
    }
  }

  String _sanitize(String trackId) =>
      trackId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_').clampLength();

  Future<WaveformData?> _loadTrackCache(String trackId, String scope) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;
      final file = File('${dir.path}/track_${_sanitize(trackId)}_$scope.json');
      if (!await file.exists()) return null;
      return _parseCacheJson(await file.readAsString(),
          expectedTrackId: trackId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTrackCache(
    String trackId,
    String scope,
    WaveformData data, {
    required String audioFingerprint,
  }) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return;
      final file = File('${dir.path}/track_${_sanitize(trackId)}_$scope.json');
      await file.writeAsString(
          jsonEncode(_toCacheJson(data, audioFingerprint: audioFingerprint)));
    } catch (e) {
      if (kDebugMode) debugPrint('Waveform cache save failed: $e');
    }
  }

  Future<WaveformData?> _loadBytesCache(
      {required String trackId, required String fingerprint}) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;
      final file =
          File('${dir.path}/bytes_${_sanitize(trackId)}_$fingerprint.json');
      if (!await file.exists()) return null;
      return _parseCacheJson(await file.readAsString(),
          expectedTrackId: trackId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveBytesCache(
      {required String trackId,
      required String fingerprint,
      required WaveformData data}) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return;
      final file =
          File('${dir.path}/bytes_${_sanitize(trackId)}_$fingerprint.json');
      await file.writeAsString(
          jsonEncode(_toCacheJson(data, audioFingerprint: fingerprint)));
    } catch (e) {
      if (kDebugMode) debugPrint('Waveform bytes-cache save failed: $e');
    }
  }

  Map<String, dynamic> _toCacheJson(WaveformData data,
      {required String audioFingerprint}) {
    return {
      'version': cacheVersion,
      'trackId': data.trackId,
      'durationMs': data.duration.inMilliseconds,
      'audioFingerprint': audioFingerprint,
      'samples': data.amplitudes,
    };
  }

  WaveformData? _parseCacheJson(String raw, {String? expectedTrackId}) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != cacheVersion) return null; // invalida v1 sintética
    final trackId = json['trackId'] as String?;
    if (trackId == null || trackId.isEmpty) return null;
    if (expectedTrackId != null && trackId != expectedTrackId) return null;
    final durationMs = (json['durationMs'] as num?)?.toInt();
    if (durationMs == null || durationMs <= 0) return null;
    final rawSamples = json['samples'] as List?;
    if (rawSamples == null || rawSamples.isEmpty) return null;
    final amplitudes =
        rawSamples.map((e) => (e as num).toDouble().clamp(0.0, 1.0)).toList();
    return WaveformData(
      trackId: trackId,
      duration: Duration(milliseconds: durationMs),
      amplitudes: amplitudes,
    );
  }

  bool _durationMatches(Duration cached, Duration requested) {
    // Tolerancia de 2 s (transcodes con distinta duración reportada).
    return (cached.inMilliseconds - requested.inMilliseconds).abs() <= 2000;
  }

  // -------------------------------------------------------------------------
  // Utilidades
  // -------------------------------------------------------------------------

  static String _extensionHint(String? hint) {
    if (hint == null || hint.isEmpty) return '.bin';
    final clean = hint.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot > clean.length - 2) return '.bin';
    final ext = clean.substring(dot, (dot + 6).clamp(0, clean.length));
    if (RegExp(r'^\.[A-Za-z0-9]{1,5}$').hasMatch(ext)) return ext.toLowerCase();
    return '.bin';
  }

  static String? _fileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final seg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      if (seg.contains('.')) return seg;
      // Navidrome stream.view no trae extensión; el Content-Type real se
      // detecta por magia de bytes (WAV) o por sniffing de ffmpeg.
      return null;
    } catch (_) {
      return null;
    }
  }
}

extension on String {
  String clampLength([int max = 64]) =>
      length <= max ? this : substring(0, max);
}

/// Semáforo mínimo: como mucho [_free] tareas a la vez, el resto espera turno.
class _Gate {
  _Gate(this._free);

  int _free;
  final Queue<Completer<void>> _waiting = Queue();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_free > 0) {
      _free--;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _free++;
      }
    }
  }
}
