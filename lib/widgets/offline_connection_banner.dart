import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Estado de la conexión y acceso a la reconexión del servidor.
class OfflineConnectionBanner extends StatefulWidget {
  const OfflineConnectionBanner({super.key});
  @override
  State<OfflineConnectionBanner> createState() =>
      _OfflineConnectionBannerState();
}

class _OfflineConnectionBannerState extends State<OfflineConnectionBanner> {
  bool _connecting = false;

  Future<void> _reconnect(NavidromeService nav) async {
    setState(() => _connecting = true);
    final offline = nav.offlineMode;
    try {
      // Degradado: repite las consultas que fallaron; solo si responden se
      // reconecta y las pantallas recargan. Un ping correcto no basta.
      await (offline ? nav.reconnect() : nav.retryDegraded());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(offline
                ? 'El servidor sigue sin estar disponible. Puedes escuchar tus descargas.'
                : 'El servidor sigue respondiendo con errores. Inténtalo de nuevo en un momento.')));
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    final offline = nav.offlineMode;
    if (!offline && !nav.serverDegraded) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                      offline
                          ? 'Sin conexión · Música del dispositivo'
                          : 'El servidor responde con errores · Datos posiblemente incompletos',
                      style: TextStyle(color: context.textSecondary)),
                  TextButton.icon(
                      onPressed: _connecting ? null : () => _reconnect(nav),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(_connecting
                          ? 'Conectando…'
                          : (offline ? 'Reconectar' : 'Reintentar')))
                ]),
          ],
        ));
  }
}

/// Estado de Inicio cuando el catálogo no se pudo cargar con el servidor vivo
/// (5xx, credenciales rechazadas, respuesta ilegible): dice qué pasó y deja
/// reintentar la carga, en vez de un vacío mudo.
class LibraryLoadError extends StatelessWidget {
  const LibraryLoadError({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Solo las excepciones propias llevan texto seguro (sin datos del servidor).
    final detail = error is SubsonicException
        ? error.toString()
        : 'No se pudo cargar el contenido.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary)),
            const SizedBox(height: 12),
            TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
