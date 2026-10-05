---
name: android-mobile-mcp
description: >-
  Automatización y pruebas E2E en Android usando mobile-mcp y Android Emulator.
  Usar para inspeccionar la UI de Scrotify en Android, ejecutar flujos de prueba,
  verificar elementos en pantalla, detectar cuelgues (crashes) y validar diseño responsivo.
---

# Android Testing y Automatización con `mobile-mcp`

Esta skill proporciona las directivas y flujo de trabajo para interactuar de forma autónoma con el emulador Android o dispositivos físicos mediante el servidor MCP `mobile-mcp`.

## 1. Verificación y Preparación del Entorno

1. **Binario del Emulador y PATH**:
   - Usar siempre `/opt/android-sdk/emulator/emulator` (nunca el ejecutable deprecado en `tools/emulator`).
   - Asegurarse de que `/opt/android-sdk/platform-tools` tenga precedencia sobre `/usr/bin` para evitar conflictos de versiones de ADB.
2. **Levantar el Emulador si no está activo**:
   - Headless (pruebas automáticas en background):
     ```bash
     /opt/android-sdk/emulator/emulator -avd pixel_test -no-snapshot-load -no-boot-anim -gpu swiftshader_indirect -no-audio -no-window &
     ```
   - Con ventana (revisión visual interactiva):
     ```bash
     /opt/android-sdk/emulator/emulator -avd pixel_test -gpu host &
     ```
   - Esperar a que ADB lo reconozca:
     ```bash
     adb wait-for-device
     ```

## 2. Herramientas MCP de `mobile-mcp`

El servidor `mobile-mcp` expone herramientas lazily-loaded llamadas con `call_mcp_tool(ServerName: "mobile-mcp", ToolName: ...)`.

### Flujo de Ejecución:
1. **Listar dispositivos**:
   - Tool: `mobile_list_available_devices`
   - Parámetros: `{}`
   - Obtiene el ID del dispositivo (ej. `pixel_test` o `emulator-5554`).
2. **Compilar e Instalar Scrotify**:
   - Ejecutar en terminal: `flutter install -d emulator-5554` o compilar APK de depuración:
     ```bash
     flutter build apk --debug
     adb install -r build/app/outputs/flutter-apk/app-debug.apk
     ```
3. **Lanzar la App**:
   - Tool: `mobile_launch_app`
   - Parámetros: `{"device": "pixel_test", "packageName": "com.example.navidrome_client"}`
4. **Inspección de la UI (Accesibilidad)**:
   - Tool: `mobile_list_elements_on_screen`
   - Parámetros: `{"device": "pixel_test"}`
   - **Regla de oro**: Siempre preferir inspeccionar el árbol de elementos antes de hacer capturas de pantalla. Proporciona coordenadas exactas, textos, identificadores y etiquetas de accesibilidad resistentes a cambios de escala.
5. **Interacción con la UI**:
   - Click/Tap: `mobile_click_on_screen_at_coordinates` con `x` e `y`.
   - Escribir texto: `mobile_type_keys` con `text`.
   - Desplazar / Scroll: `mobile_swipe_on_screen` con coordenadas de inicio y fin.
   - Acciones por lotes: `mobile_batch_commands` para encadenar taps y textos sin sobrecarga de ida y vuelta.
6. **Capturas y Verificación Visual**:
   - Tool: `mobile_take_screenshot` para verificar la apariencia gráfica final o cuando los elementos no se expongan en el árbol semántico.
7. **Monitoreo de Errores y Crashes**:
   - Tool: `mobile_list_crashes` y `mobile_get_crash`
   - Tool: `mobile_get_device_logs` filtrando por tags de Flutter / Dart.

## 3. Resolución de Problemas Frecuentes
- **Conflictos de ADB**: Si `mobile_list_available_devices` devuelve lista vacía a pesar de que el emulador está abierto, matar el servidor adb con `/opt/android-sdk/platform-tools/adb kill-server` y reiniciar.
- **RenderFlex Overflows**: Comprobar que la resolución del AVD sea de teléfono moderno (1080x2400 / 420 dpi) y no la miniatura por defecto (320x640).
