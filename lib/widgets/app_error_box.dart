import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Sustituto de la pantalla roja (debug) o gris (release) de Flutter cuando un
/// widget falla al construirse: un recuadro discreto que no depende de ningún
/// tema ni proveedor, para que el resto de la pantalla siga siendo usable.
///
/// El detalle del error ya queda en el registro de diagnóstico (lo escribe
/// `FlutterError.onError`); aquí solo se muestra completo en modo debug.
class AppErrorBox extends StatelessWidget {
  const AppErrorBox({super.key, required this.details, this.showDetails});

  final FlutterErrorDetails details;

  /// Por defecto, solo en debug.
  final bool? showDetails;

  /// Instala el recuadro como `ErrorWidget.builder`.
  static void install() {
    ErrorWidget.builder = (details) => AppErrorBox(details: details);
  }

  @override
  Widget build(BuildContext context) {
    final verbose = showDetails ?? kDebugMode;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1E1E),
          border: Border.all(color: const Color(0xFF8A4B4B)),
          borderRadius: BorderRadius.circular(8),
        ),
        // Puede caer en un hueco diminuto o sin límites: nunca debe desbordar.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta parte no se pudo mostrar',
                style: TextStyle(
                  color: Color(0xFFF2D6D6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                verbose
                    ? details.exceptionAsString()
                    : 'El resto de la app sigue funcionando. Puedes enviar el '
                        'registro desde Ajustes → Diagnóstico.',
                maxLines: verbose ? 8 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFCDB4B4),
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
