# Correcciones de sesión, conectividad y reproductor

## Alcance

Pedido: corregir los cinco hallazgos de la revisión, investigar pérdida de conexión y restaurar el fondo difuminado y la forma de onda del reproductor ampliado. Implementación delegada explícitamente por el usuario a Claude Code. Sin commits, cambios de credenciales ni consultas a producción.

## Contratos de aceptación

1. Un flush de scrobbles pertenece a una identidad/sesión fija; cambiar de cuenta detiene los siguientes envíos y conserva lo pendiente en su cola original. HTTP 2xx no basta: solo se confirma un envelope Subsonic válido con `status=ok`. Carga inicial de cola compartida entre operaciones concurrentes.
2. Sync cambia de identidad cuando cambia la cuenta y se suspende al desaparecer el perfil, sin convertir logout en opt-out permanente. Activaciones y ciclos anteriores no pueden aplicar/subir datos tras suspensión/cambio. Mantener compatibilidad con vinculación manual y opt-out explícito.
3. Búsquedas por texto/género desktop y móvil solo aplican resultados/errores de la sesión que las inició; invalidar generación al cambiar de sesión.
4. Conectividad: distinguir transporte de errores HTTP/Subsonic. No reportar éxito vacío ante una respuesta rechazada. Mantener fallback offline seguro y recuperación automática acotada. Añadir regresiones deterministas con transporte inyectado; no atribuir el incidente real sin logs.
5. Fondo ampliado: imagen ambiental ocupa el área disponible, se resuelve con identidad estable y conserva un desenfoque visible, sin reiniciar consultas en cada notificación de reproducción. Validar con widget tests y, si es posible, render capturado.
6. Waveform: analizar audio real, no sustituirlo por formas inventadas. Coalescer trabajo duplicado, preferir audio local o stream liviano y acotar coste. No bloquear UI con análisis PCM pesado. Exponer estado neutro/error honesto en plataformas sin decodificador; no prometer FFT en vivo.

## Verificación

Regresiones RED→GREEN por subsistema; `flutter analyze --no-pub`, `flutter test --no-pub --reporter=json`, `flutter build linux --debug --no-pub`, `git diff --check`. Declarar aparte cualquier validación visual/nativa no ejecutada y cualquier plataforma que siga sin decodificador.

## Resultado verificado

- Implementación delegada a tres sesiones Claude Code (sesión/Sync, conectividad y reproductor); revisión y ejecución integral independientes desde Hermes. Sin commits ni cambios de dependencias. La última sesión de revisión de Sync agotó su cuota tras restaurar la implementación; se verificó el código real, no su mensaje de finalización.
- `flutter analyze --no-pub`: PASS, sin issues.
- `flutter test --no-pub --reporter=json`: PASS, 1088 pruebas visibles aprobadas, 3 omitidas, 0 fallidas. Otros 133 eventos internos/ocultos no se cuentan como pruebas visibles.
- `flutter build linux --debug --no-pub`: PASS. Bundle en `build/linux/x64/debug/bundle/`; binario comprobado existente. Permanecen dos warnings C++ previos del plugin `hotkey_manager_linux` (variables `identifier` y `keystring`).
- `git diff --check`: PASS tras limpiar el final del checklist.
- Regresiones de scrobbles y búsquedas ejecutadas sobre snapshot HEAD: 9 fallos de comportamiento y 4 controles aprobados; sobre el código corregido pasan. Pruebas de identidad/cola/persistencia Sync y conectividad también cubren los fallos anteriores. Un probe independiente de migración legacy pasó de rojo a verde durante la revisión.
- Render de `PlayerAmbientBackground` y `WaveformProgressBar` con portada y WAV locales: PASS en claro/oscuro, con imágenes decodificadas antes de capturar. Es un render de widgets reales con fixtures, no una sesión completa de reproducción en un dispositivo.

## Causas y correcciones

- Catálogo vacío permanente: respuestas HTTP 5xx/rechazos Subsonic se ocultaban como listas vacías; el ping aceptaba cualquier HTTP 200. Ahora hay parser tipado, ping validado por sesión, retry acotado, aviso degradado por consulta y reintento visible en Home desktop/móvil.
- Fondo: tintar con `textPrimary` y `modulate` oscurecía la imagen; las portadas sanitizadas no se firmaban y el Future se recreaba en cada rebuild. El tamaño de ventana no fue la causa. Se usa tinte blanco translúcido, firma vigente y resolución estable por pista/sesión/versión.
- Waveform: analizar lossless y rechazar archivos locales de más de 30 MB dejaba la barra neutra; trabajos duplicados y cálculo PCM en UI agregaban coste. Se prefiere archivo local o stream MP3 96 kbps, se comparte trabajo, se limita concurrencia y se analiza fuera de UI. La caché distingue fuente/cuenta/subruta/archivo, y la pantalla diferencia análisis de fallo.
- Sesión: flush de scrobbles fijado a cuenta; rechazo lógico no borra el pendiente; carga inicial compartida. Sync cambia identidad y filtra archivos scoped, suspende cuentas al logout, invalida ciclos obsoletos y serializa persistencia. Búsquedas de texto/género no publican resultados ni errores de una sesión anterior.

## Límites y seguimiento

- El usuario aclara que pierde conexión y no carga nada, pero no aportó el registro del episodio ni identificó plataforma. Los fallos reproducidos explican rutas posibles; no establecen la causa de aquel corte específico. No hubo consultas a producción ni pruebas manuales en Android/iOS/Windows o múltiples dispositivos.
- La waveform temporal no es un espectro FFT en vivo. Android/iOS siguen sin decodificador de MP3/FLAC en esta implementación: se informa el motivo, sin amplitudes sintéticas. En escritorio se necesita FFmpeg CLI; libmpv con FFmpeg integrado no sustituye al ejecutable. No se produjo un paquete Windows/Android nuevo.
- Si Navidrome no transcodifica y devuelve el original, aún puede exceder el límite remoto o tardar. El PCM completo sigue ocupando memoria; no se midió rendimiento con bibliotecas o pistas reales del usuario.
- Las claves Sync antiguas sin procedencia no se consideran manuales automáticamente: esperan confirmación de cuenta. Si se reemplazan por la clave de otra cuenta, se conserva respaldo en SecureStorage. Una vinculación manual antigua puede requerir revincular su clave original. Las vinculaciones manuales explícitas son independientes del logout de Navidrome.
- La auditoría anterior `docs/auditoria-conectividad-2026-10-17.md` se dejó intacta. Este trabajo no cierra todos sus hallazgos ni constituye una auditoría exhaustiva del proyecto.
