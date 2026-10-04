---
name: scrotify-liked-songs-persistence
description: Persistencia de likes en Navidrome
metadata:
  type: project
---

Se resolvió el problema donde los "likes" en Scrotify no persistían al navegar.

**Por qué:** `NavidromeService._setStar` no validaba el código de respuesta HTTP. Cuando el servidor fallaba (ej. 4xx/5xx), la operación parecía exitosa y el estado en memoria se actualizaba, pero no se sincronizaba con el servidor. Al refrescar, los cambios se perdían.

**Cómo aplicar:** Siempre validar `response.statusCode == 200` y lanzar `Exception` si no lo es, permitiendo que el flujo de `toggleStar` revierta el estado optimista en caso de error. Se aplica a todas las llamadas `_client.get` en servicios de networking.
