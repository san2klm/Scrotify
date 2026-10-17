# Licencias de CrotoWave

Este documento explica qué licencia tiene cada parte del proyecto y qué hay que
cumplir al distribuirlo. Los textos legales que valen son los archivos
`LICENSE`; esto es un resumen.

## Resumen

| Parte | Ruta | Licencia |
|---|---|---|
| **Cliente** (Android, Android TV, Linux, Windows, macOS, iOS) | todo el repositorio salvo `crotolink-server/` y `third_party/` | **GPL-3.0-or-later** + excepción para tiendas de apps (`LICENSE`) |
| **Servidor CrotoLink** (Node 24 + `ws` + SQLite, Docker) | `crotolink-server/` | **AGPL-3.0-or-later** (`crotolink-server/LICENSE`) |
| `just_audio_media_kit` (copia parcheada) | `third_party/just_audio_media_kit/` | **The Unlicense** (dominio público), también nuestros cambios |
| Paquetes de pub.dev (`pubspec.yaml`) | caché de pub | la de cada paquete (ver abajo) |
| Librerías nativas que viajan con los binarios | AppImage, instalador de Windows | la de cada librería (ver abajo) |

Copyright (C) 2026 Lautaro ([Dante0Q](https://github.com/Dante0Q)), Thiago ([SniperWolfer](https://github.com/SniperWolfer)) y los colaboradores de CrotoWave.
Código fuente: <https://github.com/Dante0Q/CrotoWave>.

## Cliente: GPLv3 con excepción para tiendas

El cliente es software libre bajo la GNU GPL versión 3 «o posterior»
(SPDX: `GPL-3.0-or-later WITH LicenseRef-CrotoWave-AppStore-Exception`).

**Por qué GPL:** en escritorio el cliente se distribuye junto con `libmpv` y
`FFmpeg` compilados con sus partes GPL (GPL-2.0-or-later). Esas licencias se
pueden combinar con GPL-3.0, así que el conjunto queda en regla.

**La excepción (sección 7 de la GPL):** Apple App Store y Google Play imponen
DRM y condiciones propias que la GPL por sí sola no permite. Los titulares del
copyright de CrotoWave dan un permiso adicional para distribuir por esas tiendas,
con una condición: el código fuente completo de cada versión publicada tiene
que estar disponible públicamente bajo la GPLv3. El texto completo está al
final de `LICENSE` (en inglés, que es el vinculante, y en español).

Lo que la excepción **no** hace: no da permisos sobre código de terceros. Por
eso los builds para tiendas no deben incluir componentes GPL ajenos. Hoy se
cumple: en Android e iOS no van `libmpv` ni `FFmpeg` (el audio usa ExoPlayer y
AVPlayer del sistema), y todas las dependencias de Dart son permisivas.

**Por qué otros pueden quitar la excepción:** lo dice la propia GPLv3
(sección 7, segundo párrafo): quien redistribuye el programa puede eliminar
cualquier permiso adicional de su copia; no se puede impedir sin dejar de ser
GPL. No te afecta: la excepción sigue vigente en tu versión y nadie puede
quitártela. Lo que cambia es que una versión sin la excepción no se puede
publicar en tiendas, y que el código que alguien escriba en esa versión llega
solo bajo GPL pura: no se podría incorporar a la tuya para tiendas. Por eso
`CONTRIBUTING.md` pide que las contribuciones al proyecto acepten la excepción.

Regla para el futuro: **no agregar nunca un componente GPL-2.0-only** (sin «o
posterior»), porque no se puede combinar con GPL-3.0.

## Nombres y logo

La GPL protege el código, no el nombre. Por eso `LICENSE` y `crotolink-server/LICENSE`
agregan la condición que permite la sección 7(e): los nombres «CrotoWave» y
«CrotoLink» y el logo no se pueden usar en versiones modificadas; un fork que
se distribuya debe llevar otro nombre. El código se puede copiar y modificar
igual. Para una protección más fuerte (por ejemplo, frente a apps ajenas en
tiendas) haría falta registrar la marca.

## Servidor CrotoLink: AGPLv3

Cualquiera puede instalar su propio servidor CrotoLink, usarlo y modificarlo. La AGPL
agrega una sola obligación frente a la GPL (sección 13): si alguien modifica el
servidor y otras personas lo usan por red, tiene que ofrecerles el código de su
versión. Para eso el servidor publica la variable `SOURCE_URL` en `GET /source`,
en `GET /api/capabilities` y en el pie del panel `/admin` (ver
`crotolink-server/README.md`).

El cliente y el servidor son programas separados que se hablan por WebSocket:
la AGPL del servidor no afecta al cliente, y viceversa.

## Navidrome y la API de Subsonic

CrotoWave no incluye código de Navidrome (GPL-3.0). Se comunica con el servidor
solo por red, mediante la API HTTP de Subsonic/OpenSubsonic: son procesos
independientes, y ninguna de las dos licencias se extiende a la otra. Los
nombres «Navidrome», «Subsonic» y «OpenSubsonic» se usan solo para indicar
compatibilidad.

## Dependencias de Dart

Revisadas el 2026-10-16 sobre `.dart_tool/package_config.json` (incluye las
transitivas):

| Licencia | Paquetes |
|---|---|
| BSD-3-Clause | 111 (Flutter, `provider`, `path_provider`, `http`, `flutter_secure_storage`…) |
| MIT | 40 (`media_kit`, `window_manager`, `hotkey_manager`, `home_widget`…) |
| Apache-2.0 | 13 (`app_links`, `cryptography`, `rxdart`, `just_audio`…) |
| BSD-2-Clause | 5 (`sqflite` y sus partes) |
| MPL-2.0 | 3 (`dbus`, `gtk`, `nm`): compatible con GPL-3.0 (MPL 2.0, sección 3.3) |
| The Unlicense | 1 (`just_audio_media_kit`) |

Ninguna es GPL ni impone condiciones extra. Flutter junta solo sus textos de
licencia en cada build; la app los muestra en **Ajustes → Licencias de código
abierto**, junto con los avisos de las librerías nativas.

## Librerías nativas

| Componente | Dónde | Licencia | Fuente |
|---|---|---|---|
| `libmpv` | Linux (AppImage: paquete de Debian 12), Windows (build de media-kit) | GPL-2.0-or-later (compilado con GPL) | mpv.io |
| `FFmpeg`, `ffprobe` | Linux (AppImage), Windows (dentro de libmpv) | GPL-2.0-or-later (Debian usa `--enable-gpl`); LGPL-2.1-or-later sin las partes GPL | ffmpeg.org |
| `keybinder-3.0` | Linux | MIT | github.com/kupferlauncher/keybinder |
| ~170 librerías más del AppImage | Linux | LGPL, MIT, BSD, zlib… | ver `usr/share/doc` dentro del AppImage |

El AppImage lleva, para cada librería incluida, su archivo de copyright de
Debian (`usr/share/doc/<paquete>/copyright`) y la lista exacta de paquetes y
versiones con el enlace a su código fuente (`THIRD_PARTY_SOURCES.txt`). Así se
cumple la obligación de ofrecer el código de los componentes GPL/LGPL que se
redistribuyen.

## Al publicar una versión

1. Etiquetar el commit (`git tag vX.Y.Z`) y publicar ese código fuente completo
   en el repositorio público **antes** o junto con los binarios. La primera
   publicación va con historial limpio: ver `docs/PUBLICAR.md`.
2. Publicar los binarios firmados y sus sumas de verificación (ver
   `docs/SIGNING.md`).
3. Si un binario incluye librerías de terceros (AppImage, Windows), comprobar
   que llevan sus avisos y la lista de fuentes.
4. Mantener disponible el código de cada versión mientras esa versión se
   ofrezca en alguna tienda (lo exige la excepción).

## Contribuciones

Las contribuciones se aceptan bajo las mismas licencias de la carpeta que
tocan, **incluida la excepción para tiendas**. Ver `CONTRIBUTING.md`.
