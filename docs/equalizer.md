# Scrotify — Ecualizador de Tres Niveles y Modos de Alta Fidelidad

> **Documento Técnico de Referencia**  
> Proyecto: Scrotify (Cliente Flutter para Navidrome / Subsonic)  
> Componentes: `EqualizerService` v2, backends de EQ por plataforma, `HifiPlanner`  
> Fecha de actualización: 2026-10-07  

---

## 0. Estado de la integración en Scrotify (2026-10-07)

Lo que difiere del paquete original `Eculiza/scrotify_eq`:

* **Cableado automático.** La sección 8 es la referencia original; en el código ya está resuelto en `lib/main.dart`:
  * Android: `AndroidEqSetup.create()` crea los reproductores A/B con su `AndroidEqualizer`. `AndroidEqBackend` aplica siempre el último estado cuando el motor está listo (`parameters` solo se resuelve al cargar la primera pista).
  * Escritorio: `createDesktopEqBackend()` fija `af` en todos los reproductores mpv.
  * Hi-Fi: `HifiCoordinator` calcula el `HifiPlan` y lo reparte a `PlayerController.applyHifi`, al EQ y a mpv.
* **`just_audio_media_kit` parcheado** en `third_party/just_audio_media_kit` (ver `SCROTIFY_PATCH.md`): el `Player` de mpv era privado. Además `JustAudioMediaKit.pitch = false`, porque su modo de tono instala un `af` propio (`scaletempo`) que pisaba el del ecualizador; mpv sigue conservando el tono al cambiar la velocidad.
* **Modo Estándar = comportamiento anterior.** No cambia el origen del stream ni toca mpv. Alta fidelidad y Bit-perfect piden `format=raw` solo para **reproducción** (`NavidromeService.getPlaybackStreamUrl`); las descargas no cambian.
* **Bit-perfect:** volumen digital fijo al 100 %, sin EQ, ReplayGain ni crossfade. En Android 14+ con DAC USB se pide el mezclador bit-perfect por pista (`HifiAudioPlugin.kt`, con `samplingRate`/`bitDepth` que ahora lee `Track`).
* **No incluido:** el plugin de iOS (`HifiAudioPlugin.swift`; el proyecto no tiene carpeta `ios/`), la opción de motor mpv en móvil, y las propiedades de inicio de mpv (`ao`), que requerirían recrear el reproductor.
* Pruebas: `test/equalizer_test.dart`, `test/equalizer_service_test.dart`, `test/hifi_modes_test.dart` y `test/eq_mpv_integration_test.dart` (usa el libmpv del sistema; se omite si no existe).
* Pendiente de comprobar a oído en un dispositivo Android real.

---

## 1. Visión General

El ecualizador reemplaza al EQ fijo de 10 bandas por un **único motor paramétrico** con **tres interfaces** según el nivel del usuario. El audio siempre pasa por la misma cadena de filtros biquad; lo que cambia es cuánto de esa cadena se muestra.

```
            ┌──────────────────────────────────────────────┐
            │                EqualizerScreen               │
            │   [ Simple ]   [ 10 bandas ]   [ Pro ]       │
            └──────────────────────┬───────────────────────┘
                                   ▼
            ┌──────────────────────────────────────────────┐
            │  EqualizerService (modo, perfiles, preamp)   │
            │  EqMath: biquads RBJ, curva, anti-clipping   │
            └──────┬──────────────────┬───────────────┬────┘
                   ▼                  ▼               ▼
          ┌────────────────┐ ┌────────────────┐ ┌──────────────┐
          │ MpvEqBackend   │ │AndroidEqBackend│ │ Unsupported  │
          │ lavfi FFmpeg   │ │ audiofx (5–10) │ │ (iOS+AVPlayer│
          │ desktop/mobile │ │ ajuste curvas  │ │  explica por │
          └────────────────┘ └────────────────┘ │  qué)        │
                                                └──────────────┘
```

---

## 2. Los Tres Modos

| | **Simple** | **Intermedio (10 bandas)** | **Profesional (paramétrico)** |
| :--- | :--- | :--- | :--- |
| Público | Cualquier usuario | Aficionado | Audiófilo / técnico |
| Controles | Graves · Medios · Agudos | 31 Hz – 16 kHz ISO, Q fija 1.41 | Tipo, frecuencia, ganancia y Q por filtro |
| Rango | ±6 dB | ±12 dB | ±15 dB |
| Filtros | 3 (estante + campana + estante) | 10 campanas | Hasta 16 de 6 tipos |
| Presets | Por situación: *Más graves, Voces claras, Parlante chico, Auto, Modo noche…* | Por género y uso: *Rock, Electrónica, Podcast, Auriculares (Harman aprox.)…* | Importación AutoEQ / EqualizerAPO |
| Preamp | Siempre automático | Automático o manual | Automático o manual |
| Extras | *Modo noche* (loudness) | Curva de respuesta real | Curva con filtro resaltado, exportar `.txt` |

### 2.1. Conversión entre modos sin saltos de sonido
Al cambiar de modo, `EqualizerService.setMode` convierte la curva actual:
* **→ Profesional:** sin pérdida (copia los filtros).
* **→ 10 bandas:** `EqMath.fitToGraphic` ajusta las 10 ganancias por iteración de punto fijo, compensando el solapamiento de bandas vecinas (error < 0.3 dB en los centros).
* **→ Simple:** lee la curva a 60 Hz, 1 kHz y 12 kHz y redondea a 0.5 dB.

### 2.2. Tipos de filtro (modo profesional)
Campana (*peaking*), estante de graves, estante de agudos, pasa altos, pasa bajos y notch. Fórmulas del **RBJ Audio EQ Cookbook**, idénticas a las de FFmpeg, por lo que la curva dibujada es la curva que suena.

---

## 3. Anti-Clipping: Preamp Automático

Realzar frecuencias puede llevar la señal por encima de 0 dBFS y producir distorsión digital. `EqMath.autoPreampDb` muestrea la curva en 512 puntos logarítmicos (20 Hz – 20 kHz), toma el mayor realce **real** (las bandas solapadas suman: *Bass Boost* con 5+5+3 dB produce un pico de ~6.5 dB, no 5) y aplica:

$$\text{Preamp} = -(\text{máx. realce} + 0.3\ \text{dB})$$

Los 0.3 dB adicionales cubren picos inter-muestra (*true peak*). Además, en mpv se añade un `alimiter` a −0.2 dBFS como red de seguridad cuando el usuario fija un preamp manual.

La curva de la UI muestra el preamp como línea discontinua para que el usuario entienda por qué baja el volumen.

---

## 4. Backends por Plataforma

### 4.1. mpv / media_kit (Linux, Windows, macOS; opcional en Android e iOS)
`MpvEqBackend` construye la propiedad `af` de mpv como un grafo FFmpeg y la aplica a **ambos reproductores A/B**, para que el crossfade nunca mezcle una pista ecualizada con otra sin ecualizar:

```text
lavfi=[aformat=sample_fmts=fltp|dblp,volume=-6.82dB,
       bass=f=105.0:t=q:w=0.707:g=5.00,
       equalizer=f=2400.0:t=q:w=1.410:g=-3.00,
       alimiter=limit=0.977:attack=5:release=50:level=0]
```

* `aformat=fltp|dblp`: todo el procesamiento ocurre en coma flotante (sin ruido de cuantización).
* Se usan `bass`/`treble` en lugar de `lowshelf`/`highshelf` por compatibilidad con builds antiguas de FFmpeg.
* **Debounce de 90 ms** al arrastrar sliders: cambiar `af` reinicializa el grafo y, a 60 Hz, provoca chasquidos.
* Si el karaoke necesita sus propios filtros, se pasan en `extraFilters` y se concatenan, sin pisarse.

### 4.2. Android con just_audio (ExoPlayer)
`AndroidEqBackend` usa `android.media.audiofx.Equalizer`, que tiene **bandas fijas definidas por el fabricante** (casi siempre 5: ~60, 230, 910, 3.6 k y 14 kHz). La curva del usuario se aproxima con `fitToGraphic` a esas bandas, y el preamp negativo se reparte en todas ellas. La UI avisa: *"Tu dispositivo ofrece 5 bandas fijas: la curva se aproxima"*.

Cada `AudioPlayer` (A y B) necesita su propio `AndroidEqualizer` en su `AudioPipeline`.

### 4.3. iOS con just_audio (AVPlayer)
AVPlayer no permite insertar DSP propio. En lugar de simular un EQ que no hace nada, `UnsupportedEqBackend` explica el motivo y la UI sugiere activar el motor mpv.

### 4.4. Recomendación: motor mpv también en móvil
`media_kit` soporta Android e iOS. Ofrecer en **Ajustes > Audio > Motor** la opción *"mpv (EQ paramétrico exacto)"* da la misma calidad de ecualización en las 5 plataformas. just_audio sigue siendo el valor por defecto en móvil por su integración madura con `audio_service`.

---

## 5. Modos de Alta Fidelidad (`HifiPlanner`)

`HifiPlanner.plan()` devuelve un `HifiPlan` (datos puros, testeable) que `PlayerController` aplica.

| | **Estándar** | **Alta fidelidad** | **Bit-perfect** |
| :--- | :--- | :--- | :--- |
| Stream Wi-Fi | Original (`format=raw`) | Original | Original |
| Stream datos móviles | Opus a la tasa elegida | Opus (o original si el usuario lo permite) | Igual que Alta fidelidad |
| EQ / ReplayGain / Crossfade | Sí | Sí, en float con preamp automático | **No** |
| Volumen digital | Libre | Libre (máx. 100 %) | **Fijo en 100 %** |
| Remuestreo mpv | Por defecto | SoXr precisión 28 bits | Sin remuestreo |
| Salida exclusiva | No | No | Sí, donde exista |

### 5.1. Detalle por plataforma

| Plataforma | Alta fidelidad | Bit-perfect |
| :--- | :--- | :--- |
| **Windows** | mpv + SoXr, frecuencia nativa | `ao=wasapi`, `audio-exclusive=yes` (WASAPI exclusivo) |
| **macOS** | mpv + SoXr | `ao=coreaudio`, hog mode, `coreaudio-change-physical-format=yes` (el DAC cambia a 44.1/96/192 kHz por pista) |
| **Linux** | mpv + SoXr | `ao=alsa` con dispositivo `hw:`; en PipeWire configurar `default.clock.allowed-rates` |
| **Android** | Stream original; el sistema mezcla a 48 kHz | Android 14+ con DAC USB: `AudioManager.setPreferredMixerAttributes` con `MIXER_BEHAVIOR_BIT_PERFECT` (`HifiAudioPlugin.kt`). Bluetooth y parlante interno no pueden ser bit-perfect. |
| **iOS** | `AVAudioSession.setPreferredSampleRate` igual a la pista (`HifiAudioPlugin.swift`) | Igual + sin procesamiento. iOS no ofrece modo exclusivo. |

### 5.2. Parámetros de stream (Subsonic 1.16.1)
`format=raw&maxBitRate=0&estimateContentLength=true` → Navidrome entrega el archivo original sin transcodificar y con tamaño conocido (seek instantáneo).

### 5.3. Honestidad hacia el usuario
Cada plan incluye `notes` que la pantalla de Ajustes muestra tal cual. Ejemplos: *"Con Bluetooth se usa Alta fidelidad"*, *"El ecualizador está en pausa porque el modo Bit-perfect envía el audio sin modificar"*.

---

## 6. Interacción con Otros Subsistemas

* **Crossfade A/B:** el EQ se aplica a ambos reproductores; en Bit-perfect el crossfade se desactiva (mezclar dos pistas ya no es bit-perfect).
* **ReplayGain:** se suma al preamp del EQ en el mismo nodo `volume` (mpv) para un único cálculo de headroom. En Bit-perfect se desactiva.
* **Scrotify Jam:** el EQ es **local de cada dispositivo** y no se sincroniza. En escucha sincronizada el limitador añade ~5 ms de latencia, muy por debajo del umbral de deriva de 450 ms.
* **Karaoke:** sus filtros se concatenan vía `MpvEqBackend.extraFilters`.

---

## 7. Persistencia

Archivo `equalizer_v2.json` en el directorio de soporte de la app, escrito de forma atómica (`.tmp` + `rename`) con debounce de 600 ms. Guarda: modo actual, perfil activo de **cada** modo (volver a un modo recupera lo que había), presets del usuario. Un archivo corrupto arranca el EQ en plano sin crashear. Los perfiles importados se sanitizan (frecuencia 10 Hz–22 kHz, Q 0.1–18, ganancia dentro del rango del modo).

---

## 8. Integración en el Código Existente

### 8.1. Archivos nuevos
```text
lib/models/eq_models.dart
lib/services/equalizer_service.dart        (reemplaza al actual)
lib/services/eq/eq_math.dart
lib/services/eq/eq_presets.dart
lib/services/eq/eq_backends.dart
lib/services/eq/eq_import_export.dart
lib/services/hifi/hifi_profiles.dart
lib/services/hifi/hifi_native.dart
lib/screens/equalizer_screen.dart          (reemplaza al actual)
lib/widgets/eq_response_curve.dart
android/app/src/main/kotlin/.../HifiAudioPlugin.kt
ios/Runner/HifiAudioPlugin.swift
test/equalizer_test.dart
```
No requiere dependencias nuevas del registro (usa `just_audio`, `media_kit`, `provider` y `path_provider`), pero sí la copia local de `just_audio_media_kit` (ver sección 0).

### 8.2. `main.dart`
```dart
ChangeNotifierProvider(create: (_) => EqualizerService()..initialize()),
```

### 8.3. `PlayerController`: conectar el backend
```dart
// Desktop (o móvil con motor mpv):
eq.attachBackend(MpvEqBackend([
  (k, v) => (_mkA.platform as NativePlayer).setProperty(k, v),
  (k, v) => (_mkB.platform as NativePlayer).setProperty(k, v),
]));

// Android con just_audio:
final eqA = AndroidEqualizer(), eqB = AndroidEqualizer();
_a = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [eqA]));
_b = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [eqB]));
eq.attachBackend(AndroidEqBackend([eqA, eqB]));

// iOS con just_audio:
eq.attachBackend(UnsupportedEqBackend(
  'iOS no permite ecualizar con el motor actual. Activá "mpv" en Ajustes > Audio.'));
```

### 8.4. `PlayerController`: aplicar el plan Hi-Fi
```dart
Future<void> applyHifi(HifiPlan plan) async {
  for (final e in plan.mpvProperties.entries) {
    if (plan.mpvInitOnly.contains(e.key)) continue; // se aplican al recrear el player
    await _setMpvOnBoth(e.key, e.value);
  }
  await _equalizer.setHifiAllowsEq(plan.allowEq);
  _replayGainEnabled = plan.allowReplayGain;
  _crossfadeEnabled = plan.allowCrossfade;
  if (plan.lockVolumeAt100) await setVolume(1.0);
  _streamQuery = plan.stream.toQuery();       // para NavidromeService.streamUrl
}

// Al cargar cada pista (bit-perfect necesita su frecuencia):
if (plan.requestAndroidBitPerfect) {
  await HifiNative.enableAndroidBitPerfect(sampleRate: track.samplingRate, bitDepth: track.bitDepth);
}
if (plan.matchIosSampleRate) {
  await HifiNative.setIosPreferredSampleRate(track.samplingRate);
}
```
`samplingRate` y `bitDepth` los devuelve Navidrome en los objetos `child` de la API (OpenSubsonic); conviene agregarlos al modelo `Track`.

### 8.5. Pruebas
```bash
flutter test test/equalizer_test.dart
```
Cubre: biquads contra valores teóricos, preamp con bandas solapadas, ajuste a 10 y a 5 bandas, cadena FFmpeg, importación AutoEQ (incluye líneas inválidas y valores fuera de rango), planes Hi-Fi por plataforma y persistencia JSON.

---

## 9. Tabla de Referencia Rápida

| Parámetro | Valor | Descripción |
| :--- | :--- | :--- |
| Rango Simple / Intermedio / Pro | ±6 / ±12 / ±15 dB | Límite de ganancia por filtro |
| Máx. filtros Pro | 16 | Suficiente para cualquier perfil AutoEQ |
| Q gráfica | 1.41 | Ancho de 1 octava (ISO) |
| Q suave | 0.707 | Estantes y modo simple (Butterworth) |
| Frecuencias modo simple | 105 Hz / 1 kHz / 8 kHz | Estante / campana Q 0.5 / estante |
| Margen true-peak | 0.3 dB | Sumado al preamp automático |
| Debounce de aplicación | 90 ms | Evita chasquidos al arrastrar |
| Debounce de guardado | 600 ms | Escritura atómica |
| Limitador mpv | −0.2 dBFS, 5 ms ataque | Red de seguridad |
| Remuestreo Hi-Fi (mpv) | SoXr, 28 bits | Sólo si el dispositivo lo exige |
| Stream original | `format=raw&maxBitRate=0` | Navidrome sin transcodificar |
| Bit-perfect Android | API 34+, DAC USB | `MIXER_BEHAVIOR_BIT_PERFECT` |
