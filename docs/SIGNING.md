# Firma de CrotoWave

Cómo se firman los binarios, dónde están las claves y cómo se verifica una
descarga. Licencias: ver `LICENSING.md`.

## Resumen

| Plataforma | Firma | Estado |
|---|---|---|
| Android (teléfono, TV, Chromecast) | Clave propia RSA 4096 (APK v2/v3) | ✅ activa desde 2026-10-16 |
| Linux (AppImage) | `SHA256SUMS` firmado con minisign | ✅ activa desde 2026-10-16 |
| Windows | `SHA256SUMS` con minisign; Authenticode gratis con SignPath Foundation | minisign ✅; SignPath cuando el repo sea público (ver abajo) |
| iOS / macOS | requiere Apple Developer Program | no disponible |

## Dónde están las claves

Todas **fuera del repositorio**, en `~/.config/crotowave-signing/` (permisos 700):

| Archivo | Qué es |
|---|---|
| `crotowave-release.p12` | keystore Android (PKCS12, alias `crotowave`, `CN=CrotoWave`, válido hasta 2076) |
| `key.properties` | rutas y contraseña del keystore; `android/key.properties` es un enlace a este archivo |
| `minisign.key` | clave privada minisign, cifrada con tu contraseña |
| `legacy/` | clave de la etapa «Scrotify» (`cloud.templo.scrotify`): solo para migrar instalaciones viejas; se puede borrar cuando no quede ninguna |

**Haz una copia de esa carpeta fuera de la PC** (USB cifrado, gestor de
contraseñas) y guarda aparte la contraseña de minisign. Si se pierde el
keystore de Android, ninguna instalación existente se puede volver a
actualizar: Android exige la misma clave en cada versión.

Protecciones contra subirlas por error:
- `.gitignore` bloquea `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.pem`,
  `*.key`, `*.asc`, `*.sig`, `key.properties`, `signing/`, `.signing/`,
  `cosign.key` y `migration-backup/`. Las claves **públicas** (`*.pub`) sí se
  versionan.
- El hook `.githooks/pre-commit` frena los commits con esos archivos, con
  claves privadas PEM o con contraseñas de keystore. Actívalo en cada clon:
  `git config core.hooksPath .githooks`.

## Android

- `applicationId`: **`cloud.templo.crotowave`** (definitivo: cambiarlo crea otra
  app). Antes: `com.example.navidrome_client` (plantilla, clave debug) y
  `cloud.templo.scrotify` (2026-10-16, antes del cambio de nombre).
- Huella SHA-256 del certificado:
  `06:37:E6:E7:6D:F2:E7:8D:3B:C8:3F:70:F3:CD:48:BA:CC:B2:2A:52:D9:5C:EE:93:91:67:5C:9B:BD:3B:4F:7D`

`android/key.properties` (no se versiona):

```properties
storeFile=/home/<usuario>/.config/crotowave-signing/crotowave-release.p12
storePassword=…
keyAlias=crotowave
keyPassword=…
```

Con ese archivo, `scripts/build_apks.sh` firma con la clave propia. Sin él,
Gradle rechaza los release salvo que se pida la clave debug a propósito
(`ORG_GRADLE_PROJECT_allowDebugSigning=true`, solo para pruebas por adb).

Verificar un APK:

```sh
apksigner verify --print-certs CrotoWave-*.apk | grep SHA-256
```

### Migrar una instalación existente

Una app firmada con otra clave o con otro `applicationId` no se puede
actualizar: hay que instalar la nueva aparte. `tool/migrate_android_signing.sh`
pasa todos los datos (perfiles de servidor con sus contraseñas, clave de
sincronización, ajustes, temas, estadísticas, caché offline y permisos):

```sh
# Desde la app de la plantilla (com.example.navidrome_client):
tool/migrate_android_signing.sh <id-adb> phone|tv backup
tool/migrate_android_signing.sh <id-adb> phone|tv restore

# Desde la de la etapa Scrotify (cloud.templo.scrotify):
export FROM_APP=cloud.templo.scrotify
export FROM_KEY=~/.config/crotowave-signing/legacy/key.properties
tool/migrate_android_signing.sh <id-adb> phone backup
tool/migrate_android_signing.sh <id-adb> phone restore

adb -s <id-adb> uninstall <id-viejo>      # cuando todo esté bien
```

Cómo funciona: `run-as` solo entra en apps depurables, así que el script
instala encima de la vieja un build debug con el mismo id y la misma clave
(conserva los datos). Ese build, compilado con
`--dart-define=SCROTIFY_SIGNING_MIGRATION=true`, exporta el almacén seguro: está
cifrado con claves del Keystore de Android atadas a la instalación y copiar
sus archivos no serviría. Después instala la app nueva en modo migración, le
copia los datos, ella importa el almacén, y por último la actualiza al release
normal (no depurable). Los builds normales no incluyen el código de migración.

La copia queda en `migration-backup/<serie>-<sabor>-<id-viejo>/` (ignorado por
git). Hasta el `restore` contiene las contraseñas en claro; el `restore` las
borra de la copia al terminar.

Estado: ver `tasks/todo.md`. Lo que no pasa: los widgets de la pantalla de
inicio (son de la app vieja; hay que volver a ponerlos).

### CI (GitHub Actions)

Los workflows `android.yml` y `tv.yml` todavía compilan sin sabor y sin clave,
y Gradle rechaza un release sin `key.properties`. Para que CI publique APK
firmados hay que:
1. Guardar el keystore como secreto: `base64 -w0 crotowave-release.p12` →
   `ANDROID_KEYSTORE_BASE64`, y la contraseña en `ANDROID_KEYSTORE_PASSWORD`.
2. En el workflow, escribir `android/key.properties` desde esos secretos y
   compilar con `--flavor phone|tv` (como `scripts/build_apks.sh`).

Subir el keystore a GitHub es una decisión de confianza: la alternativa es
compilar y firmar los release solo en esta PC.

## Linux y Windows: sumas firmadas con minisign

Una sola clave firma la lista de sumas SHA-256 de todos los binarios del
release. Quien descarga verifica primero la firma de la lista y después el
archivo. La clave pública es `crotowave-release.pub` (en la raíz del repo).

En cada release, con los binarios en `dist/`:

```sh
scripts/sign_release.sh dist
```

Verifica que los APK tengan la huella de arriba, genera `dist/SHA256SUMS` y lo
firma (`SHA256SUMS.minisig`). La contraseña de la clave se pide en una ventana
(kdialog o zenity; sin escritorio, en la terminal): nunca se guarda ni pasa
por argumentos. Se publican `SHA256SUMS` y `SHA256SUMS.minisig` junto a los
binarios.

La clave se creó el 2026-10-16 con `scripts/sign_release.sh --init`. Si hubiera
que reemplazarla, se publica la pública nueva y se avisa en el release.

Verificar una descarga:

```sh
minisign -Vm SHA256SUMS -p crotowave-release.pub
sha256sum -c --ignore-missing SHA256SUMS
```

### Windows: SignPath Foundation (gratis)

Un certificado autofirmado **no** quita el aviso de SmartScreen: Windows solo
confía en certificados de una autoridad reconocida. La opción gratis es
[SignPath Foundation](https://signpath.org/), que firma proyectos de código
abierto con un certificado propio y un servicio en la nube conectado a CI.
Condiciones (<https://signpath.org/terms>, revisadas el 2026-10-16):

- Licencia aprobada por la OSI en todos los componentes, sin código propietario.
- Repositorio público, proyecto mantenido y **ya publicado** en la forma que se
  firma (por eso se pide después de la primera publicación).
- Build automático en CI desde el código del repositorio (workflow
  `windows.yml`); cada firma se aprueba a mano.
- MFA en GitHub y en SignPath para todo el equipo.
- Una «Code signing policy» en la página del proyecto, con la frase «Free code
  signing provided by SignPath.io, certificate by SignPath Foundation», los
  roles del equipo y la política de privacidad: ya están en
  `docs/CODE_SIGNING_POLICY.md` y `PRIVACY.md`.
- `ProductName` del ejecutable igual al nombre del proyecto (`CrotoWave`, en
  `windows/runner/Runner.rc`).

Un riesgo a confirmar al pedirlo: la licencia es GPL-3.0 con permisos
adicionales de la sección 7 (excepción para tiendas y nombres). Siguen siendo
GPL-3.0, pero conviene mencionarlo en la solicitud.

Pasos cuando el repo sea público: ver `docs/PUBLICAR.md`.

## iOS y macOS

Distribuir fuera del modo desarrollo exige firmar con un certificado de Apple
(Apple Developer Program, de pago). El `.ipa` que publica CI va sin firmar,
para instalarlo con Sideloadly/AltStore.
