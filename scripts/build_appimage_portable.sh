#!/usr/bin/env bash
# AppImage que funciona en otras PC: compila dentro de Debian 12 (Docker) y
# lleva adentro libmpv, ffmpeg y demás (ver bundle_linux_libs.sh).
#   scripts/build_appimage_portable.sh
# Necesita Docker, el SDK de Flutter local y appimagetool (APPIMAGETOOL).
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

tool=${APPIMAGETOOL:-$(command -v appimagetool || true)}
[[ -x "$tool" ]] || { echo "Falta appimagetool (exporta APPIMAGETOOL)" >&2; exit 1; }
flutter_bin=$(readlink -f "$(command -v flutter)")
flutter_sdk=$(dirname "$(dirname "$flutter_bin")")

ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
commit=$(git rev-parse --short HEAD)
[[ -n "$(git status --porcelain --untracked-files=no)" ]] && commit="$commit-mod"

docker build -q -t scrotify-linux-build -f scripts/linux-build.Dockerfile scripts >/dev/null

# Copia limpia del árbol de trabajo (sin tocar build/ de la PC).
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - 2>/dev/null | tar -xf - -C "$work"

docker run --rm -u "$(id -u):$(id -g)" \
  -e HOME=/tmp -e PUB_CACHE=/pubcache -e SCROTIFY_COMMIT="$commit" \
  -e APPIMAGETOOL=/tools/appimagetool -e ARCH=x86_64 \
  -e PATH="$flutter_sdk/bin:/usr/local/bin:/usr/bin:/bin" \
  -v "$flutter_sdk:$flutter_sdk" -v "$HOME/.pub-cache:/pubcache" \
  -v "$tool:/tools/appimagetool:ro" -v "$work:/src" -w /src \
  scrotify-linux-build bash -c 'git config --global --add safe.directory "*" && flutter config --no-analytics >/dev/null 2>&1; flutter pub get >/dev/null && scripts/build_appimage.sh'

cp "$work/Scrotify-$ver-x86_64.AppImage" "$root/"
ls -lh "$root/Scrotify-$ver-x86_64.AppImage"
