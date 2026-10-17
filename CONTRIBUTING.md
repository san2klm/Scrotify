# Contribuir a CrotoWave

## Licencia de las contribuciones

Al enviar un cambio (pull request, parche o commit) aceptás que se publique
bajo la licencia de la carpeta que modifica:

- Cliente (todo salvo `jam-server/` y `third_party/`): **GPL-3.0-or-later con
  la excepción para tiendas de aplicaciones** que está al final de `LICENSE`.
  La excepción tiene que cubrir también tu código; si no, ya no se podría
  publicar CrotoWave en Google Play ni en la App Store.
- `jam-server/`: **AGPL-3.0-or-later**.
- `third_party/just_audio_media_kit/`: **The Unlicense**.

Conservás el copyright de lo que escribiste. Ver `LICENSING.md`.

## Certificado de origen (DCO)

Cada commit lleva una línea `Signed-off-by` (`git commit -s`). Con ella
declarás lo del [Developer Certificate of Origin 1.1](https://developercertificate.org/):
que el código es tuyo, o que tenés derecho a enviarlo bajo esas licencias.

```
Signed-off-by: Tu Nombre <tu@correo>
```

No copies código de otros proyectos sin revisar antes que su licencia sea
compatible (ver la regla sobre GPL-2.0-only en `LICENSING.md`) y sin dejar su
aviso de copyright.

## Secretos

Nunca subas claves de firma, contraseñas ni archivos `key.properties`. El
`.gitignore` los bloquea y el hook de `.githooks/` revisa cada commit:
actívalo una vez con `git config core.hooksPath .githooks`.

## Antes de enviar

- `flutter analyze` sin errores ni avisos.
- `flutter test` y, si tocás el servidor, `cd jam-server && node --test`.
