#!/usr/bin/env bash
# Ejecuta las pruebas de integración de Android en UN dispositivo concreto.
#
#   tool/run_android_integration.sh emulator-5554
#
# El identificador es obligatorio a propósito: las pruebas escriben archivos en
# /storage/emulated/0/Music y conceden «acceso a todos los archivos» a la app,
# y no deben ejecutarse por error en un teléfono con tu música real.
set -euo pipefail

ADB=${ADB:-/opt/android-sdk/platform-tools/adb}
PACKAGE=com.example.navidrome_client
DEVICE=${1:-}

if [[ -z "$DEVICE" ]]; then
  echo "Uso: $0 <id-del-dispositivo>   (mira 'adb devices')" >&2
  exit 2
fi
if [[ "$DEVICE" != emulator-* && "${ALLOW_REAL_DEVICE:-}" != "1" ]]; then
  echo "'$DEVICE' no parece un emulador. Si quieres usar un dispositivo real," >&2
  echo "vuelve a ejecutar con ALLOW_REAL_DEVICE=1 (escribirá en su carpeta Music)." >&2
  exit 2
fi

cd "$(dirname "$0")/.."
# Instala primero la app para poder conceder el permiso antes de la prueba.
flutter build apk --debug --flavor phone >/dev/null
"$ADB" -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-phone-debug.apk >/dev/null
"$ADB" -s "$DEVICE" shell appops set "$PACKAGE" MANAGE_EXTERNAL_STORAGE allow

flutter test integration_test/local_music_recovery_test.dart \
  --flavor phone -d "$DEVICE"
