---
name: scrotify-pending-tasks-jam-home-artists
description: Tareas pendientes relacionadas a Jam, artistas (visuales) y cosas faltantes de Home
metadata:
  type: project
---

Se han agendado nuevas correcciones y pendientes para abordar más adelante:

**1. Scrotify Jam:**
Arreglar detalles y problemas que quedaron pendientes en el sistema de sincronización o UI.

*(2026-10-04, prioridad alta)* **El invitado no encuentra al host.** Causa real SIN confirmar.
- 2026-10-04: el `jam-server` se revirtió a la versión `ae8dde3` (sin límite de intentos de PIN, sin validación de acciones, sin ping/pong, `/rooms` lista todas las salas, host público fijo, nombres duplicados sin sufijo). Se conservó en el cliente la limpieza de credenciales en URLs de carátula (`sanitizeArtUrl`).
- Falta saber el escenario: lista / PIN / QR, LAN o servidor remoto, mensaje exacto en el teléfono.
- Sospechas LAN: PC con Wi-Fi (192.168.1.52) y cable (192.168.1.79) en la misma subred; firewall o aislamiento del AP sobre UDP 47623. El QR no depende del descubrimiento: probar con él.
- Comparar contra la versión anterior `ae8dde3` (el código de descubrimiento LAN es idéntico; solo cambió el servidor remoto).
- Ojo: `flutter test` falla el test del radar si hay un host Jam abierto en la app (comparte el puerto UDP).

**2. Artistas (Seguir artistas):**
Corregir defectos visuales en la interfaz gráfica relacionados con mantener la consistencia estética al seguir/dejar de seguir a los artistas.

**3. Pantalla de inicio (HomeScreen):**
Agregar cosas faltantes y solucionar defectos visuales que queden en la pantalla de inicio.

**How to apply:** Revisar `tasks/todo.md` (Fase 6) para el progreso de éstas tareas.
