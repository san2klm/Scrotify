# Scrotify

Cliente Flutter para Navidrome/Subsonic con Jam (escucha en grupo) para Linux, Android y Windows.

## Documentación

- [Visión general y arquitectura](docs/scrotify.md)
- [Jam: diseño](docs/jam.md)
- [Jam: roadmap](docs/jam-roadmap.md)
- [Jam: pruebas y despliegue remoto](docs/jam-pruebas.md)
- [Música local](docs/musica-local.md)
- [Servidor Jam](jam-server/README.md)
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
