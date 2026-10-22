# Waveform real en Android con el SDK nativo

## Contrato

- MP3/FLAC mediante `MediaExtractor` + `MediaCodec` en Kotlin, sin FFmpeg CLI ni dependencias nuevas. WAV conserva su decoder Dart y desktop conserva FFmpeg.
- Canal `crotowave/waveform`: `decode` recibe `jobId`, `path` absoluto local, `bins` (16..2048) y `durationUs` positivo; devuelve exclusivamente `bins` amplitudes finitas 0..1. `cancel` recibe `jobId`. Errores seguros: unsupported, timeout, cancelled, decode_failed, invalid_arguments.
- IO/codec/análisis en executor acotado: PCM por bloques, no la canción completa en memoria. Liberar extractor/codec/temporales también en fallos de inicialización, cancelación y timeout. Manejar EOS, offsets, cambios de formato y PCM entero 8/16/24/32 o float.
- Mono por promedio de canales, RMS*0.75 + pico*0.25 por ventana y normalización como `PcmWaveformAnalyzer`. Silencio real permanece en cero; nunca inventar amplitudes.
- Archivos comprimidos locales por ruta, también mayores de 30 MB. Para streaming, reutilizar el audio de análisis reducido ya descargado y un temporal privado; no enviar URL, credenciales ni PCM por el canal. Conservar caché/coalescing por origen.
- Registrar trabajos antes del primer await; cancelar al cambiar pista, vaciar cola o disponer el reproductor. La interfaz opcional `CancelableWaveformService` no rompe dobles existentes. Abortar HTTP con `AbortableRequest` de la dependencia existente, no cerrar el cliente compartido.
- Caché con temporal único por job y rename atómico. La cancelación anterior al punto de commit impide publicar; una vez iniciada la publicación, el resultado ya está comprometido y no se transforma después en cancelado. No borrar caché de otros trabajos.
- `AndroidWaveformPlugin` pertenece al `FlutterEngine`, no a la Activity. Registrar una sola instancia en `engine.plugins`; conservar el canal mientras audio_service mantiene el motor en segundo plano. En `onEngineWillDestroy`, soltar la referencia al engine antes de disponer, sin eliminar listeners mientras Flutter los itera.
- Mantener errores seguros y protecciones por generación. No cambiar modelos, permisos, firma, perfiles ni comportamiento de radios en directo. No commit/push automático ni inclusión de la auditoría histórica sin seguimiento.

## Implementación

- `android/app/src/main/kotlin/cloud/templo/crotowave/AndroidWaveformPlugin.kt`: canal, lifecycle, jobs y decodificación nativa.
- `android/app/src/main/kotlin/cloud/templo/crotowave/PcmWaveformBinner.kt`: acumulador PCM acotado.
- `lib/services/android_waveform_decoder.dart`: validación del bridge, errores seguros y temporales.
- `lib/services/audio_waveform_service.dart`: selección del decoder, descargas abortables, coalescing y publicación de caché.
- `player_controller.dart`, `player_queue.dart`, `waveform_service.dart`: cancelación opcional y descarte de resultados obsoletos.

## Verificación realizada

- RED inicial del bridge antes de implementarlo. RED→GREEN adicional para abortar descargas que ocupaban los turnos y para impedir publicar caché tras cancelación.
- `flutter analyze --no-pub`: **sin issues**.
- Tests dirigidos: **47 aprobados**. Suite completa `flutter test --no-pub --reporter=json`: **1106 aprobados, 3 omitidos preexistentes, 0 fallidos**.
- `flutter build linux --debug --no-pub`: aprobado; sin reconstruir el AppImage de distribución.
- `tool/PcmWaveformBinnerSmoke.kt`: **20 comprobaciones JVM** de 5 encodings, RMS/pico, offsets, bloques, silencio y promedio estéreo. Ejecutado con compilador y bibliotecas ya disponibles en la caché Gradle, sin instalar dependencias.
- Android 14/API 34 x86_64: APK debug con entrypoint de prueba usando `AudioWaveformService` y el canal Kotlin real, **12 comprobaciones aprobadas**: MP3, FLAC 16/24 bits, silencio digital, HTTP loopback coalescido, caché reutilizada, aborto de dos descargas detenidas con liberación de turnos, FLAC válido de 33.598.041 bytes, audio inválido, argumentos incorrectos, cancelación nativa y extracción después de destruir la Activity mientras la reproducción real continúa.
- Destrucción posterior del servicio/engine **sin crash**, comprobada leyendo el buffer de crashes tras finalizar. Se reprodujo y corrigió un `ConcurrentModificationException` por retirar el listener dentro de `onEngineWillDestroy`.
- El FLAC grande utiliza padding legal: prueba lectura por ruta sin tope de 30 MB, no rendimiento de una canción larga. Los audios de prueba son fixtures sintéticos reales de silencio–tono–silencio, no amplitudes inventadas en producción.
- APK release teléfono ARM64 normal (`lib/main.dart`) compilado y publicado en `dist/CrotoWave-1.0.0-TELEFONO-arm64.apk`, versión 1.0.0, **versionCode 12251**. Firma verificada e idéntica a la entrega anterior, no depurable, ZIP íntegro y sin entrypoint de pruebas. `SHA256SUMS` actualizado y comprobado. AppImage existente preservado.

## Límites

La ejecución Android fue en emulador, no en un teléfono ARM64 físico ni contra el servidor del usuario. Se validó el pipeline, reproducción durante cierre de Activity y cleanup; no una sesión visual completa de la aplicación. Los formatos de alta resolución/multicanal siguen dependiendo de los codecs del dispositivo. iOS no recibe un decoder comprimido en este cambio.

## Fuentes

- https://developer.android.com/reference/android/media/MediaExtractor
- https://developer.android.com/reference/android/media/MediaCodec
- https://developer.android.com/media/platform/supported-formats
- https://docs.flutter.dev/platform-integration/platform-channels
- https://api.flutter.dev/javadoc/io/flutter/embedding/engine/plugins/FlutterPlugin.html
- https://pub.dev/documentation/http/latest/http/AbortableRequest-class.html
