import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Carpeta única de datos de Scrotify.
///
/// En escritorio es el directorio de soporte de la app (oculto para el
/// usuario: `~/.local/share/...` en Linux, `%APPDATA%` en Windows), para no
/// dejar JSONs a la vista en Documentos. En móvil el directorio de documentos
/// ya es privado de la app.
Future<Directory> getAppDataDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  if (!_isDesktop) return docs;

  final dir = await getApplicationSupportDirectory();
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

/// Mueve los archivos que versiones anteriores dejaban a la vista:
/// la carpeta `<Documentos>/Scrotify` y los sueltos en Documentos.
Future<void> _migrateLegacyFiles(Directory docs, Directory to) async {
  final visible = Directory(p.join(docs.path, 'Scrotify'));
  await _moveEntries(visible, to, (_) => true);
  try {
    if (await visible.exists() && await visible.list().isEmpty) {
      await visible.delete();
    }
  } catch (_) {}
  await _moveEntries(docs, to, (name) => _legacyName.hasMatch(name));
}

Future<void> _moveEntries(
    Directory from, Directory to, bool Function(String name) accept) async {
  try {
    if (!await from.exists()) return;
    await for (final entity in from.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (!accept(name)) continue;
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
