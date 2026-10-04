---
name: scrotify-personalized-recommendations
description: Recomendación de artistas más escuchados
metadata:
  type: project
---

Se implementó el sistema de recomendaciones basado en hábitos de escucha.

**Por qué:** La sección "Recomendados para ti" mostraba tracks estáticos (alfabéticos) sin tener en cuenta qué escucha el usuario.

**Cómo aplicar:** Se usa `PlayerController.mostPlayed` para calcular una puntuación acumulada de reproducciones por cada artista. En `HomeScreen`, las canciones de la librería (`allTracks`) se ordenan según esta puntuación de artista, priorizando los favoritos del usuario.
