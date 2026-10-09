import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/local_music_service.dart';
import '../services/navidrome_service.dart';

class LocalMusicSettings extends StatefulWidget {
  const LocalMusicSettings({super.key});
  @override
  State<LocalMusicSettings> createState() => _LocalMusicSettingsState();
}

class _LocalMusicSettingsState extends State<LocalMusicSettings> {
  Future<int?>? _serverCount;
  String? _session;
  String? _error;
  String? _scanSummary;
  bool _busy = false;
  Future<void>? _initialization;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<NavidromeService>();
    if (_serverCount == null || _session != nav.currentSessionKey) {
      _session = nav.currentSessionKey;
      _serverCount = nav.getServerSongCount();
    }
    _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await context.read<LocalMusicService>().initialize();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la carpeta de música.');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo acceder a la carpeta. Comprueba los permisos.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(LocalMusicService music) async {
    String? path;
    if (Platform.isIOS) {
      final input = TextEditingController(text: music.folderPath);
      path = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Carpeta de música'),
                  content: TextField(
                      controller: input,
                      decoration: const InputDecoration(
                          labelText: 'Ruta de la carpeta')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, input.text),
                        child: const Text('Guardar'))
                  ]));
      input.dispose();
    } else {
      path = await getDirectoryPath(
          initialDirectory: music.folderPath,
          confirmButtonText: 'Usar esta carpeta');
    }
    if (path != null && path.trim().isNotEmpty) {
      await music.changeFolder(path);
      if (mounted) await _rescan(music, context.read<NavidromeService>());
    }
  }

  Future<void> _rescan(LocalMusicService music, NavidromeService nav) async {
    await music.initialize();
    await music.rescan(
        serverScope: nav.serverScope,
        catalogLoader: nav.getDownloadRecoveryCatalog);
    if (!mounted) return;
    setState(() {
      _serverCount = nav.getServerSongCount();
      _scanSummary = 'Recuperadas: ${music.recoveredByLastScan}. '
          'Archivos sin identificar: ${music.unidentifiedByLastScan}.';
      if (music.recoveryUnavailable) {
        _scanSummary =
            '$_scanSummary Conecta el servidor para identificar archivos antiguos.';
      }
      if (music.lastScanCancelled) {
        _scanSummary = 'Escaneo cancelado. $_scanSummary';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<LocalMusicService>();
    final nav = context.watch<NavidromeService>();
    final busy = _busy || music.scanning;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_open_rounded),
          title: SelectableText(music.folderPath ?? 'Preparando carpeta…')),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: busy ? null : () => _run(() => _change(music)),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Cambiar carpeta')),
        OutlinedButton.icon(
            onPressed: busy ? null : () => _run(() => _rescan(music, nav)),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(busy ? 'Escaneando…' : 'Reescanear')),
      ]),
      if (music.scanProgress != null)
        ScanProgressView(
            progress: music.scanProgress!, onCancel: music.cancelScan),
      const SizedBox(height: 16),
      FutureBuilder<int?>(
          future: _serverCount,
          builder: (context, snapshot) => Text(
              'Canciones totales del servidor: ${snapshot.connectionState == ConnectionState.waiting ? '…' : snapshot.data ?? 'No disponible'}')),
      const SizedBox(height: 8),
      Text('Canciones descargadas localmente: ${music.count(nav.serverScope)}'),
      if (_scanSummary != null)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_scanSummary!)),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
      if (Platform.isAndroid)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
                'La carpeta predeterminada es /storage/emulated/0/Music. '
                'Al descargar o reescanear, permite el acceso al almacenamiento en Android.')),
    ]);
  }
}

/// Texto de la etapa del escaneo ("Leyendo archivos… 12 de 340").
String scanProgressLabel(LocalScanProgress progress) {
  switch (progress.phase) {
    case LocalScanPhase.listing:
      return 'Buscando archivos… ${progress.done}';
    case LocalScanPhase.files:
      return 'Leyendo archivos… ${progress.done} de ${progress.total}';
    case LocalScanPhase.catalog:
      return 'Consultando el catálogo del servidor…';
    case LocalScanPhase.matching:
      return 'Identificando canciones… ${progress.done} de ${progress.total}';
  }
}

/// Barra de avance del escaneo con botón para cancelarlo.
class ScanProgressView extends StatelessWidget {
  const ScanProgressView(
      {super.key, required this.progress, required this.onCancel});

  final LocalScanProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(scanProgressLabel(progress))),
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
          ]),
        ]),
      );
}
