#!/usr/bin/env bash
# Genera dos APK separados: teléfono y Android TV.
#   scripts/build_apks.sh            -> ambos
#   scripts/build_apks.sh phone|tv   -> uno solo
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:-all}"
out="build/app/outputs/flutter-apk"
if [[ ! -f android/key.properties ]]; then
  echo "AVISO: sin android/key.properties los APK salen firmados con la clave DEBUG" >&2
  echo "       (válidos para instalar por adb, no para distribuir ni actualizar otra firma)." >&2
fi
ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')

if [[ "$target" == all || "$target" == phone ]]; then
  flutter build apk --release --flavor phone
  cp "$out/app-phone-release.apk" "Scrotify-$ver-phone.apk"
fi
if [[ "$target" == all || "$target" == tv ]]; then
  flutter build apk --release --flavor tv --dart-define=FORCE_TV=true
  cp "$out/app-tv-release.apk" "Scrotify-$ver-tv.apk"
fi
ls -lh Scrotify-"$ver"-*.apk
