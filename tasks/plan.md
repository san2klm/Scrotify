# Plan de implementación — Mejoras UI/UX Scrotify

Fecha: 2026-09-19  
Rama: Lau

---

## Resumen de pedidos

| # | Feature | Archivos principales |
|---|---------|---------------------|
| 1 | Hover en nombre de artista dentro de canciones → link clickable (por artista separado) | `interactive_artist_text.dart` |
| 2 | Quitar las dos rayitas del lado izquierdo de la barra de reproducción | `persistent_player_bar.dart` |
| 3 | Mover las rayitas (drag handle) al centro en las playlists | `playlist_detail_screen.dart` |
| 4 | Agregar tres puntitos (⋮) con opciones en cada fila de playlist | `playlist_detail_screen.dart`, `track_context_menu.dart` |
| 5 | El pin de playlist fija arriba de la biblioteca, debajo de "Me gusta" | `home_screen.dart`, `navidrome_service.dart` |
| 6 | Al añadir canción a playlist mostrar "ya está en esta playlist" en lugar de re-agregar | `track_context_menu.dart`, `navidrome_service.dart` |
| 7 | Refresco instantáneo al realizar acciones (sin salir y volver) | `track_context_menu.dart`, `playlist_detail_screen.dart`, `home_screen.dart` |
| 8 | Botón "Seguir" de artistas se guarda en la biblioteca | `navidrome_service.dart`, `artist_screen.dart`, `home_screen.dart` |
| 9 | Tres puntitos de artistas: Dejar de seguir + No reproducir + Compartir al chat | `artist_screen.dart`, `navidrome_service.dart`, `server_activity_panel.dart` |
| 10 | Compartir canción → enviar link al chat de comunidad; link lleva a la canción | `track_context_menu.dart`, `server_activity_panel.dart` |

---

## Dependencias

```
[1] InteractiveArtistText hover  ←── standalone, sin dependencias
[2] Quitar drag handle player    ←── standalone
[3] Drag handle al centro lista  ←── standalone
[4] Tres puntitos playlist       ←── depende de TrackContextMenu (ya existe)
[5] Pin ordering biblioteca      ←── depende de NavidromeService (pinnedPlaylistIds)
[6] Detectar duplicado playlist  ←── depende de NavidromeService.getPlaylistTracks
[7] Refresh instantáneo          ←── depende de NavidromeService.bumpPlaylists / notifyListeners
[8] Seguir artistas (biblioteca) ←── depende de NavidromeService (nueva feature: followedArtistIds)
[9] Menú artistas funcional      ←── depende de [8] (seguir/dejar de seguir) y NavidromeService (excludedArtistIds)
[10] Compartir canción → chat    ←── depende de ServerActivityPanel._shareTrackLink
```

---

## Fase 1 — Cambios visuales puros (sin lógica nueva)

### Tarea 1.1 — InteractiveArtistText: efecto hover en escritorio
**Archivo:** `lib/widgets/interactive_artist_text.dart`

**Qué hacer:**
- Envolver cada artista (y el texto del artista único) en un `MouseRegion` que cambie el cursor a `SystemMouseCursors.click`.
- Al hover, el color cambia a `context.accent` (o `context.textPrimary` si el texto ya es muted).
- La decoración subrayada ya existe; al hover se hace sólida en lugar de punteada.
- Para multiartista, cada `TextSpan` con `TapGestureRecognizer` se convierte en un `WidgetSpan` que contiene un `MouseRegion` + `GestureDetector` wrapeando un `Text` inline.

**Aceptación:**
- [ ] Al pasar el mouse sobre un artista, el cursor cambia a mano.
- [ ] El texto se resalta (color accent).
- [ ] Al hacer click navega al artista correcto.
- [ ] Varios artistas separados por coma quedan resaltados individualmente.

---

### Tarea 1.2 — Barra de reproducción: quitar icono de drag handle izquierdo
**Archivo:** `lib/widgets/persistent_player_bar.dart`

**Qué hacer:**
- En `_buildDesktopBar` (línea 62): eliminar `Icon(Icons.drag_handle_rounded, ...)` y el `SizedBox(width: 8)` que le sigue.
- En `_buildMobileBar` dentro del `Row` del `InkWell` (línea 176): eliminar `Icon(Icons.drag_handle_rounded, ...)` y su `SizedBox`.

**Aceptación:**
- [ ] La barra desktop no muestra las dos rayitas a la izquierda.
- [ ] La barra mobile no las muestra tampoco.
- [ ] El resto del layout no se desplaza incorrectamente.

---

### Tarea 1.3 — Playlist: mover drag handle al centro y añadir tres puntitos
**Archivo:** `lib/screens/playlist_detail_screen.dart`

**Qué hacer:**
- En `itemBuilder` del `ReorderableListView.builder` (línea 322), el `trailing` actualmente tiene: `[favorito, drag_handle]`.
- Nuevo orden `trailing`: `[drag_handle_centrado?, tres_puntitos]`.
- El drag handle pasa al **centro** de la fila, no al trailing. Para esto, reemplazar `ReorderableDragStartListener` para que envuelva un widget en el medio de la fila, o usar `customProxyDecorator` / columna con el handle en posición.
  - Opción práctica: insertar el `ReorderableDragStartListener` como hijo de un widget en la columna `subtitle` o bien usar un `Row` en el `title` que incluya el handle alineado al centro.
  - Implementación concreta: poner el handle como un elemento **leading interno** (después del CoverArt, antes del texto) en vez de trailing.
- Añadir `IconButton(Icons.more_vert)` en trailing que llame a `TrackContextMenu.show(context, track, playlistId: _playlist.id)`.

**Aceptación:**
- [ ] El drag handle (⠿) aparece visualmente en el centro horizontal de la fila.
- [ ] También funciona para arrastrar y reordenar.
- [ ] El ⋮ aparece en la derecha y abre el menú contextual pasando el `playlistId`.

---

## Fase 2 — Lógica de ordenación y detección de duplicados

### Tarea 2.1 — Pinned playlists van primero en la biblioteca
**Archivo:** `lib/screens/home_screen.dart`, `lib/services/navidrome_service.dart`

**Qué hacer:**
- En `_libraryList()`, al recibir `playlists`, ordenar para que las fijadas salgan primero:
  ```dart
  final sorted = [
    ...playlists.where((p) => nav.isPinnedPlaylist(p.id)),
    ...playlists.where((p) => !nav.isPinnedPlaylist(p.id)),
  ];
  ```
- Mismo reordenamiento en `_collapsedLibraryList()`.
- Cuando se llama a `nav.togglePinPlaylist`, el Consumer del widget ya se reconstruye porque `NavidromeService` es un `ChangeNotifier`. Verificar que se llama `notifyListeners()` en `togglePinPlaylist`. Si no lo hace, añadirlo.

**Aceptación:**
- [ ] Al fijar una playlist, aparece inmediatamente debajo de "Tus me gusta".
- [ ] Al desfijar, vuelve a la posición general.
- [ ] No requiere salir y volver a entrar.

---

### Tarea 2.2 — Detectar canción ya en playlist al añadir
**Archivo:** `lib/widgets/track_context_menu.dart`

**Qué hacer:**
- En `_showAddToPlaylistSheet`, al construir el `ListView` de playlists, para cada playlist verificar si `track.id` ya está en sus pistas.
- Como llamar `getPlaylistTracks` para cada playlist es caro, la solución es: cuando el usuario toca una playlist, **antes de añadir** verificar si la canción ya está:
  ```dart
  final existing = await nav.getPlaylistTracks(p.id);
  final alreadyIn = existing.any((t) => t.id == track.id);
  if (alreadyIn) {
    // mostrar snackbar "Ya está en 'nombre'"
    return;
  }
  await nav.updatePlaylist(...);
  ```
- En la lista visual, marcar con un ícono `Icons.check_circle_outline` (color accent) las playlists que ya contienen la canción. Para esto, hacer `FutureBuilder` para cargar los IDs de cada playlist (o simplemente verificar al tocar).
- El enfoque más simple y correcto: verificar solo al tocar (lazy), mostrar snackbar sin añadir.

**Aceptación:**
- [ ] Si la canción ya está en la playlist, aparece snackbar "Ya está en «Nombre»".
- [ ] No se duplica la canción.
- [ ] Si no está, se añade normalmente.

---

## Fase 3 — Seguir artistas (estado persistente)

### Tarea 3.1 — NavidromeService: persistir artistas seguidos y excluidos
**Archivo:** `lib/services/navidrome_service.dart`

**Qué hacer:**
- Añadir `Set<String> _followedArtistIds = {}` y `Set<String> _excludedArtistIds = {}`.
- Métodos:
  - `bool isFollowingArtist(String id)`
  - `Future<void> toggleFollowArtist(String id)` → persiste en archivo local (igual que `_pinnedPlaylistIds`)
  - `bool isArtistExcluded(String id)`
  - `Future<void> toggleExcludeArtist(String id)`
- Archivos locales: `followed_artists.json` y `excluded_artists.json` (misma carpeta que `pinned_playlists.json`).
- `notifyListeners()` al cambiar ambos sets.

**Aceptación:**
- [ ] `toggleFollowArtist` persiste entre reinicios.
- [ ] `toggleExcludeArtist` persiste entre reinicios.
- [ ] `notifyListeners()` se llama en ambos toggle.

---

### Tarea 3.2 — ArtistScreen: botón Seguir funcional + menú tres puntitos
**Archivo:** `lib/screens/artist_screen.dart`

**Qué hacer:**
- El botón `OutlinedButton('Seguir')` (línea 125) pasa a leer `nav.isFollowingArtist(widget.artist.id)`:
  - Si sigue: texto "Siguiendo", borde accent, al tocar llama `nav.toggleFollowArtist` (deja de seguir).
  - Si no sigue: texto "Seguir", borde textSecondary, al tocar llama `nav.toggleFollowArtist`.
- `_buildArtistMenu()` ya tiene las tres opciones (`follow`, `exclude`, `community`). Hacer que sean **funcionales**:
  - `follow` → `nav.toggleFollowArtist(widget.artist.id)` con snackbar apropiado.
  - `exclude` → `nav.toggleExcludeArtist(widget.artist.id)` con snackbar "No se reproducirá a [artista]" / "Se reproducirá nuevamente".
  - `community` → ya funciona (abre `ServerActivityPanel`), pero corregir: debe compartir al chat el **link del artista** (ver Tarea 4.2).

**Aceptación:**
- [ ] El botón "Seguir" / "Siguiendo" refleja estado real.
- [ ] Al tocar "Dejar de seguir" en el menú, el botón cambia sin recargar.
- [ ] Al excluir artista, snackbar confirma.

---

### Tarea 3.3 — HomeScreen: sección "Artistas que sigues" en biblioteca
**Archivo:** `lib/screens/home_screen.dart`

**Qué hacer:**
- En `_libraryList()`, añadir debajo de "Tus me gusta" y encima de las playlists una lista de artistas seguidos:
  ```dart
  final followedIds = nav.followedArtistIds; // nuevo getter
  if (followedIds.isNotEmpty) {
    for (final artistId in followedIds) {
      _libraryFollowedArtistTile(artistId, nav);
    }
  }
  ```
- El tile muestra nombre e imagen del artista (guardados en caché o buscados cuando se abre).
- NavidromeService añade `List<String> get followedArtistIds => _followedArtistIds.toList()`.
- Para obtener el nombre se puede guardar nombre también en el JSON de `followed_artists.json` como `{id: name}` map, o buscar de la caché local de artistas.

**Aceptación:**
- [ ] Los artistas seguidos aparecen en la biblioteca entre "Me gusta" y las playlists.
- [ ] Al seguir/dejar de seguir desde `ArtistScreen`, la lista se actualiza inmediatamente.

---

## Fase 4 — Compartir con la comunidad (link funcional)

### Tarea 4.1 — Compartir canción al chat como link navegable
**Archivos:** `lib/widgets/track_context_menu.dart`, `lib/widgets/server_activity_panel.dart`

**Qué hacer:**
- Definir formato de link interno: `scrotify://track/{trackId}` o simplemente un prefijo reconocible como `[TRACK:{trackId}:{trackTitle}:{artist}]`.
- En `TrackContextMenu`, opción "Compartir con la comunidad" actualmente solo abre el panel. Cambiar para que **envíe un mensaje al chat** automáticamente:
  ```dart
  final msg = '🎵 [TRACK:${track.id}] "${track.title}" — ${track.artist}';
  await nav.addChatMessage(msg);
  ServerActivityPanel.show(context); // abrir para que el usuario vea el mensaje
  ```
- En `ServerActivityPanel`, al renderizar mensajes de chat, detectar el patrón `[TRACK:{id}]`:
  - Renderizar como un tile especial con cover art, título, artista y botón "Reproducir" / "Ir a la canción".
  - Al tocar, navega al artista o reproduce la canción.

**Aceptación:**
- [ ] "Compartir con la comunidad" en los tres puntitos de canción envía el mensaje al chat.
- [ ] En el panel de comunidad, el mensaje de track se muestra con portada y botón de reproducción.
- [ ] Al tocar el link navega a la canción.

---

### Tarea 4.2 — Compartir artista al chat
**Archivos:** `lib/screens/artist_screen.dart`, `lib/widgets/server_activity_panel.dart`

**Qué hacer:**
- En el menú del artista (opción `community`), enviar:
  ```dart
  final msg = '🎤 [ARTIST:${widget.artist.id}] ${widget.artist.name}';
  await nav.addChatMessage(msg);
  ```
- En `ServerActivityPanel`, renderizar `[ARTIST:{id}]` como tile con foto del artista y botón "Ver artista".

**Aceptación:**
- [ ] Compartir artista envía el link al chat.
- [ ] El chat muestra el tile del artista navegable.

---

## Fase 5 — Refresco instantáneo

### Tarea 5.1 — Refrescar playlist detail al eliminar/añadir pistas
**Archivos:** `lib/screens/playlist_detail_screen.dart`, `lib/widgets/track_context_menu.dart`

**Qué hacer:**
- En `TrackContextMenu`, cuando se elimina una canción de la playlist (opción "Eliminar de esta playlist"), ya llama `nav.updatePlaylist`. Añadir `nav.bumpPlaylists()` después para propagar el cambio.
- En `PlaylistDetailScreen`, en `_addTracks` ya actualiza localmente. Verificar que también actualiza `_playlist` con el nuevo `songCount`.
- El `FutureBuilder` de la playlist no se reconstruye con `bumpPlaylists` porque no escucha `playlistVersion`. Añadir un `Consumer<NavidromeService>` que detecte cambios y relance `_future`.

**Aceptación:**
- [ ] Al añadir canciones, la lista se actualiza sin salir.
- [ ] Al eliminar una canción de la playlist desde el menú contextual, desaparece de la lista inmediatamente.

---

## Orden de implementación sugerido

```
1.2 → 1.3 → 1.1   (visuales simples primero)
2.1 → 2.2          (lógica de ordenación y duplicados)
3.1 → 3.2 → 3.3   (seguir artistas)
4.1 → 4.2          (compartir con comunidad)
5.1                (refresh)
```

---

## Puntos abiertos / decisiones

1. **Formato del link de canción en el chat**: ¿prefijo `[TRACK:id]` o URL custom scheme `scrotify://`? → Recomiendo `[TRACK:id:title:artist]` (sin URL externa, funciona offline).
2. **Artistas seguidos en biblioteca**: ¿mostrar todos los seguidos o solo los que tienen canciones en la biblioteca? → Todos los seguidos (el `id` viene de Navidrome).
3. **Excluir artista en reproducción aleatoria**: `PlayerController` debe filtrar artistas excluidos en `skipNext` / shuffle. Esto no está listado explícitamente pero es la única forma de "no reproducir este artista".
