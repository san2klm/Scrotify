#!/usr/bin/env bash
# Genera el instalador de Windows: installer/output/CrotoWave-Setup-<versión>.exe
#
# Necesita Inno Setup 6 (iscc): en el PATH, o con su ruta en ISCC.
# Se ejecuta desde Git Bash en Windows.
set -euo pipefail
cd "$(dirname "$0")/.."

iscc=${ISCC:-$(command -v iscc || true)}
for candidate in "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" "/c/Program Files/Inno Setup 6/ISCC.exe"; do
  [[ -z "$iscc" && -x "$candidate" ]] && iscc=$candidate
done
if [[ -z "$iscc" ]]; then
  echo "Falta Inno Setup (iscc): instálalo o exporta ISCC=/ruta/ISCC.exe" >&2
  exit 1
fi

ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
commit=$(git rev-parse --short HEAD)
[[ -n "$(git status --porcelain --untracked-files=no)" ]] && commit="$commit-mod"

flutter build windows --release   --dart-define=SCROTIFY_VERSION="$ver"   --dart-define=SCROTIFY_COMMIT="$commit"   --dart-define=SCROTIFY_BUILD_DATE="$(date +%F)"

# stage/ lo ignora git: se regenera en cada build.
rm -rf installer/stage
mkdir -p installer/stage
cp -r build/windows/x64/runner/Release/. installer/stage/

"$iscc" "/DAppVersion=$ver" installer/crotowave.iss
echo "Instalador: installer/output/CrotoWave-Setup-$ver.exe"
