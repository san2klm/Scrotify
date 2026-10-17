#!/usr/bin/env bash
# Genera el AppImage de Linux: dist/CrotoWave-<versión>-LINUX-x86_64.AppImage
# (siempre en dist/; firmar con scripts/sign_release.sh).
#
# Necesita `appimagetool` (https://github.com/AppImage/appimagetool/releases):
# en el PATH, o indicando su ruta en APPIMAGETOOL.
set -euo pipefail
cd "$(dirname "$0")/.."

tool=${APPIMAGETOOL:-$(command -v appimagetool || true)}
if [[ -z "$tool" || ! -x "$tool" ]]; then
  echo "Falta appimagetool: instálalo o exporta APPIMAGETOOL=/ruta/appimagetool" >&2
  exit 1
fi

ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
if [[ -z "${CROTOWAVE_COMMIT:-}" ]]; then
  commit=$(git rev-parse --short HEAD)
  [[ -n "$(git status --porcelain --untracked-files=no)" ]] && commit="$commit-mod"
else
  commit=$CROTOWAVE_COMMIT   # lo fija build_appimage_portable.sh (sin repo git)
fi

flutter build linux --release \
  --dart-define=CROTOWAVE_VERSION="$ver" \
  --dart-define=CROTOWAVE_COMMIT="$commit" \
  --dart-define=CROTOWAVE_BUILD_DATE="$(date +%F)"

appdir=$(mktemp -d)
trap 'rm -rf "$appdir"' EXIT
mkdir -p "$appdir/usr/bin"
cp -a build/linux/x64/release/bundle/. "$appdir/usr/bin/"
cp assets/icons/crotowave_app_icon.png "$appdir/crotowave.png"
ln -s crotowave.png "$appdir/.DirIcon"
cat > "$appdir/crotowave.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=CrotoWave
Comment=Cliente Navidrome/Subsonic
Exec=crotowave
Icon=crotowave
Categories=AudioVideo;Audio;Player;
DESKTOP
scripts/bundle_linux_libs.sh "$appdir"
cp LICENSE LICENSING.md "$appdir/"   # licencia propia junto a la de terceros
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
# Librerías y ffmpeg/ffprobe viajan dentro del AppImage.
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$HERE/usr/bin:$PATH"
exec "$HERE/usr/bin/crotowave" "$@"
APPRUN
chmod +x "$appdir/AppRun"

mkdir -p dist
out="dist/CrotoWave-$ver-LINUX-x86_64.AppImage"
# --appimage-extract-and-run: funciona también sin FUSE.
ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out" >/dev/null
chmod +x "$out"
echo "Build $ver ($commit)"
ls -lh "$out"
