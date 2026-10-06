import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  final http.Client _http;
  final Directory? cacheDirOverride;

  AudioWaveformService({http.Client? httpClient, this.cacheDirOverride})
      : _http = httpClient ?? http.Client();

  // -------------------------------------------------------------------------
  // API de producción (WaveformService)
  // -------------------------------------------------------------------------

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

    // 1. Caché por trackId (rápido + offline). El JSON guarda el fingerprint
    //    del audio analizado para trazabilidad.
    final cached = await _loadTrackCache(trackId);
    if (cached != null && _durationMatches(cached.duration, duration)) {
      return cached;
    }

    // 2. Resolver bytes reales del audio.
    final resolved = await _resolveAudioBytes(streamUrl);

    // 3. Decodificar + analizar (contenido real, no trackId).
    final amplitudes = await analyzeAudioBytes(
      resolved.bytes,
      duration: duration,
      fileNameHint: resolved.fileNameHint,
    );

    final data = WaveformData(
      trackId: trackId,
      duration: duration,
      amplitudes: amplitudes,
    );
    await _saveTrackCache(
      trackId,
      data,
      audioFingerprint: contentFingerprint(resolved.bytes),
    );
    return data;
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
    List<double> mono;
    if (WavDecoder.isWav(audioBytes)) {
      final decoded = WavDecoder.decode(audioBytes);
      mono = decoded.monoSamples;
    } else {
      final available = await FfmpegWaveformDecoder.isAvailable();
      if (!available) {
        throw const WaveformDecodeException(
          'Non-WAV audio requires the ffmpeg binary, which is not available '
          'on this platform. Decode on desktop or provide WAV audio.',
        );
      }
      mono = await FfmpegWaveformDecoder.decodeBytesToMonoFloat32(
        audioBytes,
        extensionHint: _extensionHint(fileNameHint),
      );
    }
    if (mono.isEmpty) {
      throw const WaveformDecodeException('Decoded PCM is empty');
    }
    final bins = PcmWaveformAnalyzer.targetBinsForDuration(duration);
    return PcmWaveformAnalyzer.analyzeMonoFloat32(mono, bins);
  }

  /// Huella estable del CONTENIDO de audio (sha1 hex). Solo para caché.
  static String contentFingerprint(List<int> audioBytes) {
    return sha1.convert(audioBytes).toString().substring(0, 16);
  }

  // -------------------------------------------------------------------------
  // Resolución de bytes (file://, path local, http(s))
  // -------------------------------------------------------------------------

  Future<({List<int> bytes, String? fileNameHint})> _resolveAudioBytes(
      String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const WaveformDecodeException('Empty stream URL');
    }
    // file:// URL.
    if (trimmed.startsWith('file://')) {
      final path = Uri.parse(trimmed).toFilePath();
      return _readLocalFile(path);
    }
    // Ruta local directa.
    if (trimmed.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
      try {
        return await _readLocalFile(trimmed);
      } on WaveformDecodeException {
        // No era un archivo: seguir como URL remota.
      }
    }
    // URL remota (stream Navidrome con auth por query).
    try {
      final response = await _http
          .get(Uri.parse(trimmed))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw WaveformDecodeException(
            'Audio download failed: HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.isEmpty) {
        throw const WaveformDecodeException('Downloaded audio is empty');
      }
      if (response.bodyBytes.length > _maxDownloadBytes) {
        throw const WaveformDecodeException(
            'Audio file too large for waveform analysis');
      }
      return (
        bytes: response.bodyBytes,
        fileNameHint: _fileNameFromUrl(trimmed),
      );
    } on TimeoutException {
      throw const WaveformDecodeException('Audio download timed out');
    } on WaveformDecodeException {
      rethrow;
    } catch (e) {
      throw WaveformDecodeException('Audio download failed: $e');
    }
  }

  Future<({List<int> bytes, String? fileNameHint})> _readLocalFile(
      String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw WaveformDecodeException('Audio file not found: $path');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const WaveformDecodeException('Audio file is empty');
    }
    if (bytes.length > _maxDownloadBytes) {
      // Archivo local grande: dejar que ffmpeg lo lea por path en lugar de
      // cargarlo entero (el caller de bytes ya lo cargó; aquí avisamos).
      // Para simplificar se analiza igual; el límite protege la RAM.
      throw const WaveformDecodeException(
          'Audio file too large for waveform analysis');
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

  Future<WaveformData?> _loadTrackCache(String trackId) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;
      final file = File('${dir.path}/track_${_sanitize(trackId)}.json');
      if (!await file.exists()) return null;
      return _parseCacheJson(await file.readAsString(), expectedTrackId: trackId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTrackCache(
    String trackId,
    WaveformData data, {
    required String audioFingerprint,
  }) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return;
      final file = File('${dir.path}/track_${_sanitize(trackId)}.json');
      await file.writeAsString(jsonEncode(_toCacheJson(data,
          audioFingerprint: audioFingerprint)));
    } catch (e) {
      if (kDebugMode) debugPrint('Waveform cache save failed: $e');
    }
  }

  Future<WaveformData?> _loadBytesCache(
      {required String trackId, required String fingerprint}) async {
    try {
      final dir = await _cacheDir();
      if (dir == null) return null;
      final file = File(
          '${dir.path}/bytes_${_sanitize(trackId)}_$fingerprint.json');
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
      final file = File(
          '${dir.path}/bytes_${_sanitize(trackId)}_$fingerprint.json');
      await file.writeAsString(jsonEncode(
          _toCacheJson(data, audioFingerprint: fingerprint)));
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
    final amplitudes = rawSamples
        .map((e) => (e as num).toDouble().clamp(0.0, 1.0))
        .toList();
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
      final seg =
          uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
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
