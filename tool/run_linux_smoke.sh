#!/usr/bin/env bash
# Prueba de arranque de la app de escritorio en Linux (abre la ventana real).
# Los datos de la app van a una carpeta temporal: no toca tu perfil.
# Sin pantalla (CI) se ejecuta bajo xvfb-run si está instalado.
set -euo pipefail
cd "$(dirname "$0")/.."

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export XDG_DATA_HOME="$sandbox/data" XDG_CONFIG_HOME="$sandbox/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

runner=()
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  command -v xvfb-run >/dev/null || { echo "Sin pantalla y sin xvfb-run." >&2; exit 1; }
  runner=(xvfb-run -a)
fi
# Tope corto: si el arranque falla, que no espere los 10 minutos por defecto.
"${runner[@]}" flutter test integration_test/app_smoke_test.dart -d linux --timeout 90s
