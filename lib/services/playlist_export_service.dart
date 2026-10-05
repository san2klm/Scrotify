import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';
import 'settings_controller.dart';

/// Resultado de una descarga interrumpida por un error.
class PlaylistDownloadException implements Exception {
  final int completedCount;
  final Object cause;

  const PlaylistDownloadException(this.completedCount, this.cause);

  @override
  String toString() =>
      'Se descargaron $completedCount canciones antes del error: $cause';
}

/// Exporta los temas de una playlist a CSV o los guarda como archivos locales.
class PlaylistExportService {
  PlaylistExportService._();

  static Future<String?> exportCsv(List<Track> tracks, String name) async {
    final fileName = '${_safeName(name, fallback: 'playlist')}.csv';
    final csv = _tracksToCsv(tracks);
    late File file;

    if (_isDesktop) {
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
        suggestedName: fileName,
      );
      if (location == null) return null;
      var path = location.path;
      if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';
      file = File(path);
    } else {
      final directory = await _mobileExportDirectory();
      file = File(p.join(directory.path, fileName));
    }

    await file.writeAsString('\uFEFF$csv', encoding: utf8, flush: true);
    return file.path;
  }

  /// Descarga los originales a una subcarpeta de la ubicación elegida.
  /// Devuelve el total terminado; si el usuario cancela, conserva y devuelve
  /// el número de archivos completos ya guardados.
  static Future<int?> downloadLocally(
    NavidromeService nav,
    List<Track> tracks,
    String name, {
    required void Function(int done, int total, String title) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (tracks.isEmpty) return 0;

    final selectedDirectory = _isDesktop
        ? await getDirectoryPath()
        : (await _mobileExportDirectory()).path;
    if (selectedDirectory == null) return null;

    final outputDirectory = Directory(
      p.join(selectedDirectory, _safeName(name, fallback: 'playlist')),
    );
    await outputDirectory.create(recursive: true);

    var done = 0;
    for (final track in tracks) {
      if (isCancelled()) return done;
      onProgress(done, tracks.length, track.title);

      File? temporaryFile;
      File? destinationFile;
      try {
        final extension = _safeSuffix(track.suffix);
        final baseName = _safeName(
          '${track.artist} - ${track.title} - ${track.id}',
          fallback: 'cancion-${done + 1}',
        );
        destinationFile = await _availableDestination(
          outputDirectory,
          baseName,
          extension,
        );
        temporaryFile = File('${destinationFile.path}.part');
        if (await temporaryFile.exists()) await temporaryFile.delete();

        await nav.downloadTrackStream(
          trackId: track.id,
          destinationFile: temporaryFile,
          quality: AudioQuality.lossless,
          isCancelled: isCancelled,
        );
        if (isCancelled()) {
          if (await temporaryFile.exists()) await temporaryFile.delete();
          return done;
        }

        // Recalcular si otro proceso creó el destino mientras se descargaba.
        if (await destinationFile.exists()) {
          destinationFile = await _availableDestination(
            outputDirectory,
            baseName,
            extension,
          );
        }
        await temporaryFile.rename(destinationFile.path);
        done++;
        onProgress(done, tracks.length, track.title);
      } catch (error) {
        if (temporaryFile != null && await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
        if (isCancelled()) return done;
        throw PlaylistDownloadException(done, error);
      }
    }
    return done;
  }

  static bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static Future<Directory> _mobileExportDirectory() async {
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  static String _tracksToCsv(List<Track> tracks) {
    final buffer = StringBuffer('title,artist,album,duration,id\r\n');
    for (final track in tracks) {
      buffer
        ..write(_csvCell(track.title))
        ..write(',')
        ..write(_csvCell(track.artist))
        ..write(',')
        ..write(_csvCell(track.album))
        ..write(',')
        ..write(_csvCell(track.duration))
        ..write(',')
        ..write(_csvCell(track.id))
        ..write('\r\n');
    }
    return buffer.toString();
  }

  static String _csvCell(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\r') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _safeName(String value, {required String fallback}) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return fallback;
    final truncated = StringBuffer();
    var byteLength = 0;
    for (final rune in cleaned.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (byteLength + characterBytes > 160) break;
      truncated.write(character);
      byteLength += characterBytes;
    }
    final safe = truncated.toString().trim();
    return safe.isEmpty ? fallback : safe;
  }

  static String _safeSuffix(String? suffix) {
    final cleaned = (suffix ?? '').replaceFirst(RegExp(r'^\.'), '');
    if (cleaned.isEmpty ||
        cleaned.length > 10 ||
        !RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleaned)) {
      return 'audio';
    }
    return cleaned.toLowerCase();
  }

  static Future<File> _availableDestination(
    Directory directory,
    String baseName,
    String extension,
  ) async {
    for (var ordinal = 1;; ordinal++) {
      final suffix = ordinal == 1 ? '' : ' ($ordinal)';
      final file = File(p.join(directory.path, '$baseName$suffix.$extension'));
      final part = File('${file.path}.part');
      if (!await file.exists() && !await part.exists()) return file;
    }
  }
}
