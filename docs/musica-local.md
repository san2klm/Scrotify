# Música local

- Ajustes sustituye Sesión por Música local: carpeta configurable, reescaneo, total del servidor y canciones locales únicas para la cuenta activa.
- Descargas individuales en la raíz; favoritos en `likes`; playlists en `playlist(Nombre)`.
- Identidad por servidor/canción, independiente de la ubicación. Reutilizar archivos existentes, incluso tras reiniciar, mover o copiar dentro de la biblioteca; no descargar otra vez por pertenecer a otra colección.
- Reescaneo recursivo por huella de contenido y metadatos persistentes. Archivos desconocidos no se atribuyen a canciones del servidor solo por su nombre.
- Linux usa XDG Music (o ~/Música); Windows/macOS Music; móviles usan una ubicación escribible específica de la aplicación. Cambiar carpeta no borra la anterior.
- Mantener la caché anterior y su aislamiento por servidor. No sobrescribir archivos ajenos ni seguir enlaces fuera de la carpeta autorizada.
- Verificar deduplicación, concurrencia, reinicio, reescaneo y carpetas mediante pruebas; análisis y compilación Linux.
