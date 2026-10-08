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
