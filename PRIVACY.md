# Privacidad de CrotoWave

*English summary below.*

CrotoWave no tiene telemetría, analíticas, publicidad ni informes de errores
automáticos. No hay cuentas de CrotoWave: la app se conecta a los servidores
que vos configurás. Lo que sale del dispositivo, y adónde:

| Destino | Qué se envía | Cuándo |
|---|---|---|
| Tu servidor Navidrome/Subsonic | usuario, contraseña (como token con sal) y lo que pedís reproducir o ver | siempre: es el servidor de tu música |
| Servidor CrotoLink que configures en Ajustes (no hay ninguno por defecto) | sincronización de tus datos, presencia de tus dispositivos (CrotoWave Connect) y salas CrotoLink | solo si configuraste uno, con sesión iniciada; la sincronización y Connect viajan **cifrados de extremo a extremo**: el servidor solo ve datos opacos. En las salas CrotoLink el servidor ve la cola compartida y los nombres de los participantes |
| `lrclib.net` | título, artista, álbum y duración de la canción | solo al abrir la letra, si tu servidor no la tiene |
| `api.deezer.com`, `theaudiodb.com` | nombre del artista | solo si activás «Imágenes de artistas de terceros» (apagado por defecto) |
| `ntfy.sh` | mensajes cifrados del emparejamiento por QR | solo mientras emparejás dos dispositivos |
| Discord (programa local) | canción que suena | solo si activás Discord Rich Presence (apagado por defecto) |

El registro de diagnóstico queda en memoria del dispositivo y solo sale si vos
lo copiás o compartís (Ajustes → Diagnóstico); antes oculta contraseñas,
tokens y claves.

Podés usar tu propio servidor CrotoLink (ver `jam-server/README.md`) cambiando
la dirección en Ajustes.

Fecha: 2026-10-16. Si esto cambia, se actualiza este archivo en el repositorio.

---

## English summary

CrotoWave has no telemetry, analytics, ads or automatic crash reports, and no
CrotoWave accounts. It only talks to: your Navidrome/Subsonic server; the
CrotoLink server you set in Settings (there is none by default), where sync and device presence are end-to-end encrypted; `lrclib.net`
when you open lyrics your server lacks; Deezer and TheAudioDB for artist
images only if you enable them (off by default); `ntfy.sh` with encrypted
messages while pairing devices by QR; and the local Discord app only if you
enable Rich Presence (off by default). Diagnostics stay on the device unless
you copy or share them.
