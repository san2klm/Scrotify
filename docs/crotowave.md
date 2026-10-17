# CrotoWave — Manual Técnico de Arquitectura y Funcionamiento Integral

> **Documentación Maestra del Proyecto**  
> Aplicación: CrotoWave (`navidrome_client`)  
> Tipo: Cliente de música moderno, multiplataforma, self-hosted y local-first para Navidrome (API Subsonic v1.16.1)  
> Plataformas: Linux, Windows, macOS, Android e iOS  
> Versión del código base: 1.0.0+2002  
> Fecha de consolidación: 2026-10-06  

---

## 1. Visión General y Filosofía de Diseño

**CrotoWave** es un reproductor de música de alta fidelidad diseñado para conectarse a servidores personales de música basados en el estándar **Subsonic API v1.16.1**, con optimización de primer nivel para **Navidrome**.

```
┌────────────────────────────────────────────────────────────────────────┐
│                                CROTOWAVE                                │
│         (Cliente de Música Multiplataforma Local-First & Seguro)        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    ▼                               ▼                               ▼
┌────────────────────────┐  ┌────────────────────────┐  ┌────────────────────────┐
│  REPRODUCCIÓN & DSP    │  │   MODO SOCIAL (JAM)    │  │   ALMACENAMIENTO &     │
│ • Doble Player A/B     │  │ • Escucha sincro LAN   │  │   DESCARGAS OFFLINE    │
│ • Crossfade real       │  │ • Relay Cloud WSS      │  │ • SQLite local         │
│ • ReplayGain / EQs     │  │ • Altavoz de fiesta    │  │ • Descargas en segundo │
│ • Formas de onda reales│  │ • Pinning TLS con QR   │  │   plano por lotes      │
└────────────────────────┘  └────────────────────────┘  └────────────────────────┘
```

### Principios Arquitectónicos Fundamentales:
1. **Local-First & Privacidad Absoluta:**
   * Cero telemetría de terceros, rastreadores o analíticas invasivas.
   * Sin dependencias obligatorias de servicios de nube privativos (libre de Firebase / Google Play Services requeridos).
   * Almacenamiento seguro de credenciales en el llavero nativo del sistema operativo mediante [`SecureStorage`](lib/services/secure_storage.dart).
2. **Fidelidad y Streaming Directo:**
   * Reproducción bit-perfect directa desde el servidor Navidrome en formatos Lossless (FLAC) o Lossy de alta tasa (Opus, MP3 320k, AAC).
   * En funciones colaborativas (como CrotoLink), **nunca se retransmite audio P2P**: cada cliente reproduce el flujo desde su propio servidor, ahorrando ancho de banda y batería.
3. **Adaptabilidad Nativa Multiplataforma:**
   * **Desktop (Linux, Windows, macOS):** Ventana personalizada sin marcos nativos (*frameless*), atajos globales de teclado, decodificación acelerada con FFmpeg/mpv y panel lateral expandido.
   * **Móvil (Android, iOS):** Integración completa con el sistema de notificaciones de audio en segundo plano ([`audio_service`](lib/services/scrotify_audio_handler.dart)), widget nativo para la pantalla de inicio ([`home_widget`](lib/services/home_widget_service.dart)), bloqueo biométrico y gestos táctiles.

---

## 2. Pila Tecnológica y Dependencias Clave (`pubspec.yaml`)

El proyecto está construido sobre el ecosistema de **Flutter** (Dart 3.x) con dependencias seleccionadas por su robustez y rendimiento nativo:

| Paquete | Versión | Rol en CrotoWave |
| :--- | :--- | :--- |
| `just_audio` | `^0.9.44` | Motor de audio primario en Dart con soporte de pipelines avanzados. |
| `just_audio_media_kit` | `^2.1.0` | Backend nativo de audio para sistemas operativos de escritorio basado en `libmpv`. |
| `media_kit` | `^1.2.0` | Motor multimedia de bajo nivel para el modo Karaoke y cancelación vocal. |
| `audio_service` / `audio_session` | `^0.18.19` / `^0.1.25` | Gestión de ciclo de vida de audio en segundo plano y controles nativos en Android/iOS. |
| `home_widget` | `^0.10.0` | Integración con widgets en la pantalla de inicio de Android. |
| `sqflite` + `path` | `^2.4.4` / `^1.9.1` | Base de datos relacional local SQLite para descargas, caché y metadatos offline. |
| `flutter_secure_storage` | `^11.1.1` | Almacenamiento cifrado en Keychain (iOS/macOS), Keystore (Android) y Secret Service (Linux). |
| `cryptography` | `^2.9.0` | Primitivas criptográficas modernas (X25519, ChaCha20-Poly1305) para emparejamiento PC-móvil. |
| `basic_utils` + `crypto` | `^5.8.2` / `^3.0.3` | Generación de certificados X.509 RSA-2048 y hashing SHA-256 para CrotoLink LAN. |
| `window_manager` | `^0.5.2` | Manejo de ventana frameless y controles de minimizar/maximizar/cerrar en desktop. |
| `mobile_scanner` + `qr_flutter` | `^5.0.0` / `^4.1.0` | Escaneo y generación de códigos QR para CrotoLink y emparejamiento rápido. |
| `web_socket_channel` | `^2.4.0` | Comunicación bidireccional en tiempo real para sesiones CrotoLink (LAN y Cloud). |
| `provider` | `^6.1.1` | Inyección de dependencias y gestión de estado reactiva desacoplada. |
| `local_auth` | `^3.0.2` | Autenticación biométrica nativa (huella dactilar y reconocimiento facial). |

---

## 3. Estructura de Directorios del Código Fuente

```text
lib/
├── main.dart                      # Inicialización, arranque sin parpadeo y MultiProvider global
├── models/                        # Modelos de datos inmutables y contratos serializables
│   ├── album.dart                 # Modelo de álbum musical
│   ├── track.dart                 # Modelo de pista y metadatos
│   ├── server_profile.dart        # Configuración de perfiles de servidor
│   ├── jam_models.dart            # Modelos de estado, participantes y colas CrotoLink
│   └── pairing_models.dart        # Modelos para emparejamiento criptográfico
├── services/                      # Lógica de negocio, servicios de red y audio
│   ├── navidrome_service.dart     # Cliente de API Subsonic v1.16.1
│   ├── player_controller.dart     # Orquestador del reproductor de audio A/B
│   ├── scrotify_audio_handler.dart# Servicio de segundo plano y notificaciones OS
│   ├── audio_waveform_service.dart# Generador de formas de onda por análisis PCM real
│   ├── offline_download_manager.dart # Gestor de descargas concurrentes en background
│   ├── offline_cache_service.dart # Base de datos SQLite y caché en disco
│   ├── server_profiles_controller.dart # Gestor multicuenta de servidores
│   ├── jam_controller.dart        # Orquestador de sesiones CrotoLink
│   ├── jam_host_service.dart      # Servidor WebSocket y radar UDP local del Host
│   ├── jam_guest_service.dart     # Cliente WebSocket y radar del Invitado
│   ├── remote_jam_service.dart    # Cliente de conexión al servidor CrotoLink en la nube
│   ├── lyrics_service.dart        # Búsqueda de letras sincronizadas (Navidrome + LRCLIB)
│   ├── equalizer_service.dart     # Configuración y presets del ecualizador de 10 bandas
│   ├── listening_stats_service.dart # Métricas de escucha personalizadas (CrotoWave Wrapped)
│   ├── pairing_server.dart        # Servidor de emparejamiento con cifrado de clave pública
│   ├── pairing_client.dart        # Cliente móvil de emparejamiento por QR
│   ├── theme_controller.dart      # Gestor de temas bundleados y comunitarios .zip
│   ├── app_theme.dart             # Definición de paletas de color y Material ThemeData
│   └── secure_storage.dart        # Fachada estática de almacenamiento seguro
├── screens/                       # Pantallas y vistas completas
│   ├── login_screen.dart          # Login híbrido adaptativo
│   ├── home_shell.dart            # Contenedor de navegación desktop/móvil
│   ├── home_screen.dart           # Inicio en escritorio con cuadrículas de contenido
│   ├── mobile_home_screen.dart    # Inicio optimizado para pantallas táctiles
│   ├── player_screen.dart         # Reproductor expandido con forma de onda y controles
│   ├── karaoke_screen.dart        # Modo karaoke inmersivo con auto-scroll
│   ├── album_detail_screen.dart   # Vista detallada de álbum y lista de pistas
│   ├── artist_screen.dart         # Vista de artista, biografía y top de canciones
│   ├── playlist_detail_screen.dart# Gestión de listas de reproducción
│   ├── liked_songs_screen.dart    # Pantalla de canciones favoritas (con estrella)
│   ├── stats_screen.dart          # Panel visual de estadísticas de escucha
│   ├── server_profiles_screen.dart# Pantalla de gestión de servidores
│   ├── settings_screen.dart       # Ajustes de audio, temas, caché y atajos
│   └── equalizer_screen.dart      # Control interactivo de las 10 bandas del EQ
├── widgets/                       # Componentes visuales reutilizables
│   ├── waveform_progress_bar.dart # Barra de progreso con forma de onda real interactiva
│   ├── desktop_window_frame.dart  # Marco de ventana frameless con controles
│   ├── interactive_artist_text.dart # Texto con enlaces independientes a múltiples artistas
│   ├── jam_dialog.dart            # Diálogo y modal de gestión de sesiones CrotoLink
│   ├── jam_queue_panel.dart       # Panel de cola compartida con avatar del usuario
│   ├── persistent_player_bar.dart # Barra de reproducción inferior persistente
│   └── lyrics_overlay.dart        # Panel flotante de letras en seguimiento
└── utils/                         # Utilidades generales y helpers
    ├── app_colors.dart            # Extensiones de contexto para colores del tema
    ├── crypto_helper.dart         # Cifrado simétrico y derivación de claves
    └── responsive.dart            # Breakpoints para escritorio, tablet y móvil
```

---

## 4. Inicialización y Gestión de Estado Global (`lib/main.dart`)

El punto de entrada del sistema garantiza un arranque inmediato sin artefactos visuales:

### 4.1. Arranque sin Parpadeo de Tema (*Flash-Free Startup*)
Antes de ejecutar `runApp()`, CrotoWave invoca de forma asíncrona [`ThemeController.readInitial()`](lib/services/theme_controller.dart#L79-L89), leyendo la configuración del archivo local `themes.json`. Al renderizar el primer cuadro, el `ThemeData` ya posee la paleta exacta elegida por el usuario (evitando destellos blancos sobre temas oscuros).

### 4.2. Inyección de Dependencias mediante `MultiProvider`
El árbol de la aplicación registra los servicios en estricto orden de dependencia topológica:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => HomeNavigationController()),
    ChangeNotifierProvider(create: (_) => MiniPlayerController()),
    ChangeNotifierProvider(create: (_) => SettingsController()),
    ChangeNotifierProvider(create: (_) => ServerProfilesController()),
    ChangeNotifierProvider(create: (_) => EqualizerService()),
    ChangeNotifierProvider(create: (_) => ListeningStatsService()),
    ChangeNotifierProvider(create: (_) => ThemeController(initial: initialTheme)),
    Provider<PairingServer>(create: (_) => PairingServer(), dispose: (_, s) => s.stop()),
    ChangeNotifierProvider(create: (ctx) => NavidromeService(...)),
    Provider<OfflineCacheService>(create: (_) => OfflineCacheService(), dispose: (_, s) => s.close()),
    ChangeNotifierProvider(create: (ctx) => OfflineDownloadManager(...)..initialize()),
    ChangeNotifierProvider(create: (ctx) => PlayerController(...)),
    ChangeNotifierProvider(create: (ctx) => JamController(...)),
  ],
  child: MyApp(...),
)
```

---

## 5. Capa de Red y API Subsonic / Navidrome (`lib/services/navidrome_service.dart`)

[`NavidromeService`](lib/services/navidrome_service.dart) es la fachada central de comunicación HTTP contra el servidor.

### 5.1. Protocolo de Autenticación Criptográfica
Por motivos de seguridad, CrotoWave **no envía la contraseña en texto plano**. Implementa el esquema canónico de Subsonic:
1. Genera un valor aleatorio de sal (*salt*) de 16 caracteres alfanuméricos en minúsculas.
2. Calcula el token de autenticación:
   $$\text{token} = \text{MD5}(\text{password} + \text{salt})$$
3. Cada petición HTTP incluye los parámetros: `?u=usuario&t=token&s=salt&v=1.16.1&c=CrotoWave&f=json`.

### 5.2. Catálogo de Endpoints Implementados
* **Exploración de Biblioteca:**
  * `ping.view`: Verificación rápida de conectividad y estado del servidor.
  * `getArtists.view` / `getArtist.view`: Listado completo y perfil de artista.
  * `getAlbums.view` / `getAlbum.view`: Catálogo de álbumes y pistas correspondientes.
  * `getAlbumList2.view`: Álbumes recientes (`newest`), más escuchados (`frequent`), aleatorios (`random`) y favoritos (`starred`).
  * `getGenres.view` / `getSongsByGenre.view`: Clasificación por géneros musicales.
  * `search3.view`: Búsqueda instantánea unificada en pistas, artistas y álbumes.
* **Gestión de Playlists:**
  * `getPlaylists.view` / `getPlaylist.view`: Consulta y carga de listas de reproducción.
  * `createPlaylist.view`, `updatePlaylist.view`, `deletePlaylist.view`: Creación, edición de pistas y eliminación.
* **Interacciones del Usuario:**
  * `star.view` / `unstar.view`: Marcar o desmarcar canciones, álbumes y artistas con estrella (*favoritos*).
  * `setRating.view`: Calificación personalizada de 1 a 5 estrellas.
* **Scrobbling y Estado Actual:**
  * `scrobble.view`: Registra `nowPlaying` al comenzar una canción y emite un scrobble permanente cuando se ha reproducido al menos el 50% de su duración.
* **Streaming y Medios:**
  * `stream.view`: URL directa de flujo de audio optimizada según el perfil de calidad seleccionado.
  * `getCoverArt.view`: Recuperación de carátulas con soporte de tamaños dinámicos y caché local.
  * `getLyricsBySongId.view`: Letras incrustadas o escaneadas desde archivos `.lrc`.

---

## 6. Motor de Audio Avanzado (`lib/services/player_controller.dart`)

El reproductor de CrotoWave incorpora una arquitectura especializada para satisfacer exigencias audiófilas y operativas:

### 6.1. Doble Reproductor A/B para Crossfade Real y Gapless Playback
En lugar de depender de un único reproductor con pausas entre pistas, `PlayerController` mantiene dos instancias de `AudioPlayer`: `_a` y `_b`.

```
        TIEMPO --->
Reproductor Lead (_a): [==== CANCIÓN 1 ====] \ (Rampa de bajada de volumen)
Reproductor Fade (_b):             (Rampa de subida) / [==== CANCIÓN 2 ====]
                                   ▲
                                   └─ Cruce de volúmenes simultáneo (Crossfade)
```

1. **Reproductor Conductor (*Lead*):** Emite el audio audible y alimenta los flujos de progreso visualizados en la UI.
2. **Reproductor Secundario (*Fade*):** Pre-carga la siguiente canción en segundo plano. Al alcanzar el umbral de cruce (configurable de 1 a 12 segundos), el reproductor secundario arranca a volumen cero y ambos cruzan sus volúmenes de manera exponencial hasta que la pista anterior finaliza, rotando sus roles transparentemente (`_useA = !_useA`).
3. **Reproducción Continua (*Gapless*):** Si el crossfade está desactivado, el reproductor de reserva inicia en el instante exacto en que termina la canción anterior, eliminando cualquier milisegundo de silencio provocado por el búfer de red.

### 6.2. Normalización de Volumen con ReplayGain
Evita saltos abruptos de sonoridad entre pistas masterizadas a distintos volúmenes:
* Lee las etiquetas `trackGain`, `albumGain`, `trackPeak` y `albumPeak` devueltas por la API de Navidrome.
* **Modos Soportados:** Por pista (*Track Gain*), por álbum (*Album Gain*, preservando la dinámica intencional del disco) y Desactivado.
* **Prevención de Recorte (*Clipping Prevention*):** Calcula el factor de ganancia y reduce el volumen nominal si la suma de la ganancia y el pico excede los 0 dBFS, evitando la saturación digital.

### 6.3. Perfiles de Calidad de Audio Diferenciados
El usuario puede configurar límites de ancho de banda independientes en [`SettingsController`](lib/services/settings_controller.dart):
* **Modo Wi-Fi:** Transmisión sin pérdida (*Lossless* / formato original FLAC) por defecto.
* **Modo Red Móvil (Datos 4G/5G):** Transcodificación en servidor a 320 kbps, 256 kbps, 192 kbps o 128 kbps para ahorrar datos móviles.

### 6.4. Modo Karaoke y Cancelación Vocal
En plataformas de escritorio (Linux, Windows, macOS), CrotoWave aprovecha el backend [`media_kit`](lib/services/player_controller.dart#L113-L139) para aplicar un filtro DSP nativo de inversión de fase y ecualización paramétrica sobre el canal central, atenuando las frecuencias vocales de la música y permitiendo cantar sobre la pista instrumental en tiempo real.

---

## 7. Formas de Onda Reales por Análisis PCM (`lib/services/audio_waveform_service.dart`)

Una de las características visuales distintivas de CrotoWave es su barra de progreso basada en la **forma de onda acústica real** de la pista:

```
Archivo de Audio (FLAC/MP3/Opus)
  │
  ▼
Decodificación PCM (WAV puro en Dart / FFmpeg nativo en Desktop)
  │
  ▼
Extracción de muestras mono float de audio real
  │
  ▼
Cálculo de envolvente por ventana: Envelope = (0.75 * RMS) + (0.25 * Peak)
  │
  ▼
Normalización a ~2048 bins (1 bin cada 50 ms)
  │
  ▼
Persistencia en caché de disco (waveform_cache_v2)
  │
  ▼
CustomPainter reactivo en WaveformProgressBar (con seeking suave)
```

> **Garantía de Fidelidad:** El sistema **prohíbe estrictamente curvas sintéticas o aleatorias**. Si una pista no puede decodificarse o no hay conexión, se muestra una barra de progreso sobria en lugar de amplitudes inventadas.

---

## 8. Letras Sincronizadas y Modo Karaoke (`lib/services/lyrics_service.dart`)

[`LyricsService`](lib/services/lyrics_service.dart) implementa una jerarquía de búsqueda en cuatro fases para garantizar que las letras se muestren acompasadas a la música:

1. **Caché Local de Navidrome:** Consulta letras integradas en las etiquetas ID3/Vorbis o archivos `.lrc` presentes en la carpeta del álbum en el servidor.
2. **LRCLIB Exacto:** Si el servidor local solo tiene texto plano o carece de letras, realiza una consulta a la API pública de **LRCLIB** (`https://lrclib.net/api/get`) enviando título, artista, álbum y duración exacta de la pista.
3. **Búsqueda Difusa en LRCLIB:** Si la coincidencia exacta falla, consulta el motor de búsqueda difusa (`/api/search`).
4. **Fallback a Texto Plano:** Si no existen líneas temporizadas, presenta la letra en modo lectura estática.

### Experiencia Visual en [`KaraokeScreen`](lib/screens/karaoke_screen.dart):
* Fondo inmersivo con desenfoque gaussiano dinámico extraído de la carátula activa.
* Desplazamiento vertical fluido automático (*auto-scroll*) que mantiene la estrofa actual en el centro visual de la pantalla.
* Efecto tipográfico brillante y escala aumentada en la línea que se está reproduciendo en el segundo exacto.

---

## 9. Modo Offline y Gestor de Descargas (`lib/services/offline_download_manager.dart`)

CrotoWave permite almacenar canciones y álbumes completos localmente para reproducir en aviones, viajes o zonas sin cobertura:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        OFFLINE DOWNLOAD MANAGER                        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┴───────────────────────────────┐
    ▼                                                               ▼
┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
│     SQLite DB (offline_cache.db)    │   │      Almacenamiento en Disco        │
├─────────────────────────────────────┤   ├─────────────────────────────────────┤
│ • Tabla de pistas descargadas       │   │ • Archivos de audio cifrados/scoped │
│ • Metadatos de álbum y artista      │   │ • Portadas en alta resolución       │
│ • Estado de descarga por lotes      │   │ • Estructura aislada por servidor   │
│ • Aislamiento seguro (serverScope)  │   │   (previniendo colisiones de ID)    │
└─────────────────────────────────────┘   └─────────────────────────────────────┘
```

### Características del Sistema Offline:
* **Aislamiento por Servidor (*Server Scoping*):** Las pistas descargadas se agrupan bajo un identificador sanitizado del servidor origen (`serverScope`). Si el usuario cambia entre su servidor personal y el de un amigo, las canciones no se mezclan ni generan colisiones de IDs.
* **Descargas Concurrentes Resilientes:** Soporte para pausar, reanudar y reintentar descargas individuales o álbumes completos.
* **Sanitización de Errores:** Cualquier fallo de red o almacenamiento registrado en la base de datos es despojado previamente de URLs, tokens o credenciales para evitar fugas en logs de diagnóstico.

---

## 10. Gestión de Servidores y Perfiles Múltiples (`lib/services/server_profiles_controller.dart`)

Para usuarios que administran más de una biblioteca (servidor en el hogar, servidor en la nube, biblioteca de trabajo):
* Permite dar de alta múltiples instancias mediante [`ServerProfile`](lib/models/server_profile.dart).
* Cada perfil almacena su URL base, credenciales protegidas en `SecureStorage`, nombre amigable y estado de sesión.
* **Conmutación Instantánea:** El usuario puede alternar entre servidores desde el menú superior sin tener que cerrar sesión ni reingresar contraseñas manualmente.

---

## 11. Emparejamiento Rápido entre Dispositivos (`lib/services/pairing_server.dart`)

Configurar un cliente de música en un teléfono móvil escribiendo URLs largas y contraseñas complejas suele ser tedioso. CrotoWave resuelve esto con su sistema de **Emparejamiento por Código QR Criptográfico**:

```
[ PC / Servidor Desktop ]                             [ Teléfono Móvil ]
      │                                                       │
  1. Genera par de claves efímeras                            │
     X25519 (Diffie-Hellman)                                  │
      │                                                       │
  2. Muestra Código QR en pantalla ── Escanea QR ──────────► 3. Extrae clave pública
      │                                                       │  del PC y PIN
      │                                                       │
      │                                                    4. Genera su propio par
      │                                                       X25519 y calcula secreto
      │                                                       compartido
      │                                                       │
      │ ◄─── Envía clave pública del móvil por LAN o Relay ───┘
      │
  5. Calcula el mismo secreto compartido
  6. Cifra credenciales con ChaCha20-Poly1305
  7. Transmite payload cifrado ─────────────────────────────► 8. Descifra credenciales
                                                                 y se autentica de
                                                                 inmediato
```

* **Cero Configuración Externa:** Funciona automáticamente en la red local Wi-Fi vía UDP o mediante un canal de retransmisión temporal cifrado en `ntfy.sh`.
* **Seguridad:** El enlace dura un máximo de 5 minutos (TTL) y se bloquea tras 5 intentos fallidos de validación.

---

## 12. Métricas y Estadísticas de Escucha (`lib/services/listening_stats_service.dart`)

CrotoWave incorpora su propio motor de estadísticas de escucha privadas (*CrotoWave Wrapped* local):
* **Registro de Eventos Calificados:** Una reproducción solo cuenta como escucha legítima si supera el 50% de la pista o al menos 30 segundos continuos.
* **Métricas Disponibles en [`StatsScreen`](lib/screens/stats_screen.dart):**
  * Minutos totales de música reproducidos.
  * Ranking de pistas más escuchadas.
  * Artistas y álbumes predilectos.
  * Distribución porcentual por géneros musicales.
  * Historial temporal desglosado por semana, mes y año.

---

## 13. Ecualizador Paramétrico de 10 Bandas (`lib/services/equalizer_service.dart`)

[`EqualizerService`](lib/services/equalizer_service.dart) proporciona un control tonal para los oyentes:
* **Frecuencias Centrales:** 31 Hz, 62 Hz, 125 Hz, 250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz, 8 kHz y 16 kHz.
* **Rango Dinámico:** Ganancias ajustables entre **-12.0 dB y +12.0 dB**.
* **Presets de Fábrica:** *Flat*, *Bass Boost*, *Vocal*, *Treble Boost*.
* **Persistencia:** Guarda las curvas ecualizadas en disco y permite conmutar entre modo activo y bypass instantáneamente.

---

## 14. Sistema de Temas y Personalización Visual (`lib/services/app_theme.dart`)

El diseño de CrotoWave sigue estándares visuales modernos y adaptables:

### 14.1. Temas Fijos Integrados (*Built-in Themes*)
* **Catppuccin Mocha:** Tema oscuro cálido pastel (predeterminado).
* **Catppuccin Latte:** Tema claro suave diseñado para lectura diurna.
* **Kanagawa Wave:** Tonos azules y grisáceos inspirados en paletas orientales.
* **Stark HUD:** Estética cyberpunk de alto contraste con acentos cian neón sobre negro absoluto.
* **Vision Dark & Vision Navy:** Paletas doradas optimizadas para usuarios con daltonismo (*Color Vision Deficiency safe*).

### 14.2. Temas Comunitarios en Paquetes `.zip`
El usuario puede importar archivos `.zip` conteniendo un archivo de metadatos `manifest.json` y una hoja de estilos `theme.css`.  
Antes de activarse, [`theme_validation.dart`](lib/services/theme_validation.dart) analiza sintácticamente las variables CSS para prevenir fallos visuales o inyecciones de código.

### 14.3. Ventana Desktop Frameless (`lib/widgets/desktop_window_frame.dart`)
En Linux, Windows y macOS, la aplicación oculta la barra de título tradicional del sistema operativo y renderiza un marco integrado con la estética del tema activo, proveyendo botones propios de minimizar, maximizar y cerrar, junto con bordes elásticos invisibles para redimensionar la ventana.

---

## 15. CrotoLink — Sincronización Social en Tiempo Real

> *Para el desglose técnico exhaustivo de este subsistema, consulte el archivo canónico [**`JAM.md`**](JAM.md).*

CrotoLink permite que múltiples personas escuchen juntas o colaboren en una misma cola de reproducción:

```
┌────────────────────────────────────────────────────────────────────────┐
│                              CROTOWAVE JAM                              │
└───────────────────┬────────────────────────────────┬───────────────────┘
                    │                                │
                    ▼                                ▼
     ┌─────────────────────────────┐  ┌─────────────────────────────┐
     │      MODO DE OPERACIÓN      │  │      CANAL DE CONEXIÓN      │
     ├─────────────────────────────┤  ├─────────────────────────────┤
     │ • Altavoz de Fiesta         │  │ • LAN Directa P2P (WSS)     │
     │   (Música suena en el Host, │  │   con Pinning TLS en QR     │
     │   invitados son control/cola│  │ • Cloud Relay WebSocket     │
     │ • Escucha Sincronizada      │  │   (jam.templo.cloud:443)    │
     │   (Audio simultáneo en todos│  │ • Radar Multi-Vía           │
     │   con compensación de drift)│  │   (UDP + Navidrome + Cloud) │
     └─────────────────────────────┘  └─────────────────────────────┘
```

* **Sin Retransmisión de Audio P2P:** Solo se intercambian metadatos, orden de cola y posiciones temporales.
* **Compensación de Latencia:** Ajuste automático del retardo de tránsito en red ($\Delta T_{\text{transit}}$) con un umbral de corrección de deriva (*drift*) de 450 ms para evitar microcortes.
* **Seguridad Estricta:** Certificados TLS efímeros RSA-2048 con huella SHA-256 fijada por código QR, tokens de reconexión de 128 bits y sanitización obligatoria de credenciales Subsonic mediante [`sanitizeArtUrl`](lib/models/jam_models.dart#L9-L18).

---

## 16. Componentes Clave de Interfaz de Usuario

* **[`InteractiveArtistText`](lib/widgets/interactive_artist_text.dart):**  
  Analiza cadenas de texto compuestas en el campo de artista (ej. *"Queen, David Bowie feat. Annie Lennox"*), separa los nombres de forma inteligente y renderiza cada artista como un enlace interactivo independiente que navega directamente a la ficha de ese artista.
* **[`WaveformProgressBar`](lib/widgets/waveform_progress_bar.dart):**  
  Pinta las barras de amplitud PCM reales en dos colores (zona reproducida con color de acento y zona pendiente atenuada). Admite arrastre para adelantar o retroceder en la canción con precisión milimétrica.
* **[`PersistentPlayerBar`](lib/widgets/persistent_player_bar.dart):**  
  Barra de control que flota permanentemente en la parte inferior de la ventana en escritorio, con controles de transporte, carátula, título, artista interactivo, barra de progreso y control deslizante de volumen.
* **[`HomeShell`](lib/screens/home_shell.dart):**  
  Orquestador responsivo que conmuta entre diseño de escritorio (con barra lateral retráctil) y diseño móvil (con barra de navegación inferior de tres pestañas: Explorar, Buscar y Biblioteca).

---

## 17. Guía de Ejecución, Pruebas y Comandos Útiles

### 17.1. Análisis Estático de Código
Para validar la integridad del código Dart:
```bash
flutter analyze
```
*(Criterio de aceptación: 0 errores, 0 advertencias).*

### 17.2. Suite de Pruebas Automatizadas
Para ejecutar las pruebas unitarias y de integración de widgets:
```bash
flutter test
```

Para ejecutar pruebas específicas de subsistemas (ej. CrotoLink):
```bash
flutter test test/jam_test.dart test/jam_ui_recovery_test.dart
```

### 17.3. Servidor CrotoLink en Node.js
Para ejecutar la suite de pruebas del servidor WebSocket central:
```bash
cd jam-server
npm install
node --test test/server.test.js
```

### 17.4. Compilación y Ejecución en Desarrollo
* **En Linux Desktop:**
  ```bash
  flutter run -d linux
  ```
* **En Dispositivo/Emulador Android:**
  ```bash
  flutter run -d android
  ```

---

## 18. Matriz Resumen de Subsistemas de CrotoWave

| Subsistema | Componente Principal | Protocolo / Tecnología | Persistencia / Almacenamiento |
| :--- | :--- | :--- | :--- |
| **API de Música** | [`NavidromeService`](lib/services/navidrome_service.dart) | Subsonic API v1.16.1 (HTTP REST + MD5 Auth) | Memoria / Caché HTTP |
| **Reproductor** | [`PlayerController`](lib/services/player_controller.dart) | Doble `AudioPlayer` A/B (`just_audio` + `media_kit`) | Memoria / `ListeningStatsService` |
| **Formas de Onda** | [`AudioWaveformService`](lib/services/audio_waveform_service.dart) | Decodificación PCM real (FFmpeg / WAV) | Disco (`waveform_cache_v2/`) |
| **Letras** | [`LyricsService`](lib/services/lyrics_service.dart) | Subsonic Lyrics + LRCLIB REST API | Memoria / Caché por `trackId` |
| **Audio en Background** | [`ScrotifyAudioHandler`](lib/services/scrotify_audio_handler.dart) | Android MediaSession / iOS AudioSession | Notificación del Sistema Operativo |
| **Widget Móvil** | [`HomeWidgetService`](lib/services/home_widget_service.dart) | Android AppWidget Provider | SharedPreferences de Android |
| **Descargas Offline** | [`OfflineDownloadManager`](lib/services/offline_download_manager.dart) | HTTP Streaming por bloques concurrentes | SQLite (`offline_cache.db`) + Disco |
| **Gestión de Cuentas** | [`ServerProfilesController`](lib/services/server_profiles_controller.dart) | Perfiles multicuenta serializables | [`SecureStorage`](lib/services/secure_storage.dart) (Keystore/Keychain) |
| **Emparejamiento** | [`PairingServer`](lib/services/pairing_server.dart) | X25519 Diffie-Hellman + ChaCha20-Poly1305 | Sesiones efímeras con TTL de 5 min |
| **CrotoLink** | [`JamController`](lib/services/jam_controller.dart) | WebSockets (WSS) + UDP Radar (LAN y Cloud) | Estado efímero en RAM |
| **Temas y Estilos** | [`ThemeController`](lib/services/theme_controller.dart) | Paletas CSS variables y paquetes `.zip` | `themes.json` (preload sin flash) |
| **Estadísticas** | [`ListeningStatsService`](lib/services/listening_stats_service.dart) | Eventos de escucha calificados (>50%) | `listening_events.json` |
