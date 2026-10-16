#!/usr/bin/env bash
# Genera el AppImage de Linux: Scrotify-<versión>-x86_64.AppImage en la raíz.
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
if [[ -z "${SCROTIFY_COMMIT:-}" ]]; then
  commit=$(git rev-parse --short HEAD)
  [[ -n "$(git status --porcelain --untracked-files=no)" ]] && commit="$commit-mod"
else
  commit=$SCROTIFY_COMMIT   # lo fija build_appimage_portable.sh (sin repo git)
fi

flutter build linux --release \
  --dart-define=SCROTIFY_VERSION="$ver" \
  --dart-define=SCROTIFY_COMMIT="$commit" \
  --dart-define=SCROTIFY_BUILD_DATE="$(date +%F)"

appdir=$(mktemp -d)
trap 'rm -rf "$appdir"' EXIT
mkdir -p "$appdir/usr/bin"
cp -a build/linux/x64/release/bundle/. "$appdir/usr/bin/"
cp assets/icons/scrotify_app_icon.png "$appdir/scrotify.png"
ln -s scrotify.png "$appdir/.DirIcon"
cat > "$appdir/scrotify.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Scrotify
Comment=Cliente Navidrome/Subsonic
Exec=navidrome_client
Icon=scrotify
Categories=AudioVideo;Audio;Player;
DESKTOP
scripts/bundle_linux_libs.sh "$appdir"
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
# Librerías y ffmpeg/ffprobe viajan dentro del AppImage.
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$HERE/usr/bin:$PATH"
exec "$HERE/usr/bin/navidrome_client" "$@"
APPRUN
chmod +x "$appdir/AppRun"

out="Scrotify-$ver-x86_64.AppImage"
# --appimage-extract-and-run: funciona también sin FUSE.
ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out" >/dev/null
chmod +x "$out"
echo "Build $ver ($commit)"
ls -lh "$out"
