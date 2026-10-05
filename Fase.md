# SCROTIFY — PROMPT MAESTRO DE IMPLEMENTACIÓN Y ROADMAP

Quiero continuar y completar el desarrollo de Scrotify.

Este documento es la especificación consolidada del proyecto para las siguientes
fases de desarrollo.

IMPORTANTE:

Antes de modificar absolutamente nada:

1. Leer el repositorio completo y entender la arquitectura existente.
2. Revisar:
   - PlayerController
   - NavidromeService
   - OfflineCacheService
   - modelos Track / Album / Artist
   - reproductor de audio
   - home
   - mobile home
   - login móvil
   - sistema de themes
   - navegación
   - SharedPreferences / almacenamiento
   - base de datos local
   - servicios existentes
   - tests existentes
   - integración con Jam
3. Ejecutar baseline:
   - flutter analyze
   - flutter test
   - dart format --output=none --set-exit-if-changed .
4. Registrar el estado inicial.
5. NO asumir que una API, método, plugin o endpoint existe sin comprobarlo.
6. NO inventar APIs.
7. NO reescribir arquitectura funcional si puede extenderse de forma limpia.
8. NO introducir regresiones.
9. Mantener compatibilidad con las plataformas actualmente soportadas por el
   proyecto.
10. Implementar una fase por vez y validarla antes de continuar.

Si algo del documento entra en conflicto con la implementación real del
repositorio, investigar primero y adaptar la solución preservando el objetivo
funcional.

Nunca implementar ciegamente pseudocódigo de este documento.

---

# ESTADO BASE A RESPETAR

Hay funcionalidades que ya pueden existir o haber sido implementadas.

Antes de volver a programarlas, comprobar el código actual.

En especial:

- autenticación biométrica móvil;
- InteractiveArtistText;
- navegación hacia artistas;
- uso de InteractiveArtistText en Home;
- uso en Home móvil;
- resultados de búsqueda;
- recientes;
- álbumes;
- recomendados.

Si ya están correctamente implementadas:

NO duplicarlas.

Verificarlas mediante código y tests y continuar.

---

# REGLAS GENERALES DE DESARROLLO

Trabajar preferentemente siguiendo TDD:

1. test que falla;
2. implementación mínima correcta;
3. test pasa;
4. refactor;
5. flutter analyze;
6. flutter test.

Siempre que una fase introduzca persistencia:

- definir formato;
- migración si corresponde;
- versionado;
- invalidación;
- manejo de datos antiguos.

Siempre que una fase involucre red:

- loading;
- timeout;
- error;
- pérdida de conexión;
- reconexión;
- caché cuando corresponda.

Siempre que una fase involucre UI:

- desktop;
- móvil;
- tema claro;
- tema oscuro;
- distintos tamaños;
- accesibilidad;
- estados vacíos;
- estados de error.

Siempre que una fase involucre audio:

- playback;
- pause;
- resume;
- seek;
- cambio rápido de canción;
- canciones largas;
- conexión lenta;
- offline;
- reproducción desde caché;
- no bloquear el hilo de UI.

No introducir procesamiento costoso en el main isolate si puede afectar la
reproducción.

---

# FASE 1 — CACHÉ DE PISTAS / MODO OFFLINE
## Ítem 6

## Objetivo

Permitir escuchar contenido incluso cuando el servidor Navidrome no esté
disponible o el dispositivo pierda conexión.

La experiencia esperada es:

online
→ reproducir
→ guardar/cachar cuando corresponda
→ perder conexión
→ seguir teniendo acceso al contenido cacheado.

---

## Arquitectura

Revisar primero si ya existe:

OfflineCacheService

Si existe, extenderlo.

No crear un segundo sistema paralelo.

La integración principal será con:

- OfflineCacheService
- PlayerController
- NavidromeService
- almacenamiento local
- metadata de Track

Puede utilizarse SQLite / sqflite para metadata.

Los archivos de audio deben almacenarse mediante el sistema de archivos,
no como blobs gigantes dentro de SQLite salvo que la arquitectura existente
ya lo haga y exista una buena razón.

---

## Datos recomendados

Como mínimo:

trackId
serverId
localPath
title
artist
album
duration
size
downloadedAt
lastAccessedAt
sourceUrl/version
cacheVersion

Adaptar los campos al modelo real.

---

## Playback

PlayerController debería resolver aproximadamente:

Track
↓
¿archivo offline válido?
↓ sí
reproducir localmente

↓ no
¿Navidrome disponible?
↓ sí
stream remoto

↓ no
mostrar error/offline unavailable

No romper streaming normal.

---

## Manejo del caché

Debe existir una política clara:

- tamaño máximo;
- limpieza;
- invalidación;
- archivos huérfanos;
- metadata sin archivo;
- archivo sin metadata.

Evitar crecimiento ilimitado.

---

## UX

El usuario debe poder distinguir:

- pista online;
- pista descargada/cacheada;
- pista disponible offline;
- descarga en progreso;
- descarga fallida.

Si el proyecto tiene Settings, considerar una sección:

Ajustes → Offline / Caché

con:

- tamaño usado;
- limpiar caché;
- política de almacenamiento;
- posiblemente límite configurable.

---

## Tests

### Unitarios

- cache hit;
- cache miss;
- archivo eliminado;
- metadata corrupta;
- servidor caído;
- invalidación.

### Integración

1. reproducir canción online;
2. verificar archivo disponible localmente;
3. desconectar Navidrome;
4. reproducir nuevamente;
5. confirmar que funciona desde caché.

---

# FASE 2 — AUTENTICACIÓN BIOMÉTRICA MÓVIL

## Estado esperado

Esta funcionalidad puede estar ya implementada con:

local_auth

y MobileLoginScreen.

NO volver a programarla si ya existe correctamente.

---

## Objetivo

Cuando el usuario ya tenga credenciales configuradas y el dispositivo tenga
biometría disponible:

abrir app
→ solicitar huella/rostro
→ validar
→ ingresar sin volver a escribir credenciales.

---

## Verificaciones

Comprobar:

- Android;
- lifecycle;
- volver desde background;
- biometría no disponible;
- biometría temporalmente bloqueada;
- usuario cancela;
- fallback a login normal;
- credenciales inexistentes;
- error del sistema biométrico.

Nunca impedir permanentemente el acceso por un fallo biométrico.

---

## Tests

- biometría disponible;
- biometría no disponible;
- cancelación;
- autenticación correcta;
- autenticación fallida;
- fallback manual.

Si ya está todo correcto:

marcar:

VERIFIED

y continuar.

---

# FASE 3 — MÚLTIPLES SERVIDORES Y PERFILES NAVIDROME
## Ítem 3

## Objetivo

Poder tener, por ejemplo:

Servidor local:
http://192.168.1.20:4533

Servidor remoto:
https://music.example.com

y cambiar entre ambos sin reconfigurar completamente la aplicación.

---

## UI

Settings
→ Perfiles / Servidores

Debe permitir:

- agregar;
- editar;
- eliminar;
- seleccionar;
- probar conexión.

Cada perfil debe almacenar como mínimo:

id
name
baseUrl
username / auth reference
createdAt
lastUsedAt

Las credenciales reales deben integrarse posteriormente con la Fase 4.

---

## Arquitectura

Eliminar dependencias innecesarias de un NavidromeService global estático si
eso impide múltiples perfiles.

Preferir la arquitectura que ya utilice el proyecto.

Por ejemplo:

Provider / Riverpod / servicio inyectado

solo si encaja con el código existente.

NO introducir un framework de estado nuevo solamente por esta función si no
es necesario.

---

## Cambio de perfil

Al cambiar servidor:

- detener solicitudes anteriores;
- actualizar sesión;
- actualizar biblioteca;
- limpiar estados temporales;
- evitar mostrar resultados del servidor anterior;
- mantener cachés separados por serverId.

---

## Ejemplo

Perfil:

Casa
192.168.1.50

Perfil:

Remoto
music.midominio.com

Usuario selecciona "Remoto".

Todo:

Home
Search
Albums
Artists
Player
Ratings
Genres

debe consultar el servidor seleccionado.

---

## Tests

- crear perfil;
- editar;
- eliminar;
- seleccionar;
- persistencia;
- dos servidores con IDs de pistas iguales;
- cambio rápido entre perfiles.

---

# FASE 4 — CIFRADO DE CREDENCIALES
## Ítem 4

## Objetivo

No almacenar credenciales sensibles en SharedPreferences en texto plano.

---

## Requisito

Utilizar almacenamiento seguro adecuado para cada plataforma.

La propuesta original menciona:

AES-256
libsodium
clave maestra

pero NO implementar criptografía casera si existe una solución segura ya
soportada por el proyecto/plataforma.

Auditar primero.

---

## Debe protegerse

- password;
- token;
- API key;
- secret;
- cualquier credencial de Navidrome.

Los datos no sensibles como nombre del perfil o URL pueden permanecer en
almacenamiento normal si corresponde.

---

## Migración

Si actualmente hay credenciales en SharedPreferences:

versión vieja
→ detectar
→ migrar a almacenamiento seguro
→ verificar escritura
→ eliminar valor antiguo

No destruir credenciales antes de confirmar la migración.

---

## Tests

- save;
- read;
- update;
- delete;
- migración;
- error de almacenamiento;
- profile switch.

---

# FASE 5 — SLEEP TIMER + FADE OUT
## Ítem 9

## Objetivo

Permitir detener reproducción automáticamente después de un tiempo.

Ejemplos:

15 min
30 min
45 min
1 hora
fin de canción

---

## UX

Desde el reproductor:

Sleep Timer

Opciones:

15 min
30 min
45 min
60 min
Fin de la canción
Personalizado
Cancelar timer

Mostrar el tiempo restante.

---

## Fade Out

Antes de detener:

volumen actual
↓
reducción progresiva
↓
0
↓
pause/stop

No bajar el volumen global del sistema si solamente debe afectar a Scrotify.

Después de finalizar:

restaurar volumen interno correctamente para la próxima reproducción.

---

## Casos especiales

- usuario pausa;
- usuario cambia canción;
- app background;
- pantalla bloqueada;
- timer cancelado;
- timer reemplazado;
- app cerrada;
- nueva sesión.

---

## Tests

- timer normal;
- cancelación;
- reemplazo;
- fade;
- restauración de volumen;
- end-of-track.

---

# FASE 6 — WAVEFORM / SPECTRUM COMO BARRA DE PROGRESO
## Ítem 10

# REQUISITO CRÍTICO

Esta sección reemplaza cualquier interpretación anterior de:

"barras saltando al ritmo"

como objetivo principal.

NO quiero un ecualizador decorativo separado de la barra.

NO quiero un FFT genérico que simplemente se anime.

EL SPECTRUM / WAVEFORM DEBE SER LA BARRA DE PROGRESO DEL REPRODUCTOR.

Y debe representar EL AUDIO COMPLETO DE LA CANCIÓN.

---

# CONCEPTO

Referencia visual:

          ▂▃▄▆▇▅▃▂▃▄▆████▇▅▃▂
        ▃█████████████████████▃
────────────── progreso ──────────────
        ▃█████████████████████▃
          ▂▃▄▆▇▅▃▂▃▄▆████▇▅▃▂

Visualmente:

- muchas barras verticales finas;
- centradas;
- simétricas hacia arriba y abajo;
- separaciones pequeñas;
- minimalista;
- adaptada al tema.

---

# ES LA BARRA DE PROGRESO

NO:

waveform
+
slider tradicional separado.

Quiero:

WAVEFORM = PROGRESS BAR

Ejemplo:

0:00                                            4:32
▂▃▅██▇▄▂▃▅████▇▃▂▂▄▇███▅▃▂▃▆████▅▂
██████████████░░░░░░░░░░░░░░░░░░░░░
              ↑
          posición actual

La parte ya escuchada:

activeColor

La parte pendiente:

inactiveColor

La forma geométrica es EXACTAMENTE la misma.

Solamente cambia:

- color;
- opacidad;
- estilo.

---

# TODA LA CANCIÓN

El ancho completo debe representar:

0:00 → duración total.

Ejemplo:

canción 4:00
waveform visible completa

0:00                                    4:00
│------------------------------------------│
▁▁▂▃▄▆██▇▅▄▃▂▄▆████▇▄▂▃▆██▅▄▃▂

NO mostrar únicamente los últimos milisegundos.

NO desplazar una ventana FFT horizontal como sustituto.

---

# LA FORMA DEBE SALIR DEL AUDIO REAL

NO usar:

- Random();
- ruido;
- barras proceduralmente generadas;
- ondas sinusoidales de mentira;
- patrón reutilizado;
- alturas inventadas según posición;
- una waveform fija para todas las pistas.

Cada canción debe producir una forma diferente.

---

# EJEMPLOS

## Balada

▁▁▂▂▃▄▅▆▅▄▃▃▄▅▆██▇▅▄▃▂▁

## Metal / EDM

▆██████▇████████████▇████▆

## Acústico dinámico

▂▄▃▅▂▆▄▇▃▅▂█▄▆▃▂▄

## Silencio al inicio y final

▁▁▁▂▃▆████████▇▅▃▂▁▁▁

Esto es intencional.

La waveform debe adaptarse al sonido real del tema.

---

# WAVEFORM VS FFT

No confundir conceptos.

FFT tradicional:

eje X = frecuencia

bass → mids → treble

Waveform requerida aquí:

eje X = tiempo

0:00 → final de canción

El componente principal requerido es por lo tanto una:

WAVEFORM TEMPORAL

aunque dentro del proyecto podamos llamarla:

SpectrumProgressBar

o similar.

---

# EXTRACCIÓN DEL AUDIO

Auditar primero la capa de audio existente.

La implementación conceptual es:

archivo/stream
↓
PCM o información equivalente
↓
dividir duración en ventanas
↓
calcular amplitud representativa
↓
normalizar
↓
guardar N valores
↓
dibujar waveform

---

# CÁLCULO

Por ventana temporal puede utilizarse:

RMS
peak
envelope
RMS + peak

Ejemplo conceptual:

amplitude =
    rms * 0.7 +
    peak * 0.3

Los valores 0.7/0.3 son solamente ejemplo.

Elegir el método que produzca una representación:

- fiel;
- estable;
- visualmente útil.

---

# ESTÉREO

No necesito:

L waveform
R waveform

separadas.

Combinar los canales.

Preferiblemente evitar:

(L + R) / 2

si existe riesgo de cancelación.

Puede utilizarse una medida como:

sqrt((L² + R²) / 2)

cuando sea apropiado.

---

# NORMALIZACIÓN

Guardar valores aproximadamente:

0.0 → 1.0

Ejemplo:

[
  0.08,
  0.12,
  0.21,
  0.44,
  0.83,
  0.71,
  0.38
]

No dejar que un único pico extremo aplaste visualmente al resto del tema.

Considerar:

- normalización robusta;
- percentiles;
- compresión logarítmica suave.

Mantener un mínimo visible.

---

# RESOLUCIÓN

No guardar un valor por sample PCM.

Crear una representación reducida.

Por ejemplo:

512
1024
2048

bins por canción.

Elegir según rendimiento.

Después:

waveform fuente
↓
downsampling
↓
cantidad necesaria para la pantalla.

---

# EJEMPLO RESPONSIVE

Desktop:

1000 px
→ aproximadamente 300 barras

Móvil:

360 px
→ aproximadamente 100-130 barras

NO volver a analizar la canción porque cambió el tamaño de ventana.

---

# DIBUJO

Una opción adecuada en Flutter puede ser:

CustomPainter

pero reutilizar infraestructura existente si ya existe.

Cada barra:

centerY - height/2
centerY + height/2

para obtener la forma simétrica.

---

# PROGRESS CLIPPING

Implementación visual recomendable:

1. dibujar toda la waveform con inactiveColor;
2. calcular progressX;
3. hacer clipRect(0 → progressX);
4. dibujar la misma waveform con activeColor.

Así:

████████░░░░░░░░░░░░

sin alterar la geometría.

---

# SEEK

La waveform también es un control interactivo.

Debe permitir:

- tap;
- click;
- drag;
- scrub.

Cálculo:

percent = localX / width

seek =
duration * percent

Ejemplo:

duración = 240 segundos
tap = 75 %

240 × 0.75 = 180 segundos

seek → 3:00

Clamp:

0 <= seek <= duration

---

# SCRUB

Mientras se arrastra:

actualizar la representación visual inmediatamente.

El seek real puede:

- actualizar continuamente con throttle;

o

- ejecutarse al soltar;

dependiendo de qué opción funcione mejor con el backend actual.

No ejecutar cientos de seeks innecesarios si genera problemas.

---

# TIEMPOS

Mantener:

posición actual
duración total

Ejemplo:

1:42                                  4:17
▂▄▆██▇▅▃▂▃▇████▇▅▃▂▄▇██▆▄▂

La waveform reemplaza la barra gráfica.

No necesariamente reemplaza los textos.

---

# CACHE DE WAVEFORM

NO analizar cada canción cada vez que se reproduce.

Crear caché.

Clave ideal:

serverId
trackId
fileVersion / modified / size

Ejemplo conceptual:

WaveformData {
  trackId
  serverId
  duration
  samples
  version
}

Puede almacenarse en:

SQLite
archivo binario
JSON

según la arquitectura existente.

No introducir SQLite adicional si ya existe una DB apropiada.

---

# INVALIDACIÓN

Regenerar si:

- cambia archivo;
- cambia duración;
- cambia versión;
- cambia algoritmo;
- caché corrupta.

Agregar algo equivalente a:

waveformFormatVersion

---

# OFFLINE

Si existe archivo offline:

preferir analizarlo localmente.

Si existe waveform cacheada:

mostrarla offline.

No necesitar Navidrome solamente para dibujar una waveform ya calculada.

---

# STREAMING

Si la pista aún no está local:

NO bloquear reproducción esperando análisis.

Flujo:

play
↓
audio empieza
↓
placeholder waveform
↓
análisis asíncrono
↓
waveform aparece

---

# PLACEHOLDER

Mientras se genera:

────────────────────────────

o un skeleton coherente con el diseño.

NO generar una waveform falsa.

---

# RACE CONDITION

Ejemplo:

Track A
→ análisis empieza

usuario cambia a Track B

Track B empieza

termina análisis de A

NO mostrar A.

Antes de aplicar resultados:

waveform.trackId == currentTrack.id

y serverId si corresponde.

---

# PERFORMANCE

No bloquear:

- playback;
- main isolate;
- scroll;
- animaciones.

Evaluar:

- isolate;
- worker;
- proceso externo;
- backend nativo;
- procesamiento chunked.

Depende de la arquitectura existente.

---

# ACTUALIZACIONES DE UI

No reconstruir toda PlayerScreen 30-60 veces por segundo.

Utilizar el mecanismo de estado más localizado disponible.

Por ejemplo:

ValueListenable
StreamBuilder localizado
AnimatedBuilder
CustomPainter + repaint
RepaintBoundary

según la arquitectura real.

---

# THEMES

NO hardcodear el color de la captura de referencia.

Usar:

Theme.of(context)

o el sistema existente.

Ejemplo conceptual:

played:
colorScheme.primary

pending:
onSurface con menor opacity

La FORMA cambia por canción.

El COLOR cambia por tema.

Son cosas distintas.

---

# MOBILE

La barra puede medir visualmente ~40 px, pero el hitbox debe ser suficientemente
grande.

Objetivo:

mínimo táctil razonable, aproximadamente 48 px cuando el layout lo permita.

---

# DESKTOP

Permitir:

- click;
- drag;
- hover si encaja;
- cursor apropiado.

Opcional:

tooltip con tiempo.

Ejemplo:

mouse al 62 %
→ 2:37

---

# PLAYHEAD

No colocar obligatoriamente un círculo gigante como Slider.

Si hace falta:

playhead fino

▂▄▆██▇▃▂▅██│██▅▃
             │

pero la diferencia active/inactive ya debería ser suficiente.

---

# TESTS DE WAVEFORM

## Normalización

Todos los valores:

0 <= x <= 1

---

## Diferencia entre canciones

Audio A:

tono constante

Audio B:

silencio + tono fuerte + silencio

Las waveforms DEBEN ser distintas.

Ejemplo:

A:
▄▄▄▄▄▄▄▄▄▄

B:
▁▁▁████▁▁▁

---

## Seek

width = 1000
tapX = 750
duration = 240 sec

resultado:

180 sec

---

## Clamp

tapX < 0
→ 0

tapX > width
→ duration

---

## Cache

Primera reproducción:

analysisCount = 1

Segunda:

cache hit
analysisCount = 1

Archivo modificado:

analysisCount = 2

---

## Cambio rápido

A → B

A termina tarde.

current waveform debe seguir siendo:

B

---

# CRITERIOS DE ACEPTACIÓN DE FASE 6

PASS solamente si:

- waveform = barra de progreso;
- representa canción completa;
- forma viene del audio real;
- pistas diferentes generan formas distintas;
- progreso activo/inactivo funciona;
- tap seek funciona;
- drag funciona;
- mobile funciona;
- desktop funciona;
- themes funcionan;
- cache funciona;
- offline contemplado;
- no bloquea playback;
- no utiliza random;
- no utiliza una forma fija;
- no rompe PlayerController;
- no rompe Jam.

---

# FASE 7 — MEZCLA INTELIGENTE + ELIMINACIÓN DE SILENCIOS
## Ítems 12 y 17

## Parte A — Mezcla inteligente

## Objetivo

Evitar repetir artistas demasiado seguido.

Ejemplo:

NO:

Taylor Swift
Taylor Swift
Taylor Swift

Preferir:

Taylor Swift
Daft Punk
Paramore
Taylor Swift

cuando la cola tenga suficientes alternativas.

---

## Algoritmo inicial

Mantener historial corto en PlayerController.

Ejemplo:

M = 2

No seleccionar artista si apareció en los últimos dos slots salvo que no exista
otra alternativa razonable.

No romper orden manual del usuario.

Esta lógica debe aplicarse solamente en modos automáticos/inteligentes donde
corresponda.

---

# Parte B — Detección y eliminación de silencios

## Objetivo

Opcionalmente eliminar silencio al inicio y final para reproducción continua.

Config:

skipSilences = false

por defecto.

---

## Detección

Analizar audio relevante.

La especificación original utiliza:

RMS < aproximadamente -40 dBFS

durante cierto tiempo.

Ese valor debe poder ajustarse internamente según resultados.

---

## Inicio

Si existe silencio:

seek hasta primera sección útil.

Ejemplo:

0:00 - 0:02 silencio
0:02 música

reproducción efectiva:

~0:02

---

## Final

Si el tramo final es silencio:

avanzar a siguiente canción cuando comience el silencio detectado de forma
segura.

No cortar reverbs o finales musicales suaves incorrectamente.

---

## Settings

Ajustes → Reproducción

Eliminar silencios

toggle.

Persistir configuración.

---

## Tests

### SilenceDetectorTest

Audio:

2 segundos silencio
5 segundos música
2 segundos silencio

verificar inicio/fin.

### PlayerControllerTest

cuando hay silencio inicial:

seek llamado.

### Widget

toggle persistido.

### Integración

usar archivo de prueba con silencio evidente y comprobar comportamiento real.

---

# FASE 8 — RATING 1-5 ESTRELLAS
## Ítem 13

## Objetivo

Permitir puntuar pistas:

★
★★
★★★
★★★★
★★★★★

además del Like/Favorite existente.

---

## Navidrome

Auditar qué operaciones de rating soporta realmente el servidor/Subsonic API.

Integrar mediante NavidromeService.

NO inventar:

getRating

si la API real utiliza otro endpoint.

Verificar primero.

---

## UI

Desde:

- track;
- menú contextual;
- player;
- posiblemente listas.

Permitir:

1 → 5
quitar rating

---

## Ordenación

Cuando corresponda:

ordenar por rating descendente.

Ejemplo:

★★★★★
★★★★★
★★★★
★★★
★

---

## Tests

- set rating;
- update;
- remove;
- persistencia servidor;
- render estrellas;
- sorting.

---

# FASE 9 — RECIENTEMENTE AGREGADOS + BÚSQUEDA POR GÉNERO
## Ítems 14 y 16

# Parte A — Recientemente agregados

## Objetivo

Mostrar contenido incorporado recientemente.

Ventana inicial:

7 días

---

## NavidromeService

Crear algo equivalente a:

getRecentlyAdded(Duration since)

La propuesta original utiliza:

getMusicFolder
modifiedSince

pero verificar primero la API real soportada por el servidor.

El objetivo funcional importa más que conservar un endpoint incorrecto.

---

## RecentlyAddedSection

Crear sección similar a:

_recommendedGrid

Mostrar:

- portada;
- título;
- artista.

El artista debe mantener InteractiveArtistText si esa infraestructura ya existe.

---

## Home

Insertar aproximadamente:

Quick Access
↓
Recently Added
↓
Recommended

adaptando al layout real.

---

## Refresh

Permitir:

manual:
botón reload

automático:
aproximadamente cada 1 hora

Evitar timers filtrados/leaks.

Cancelar correctamente en dispose.

---

## Offline

Si no hay conexión:

mostrar mensaje apropiado.

Si existe información cacheada:

permitir mostrarla.

No borrar la sección simplemente porque Navidrome está temporalmente caído.

---

## Tests

### NavidromeServiceTest

verificar:

since
timestamp
resultado.

### RecentlyAddedSectionTest

mock:

3 pistas

esperar:

3 portadas
títulos
artistas.

### Ventana 7 días

track A:
hace 2 días

track B:
hace 6 días

track C:
hace 8 días

resultado:

A
B

no C.

### Integración

agregar pista a Navidrome
→ refresh
→ aparece.

---

# Parte B — Búsqueda y filtrado por género

## Modelos

Si la API/modelo lo requiere:

Track.genre
Album.genre
Artist.genre

como campos opcionales.

No duplicar información si los modelos actuales ya resuelven género de otra
forma.

---

## NavidromeService

Agregar funcionalidad equivalente a:

searchByGenre(
    String genre,
    {int limit = 20}
)

y para listas locales:

filterByGenre(
    List<Track> tracks,
    String genre
)

---

## Lista de géneros

Obtener mediante API real.

Ejemplos:

Rock
Metal
Pop
Electronic
Jazz

---

## UI

Integrar en:

GlobalTopBar
Drawer
Search

según diseño existente.

Debe permitir autocompletar.

Ejemplo:

usuario escribe:

Met

sugerencias:

Metal
Metalcore
Symphonic Metal

---

## Aplicar filtro

Ejemplo:

Recently Added

sin filtro:

Metal
Pop
Rock
Metal

filtro:

Metal

resultado:

Metal
Metal

---

## SearchResults

Mostrar género cuando esté disponible.

Pulsar género:

aplicar filtro.

---

## Persistencia

Guardar último género utilizado como sugerencia.

No bloquear al usuario en ese género al volver.

---

## Tests

- searchByGenre;
- filterByGenre;
- autocompletado;
- UI;
- persistencia;
- resultados reales desde Navidrome.

---

# FASE 10 — ECUALIZADOR + ESTADÍSTICAS
## Ítems 15 y 18

# Parte A — Ecualizador de 10 bandas

## Objetivo

Permitir controlar ganancia por frecuencia.

Rango:

-12 dB
→
+12 dB

---

## Bandas

Utilizar diez bandas razonables.

Ejemplo típico:

31 Hz
62 Hz
125 Hz
250 Hz
500 Hz
1 kHz
2 kHz
4 kHz
8 kHz
16 kHz

Adaptar según backend disponible.

---

## EqualizerService

Conceptualmente:

setBand(index, gain)

estado:

[
  band1,
  band2,
  ...
  band10
]

Persistir configuración.

---

## Backend de audio

NO asumir que:

AudioSession
JustAudioMediaKit
flutter_eq
ffmpeg
AudioEffect

ofrecen exactamente la API necesaria.

Auditar primero qué backend está usando realmente Scrotify.

Elegir implementación válida por plataforma.

Posibilidades descritas en el proyecto:

Android:
AudioEffect.Equalizer

iOS:
AVAudioUnitEQ

Desktop:
backend compatible existente / proceso / filtro apropiado

Software DSP:
solo si realmente es viable.

---

## IMPORTANTE

No implementar un ecualizador DSP en Dart que cause:

- stutter;
- latencia;
- consumo absurdo;
- degradación de audio

si existe una solución nativa mejor.

---

## UI

EqualizerScreen

con:

10 sliders verticales

y presets:

- Flat
- Bass Boost
- Vocal
- Treble Boost

Los cambios deben escucharse en tiempo real cuando el backend lo permita.

---

## Persistencia

Guardar:

enabled
band gains
preset

Al reiniciar:

restaurar.

---

## Bypass

Todas las bandas:

0 dB

deberían equivaler aproximadamente a señal original.

---

## Tests

### EqualizerServiceTest

señal:

1 kHz

aplicar ganancia.

Verificar modificación esperada.

### Bypass

0 dB

salida sin modificación significativa.

### Widget

mover slider
→ setBand llamado.

### Integración

reproducir tonos conocidos y comprobar efecto.

---

# Parte B — Estadísticas de escucha

## Objetivo

Crear un mini "Spotify Wrapped" local.

---

## ListeningStatsService

Registrar eventos de escucha.

Campos conceptuales:

trackId
artistId
genreId
timestamp
durationPlayed

Agregar serverId si existen múltiples servidores.

---

## ¿Cuándo contar reproducción?

No contar simplemente porque se cargó una canción.

Definir criterio.

Ejemplo:

- reproducción completada;

o

- cantidad mínima escuchada.

Evitar que hacer skip a los 2 segundos cuente igual que escuchar una canción
entera si eso contradice el objetivo de estadísticas.

---

## Consultas

Proveer:

- top artistas;
- top géneros;
- tracks más escuchados;
- reproducciones por día;
- semana;
- mes;
- tiempo total.

---

## StatsScreen

Secciones/pestañas:

Artistas
Géneros
Temporal

Utilizar:

fl_chart

o widgets/custom paint si encajan mejor con el proyecto.

---

## Ejemplo

Este mes:

Tiempo escuchado:
42 h 18 min

Top artistas:

1. Artist A — 8h
2. Artist B — 5h
3. Artist C — 4h

Top géneros:

Rock
Metal
Electronic

---

## Exportación

Opcionalmente:

CSV
JSON

para backup.

---

## Limpieza

Evitar DB infinita.

La propuesta inicial sugiere eliminar registros antiguos mayores a un año.

Antes de hacerlo automáticamente, evaluar si puede agregarse información
agregada para no destruir estadísticas históricas útiles.

No borrar datos silenciosamente sin una política documentada.

---

## Tests

### ListeningStatsTest

insertar reproducciones artificiales.

Verificar:

top artists
top genres
tiempo.

### Agregado mensual

enero
febrero

comprobar agrupación independiente.

### StatsScreen

datos mock

verificar gráficos/textos.

### Export

verificar archivo generado.

### Integración

reproducir varias canciones y confirmar valores.

---

# EXTRA MÓVIL — MODO AHORRO DE BATERÍA

Además de las fases principales, implementar o dejar preparado:

Modo ahorro de batería.

---

## Objetivo

Reducir consumo durante sesiones largas.

Cuando está activo puede:

- reducir animaciones;
- limitar refrescos no críticos;
- evitar trabajos pesados mientras reproduce;
- limitar procesamiento visual innecesario;
- reducir resolución de imágenes cuando sea razonable;
- ejecutar sincronizaciones pesadas cuando esté cargando/Wi-Fi si aplica.

IMPORTANTE:

La waveform de progreso NO debe desaparecer necesariamente.

Como es una forma estática cacheada, puede seguir mostrándose.

Lo que debe evitarse son visualizadores FFT continuos y procesamiento
innecesario.

---

# INTERACCIÓN ENTRE FASES

Las fases NO son completamente independientes.

Tener en cuenta:

## Offline + waveform

Si hay archivo local:

analizar local.

## Multiple servers + cache

Separar:

serverId + trackId.

## Multiple servers + stats

Guardar serverId para evitar colisiones.

## Multiple servers + rating

Aplicar rating al servidor correcto.

## Secure credentials + profiles

Nunca guardar passwords dentro del objeto Profile en texto plano.

## Skip Silence + waveform

Ambas pueden usar análisis del audio.

Evitar analizar la misma canción dos veces innecesariamente si puede existir una
capa compartida.

Por ejemplo:

AudioAnalysisService

podría calcular:

waveform
RMS
silence ranges

SOLO si esto encaja naturalmente con la arquitectura.

No crear mega-servicios por anticipación.

---

# PRUEBAS GENERALES OBLIGATORIAS

Al terminar CADA fase:

flutter analyze

flutter test

dart format --output=none --set-exit-if-changed .

Y cuando exista infraestructura disponible:

flutter drive / integration_test

---

# PRUEBAS DE REGRESIÓN

Comprobar que sigan funcionando:

- login;
- biometría;
- Home;
- Home móvil;
- artistas clickeables;
- búsqueda;
- reproducción;
- pause/resume;
- seek;
- cola;
- shuffle;
- repeat;
- Navidrome;
- Jam;
- portadas;
- playlists;
- perfiles;
- offline cuando corresponda.

---

# REGLA DE NO REGRESIÓN

Si una fase rompe algo existente:

NO continuar a la siguiente fase.

Primero:

identificar
↓
reproducir
↓
arreglar
↓
test
↓
continuar.

---

# GIT / ORGANIZACIÓN

Preferiblemente una rama/commit lógico por fase.

Ejemplos:

feature/offline-cache
feature/navidrome-profiles
feature/secure-credentials
feature/sleep-timer
feature/waveform-progress
feature/smart-mix
feature/ratings
feature/recent-genres
feature/equalizer-stats

Adaptar al flujo Git real del proyecto.

---

# CHANGELOG Y DOCUMENTACIÓN

Al completar cada fase:

actualizar:

CHANGELOG.md

y documentación técnica relevante.

Documentar:

- arquitectura;
- decisiones;
- limitaciones;
- plataformas soportadas;
- almacenamiento;
- migraciones;
- nuevos tests.

---

# NO HACER

NO:

- borrar funcionalidades existentes;
- ocultar errores;
- desactivar tests porque fallan;
- usar Random para waveform;
- hardcodear colores;
- guardar password en plaintext;
- duplicar servicios;
- inventar endpoints;
- asumir APIs de plugins;
- meter dependencias enormes sin necesidad;
- bloquear UI;
- analizar audio continuamente si ya existe caché;
- mezclar datos entre servidores;
- marcar COMPLETED sin pruebas;
- cambiar muchas fases simultáneamente sin poder aislar regresiones.

---

# FORMA DE TRABAJO DEL AGENTE

Para cada fase:

1. Investigar implementación existente.
2. Informar qué encontró.
3. Proponer solución concreta basada en el código real.
4. Implementar.
5. Agregar tests.
6. Ejecutar tests.
7. Ejecutar analyze.
8. Ejecutar formatter.
9. Revisar diff.
10. Corregir regresiones.
11. Documentar.
12. Crear commit solamente si corresponde al flujo solicitado.
13. Entregar informe.

No dar por terminada una fase solamente porque "compila".

---

# CRITERIO DE ESTADO

## COMPLETED

Todo implementado y probado.

## PARTIAL

Parte implementada pero falta algún requisito o plataforma.

## BLOCKED

No puede completarse por una dependencia externa concreta.

No utilizar COMPLETED cuando existen:

- tests sin correr;
- plataformas sin verificar que eran requisito;
- errores;
- warnings nuevos relevantes;
- TODO críticos;
- funcionalidad simulada;
- mocks sustituyendo validación real cuando se requiere integración.

---

# INFORME FINAL OBLIGATORIO POR FASE

Responder con:

# INFORME FINAL — FASE X

## ESTADO
COMPLETED / PARTIAL / BLOCKED

## OBJETIVO
Qué se buscaba implementar.

## BASELINE
Resultado inicial de:
- flutter analyze
- flutter test

## ARCHIVOS MODIFICADOS
Lista exacta.

## ARQUITECTURA
Qué componentes se añadieron/modificaron.

## IMPLEMENTACIÓN
Descripción técnica.

## PERSISTENCIA
Qué se almacena y dónde.

## NETWORK
Impacto sobre Navidrome si aplica.

## AUDIO
Impacto en reproducción si aplica.

## MOBILE
Estado.

## DESKTOP
Estado.

## OFFLINE
Estado.

## TESTS NUEVOS
Lista.

## FLUTTER TEST
Comando exacto + resultado.

## FLUTTER ANALYZE
Comando exacto + resultado.

## FORMAT
Resultado.

## PRUEBA MANUAL
Qué se probó realmente.

## REGRESIONES
Encontradas / solucionadas / pendientes.

## LIMITACIONES
Cualquier limitación real.

## CRITERIOS DE ACEPTACIÓN
PASS / FAIL / NOT TESTED por requisito.

## COMMIT
Hash si se realizó commit.

---

# INFORME ESPECIAL PARA FASE 6 — WAVEFORM

Además del informe normal, incluir:

## TRACK A

tipo de audio:
por ejemplo balada

waveform resumida:

[0.04, 0.08, 0.14, 0.27, 0.53, 0.81, ...]

## TRACK B

por ejemplo metal/EDM:

[0.58, 0.83, 0.92, 0.88, 0.95, ...]

## TRACK C

por ejemplo intro silenciosa:

[0.01, 0.02, 0.03, 0.08, 0.42, 0.79, ...]

Las tres formas deben ser distintas.

También demostrar:

seek 25 %
seek 50 %
seek 75 %

y confirmar que:

posición visual
=
posición real del reproductor.

---

# RESULTADO FINAL ESPERADO DEL ROADMAP

Scrotify debe terminar teniendo:

- reproducción online;
- reproducción offline/cache;
- biometría móvil;
- múltiples perfiles Navidrome;
- credenciales protegidas;
- sleep timer;
- fade out;
- waveform real como barra de progreso;
- seek directamente sobre waveform;
- waveform distinta para cada audio;
- mezcla inteligente;
- eliminación de silencios;
- rating 1-5;
- sección recientemente agregados;
- búsqueda/filtros por género;
- ecualizador de 10 bandas;
- estadísticas de escucha;
- buen comportamiento móvil;
- buen comportamiento desktop;
- compatibilidad con themes;
- tests;
- manejo correcto de errores;
- cero regresiones graves.

La prioridad es:

CORRECTITUD
>
ESTABILIDAD
>
COMPATIBILIDAD
>
RENDIMIENTO
>
UX
>
NUEVAS FUNCIONES.

No sacrificar reproducción estable por una mejora visual.
