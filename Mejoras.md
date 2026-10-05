# SCROTIFY — AUDITORÍA + EVOLUCIÓN INTEGRAL

Actuá como **Tech Lead principal del proyecto Scrotify**.

Tu trabajo no es solamente proponer cambios: tenés que **auditar el estado real del repositorio, diseñar la integración correcta, implementar las mejoras, probarlas y documentarlas**, respetando la arquitectura y funcionalidad existente.

Si necesitás delegar trabajo a un agente externo, utilizá exclusivamente el workflow actualmente soportado con `agy`. **No agregues ninguna dependencia de Codex CLI**.

---

# 0. OBJETIVO GENERAL

Convertir Scrotify en un cliente Navidrome/Jam robusto, moderno, multiplataforma y orientado a self-hosting, mejorando especialmente:

- reproducción de audio;
- estabilidad;
- Jam;
- reproducción offline;
- integración con Android/iOS/desktop;
- experiencia de usuario;
- gestión de servidores;
- arquitectura interna;
- seguridad;
- testing;
- mantenibilidad.

El resultado debe sentirse como una aplicación musical completa y nativa, no como una colección de features aisladas.

---

# 1. REGLAS DE TRABAJO

## 1.1 Auditar antes de modificar

ANTES de implementar cualquier feature:

1. inspeccioná el código existente;
2. buscá implementaciones parciales o completas;
3. buscá tests existentes;
4. identificá arquitectura, servicios y modelos involucrados;
5. identificá posibles duplicaciones;
6. determiná dependencias entre features;
7. verificá qué plataformas soporta actualmente cada componente.

No reimplementes una feature que ya exista.

Si algo existe parcialmente:

- reutilizalo;
- refactorizalo;
- completalo;
- agregá tests.

No crees un segundo sistema paralelo.

---

# 2. RESTRICCIONES IMPORTANTES

No:

- inventes resultados de tests;
- marques algo como PASS sin haberlo ejecutado;
- agregues mocks al runtime productivo;
- simules datos que deberían ser reales;
- agregues TODO como sustituto de una implementación;
- agregues features visuales sin backend real;
- escondas fallos silenciosamente;
- hagas refactors masivos no relacionados;
- cambies arquitectura estable sin justificación;
- rompas compatibilidad actual de Navidrome;
- debilites seguridad para hacer funcionar una feature;
- introduzcas dependencias cloud obligatorias;
- dependas de Firebase para funciones centrales;
- hagas downgrade de WSS a WS en Jam;
- desactives certificate pinning;
- guardes secretos en texto plano.

Scrotify debe mantener una filosofía principalmente:

**self-hosted + local-first + privacy-friendly.**

---

# 3. ESTADO EXISTENTE QUE DEBE PRESERVARSE

## Jam

La implementación existente de Jam incluye conceptos como:

- LAN;
- WebSocket;
- descubrimiento;
- Navidrome;
- modo cloud;
- Party Speaker;
- Synchronized Listening;
- permisos de guests;
- QR/PIN;
- cola colaborativa.

La versión segura actual de Jam debe conservar:

- WSS;
- TLS;
- pinning;
- fingerprint distribuido mediante QR;
- rechazo de conexiones legacy inseguras;
- ausencia de downgrade automático a WS.

No sacrifiques estas garantías para implementar reconexión u otras mejoras.

---

# 4. WAVEFORM

Scrotify ya posee trabajo realizado alrededor de:

- `WaveformService`;
- `WaveformProgressBar`;
- `PlayerController`;
- integración visual de waveform.

NO desarrolles otro sistema paralelo.

Auditá el existente y evolucioná solamente lo necesario para:

- extracción real;
- cache;
- drag-to-seek;
- desktop hover;
- haptic feedback;
- sincronización con player.

Nunca presentes un visualizador falso como waveform real.

---

# 5. FASE 1 — ROBUSTEZ DE JAM

Esta fase tiene prioridad máxima.

---

## 5.1 PIN criptográficamente seguro

Auditar `JamCode.generate()`.

Eliminar cualquier PRNG basado en:

- timestamp;
- `Random(seed)`;
- seeds predecibles.

Usar una fuente criptográficamente segura como:

`Random.secure()`

Agregar tests de generación.

---

## 5.2 Reconexión automática

Implementar reconexión automática para guests cuando se pierda el WebSocket.

Backoff sugerido:

- 1 s;
- 2 s;
- 4 s;
- 8 s;
- 16 s;
- máximo 30 s.

Agregar jitter si corresponde.

La UI debe indicar claramente estados:

- Connected;
- Reconnecting;
- Disconnected;
- Failed.

Una reconexión debe intentar recuperar:

- identidad;
- permisos;
- sesión;
- posición;
- track actual;
- cola;
- estado playback.

Evitar crear participantes duplicados.

---

## 5.3 Reconexión del host/cloud

Aplicar estrategia equivalente cuando el host pierda conexión contra infraestructura remota.

No bloquear Jam LAN porque el cloud esté caído.

---

## 5.4 Heartbeat ping/pong

Implementar heartbeat Host ↔ Guest.

Ejemplo:

- ping cada ~15 s;
- timeout aproximado ~10 s.

Si un guest deja de responder:

- cerrarlo;
- eliminarlo de participantes activos;
- limpiar recursos;
- emitir evento de desconexión.

Evitar usuarios zombie.

---

## 5.5 Race condition de synchronized playback

Auditar `_syncGuestAudioIfApplicable`.

Actualmente pueden superponerse:

- `playQueue`;
- seek;
- playback updates;
- cambio de track.

Implementar protección mediante:

- token generacional;
- operación serializada;
- cancellation;
- mutex lógico;
- mecanismo equivalente.

Nunca aplicar una posición vieja sobre un track nuevo.

---

## 5.6 Memory leak `_trackAddedBy`

No usar instancia de `Track` como key si no hay igualdad estable garantizada.

Migrar a:

`track.id`

o identificador estable equivalente.

Limpiar correctamente cuando corresponda.

Agregar test de regresión.

---

## 5.7 Rate limiting

Agregar rate limiting por participante.

Aplicarlo a:

- add_to_queue;
- remove_from_queue;
- reorder;
- playback_control;
- seek;
- chat;
- votos.

Evitar spam y abuso.

No aplicar un límite que vuelva molesta la UX normal.

---

## 5.8 Reducir ruido UDP

Revisar presencia/discovery.

No transmitir innecesariamente una presencia por segundo durante toda la sesión.

Usar estrategia aproximada:

- ráfaga rápida durante inicio;
- luego presencia cada 5-10 s.

No comprometer velocidad de descubrimiento.

---

# 6. FASE 2 — PLAYER Y AUDIO

---

## 6.1 Background playback

Implementar correctamente reproducción en background.

Debe continuar al:

- apagar pantalla;
- cambiar aplicación;
- bloquear dispositivo.

Integrarse con lifecycle de Android/iOS.

---

# 6.2 Media Session / controles del sistema

Integración nativa con controles multimedia del sistema.

Debe exponer como mínimo:

- play;
- pause;
- previous;
- next;
- seek;
- artwork;
- track;
- artist;
- album;
- duración;
- posición.

---

# 6.3 Lock screen

Mostrar correctamente Now Playing en:

### Android

- media notification;
- lock screen controls;
- MediaSession.

### iOS

- MPNowPlayingInfoCenter;
- Remote Command Center.

---

# 6.4 Audio Focus

Implementar manejo correcto de audio focus.

Ejemplos:

- llamada;
- otra aplicación reproduciendo;
- navegación GPS;
- alarma.

Soportar pause/duck/resume según corresponda.

---

# 6.5 ReplayGain

Agregar soporte REAL de ReplayGain.

Detectar cuando estén disponibles metadatos como:

- ReplayGain Track Gain;
- ReplayGain Track Peak;
- ReplayGain Album Gain;
- ReplayGain Album Peak.

Crear opción configurable:

ReplayGain:

- Off;
- Track;
- Album.

Agregar configurable:

- preamp;
- prevención de clipping si es viable.

No modificar permanentemente el archivo de audio.

Aplicar ganancia durante playback.

Preservar volumen elegido por usuario.

Evitar clipping audible.

Si el backend/plataforma no permite aplicar ReplayGain correctamente, documentar claramente la limitación y no fingir soporte.

---

# 6.6 Crossfade

Agregar crossfade configurable:

- Off;
- 2 s;
- 5 s;
- 8 s;
- custom si la arquitectura lo permite.

Debe manejar correctamente:

- skip manual;
- stop;
- seek;
- cambio de cola;
- tracks cortos;
- streaming.

---

# 6.7 Sleep Timer

Crear servicio central de Sleep Timer.

Opciones:

- 15 min;
- 30 min;
- 45 min;
- 60 min;
- duración personalizada;
- al terminar la canción.

Agregar fade-out antes de detener audio.

Mostrar estado en Player.

Agregar acción rápida:

**Sleep**

que utilice una duración predeterminada configurable.

En Android, agregar notificación persistente mientras esté activo y permitir cancelarlo desde allí si es viable.

---

# 6.8 Tiempo transcurrido / restante

El tiempo del player debe poder alternar al tocarlo:

`1:42`

↔

`-2:35`

Persistencia opcional de preferencia.

---

# 6.9 Shuffle y Repeat

Soportar claramente:

Shuffle:

- on/off.

Repeat:

- off;
- all;
- one.

Indicadores inequívocos.

---

# 6.10 Smart Shuffle

Agregar modo opcional de shuffle inteligente.

Evitar repetir el mismo artista durante los últimos N tracks.

N configurable.

No reemplazar shuffle tradicional: debe ser otra opción.

---

# 6.11 Skip Silence

Agregar opción avanzada de detección de silencio en:

- inicio;
- final.

Usar RMS/umbral u otra implementación técnicamente válida.

OFF por defecto.

No cortar audio musical real agresivamente.

---

# 7. ANDROID AUTO + APPLE CARPLAY

Implementar soporte cuando sea técnicamente compatible con la arquitectura actual.

---

## Android Auto

Integrar Scrotify con Android Auto mediante las APIs multimedia oficiales compatibles con Flutter/plataforma.

Mostrar como mínimo:

- Recently Played;
- albums;
- artists;
- playlists;
- favorites;
- queue cuando corresponda.

Playback:

- play;
- pause;
- next;
- previous.

La UI debe respetar las restricciones de seguridad de Android Auto.

No implementar una UI custom peligrosa mientras el vehículo está en movimiento.

---

## Apple CarPlay

Investigar primero los requisitos técnicos y entitlement correspondiente.

Si el proyecto puede soportarlo legítimamente:

- integrar navegación musical;
- biblioteca;
- playlists;
- albums;
- artists;
- Now Playing;
- controles multimedia.

Si Apple requiere entitlement/aprobación que no puede resolverse únicamente desde código:

documentarlo explícitamente.

No marcar CarPlay como COMPLETED si falta autorización externa.

---

# 8. FASE 3 — SISTEMA OFFLINE

---

# 8.1 OfflineCacheService

Crear/refactorizar un servicio responsable del almacenamiento offline.

Separar:

### metadata

SQLite o DB existente.

### audio/artwork

filesystem.

Relacionar cache con:

- serverId;
- trackId;
- versión/hash;
- calidad.

---

# 8.2 Download Manager

Implementar cola de descargas.

Debe soportar:

- progreso;
- retry;
- pause;
- resume;
- cancel;
- concurrencia limitada;
- persistencia entre reinicios.

---

# 8.3 Download All

Agregar acciones para:

- álbum completo;
- playlist completa.

Mostrar:

- cantidad;
- tamaño estimado cuando sea posible;
- progreso global;
- progreso individual.

---

# 8.4 Integridad

Verificar downloads mediante:

- tamaño;
- checksum cuando sea posible;
- respuesta HTTP;
- metadata.

Nunca marcar un archivo incompleto como descargado.

---

# 8.5 Cleanup

Agregar sistema que limpie:

- archivos huérfanos;
- metadata inexistente;
- temporales;
- descargas fallidas.

---

# 8.6 Límite de caché

Configurable:

- sin límite;
- tamaño máximo.

Agregar política de limpieza segura.

No borrar explícitamente contenido marcado por usuario como descarga permanente sin autorización.

---

# 8.7 Ubicación de almacenamiento

Desktop:

permitir elegir ubicación.

Android:

investigar SAF/external storage correctamente.

No pedir permisos más amplios de los necesarios.

---

# 8.8 Connectivity listener

Detectar cambios de red.

Estados:

- online;
- offline;
- metered cuando esté disponible.

Cuando se pierda red:

- continuar con cache;
- no romper player;
- poner acciones sincronizables en cola cuando tenga sentido.

---

# 8.9 Cache warm-up

Opcionalmente prefetch:

- siguiente canción;
- quizás segunda siguiente.

No descargar media biblioteca silenciosamente.

Respetar:

- límite de cache;
- Wi-Fi/metered;
- configuración del usuario.

---

# 9. FASE 4 — JAM 2.0

---

# 9.1 Cola persistente

Persistir Jam queue de manera segura.

Al reiniciar aplicación, intentar restaurar el contexto cuando corresponda.

Nunca revivir automáticamente una sesión expirada sin validarla.

---

# 9.2 Drag & Drop

En Jam Queue:

mostrar handle de reordenamiento.

Ejemplo:

`≡ Canción`

Permitir arrastrar para modificar posición.

Verificar permisos ANTES de aplicar.

Sin permisos:

- no mostrar affordance activo;
- o mostrarlo deshabilitado.

Sincronizar inmediatamente mediante Jam WebSocket.

Resolver conflictos concurrentes correctamente.

---

# 9.3 Swipe para eliminar

En móvil:

swipe hacia izquierda sobre una canción.

Mostrar acción:

**Eliminar**

Opcionalmente usar confirmación solo cuando realmente haga falta.

Respetar permisos.

No permitir eliminar mediante gesto si el usuario no tiene permisos de edición.

Desktop debe tener alternativa equivalente mediante:

- menú contextual;
- botón contextual;
- teclado si corresponde.

---

# 9.4 Detector de pistas duplicadas

Implementar `Duplicate Track Detector`.

Al agregar una canción que ya existe en:

- queue;
- Jam queue;

detectar por identificador estable, preferentemente:

`serverId + trackId`

Mostrar aviso no intrusivo.

Opciones posibles:

- agregar igualmente;
- cancelar.

No bloquear duplicados automáticamente porque puede ser intencional.

Para operaciones masivas, evitar generar 50 dialogs.

Usar resumen.

Ejemplo:

`3 canciones ya estaban en la cola.`

---

# 9.5 Votación

Agregar votos en Jam Queue.

Cada participante puede votar pistas.

Mostrar contador:

`▲ 5`

Implementar dos estrategias:

### Manual

los votos son informativos.

### Orden por votos

la cola se ordena respetando reglas definidas.

Evitar votos duplicados del mismo participantId.

Sincronizar en tiempo real.

---

# 9.6 Chat Jam

Agregar chat en tiempo real mediante el canal Jam.

No depender de Navidrome chat para el canal interno de una Jam.

Modelo aproximado:

- participantId;
- displayName;
- message;
- timestamp.

Rate limit obligatorio.

Mantener historial solamente durante la sesión salvo que luego exista una opción explícita para conservarlo.

---

# 9.7 Eventos del sistema

El chat/event feed puede representar eventos:

- usuario conectado;
- usuario desconectado;
- usuario agregó canción;
- usuario eliminó canción;
- host cambió permisos.

Diferenciar mensajes humanos de eventos del sistema.

---

# 9.8 Feedback al conectarse

Host debe recibir feedback visual discreto:

`Agus se unió a la Jam`

Guest:

`Conectado a la Jam de Thiago`

---

# 9.9 Permisos individuales

Actualmente pueden existir permisos globales.

Agregar control granular por participante:

- controlar playback;
- agregar canciones;
- borrar canciones;
- reordenar cola;
- votar;
- chat si corresponde.

Host conserva autoridad final.

---

# 9.10 Indicador Listening Along

En player / mini-player:

`🎵 Escuchando con 4 personas`

Al tocar:

abrir Jam.

---

# 9.11 Historial Jam

Al finalizar una sesión, opcionalmente almacenar localmente:

- fecha;
- duración;
- participantes;
- tracks reproducidos.

No guardar mensajes privados del chat indefinidamente por defecto.

---

# 9.12 Iniciar Jam desde playlist

Permitir:

`Playlist → Start Jam`

La playlist seleccionada debe convertirse en cola inicial.

Revisar si `initialPlaylistId` u otra infraestructura ya existe antes de crear nuevos campos.

---

# 10. FASE 5 — EXPERIENCIA DE BIBLIOTECA

---

# 10.1 Recently Played

Persistir historial local y/o usar Navidrome cuando corresponda.

Mostrar acceso rápido.

---

# 10.2 Recently Added

Sección Home.

Ventana por defecto:

últimos 7 días.

Permitir refresh.

Usar cache si está offline.

---

# 10.3 Géneros

Agregar:

- listado;
- búsqueda;
- autocomplete;
- filtro.

Permitir navegar:

Genre → Albums / Artists / Tracks.

---

# 10.4 Ratings

Integrar ratings de Navidrome/Subsonic.

UI:

- listas;
- player;
- context menu.

Usar 1-5 estrellas cuando el backend realmente lo soporte.

---

# 10.5 Like/Love

Agregar acción rápida compatible con backend.

Actualizar UI optimísticamente, pero revertir correctamente si servidor falla.

---

# 10.6 Lyrics

Crear `LyricsService`.

Soportar:

- lyrics sin timestamps;
- lyrics sincronizadas cuando existan.

UI:

scrolling overlay / pantalla dedicada.

Sincronizar según tiempo solamente cuando los timestamps sean válidos.

---

# 10.7 Go to Artist / Go to Album

Desde:

- player;
- track menu;
- search;
- queue.

---

# 10.8 Radio

Agregar:

**Play Radio**

basada en:

- artista;
- género;
- random songs de Navidrome;
- funciones compatibles.

Agregar también:

**Queue from Radio**

para anexar canciones sin reemplazar cola existente.

---

# 10.9 Smart Playlists

Generación mediante reglas:

- género;
- año;
- rating;
- artista;
- fecha agregada.

Separar reglas de UI.

---

# 10.10 Explicit content

Si Navidrome/API provee flag confiable:

agregar filtro:

- mostrar;
- ocultar.

Si el backend no entrega ese dato, no inventarlo.

---

# 11. FASE 6 — MÚLTIPLES SERVIDORES

Refactorizar `NavidromeService` para múltiples perfiles.

Cada perfil debe soportar:

- serverId estable;
- nombre;
- URL;
- usuario;
- secreto almacenado de forma segura;
- opciones TLS;
- cache independiente;
- preferencias;
- Wake-on-LAN;
- estado;
- última conexión.

Ejemplo:

Casa  
192.168.1.20  
Online

Tailscale  
hostname.ts.net  
Online

Servidor backup  
Offline

No mezclar cache entre servidores aunque coincida `trackId`.

Clave conceptual:

`serverId + trackId`

---

# 11.1 Secure Storage

Credenciales en:

- Android Keystore;
- iOS Keychain;
- almacenamiento seguro equivalente en desktop.

No usar SharedPreferences para passwords.

Si existe almacenamiento anterior inseguro:

crear migración controlada.

Eliminar secreto viejo luego de migración exitosa.

---

# 11.2 Wake-on-LAN

Agregar configuración opcional por servidor:

- MAC;
- broadcast;
- puerto.

Botón:

**Encender servidor**

Después del magic packet:

intentar reconectar con backoff razonable.

No asumir que recibir magic packet significa que Navidrome ya arrancó.

---

# 12. DESKTOP

---

# 12.1 Media keys

Soportar teclas físicas:

- Play/Pause;
- Next;
- Previous;
- Stop si corresponde.

---

# 12.2 Hotkeys

Permitir shortcuts globales/locales según soporte de SO.

Configurable más adelante si la infraestructura lo permite.

---

# 12.3 System Tray

Windows/Linux/macOS cuando sea viable.

Mostrar:

- track actual;
- play/pause;
- next;
- previous;
- abrir Scrotify;
- salir.

---

# 12.4 NOTIFICACIONES NATIVAS DEL SISTEMA

NO implementar notificaciones HTML5.

La notificación de cambio de canción debe integrarse NATIVAMENTE con cada SO.

### Windows

usar Windows Notifications/Toast mediante integración nativa adecuada.

### Linux

usar el sistema estándar del escritorio:

- D-Bus / freedesktop notifications;
- equivalente mediante plugin realmente nativo.

Además integrar MPRIS cuando sea apropiado para media controls.

### macOS

usar UserNotifications / integración del sistema.

La notificación puede mostrar:

- artwork;
- canción;
- artista;
- álbum.

No mostrar una notificación en cada cambio si el usuario las desactiva.

Agregar setting:

`Notificaciones de cambio de canción`

ON/OFF.

---

# 13. MINI PLAYER

Mantener un mini-player persistente en interfaces donde tenga sentido.

Debe mostrar:

- artwork;
- track;
- artist;
- play/pause;
- previous;
- next;
- progreso;
- estado Jam si está activa.

---

# 14. WAVEFORM INTERACTIVA

Sobre la infraestructura existente:

agregar drag-to-seek.

Mobile:

- arrastre;
- haptic feedback discreto.

Desktop:

- hover;
- tooltip con timestamp;
- click/drag.

El seek debe ser preciso y no generar requests absurdamente frecuentes.

Aplicar throttle/debounce cuando corresponda.

---

# 15. PLAYLISTS

Agregar progresivamente:

- drag & drop;
- swipe-to-remove en móvil;
- batch operations;
- folders;
- import/export.

Formatos de import/export cuando sean viables:

- M3U;
- PLS;
- JSON.

---

# 16. BACKUP / EXPORT

Permitir exportar configuración a JSON.

Incluir donde tenga sentido:

- settings;
- server profiles SIN secretos en texto plano;
- playlists locales;
- ratings/config relacionados;
- preferencias.

Nunca exportar passwords/tokens sin mecanismo explícito y seguro.

Implementar import con:

- validación de schema;
- versión;
- migraciones.

---

# 17. SHARE / DEEP LINKS

Agregar deep links hacia:

- track;
- album;
- artist;
- playlist.

Acción Share:

- deep link;
- o texto cuando no pueda generar URL accesible.

No asumir que una URL LAN será útil para otra persona.

---

# 18. DATA USAGE

Agregar contador por sesión:

- bytes downloaded;
- bytes uploaded cuando pueda medirse correctamente.

Configurable:

`Evitar sync/download en conexión medida`

No inventar estadísticas si no puede observarse el tráfico real.

---

# 19. TEMAS / RESPONSIVE / ACCESIBILIDAD

Verificar:

- Dark theme;
- Light theme;
- persistencia;
- layouts mobile/tablet/desktop.

Agregar semántica/accessibility en controles:

- botones;
- sliders;
- waveform;
- Jam;
- listas.

---

# 20. INTERNACIONALIZACIÓN

Preparar i18n correctamente con ARB.

Como mínimo:

- español;
- inglés.

No dejar textos hardcodeados nuevos si ya existe sistema de localization.

---

# 21. ERROR HANDLING

Centralizar errores.

Network:

- retry;
- exponential backoff;
- mensajes comprensibles.

UI:

Snackbar/inline status según contexto.

No inundar al usuario con stack traces.

Logs técnicos quedan en logs.

---

# 22. ARQUITECTURA

Auditar arquitectura antes de imponer Riverpod/get_it/etc.

Objetivo:

UI no debe depender directamente de detalles HTTP de Navidrome.

Separación recomendada:

Presentation  
↓  
Controllers / State  
↓  
Domain / Repositories  
↓  
Services / APIs  
↓  
Storage / Network

Si ya existe una arquitectura equivalente y sana:

mantenerla.

No migrar toda la aplicación simplemente por preferencia personal.

---

# 23. DEPENDENCY INJECTION

Eliminar construcciones rígidas innecesarias de servicios dentro de widgets.

Permitir:

- testing;
- mocks;
- múltiples server profiles;
- aislamiento.

Usar la estrategia DI ya existente si es correcta.

---

# 24. TESTING

Agregar tests para todo cambio relevante.

Prioridad especial:

- NavidromeService;
- repository;
- OfflineCacheService;
- download manager;
- PlayerController;
- ReplayGain;
- Sleep Timer;
- JamController;
- reconnection;
- heartbeat;
- permissions;
- rate limit;
- Jam voting;
- Duplicate Detector;
- gestures donde sean testeables;
- cache;
- server profiles.

---

# 24.1 Regresiones Jam obligatorias

Tests mínimos:

### PIN

PIN usa CSPRNG.

### reconnect

guest se desconecta y vuelve.

### duplicate reconnect

reconectar no crea usuario doble.

### heartbeat

guest muerto es eliminado.

### permission

guest sin permiso no puede reorder/remove/control.

### rate limit

spam es rechazado/throttled.

### track attribution

no leak por instancias Track.

### concurrent sync

actualizaciones antiguas no pisan track nuevo.

---

# 24.2 Offline

Probar:

- descarga;
- pause;
- resume;
- retry;
- archivo incompleto;
- cleanup;
- eviction;
- offline playback.

---

# 24.3 ReplayGain

Probar:

- off;
- track;
- album;
- ausencia de tags;
- peak;
- preamp;
- transición entre tracks.

---

# 25. CI

Configurar/verificar GitHub Actions:

- `dart format --set-exit-if-changed`;
- `flutter analyze`;
- `flutter test`.

Si existen builds viables:

- Android;
- Linux;
- Windows.

No romper el pipeline por intentar compilar targets que el runner no soporta sin setup específico.

---

# 26. COVERAGE

Medir cobertura.

Objetivo orientativo para lógica crítica:

≥80%.

No escribir tests inútiles únicamente para aumentar porcentaje.

Priorizar comportamiento y regresiones.

---

# 27. PERFORMANCE

Revisar particularmente:

- listas largas;
- waveform;
- Jam queue;
- artwork;
- cache;
- state rebuilds;
- DB;
- networking.

Evitar rebuilds globales del player cada pocos milisegundos.

---

# 28. COSAS QUE NO SON PRIORIDAD

No priorizar ahora salvo que resulten triviales:

- Firebase Remote Config;
- push notifications cloud genéricas;
- daemon Linux headless;
- crowdsourcing de traducciones;
- set as ringtone;
- easter eggs.

No eliminar infraestructura existente si ya existe; simplemente no sacrificar features importantes por esto.

---

# 29. ORDEN DE IMPLEMENTACIÓN

Seguir preferentemente:

## FASE A — Jam Hardening

1. Secure PIN.
2. Memory leak.
3. Race condition.
4. Reconnect.
5. Heartbeat.
6. Rate limiting.
7. UDP tuning.

## FASE B — Player Core

1. Background playback.
2. Media Session.
3. Lock screen.
4. Audio focus.
5. ReplayGain.
6. Crossfade.
7. Sleep Timer.
8. Repeat/shuffle.
9. time remaining.

## FASE C — Offline

1. cache architecture.
2. Download Manager.
3. Download All.
4. integrity.
5. cleanup.
6. storage limits.
7. connectivity.
8. prefetch.

## FASE D — Jam UX 2.0

1. Drag & Drop.
2. Swipe remove.
3. Duplicate detector.
4. Votes.
5. Chat.
6. participant events.
7. individual permissions.
8. Listening Along.
9. playlist → Jam.
10. history.

## FASE E — Platform integration

1. Android Auto.
2. CarPlay feasibility/integration.
3. desktop media keys.
4. system tray.
5. native OS song notifications.

## FASE F — Library

1. Recently Played.
2. Recently Added.
3. genres.
4. ratings.
5. love.
6. lyrics.
7. radio.
8. smart playlists.

## FASE G — Power User

1. multi-server.
2. Wake-on-LAN.
3. backups.
4. deep links.
5. configurable cache storage.
6. data usage.

## FASE H — Quality

1. architecture cleanup.
2. tests.
3. coverage.
4. CI.
5. documentation.
6. profiling.

---

# 30. COMMITS

Trabajar con commits pequeños y lógicos.

Ejemplo:

`fix(jam): use secure random for join codes`

`fix(jam): prevent stale playback sync`

`feat(jam): add websocket reconnection`

`feat(player): add replaygain support`

`feat(offline): add persistent download queue`

No mezclar 30 cambios distintos en un único commit gigante.

No hacer push remoto salvo que el workflow existente lo autorice explícitamente.

---

# 31. DOCUMENTACIÓN

Actualizar según corresponda:

- README;
- ARCHITECTURE.md;
- documentación Jam;
- protocolo Jam;
- settings;
- platform setup;
- Android Auto;
- CarPlay requirements;
- offline storage;
- migrations.

No documentar features que todavía no funcionan.

---

# 32. MIGRACIONES

Toda modificación persistente debe ser migrable.

Ejemplos:

- DB;
- secure storage;
- server profiles;
- cache metadata;
- Jam state.

Nunca borrar datos del usuario porque cambió el schema.

---

# 33. COMPATIBILIDAD

Verificar como mínimo los targets realmente soportados por el repositorio.

Especial atención a:

- Android;
- Linux;
- Windows.

Y cuando exista infraestructura:

- iOS;
- macOS.

Una feature exclusiva de plataforma debe degradar elegantemente.

Ejemplo:

CarPlay no debe impedir compilar Linux.

---

# 34. CONFIGURACIÓN DE FEATURES

Crear settings solamente donde tengan sentido.

Ejemplos:

### Audio

ReplayGain  
Crossfade  
Smart Shuffle  
Skip Silence  

### Playback

Sleep Timer default  
Repeat  
Shuffle  

### Downloads

Cache max size  
Prefetch  
Metered connections  

### Desktop

Native notifications  
System tray  
Hotkeys  

### Jam

Vote ordering  
Join notifications  

Evitar una pantalla de configuración con 200 switches innecesarios.

---

# 35. UX

Mantener diseño consistente con Scrotify actual.

No rehacer toda la UI.

Principios:

- acciones frecuentes visibles;
- acciones raras en menú contextual;
- feedback inmediato;
- errores comprensibles;
- mobile gestures;
- keyboard/mouse equivalentes en desktop.

---

# 36. DEFINITION OF DONE

Una feature solo es COMPLETED cuando:

1. existe implementación real;
2. compila;
3. está integrada a UI cuando corresponde;
4. tiene persistencia cuando corresponde;
5. tiene tests relevantes;
6. tests pasan;
7. analyze no introduce errores;
8. no rompe features anteriores;
9. funciona en plataformas declaradas;
10. documentación está actualizada.

Si falta una parte crítica:

estado `PARTIAL`.

Si no pudo implementarse:

estado `BLOCKED`.

Nunca usar `COMPLETED` solamente porque el código fue escrito.

---

# 37. VALIDACIÓN FINAL

Al finalizar ejecutar, según disponibilidad real:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Luego compilar los targets que el entorno permita realmente.

Ejemplos:

```bash
flutter build apk
flutter build linux
flutter build windows
```

No reportar un build como PASS si no fue ejecutado.

---

# 38. INFORME FINAL OBLIGATORIO

Responder exactamente con una estructura equivalente a:

# INFORME FINAL — SCROTIFY EVOLUTION

## ESTADO

COMPLETED / PARTIAL / BLOCKED

## BRANCH

...

## COMMIT BASE

...

## COMMIT FINAL

...

## AUDITORÍA INICIAL

- qué ya existía;
- qué estaba parcial;
- qué estaba ausente;
- duplicaciones evitadas.

## CAMBIOS IMPLEMENTADOS

Agrupados por fase.

## JAM

- secure PIN:
- reconnect:
- heartbeat:
- rate limiting:
- sync race:
- permissions:
- drag/drop:
- swipe:
- duplicate detector:
- votes:
- chat:

## PLAYER

- background:
- media session:
- ReplayGain:
- crossfade:
- Sleep Timer:
- audio focus:

## OFFLINE

- cache:
- download manager:
- retry:
- integrity:
- cleanup:
- prefetch:

## PLATFORM

- Android Auto:
- Apple CarPlay:
- Android lockscreen:
- iOS Now Playing:
- Windows native integration:
- Linux MPRIS:
- native desktop notifications:

## LIBRARY

- Recently Played:
- Recently Added:
- ratings:
- lyrics:
- smart playlists:
- radio:

## MULTI-SERVER

- profiles:
- credential storage:
- cache isolation:
- Wake-on-LAN:

## TESTS

Indicar comandos REALES ejecutados.

Ejemplo:

flutter test: X PASS / Y FAIL

flutter analyze:
...

## BUILDS

Android:
PASS / FAIL / NOT_RUN

Linux:
PASS / FAIL / NOT_RUN

Windows:
PASS / FAIL / NOT_RUN

iOS:
PASS / FAIL / NOT_RUN

macOS:
PASS / FAIL / NOT_RUN

## REGRESIONES

...

## ARCHIVOS MODIFICADOS

...

## MIGRACIONES

...

## DOCUMENTACIÓN

...

## RIESGOS / LIMITACIONES

Especialmente:

- CarPlay entitlement;
- diferencias de audio por plataforma;
- ReplayGain;
- Android Auto;
- desktop integrations.

## PENDIENTES

Solamente pendientes reales.

---

# 39. INSTRUCCIÓN FINAL

Primero realizá la auditoría.

Después implementá.

No te quedes únicamente en recomendaciones o un plan.

No me preguntes por decisiones menores que puedas resolver inspeccionando el repositorio.

Tomá decisiones técnicas conservadoras y compatibles con la arquitectura existente.

Cuando existan varias opciones razonables, elegí la que:

1. introduzca menos deuda técnica;
2. preserve compatibilidad;
3. sea más testeable;
4. reduzca dependencias externas;
5. respete el enfoque self-hosted;
6. mantenga la seguridad actual.

Ante un bloqueo verdaderamente externo —por ejemplo un entitlement de Apple— completá todo lo técnicamente posible, documentá exactamente el bloqueo y marcá solamente esa parte como `BLOCKED` o `PARTIAL`.

El objetivo no es llenar Scrotify de features.

El objetivo es que cada feature agregada quede **bien integrada, estable, segura, testeada y mantenible**.
