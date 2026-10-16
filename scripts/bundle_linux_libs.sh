#!/usr/bin/env bash
# Copia dentro de un AppDir las librerías y binarios que la app necesita y que
# una PC cualquiera puede no tener: libmpv (+ffmpeg), ffmpeg/ffprobe, keybinder…
#   scripts/bundle_linux_libs.sh <appdir>
# Se dejan fuera las del sistema que no conviene mezclar (glibc, gráficos,
# X11/Wayland, pila GTK/GLib, audio del sistema): toda PC de escritorio las trae.
set -euo pipefail
appdir=${1:?uso: $0 <appdir>}
export PATH="$PATH:/sbin:/usr/sbin"   # ldconfig no siempre está en el PATH
lib="$appdir/usr/lib"
mkdir -p "$lib"

skip='^(ld-linux.*|libc|libm|libdl|libpthread|librt|libutil|libresolv|libnsl|libanl|libthread_db'
skip+='|libGL|libGLX|libGLdispatch|libEGL|libGLESv2|libOpenGL|libdrm.*|libgbm'
skip+='|libX.*|libxcb.*|libxkbcommon.*|libwayland.*'
skip+='|libgtk-3|libgdk-3|libgdk_pixbuf-2.0|libpango.*|libcairo.*|libatk.*|libatspi|libglib-2.0|libgobject-2.0'
skip+='|libgio-2.0|libgmodule-2.0|libepoxy|libcloudproviders|libdbus-1|libsystemd|libmount|libblkid|libselinux'
skip+='|libpipewire-0.3|libspa.*|libpulse.*|libasound|libjvm|libglycin.*)\.so'
# libmpv enlaza directo libjack, libsndio, librsvg, libvulkan, libva, libdecor…:
# si faltan en la PC destino, libmpv no carga. Por eso viajan dentro.

declare -A seen
queue=()
add() { [[ -n ${seen[$1]:-} ]] || { seen[$1]=1; queue+=("$1"); }; }

# Raíces: lo que ya está en el bundle, libmpv y los binarios de ffmpeg.
roots=("$appdir"/usr/bin/navidrome_client "$appdir"/usr/bin/lib/*.so)
mpv=$(ldconfig -p | awk '/libmpv\.so\.2 /{print $NF}' | head -1 || true)
[[ -n "$mpv" ]] || { echo "Falta libmpv en el sistema" >&2; exit 1; }
roots+=("$mpv")
for b in ffmpeg ffprobe; do
  p=$(command -v "$b" || true)
  [[ -n "$p" ]] || { echo "Falta $b en el sistema" >&2; exit 1; }
  cp -L "$p" "$appdir/usr/bin/$b"
  roots+=("$p")
done
kb=$(ldconfig -p | awk '/libkeybinder-3\.0\.so\.0 /{print $NF}' | head -1 || true)
[[ -n "$kb" ]] && roots+=("$kb")
for r in "${roots[@]}"; do add "$r"; done

i=0
while (( i < ${#queue[@]} )); do
  f=${queue[i]}; i=$((i+1))
  while read -r dep; do
    [[ -n "$dep" ]] || continue
    name=$(basename "$dep")
    [[ $name =~ $skip ]] && continue
    [[ -e "$appdir/usr/bin/lib/$name" ]] && continue   # ya viene en el bundle
    add "$dep"
  done < <(ldd "$f" 2>/dev/null | sed -n 's/.*=> \(\/.*\) (0x.*/\1/p')
done

n=0
for f in "${queue[@]}"; do
  # Solo las dependencias (no el ejecutable ni los .so del propio bundle).
  case "$f" in "$appdir"/*|/usr/bin/*|*/release/bundle/*) continue ;; esac
  cp -L "$f" "$lib/$(basename "$f")"; n=$((n+1))
done
echo "Librerías incluidas: $n ($(du -sh "$lib" | cut -f1))"
