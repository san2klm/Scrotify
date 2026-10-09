#!/usr/bin/env bash
# Instala Scrotify en UN dispositivo concreto y comprueba que arranca.
#
#   tool/install_android.sh <id-del-dispositivo> phone|tv
#   tool/install_android.sh <id> phone --check     (solo valida, no instala)
#   tool/install_android.sh <id> phone --no-launch (instala sin abrir la app:
#                                    no interrumpe lo que haya en pantalla,
#                                    pero tampoco comprueba el arranque)
#
# El id es obligatorio: suele haber varios dispositivos por adb (teléfono,
# tele, emulador) con arquitecturas distintas, y un APK de 32 bits instalado en
# un teléfono de 64 hace que la app se cierre al abrir. Este script elige el
# APK de la arquitectura del dispositivo, verifica que trae el motor de
# Flutter para ella, instala conservando los datos (-r) y falla si la app no
# sigue viva unos segundos después de abrirla.
#
# Los APK se generan antes con scripts/build_apks.sh.
set -euo pipefail

ADB=${ADB:-/opt/android-sdk/platform-tools/adb}
PACKAGE=com.example.navidrome_client
DEVICE=${1:-}
FLAVOR=${2:-}
CHECK_ONLY=0
LAUNCH=1
[[ "${3:-}" == "--check" ]] && CHECK_ONLY=1
[[ "${3:-}" == "--no-launch" ]] && LAUNCH=0

if [[ -z "$DEVICE" || ( "$FLAVOR" != phone && "$FLAVOR" != tv ) ]]; then
  echo "Uso: $0 <id-del-dispositivo> phone|tv [--check|--no-launch]" >&2
  echo "Dispositivos conectados:" >&2
  "$ADB" devices -l | sed 1d >&2
  exit 2
fi

cd "$(dirname "$0")/.."
adb() { "$ADB" -s "$DEVICE" "$@"; }

if ! adb get-state >/dev/null 2>&1; then
  echo "No hay ningún dispositivo '$DEVICE' conectado." >&2
  exit 1
fi

abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
model=$(adb shell getprop ro.product.model | tr -d '\r')
is_tv=0
features=$(adb shell pm list features)
grep -q 'android.software.leanback' <<<"$features" && is_tv=1
if [[ $FLAVOR == tv && $is_tv == 0 ]]; then
  echo "'$model' no es un Android TV: usa el sabor phone." >&2
  exit 1
fi
if [[ $FLAVOR == phone && $is_tv == 1 ]]; then
  echo "'$model' es un Android TV: usa el sabor tv." >&2
  exit 1
fi

ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
apk="Scrotify-$ver-$FLAVOR-$abi.apk"
[[ -f "$apk" ]] || apk="Scrotify-$ver-$FLAVOR-universal.apk"
if [[ ! -f "$apk" ]]; then
  echo "No hay APK de $FLAVOR para $abi ($model)." >&2
  echo "Genéralo con: scripts/build_apks.sh $FLAVOR   (o con --universal para un emulador)" >&2
  exit 1
fi
# Sin tubería directa a grep -q: con pipefail cortaría a unzip y daría falso.
contents=$(unzip -l "$apk")
if ! grep -q "lib/$abi/libflutter.so" <<<"$contents"; then
  echo "$apk no trae el motor de Flutter para $abi: no se instala." >&2
  exit 1
fi
echo "$model ($abi) <- $apk"
[[ $CHECK_ONLY == 1 ]] && { echo "Comprobación correcta; no se instala (--check)."; exit 0; }

adb install -r "$apk" | tail -1
if [[ $LAUNCH == 0 ]]; then
  echo "Instalada sin abrir: $(adb shell dumpsys package "$PACKAGE" | grep -m1 versionCode | xargs)"
  exit 0
fi

# Arranque: la app debe seguir viva y sin cierres nuevos.
since=$(adb shell date +%s | tr -d '\r')
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER \
  -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1
sleep 8
pid=$(adb shell pidof "$PACKAGE" | tr -d '\r' || true)
crashes=$(adb logcat -b crash -d -t "$since.0" 2>/dev/null | grep -c "Process: $PACKAGE" || true)
if [[ -z "$pid" || "$crashes" != 0 ]]; then
  echo "La app no quedó abierta tras instalar (cierres registrados: $crashes)." >&2
  adb logcat -b crash -d -t "$since.0" 2>/dev/null | grep -m5 -E "Caused by|FATAL" >&2 || true
  exit 1
fi
echo "Instalada y abierta (pid $pid): $(adb shell dumpsys package "$PACKAGE" | grep -m1 versionCode | xargs)"
