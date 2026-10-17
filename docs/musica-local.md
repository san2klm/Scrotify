# Música local

- Ajustes sustituye Sesión por Música local: carpeta configurable, reescaneo, total del servidor y canciones locales únicas para la cuenta activa.
- Descargas individuales en la raíz; favoritos en `likes`; playlists en `playlist(Nombre)`.
- Identidad por servidor/canción, independiente de la ubicación. Reutilizar archivos existentes, incluso tras reiniciar, mover o copiar dentro de la biblioteca; no descargar otra vez por pertenecer a otra colección.
- Reescaneo recursivo por huella de contenido y metadatos persistentes. Archivos desconocidos no se atribuyen a canciones del servidor solo por su nombre.
- Linux usa XDG Music (o ~/Música); Windows/macOS Music; Android usa `/storage/emulated/0/Music` (sin subcarpeta CrotoWave); iOS usa una ubicación específica de la aplicación. Cambiar carpeta no borra la anterior.
- En Android, solicitar acceso al almacenamiento compartido al descargar, cambiar carpeta o reescanear; no abrir permisos durante el arranque. Migrar la ruta predeterminada anterior conservando sus archivos y las carpetas elegidas manualmente.
- Mantener la caché anterior y su aislamiento por servidor. No sobrescribir archivos ajenos ni seguir enlaces fuera de la carpeta autorizada.
- Verificar deduplicación, concurrencia, reinicio, reescaneo y carpetas mediante pruebas; análisis y compilación Linux.

## Verificación del contador

El total usa `getScanStatus` una vez terminado el escaneo del servidor. Durante
un escaneo se muestra «No disponible» porque el contador representa el progreso,
no el total definitivo ([implementación de Navidrome](https://github.com/navidrome/navidrome/blob/master/scanner/controller.go)).

## Biblioteca sin conexión

- Guardar nombres, IDs, orden y pertenencia de playlists y likes por usuario/servidor, sin URLs autenticadas ni claves.
- Las lecturas del servidor recurren a las canciones disponibles en disco al perder la red; las colecciones muestran únicamente canciones reproducibles localmente.
- Restaurar la cuenta activa guardada si falla la conexión por red y hay audio local; un error de autenticación no habilita esta entrada.
- Recuperar las descargas anteriores agrupadas en playlist(Nombre)/likes aunque procedan del índice previo.
- Mostrar canciones, playlists y likes disponibles tras reiniciar sin internet en las vistas habituales; ofrecer Reconectar en Inicio, sin tarjeta adicional de «Descargadas».

## Portadas y metadatos sin internet

- Guardar imágenes de canciones y playlists en la carpeta interna `artwork`, con nombres derivados del servidor y el ID. No guardar URLs, tokens ni credenciales.
- Descargar la portada junto con la canción; un fallo de imagen no cancela la descarga del audio. Buscar la portada externa cuando el servidor no la ofrece.
- Completar portadas de canciones descargadas al abrir canciones, likes y playlists con conexión; la imagen local se reutiliza tras reiniciar.
- Las listas, mini reproductor, reproductor y fondos admiten imágenes locales. Sin conexión no buscar imágenes en fuentes externas.
- Conservar también género, número de pista, identificadores musicales, fecha, reproducciones y ReplayGain.
- Validar la imagen antes de guardarla y limitar su tamaño a 8 MB; mantener la separación entre servidores.

## Recuperar archivos antiguos sin índice

Reescanear recorre la carpeta configurada y sus subcarpetas, conserva la identidad
por hash de las descargas conocidas y recupera archivos desconocidos mediante sus
etiquetas. La recuperación inicial requiere conexión con el servidor: consulta
su catálogo completo y exige título, artista y duración (tolerancia de 2 s), además
del álbum cuando el archivo lo incluye. Las coincidencias ambiguas se dejan sin
identificar; el nombre del archivo por sí solo no prueba la identidad.

Las copias idénticas se registran una sola vez, conservando sus rutas. El registro
persistido permite reproducir sin red y evita descargar otra vez desde likes u
otras playlists. Cambiar de carpeta ejecuta también esta recuperación. El resultado
muestra canciones recuperadas y contenidos sin identificar, y pide conexión cuando
no se pudo consultar el catálogo. Un archivo sin etiquetas suficientes permanece
sin identificar.

Android utiliza MediaMetadataRetriever. En escritorio se necesita ffprobe en PATH
para leer etiquetas de archivos desconocidos; las descargas con índice previo
continúan funcionando sin él. La prueba de integración del lector se ejecuta con
`SCROTIFY_METADATA_INTEGRATION=1 flutter test test/local_music_recovery_test.dart`
(en Linux, con ffmpeg y ffprobe).
