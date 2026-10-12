# Scrotify

Cliente Flutter para Navidrome/Subsonic con Jam (escucha en grupo) para Linux, Android, Windows e iOS.

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

En escritorio los datos de la app se guardan en `Documentos/Scrotify/`.

## Versiones y Descargas por Plataforma (Releases)

Cada plataforma cuenta con su propio workflow automatizado en GitHub Actions y su release dedicada:

| Plataforma | Formato | Release en GitHub | Descripción |
| :--- | :--- | :--- | :--- |
| **Android Móvil** | `.apk` | `android-latest` | Optimizado para celulares y tablets Android con interfaz táctil vertical. |
| **Android TV** | `.apk` | `tv-latest` | Diseñado para Smart TVs (Philips 4K, TCL, Xiaomi, Chromecast, Fire TV). Soporta D-Pad y Leanback Launcher. |
| **Windows** | `.zip` (`.exe`) | `windows-latest` | Ejecutable nativo para Windows x64 (descomprimir y ejecutar `Scrotify.exe`). |
| **Linux** | `.tar.gz` | `linux-latest` | Binario nativo para Linux x64 con integración GTK y control por mouse/teclado. |
| **iPhone (iOS)** | `.ipa` | `ios-latest` | IPA sin firmar para instalar vía Sideloadly / AltStore. |

