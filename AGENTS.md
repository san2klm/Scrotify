# AGENTS.md — Directivas y Activación Automática de Skills para CrotoWave

> Este archivo rige el comportamiento de cualquier agente de IA en este proyecto (`CrotoWave`).
> Las directivas y skills detalladas aquí se deben **activar y aplicar de forma autónoma** según la tarea en curso, sin requerir que el usuario las invoque manualmente.

---

## 1. Ciclo de Desarrollo e Ingeniería Autónomo (Addy Osmani + Cloudflare)

El agente debe operar bajo el flujo de ingeniería de software estructurado, activando automáticamente las siguientes skills según la fase de la tarea:

```
  DEFINE             PLAN              BUILD             VERIFY           REVIEW/HARDEN        SHIP
┌─────────────┐    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌───────────────┐   ┌─────────────┐
│interview-me │─▶  │planning-task│─▶ │incremental- │─▶ │test-driven- │─▶ │code-review-   │─▶ │shipping-and-│
│spec-driven  │    │constraint-  │   │  impl       │   │  dev        │   │  quality      │   │  launch     │
│idea-refine  │    │  driven     │   │source-driven│   │debugging-   │   │security-audit │   │observability│
└─────────────┘    └─────────────┘   └─────────────┘   └─────────────┘   └───────────────┘   └─────────────┘
```

### 🎯 Fase A — Definición y Requerimientos (Define)
* **`interview-me`**: Si el usuario plantea un requerimiento ambiguo, nueva funcionalidad o cambio de alcance, interrogar de manera estructurada una pregunta a la vez antes de escribir código.
* **`spec-driven-development`**: Redactar o actualizar especificaciones claras en `tasks/` o `docs/` antes de implementar cambios estructurales.
* **`idea-refine`**: Si una idea o propuesta arquitectónica es vaga o preliminar, aplicar análisis divergente/convergente para refinarla antes de ejecutar.

### 📋 Fase B — Planificación y Restricciones (Plan)
* **`planning-and-task-breakdown`**: Desglosar tareas complejas en subtareas atómicas y ordenadas (como se gestiona en `tasks/todo.md`), estimando impacto y dependencias.
* **`constraint-driven-development`**: Respetar estrictamente las restricciones del proyecto (soporte multiplataforma Linux/Android/Windows/iOS, audio en background, headless CrotoLink Server, dependencias fijas).

### 🛠️ Fase C — Construcción Limpia e Incremental (Build)
* **`incremental-implementation`**: Implementar los cambios en rebanadas delgadas y verificables (*thin vertical slices*), asegurando que cada paso compile y pase tests antes de avanzar al siguiente.
* **`flutter-workflow`**: Flujo de trabajo estándar en Flutter: resolución de dependencias, ciclo de vida del build, hot-reload y ejecución en emuladores/dispositivos.
* **`flutter-apply-architecture-best-practices`**: Estructurar la app según capas desacopladas (UI, Lógica de Negocio y Datos).
* **`source-driven-development`**: Fundamentar cada decisión de API en la documentación oficial (Subsonic API v1.16.1, Flutter framework, `just_audio`, `media_kit`).
* **`api-and-interface-design`**: Mantener contratos limpios y tipados entre servicios (`services/`), controladores de estado (`ChangeNotifier`), y widgets de UI.

### 🧪 Fase D — Verificación y Depuración (Verify)
* **`test-driven-development`** / **`tdd-superpowers`**: Conducir desarrollo con ciclo red-green-refactor estricto para lógica de servicios, parsers y controladores.
* **`debugging-and-error-recovery`** / **`systematic-debugging`**: Ante fallos de tests o builds, aplicar análisis metódico de causa raíz en 4 fases, sin parches superficiales ni conjeturas.
* **`dart-fix-runtime-errors`**: Localizar y corregir excepciones en tiempo de ejecución analizando stack traces activos.
* **`dart-log-failure-parser`**: Interpretar fallos detallados en logs de tests unitarios y de integración de Dart/Flutter.
* **`doubt-driven-development`**: Validar activamente suposiciones y verificar que los tests realmente fallen si la lógica falla.

### 🔍 Fase E — Revisión, Calidad y Simplificación (Review)
* **`code-review-and-quality`**: Evaluación previa al cierre en 5 dimensiones: corrección, legibilidad, arquitectura, seguridad y rendimiento.
* **`code-simplification`**: Refactorizar código recién escrito para eliminar duplicaciones y complejidad accidental, priorizando claridad (*clarity over cleverness*).

### 🛡️ Fase F — Seguridad y Auditoría (Harden & Audit)
* **`security-and-hardening`**: Proteger credenciales en `SecureStorage`, validación de tokens MD5+salt para Subsonic, sanitización de inputs y prevención de fugas de secretos en logs.
* **`security-audit`** *(Cloudflare)*: 
  * Auditar comunicación en red (HTTP Subsonic y WebSockets en CrotoLink).
  * Verificar aislamiento de datos entre perfiles locales (`server_profiles`).
  * Aplicar validación estricta de esquemas JSON en mensajes de CrotoLink Server y cliente para evitar inyecciones o estados corruptos.

### 🚀 Fase G — Lanzamiento y Observabilidad (Ship & Observe)
* **`shipping-and-launch`**: Lista de comprobación previa a dar por cerrada una fase o release.
* **`observability-and-instrumentation`**: Registro de errores y métricas diagnósticas en controladores de reproducción y conexión para facilitar soporte.

---

## 2. Especialización de Dominio en CrotoWave

Además del ciclo general, el agente debe activar las skills técnicas específicas según el subsistema intervenido:

### 🎨 UI, Pantallas, Layouts y Correcciones Visuales
* **Skills:** `flutter-fix-layout-issues`, `flutter-build-responsive-layout`, `flutter-adaptive-ui`, `frontend-ui-engineering`, `flutter-setup-declarative-routing`, `flutter-setup-localization`.
* **Directivas:** Diagnosticar RenderFlex overflows, desacoplar widgets con `LayoutBuilder` y `MediaQuery` para Desktop vs Móvil, soporte para hover de ratón y atajos.

### ✨ Animaciones, Espectros y Micro-interacciones
* **Skills:** `flutter-animations`, `improve-animations`, `crotowave-dev`, `songsee`, `audio-video-sync`.
* **Directivas:** `AnimationController` con tickers a 60fps, física de muelles (*springs*), decodificación ffmpeg local cacheada en desktop y curva procedural determinística en móvil (`Random` + hash `track.id`).

### 📱 Testing en Emulador y Automatización Android (`mobile-mcp`)
* **Skills:** `android-mobile-mcp`, `flutter-workflow`, `flutter-add-integration-test`, `adversarial-ux-test`.
* **Directivas:**
  * **Ejecutable del Emulador:** Usar obligatoriamente `/opt/android-sdk/emulator/emulator` (nunca el script deprecado en `/opt/android-sdk/tools/emulator`).
  * **Inspección de UI:** Usar `mobile_list_elements_on_screen` antes de tomar screenshots para identificar refs y coordenadas seguras de widgets.
  * **Interacción Autónoma:** Utilizar `mobile_click_on_screen_at_coordinates`, `mobile_type_keys` y `mobile_batch_commands`.
  * **Diagnóstico de Estabilidad:** Monitorear cuelgues con `mobile_list_crashes`, `mobile_get_crash` y `mobile_get_device_logs`.
  * **ADB Unificado:** Asegurar que las llamadas de adb usen `/opt/android-sdk/platform-tools/adb` para prevenir desincronizaciones de servidor.

### 📻 CrotoWave CrotoLink & Sincronización en Tiempo Real
* **Skills:** `websocket-engineer`, `docker-management`.
* **Directivas:** Esquemas tipados de mensajes, compensación de latencia, reconexión con retroceso exponencial, heartbeats/ping-pong, tests en `crotolink-server` con `node --test` y Docker Compose.

### 🧪 Pruebas Automatizadas y Análisis Estático
* **Skills:** `flutter-add-widget-test`, `flutter-add-integration-test`, `dart-add-unit-test`, `dart-generate-test-mocks`, `dart-run-static-analysis`, `dart-log-failure-parser`.
* **Directivas:** En tests con `AnimationController`, avanzar frames con `await tester.pump(Duration(milliseconds: 16))`. Mocks desacoplados de red. `flutter analyze` obligatorio con 0 errores/warnings.

### 📦 Modelos de Datos, API Subsonic y FFI Nativo
* **Skills:** `flutter-implement-json-serialization`, `dart-setup-ffi-assets`.
* **Directivas:** Serialización con `json_annotation` y `build_runner`. Bindings C/C++ vía `dart:ffi` y `media_kit_libs_*`.

---

## 3. Invariantes Estrictos del Proyecto CrotoWave

1. **Modelos canónicos:** Los tipos canónicos `Track`, `Album` y `Artist` son los definidos en `lib/services/navidrome_service.dart`. No crear modelos duplicados ni importar copias paralelas.
2. **Imports limpios:** Usar siempre `package:crotowave/...`, nunca rutas relativas `../lib/...` desde `test/` (rompe el análisis estático).
3. **SecureStorage:** Usar exclusivamente los métodos públicos estáticos: `SecureStorage.secureRead`, `SecureStorage.secureWrite`, `SecureStorage.secureDelete`.
4. **Provider:** Todo nuevo servicio principal debe extender `ChangeNotifier` y registrarse en el `MultiProvider` de `lib/main.dart` respetando el orden de dependencias.
5. **Verificación de archivos:** Los subagentes pueden reportar escrituras falsas; siempre comprobar mutaciones reales con `git status --porcelain`.
6. **Carga segura en Home:** Los futuros de Home (géneros, recientes) deben manejar la falta de conexión devolviendo listas vacías sin lanzar errores no controlados.

---

## 4. Criterios de Aceptación (Definition of Done)

Antes de marcar una tarea como completada en `tasks/todo.md` o presentarla al usuario:
1. `flutter analyze` debe pasar limpio (0 errores, 0 warnings).
2. Los tests relevantes en `test/` deben pasar exitosamente (`flutter test`).
3. Registrar cambios y avance de fases en `tasks/todo.md` de forma concisa.
