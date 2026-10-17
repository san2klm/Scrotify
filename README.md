# CrotoWave

Cliente Flutter para Navidrome/Subsonic con CrotoLink (escucha en grupo) para Linux, Android y Windows.

## Documentación

- [Visión general y arquitectura](docs/crotowave.md)
- [CrotoLink: diseño](docs/jam.md)
- [CrotoLink: roadmap](docs/jam-roadmap.md)
- [CrotoLink: pruebas y despliegue remoto](docs/jam-pruebas.md)
- [Música local](docs/musica-local.md)
- [Servidor CrotoLink](jam-server/README.md)
- [Plan y tareas](tasks/todo.md)

## Desarrollo

```
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

En escritorio los datos de la app se guardan en la carpeta de soporte de la
aplicación (`%APPDATA%` en Windows, `~/.local/share` en Linux).

## Compilar

El repositorio incluye `android/`, `linux/` y `windows/`: basta con
`flutter pub get`.

### Android

Hay dos sabores: `phone` y `tv`.

```
flutter build apk --flavor phone --debug      # desarrollo
scripts/build_apks.sh [phone|tv] [--universal] # releases por arquitectura
```

Un release exige `android/key.properties` (`storeFile`, `storePassword`,
`keyAlias`, `keyPassword`). Sin él, Gradle se niega a firmar con la clave debug
salvo que se defina `ORG_GRADLE_PROJECT_allowDebugSigning=true`
(`scripts/build_apks.sh` lo hace solo para instalaciones locales por adb).

### Windows

```
flutter build windows --release
scripts/build_windows_installer.sh   # necesita Inno Setup 6
```

### Linux

```
flutter build linux --release
scripts/build_appimage.sh            # necesita appimagetool
```

iOS no está soportado todavía (no hay carpeta `ios/`).

## Versiones y Descargas por Plataforma (Releases)

Cada plataforma cuenta con su propio workflow automatizado en GitHub Actions y su release dedicada:

| Plataforma | Formato | Release en GitHub | Descripción |
| :--- | :--- | :--- | :--- |
| **Android Móvil** | `.apk` | `android-latest` | Optimizado para celulares y tablets Android con interfaz táctil vertical. |
| **Android TV** | `.apk` | `tv-latest` | Diseñado para Smart TVs (Philips 4K, TCL, Xiaomi, Chromecast, Fire TV). Soporta D-Pad y Leanback Launcher. |
| **Windows** | `.zip` (`.exe`) | `windows-latest` | Ejecutable nativo para Windows x64 (descomprimir y ejecutar `CrotoWave.exe`). |
| **Linux** | `.tar.gz` | `linux-latest` | Binario nativo para Linux x64 con integración GTK y control por mouse/teclado. |
| **iPhone (iOS)** | `.ipa` | `ios-latest` | IPA sin firmar para instalar vía Sideloadly / AltStore. |


## Licencia

El cliente es software libre bajo **GPL-3.0-or-later** con una excepción que
permite publicarlo en Google Play y la App Store; el servidor CrotoLink, bajo
**AGPL-3.0-or-later**. Detalle por componente en [`LICENSING.md`](LICENSING.md),
firma de los binarios en [`docs/SIGNING.md`](docs/SIGNING.md) y cómo contribuir
en [`CONTRIBUTING.md`](CONTRIBUTING.md). Los nombres «CrotoWave» y «CrotoLink» y
el logo no se pueden usar en versiones modificadas.

- [Privacidad](PRIVACY.md): qué datos salen del dispositivo y adónde.
- [Code signing policy](docs/CODE_SIGNING_POLICY.md).
- Verificar una descarga: `minisign -Vm SHA256SUMS -p crotowave-release.pub`
  y luego `sha256sum -c --ignore-missing SHA256SUMS`.
