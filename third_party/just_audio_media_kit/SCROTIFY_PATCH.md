# Copia parcheada de just_audio_media_kit 2.1.0

Origen: https://pub.dev/packages/just_audio_media_kit (dominio público, Unlicense).

Cambios para Scrotify (solo añaden API, no cambian el comportamiento):

* `MediaKitPlayer.player`: acceso al `Player` de media_kit (mpv). El campo
  original era privado y no había forma de fijar propiedades de mpv.
* `JustAudioMediaKit.mpvPlayers` / `activePlayers`: reproductores mpv activos.
* `JustAudioMediaKit.onPlayerReady`: aviso al quedar listo un reproductor.

Se usan para aplicar el filtro `af` del ecualizador y los ajustes Hi-Fi.
Si se actualiza el paquete original, hay que volver a aplicar estos tres cambios.
