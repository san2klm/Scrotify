import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/diagnostics_log.dart';
import '../utils/app_colors.dart';
import '../utils/app_data_dir.dart';
import '../utils/build_info.dart';

/// Ajustes → Diagnóstico: copiar o guardar el registro reciente de la app
/// para adjuntarlo al reportar un fallo.
class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({super.key, this.log, this.directory});

  /// Registro a mostrar; por defecto, el global.
  final DiagnosticsLog? log;

  /// Carpeta donde se guarda el archivo; por defecto, la de datos de la app.
  final Future<Directory> Function()? directory;

  DiagnosticsLog get _log => log ?? DiagnosticsLog.instance;

  String _export() => _log.export(header: {
        'App': 'Scrotify ${BuildInfo.label}',
        'Sistema':
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'Generado': DateTime.now().toIso8601String(),
      });

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _export()));
    if (context.mounted) _notify(context, 'Diagnóstico copiado');
  }

  Future<void> _save(BuildContext context) async {
    try {
      final dir = await (directory ?? getAppDataDirectory)();
      final stamp = DateTime.now()
          .toIso8601String()
          .split('.')
          .first
          .replaceAll(':', '-');
      final file = File(p.join(dir.path, 'diagnostico-$stamp.txt'));
      await file.writeAsString(_export(), flush: true);
      if (context.mounted) _notify(context, 'Guardado en ${file.path}');
    } catch (e) {
      if (context.mounted) _notify(context, 'No se pudo guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(color: context.textSecondary, fontSize: 13);
    return ListenableBuilder(
      listenable: _log,
      builder: (context, _) {
        final count = _log.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scrotify guarda en memoria los últimos mensajes internos '
              '(conexión, reproducción, Jam). No salen del dispositivo salvo '
              'que los copies o guardes, y las contraseñas y claves se ocultan.',
              style: secondary,
            ),
            const SizedBox(height: 8),
            Text(
              count == 0
                  ? 'Todavía no hay mensajes.'
                  : '$count mensajes registrados desde que abriste la app.',
              style: TextStyle(color: context.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: count == 0 ? null : () => _copy(context),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copiar'),
                ),
                OutlinedButton.icon(
                  onPressed: count == 0 ? null : () => _save(context),
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('Guardar en archivo'),
                ),
                TextButton(
                  onPressed: count == 0 ? null : _log.clear,
                  child: const Text('Vaciar'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
