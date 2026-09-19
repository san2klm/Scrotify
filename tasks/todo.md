# TODO — Mejoras UI/UX Scrotify

## Fase 1 — Visuales puros

- [x] **1.1** `interactive_artist_text.dart` — Hover sobre nombre de artista: cursor mano + color accent + subrayado sólido; cada artista separado resaltado independientemente
- [x] **1.2** `persistent_player_bar.dart` — Eliminar `Icon(Icons.drag_handle_rounded)` izquierdo en desktop y mobile bar
- [x] **1.3** `playlist_detail_screen.dart` — Mover drag handle al centro de la fila; añadir ⋮ en trailing que abre `TrackContextMenu`

## Fase 2 — Lógica de ordenación y duplicados

- [x] **2.1** `home_screen.dart` + `navidrome_service.dart` — Playlists fijadas aparecen primero en la biblioteca, debajo de "Me gusta"; reordenamiento reactivo sin reinicios
- [x] **2.2** `track_context_menu.dart` — Detectar si canción ya está en playlist antes de añadir; mostrar "Ya está en Nombre" y no duplicar

## Fase 3 — Seguir artistas

- [x] **3.1** `navidrome_service.dart` — Añadir `_followedArtistIds` y `_excludedArtistIds` con persistencia en JSON local; getters y toggles con `notifyListeners()`
- [x] **3.2** `artist_screen.dart` — Botón Seguir/Siguiendo funcional; menú Dejar de seguir / No reproducir / Compartir con funcionalidad real
- [x] **3.3** `home_screen.dart` — Mostrar artistas seguidos en la biblioteca entre "Me gusta" y playlists

## Fase 4 — Compartir con comunidad (links)

- [x] **4.1** `track_context_menu.dart` + `server_activity_panel.dart` — "Compartir canción": envía `[TRACK:id:title:artist]` al chat; el chat renderiza tile navegable con portada y botón reproducir
- [x] **4.2** `artist_screen.dart` + `server_activity_panel.dart` — "Compartir artista": envía `[ARTIST:id:name]` al chat; el chat renderiza tile con foto y botón "Ver artista"

## Fase 5 — Refresco instantáneo

- [x] **5.1** `playlist_detail_screen.dart` + `track_context_menu.dart` — Al añadir/eliminar canciones de playlist, refresco inmediato sin salir y volver; `bumpPlaylists()` propaga cambios al Consumer
