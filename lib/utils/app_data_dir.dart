import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Carpeta única de datos de Scrotify.
///
/// En escritorio es `<Documentos>/Scrotify`, para no esparcir JSONs sueltos
/// en Documentos. En móvil el directorio de documentos ya es privado de la app.
Future<Directory> getAppDataDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  if (!_isDesktop) return docs;

  final dir = Directory(p.join(docs.path, 'Scrotify'));
  await dir.create(recursive: true);
  if (_migrated.add(docs.path)) await _migrateLegacyFiles(docs, dir);
  return dir;
}

final Set<String> _migrated = <String>{};

bool get _isDesktop =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

final RegExp _legacyName = RegExp(
  r'^(equalizer|settings|listening_stats|recently_played|most_played|'
  r'followed_artists|excluded_artists|pinned_playlists|starred_track_order|'
  r'track_ratings|last_genre_suggestion)(_[^/]*)?\.json(\.tmp)?$'
  r'|^offline_cache\.db(-journal|-wal|-shm)?$|^waveform_cache_v2$',
);

/// Mueve los archivos que versiones anteriores dejaban en Documentos.
Future<void> _migrateLegacyFiles(Directory from, Directory to) async {
  try {
    await for (final entity in from.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (!_legacyName.hasMatch(name)) continue;
      final target = p.join(to.path, name);
      if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
        continue;
      }
      try {
        await entity.rename(target);
      } catch (_) {
        // Si no se puede mover, la versión antigua queda donde estaba.
      }
    }
  } catch (_) {}
}
