#!/usr/bin/env bash
# Genera los APK de teléfono y de Android TV, uno por arquitectura.
#   scripts/build_apks.sh                 -> ambos
#   scripts/build_apks.sh phone|tv        -> uno solo
#   scripts/build_apks.sh phone --universal
#       -> un único APK con todas las arquitecturas (más pesado; para emulador)
#
# Salida en la raíz: Scrotify-<versión>-<sabor>-<abi>.apk
#   phone: arm64-v8a            tv: arm64-v8a y armeabi-v7a (Chromecast HD)
# Instalar con tool/install_android.sh, que elige el APK correcto.
set -euo pipefail
cd "$(dirname "$0")/.."

target=all
universal=0
for arg in "$@"; do
  case "$arg" in
    all|phone|tv) target=$arg ;;
    --universal) universal=1 ;;
    *) echo "Uso: $0 [all|phone|tv] [--universal]" >&2; exit 2 ;;
  esac
done

out="build/app/outputs/flutter-apk"
if [[ ! -f android/key.properties ]]; then
  echo "AVISO: sin android/key.properties los APK salen firmados con la clave DEBUG" >&2
  echo "       (válidos para instalar por adb, no para distribuir ni actualizar otra firma)." >&2
fi

ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
commit=$(git rev-parse --short HEAD)
[[ -n "$(git status --porcelain --untracked-files=no)" ]] && commit="$commit-mod"
# Crece con cada commit, así una instalación nueva nunca es un «downgrade».
# Por arquitectura Flutter le suma 1000 (armv7) o 2000 (arm64).
build_number=$((10000 + $(git rev-list --count HEAD)))

# Sin android/key.properties Gradle rechaza el release; aquí es una instalación
# local por adb, así que se permite la clave debug de forma explícita.
if [[ ! -f android/key.properties ]]; then
  echo "AVISO: sin android/key.properties; el APK se firma con la clave debug (solo para adb)." >&2
  export ORG_GRADLE_PROJECT_allowDebugSigning=true
fi

build() { # sabor  plataformas  [defines extra...]
  local flavor=$1 platforms=$2
  shift 2
  local mode=(--split-per-abi --target-platform "$platforms")
  [[ $universal == 1 ]] && mode=()
  flutter build apk --release --flavor "$flavor" "${mode[@]}" \
    --build-number "$build_number" \
    --dart-define=SCROTIFY_VERSION="$ver" \
    --dart-define=SCROTIFY_COMMIT="$commit" \
    --dart-define=SCROTIFY_BUILD_DATE="$(date +%F)" \
    "$@"
  rm -f "Scrotify-$ver-$flavor"*.apk
  if [[ $universal == 1 ]]; then
    cp "$out/app-$flavor-release.apk" "Scrotify-$ver-$flavor-universal.apk"
  else
    local abi
    for abi in ${platforms//,/ }; do
      case "$abi" in
        android-arm64) abi=arm64-v8a ;;
        android-arm) abi=armeabi-v7a ;;
      esac
      cp "$out/app-$abi-$flavor-release.apk" "Scrotify-$ver-$flavor-$abi.apk"
    done
  fi
}

if [[ "$target" == all || "$target" == phone ]]; then
  build phone android-arm64
fi
if [[ "$target" == all || "$target" == tv ]]; then
  build tv android-arm64,android-arm --dart-define=FORCE_TV=true
fi
echo "Build $ver ($commit), número $build_number"
ls -lh Scrotify-"$ver"-*.apk
