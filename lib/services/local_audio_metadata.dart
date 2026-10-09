import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Lee etiquetas locales sin reproducir el archivo ni consultar la red.
Future<Map<String, dynamic>?> readLocalAudioMetadata(File file) async {
  try {
    if (Platform.isAndroid) {
      return await const MethodChannel('scrotify/music_storage')
          .invokeMapMethod<String, dynamic>(
              'readAudioMetadata', {'path': file.path});
    }
    final process = await Process.start('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'format=duration:format_tags=title,artist,album',
      '-of',
      'json',
      file.path
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    int exit;
    try {
      exit = await process.exitCode.timeout(const Duration(seconds: 10));
    } finally {
      process.kill();
    }
    await errors;
    if (exit != 0) return null;
    final format = (jsonDecode(await output) as Map)['format'] as Map;
    final tags = <String, dynamic>{
      for (final entry in (format['tags'] as Map? ?? {}).entries)
        entry.key.toString().toLowerCase(): entry.value,
    };
    return {...tags, 'duration': double.tryParse('${format['duration']}')};
  } catch (_) {
    // Un archivo dañado o un lector no disponible no impide revisar los demás.
    return null;
  }
}
