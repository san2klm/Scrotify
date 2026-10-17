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
skip+='|libpipewire-0.3|libspa.*|libpulse.*|libasound|libjvm|libglycin.*'
# Todo lo que la pila GTK/Pango del sistema enlaza (texto, imágenes, regex) y el
# runtime de C++: si viaja una copia más vieja (Debian 12) tapa a la del sistema y
# Pango/GLib fallan con «undefined symbol» en distros nuevas (Arch, Fedora…).
skip+='|libharfbuzz.*|libfreetype|libfontconfig|libfribidi|libpcre2.*|libgraphite2'
skip+='|libdatrie|libthai|libpixman.*|libpng16|libtiff|libexpat|libffi'
skip+='|libstdc\+\+|libgcc_s|libssl|libcrypto)\.so'
# libmpv enlaza directo libjack, libsndio, librsvg, libvulkan, libva, libdecor…:
# si faltan en la PC destino, libmpv no carga. Por eso viajan dentro.

declare -A seen
queue=()
add() { [[ -n ${seen[$1]:-} ]] || { seen[$1]=1; queue+=("$1"); }; }

# Raíces: lo que ya está en el bundle, libmpv y los binarios de ffmpeg.
roots=("$appdir"/usr/bin/crotowave "$appdir"/usr/bin/lib/*.so)
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
shipped=()   # archivos de terceros que viajan en el AppImage (para los avisos)
for f in "${queue[@]}"; do
  case "$f" in "$appdir"/*|*/release/bundle/*) continue ;; esac
  shipped+=("$f")
  # Solo las dependencias (no el ejecutable ni los .so del propio bundle).
  case "$f" in /usr/bin/*) continue ;; esac
  cp -L "$f" "$lib/$(basename "$f")"; n=$((n+1))
done
echo "Librerías incluidas: $n ($(du -sh "$lib" | cut -f1))"

# Avisos legales: copyright de cada paquete incluido y dónde está su código
# fuente (obligación de GPL/LGPL al redistribuir binarios). Ver LICENSING.md.
notices="$appdir/THIRD_PARTY_SOURCES.txt"
if ! command -v dpkg-query >/dev/null; then
  echo "AVISO: sin dpkg no se generan los avisos de terceros; para distribuir usa" \
    "scripts/build_appimage_portable.sh (Debian 12)." >&2
  exit 0
fi
declare -A pkgs
for f in "${shipped[@]}"; do
  real=$(readlink -f "$f")
  # Debian 12 usa /usr fusionado: dpkg puede registrar la ruta con o sin /usr.
  pkg=$(dpkg -S "$real" 2>/dev/null || dpkg -S "${real#/usr}" 2>/dev/null ||
    dpkg -S "/usr$real" 2>/dev/null || true)
  pkg=${pkg%%:*}
  [[ -n "$pkg" ]] && pkgs[$pkg]=1 || echo "AVISO: sin paquete para $f" >&2
done
{
  echo "CrotoWave AppImage: componentes de terceros incluidos"
  echo "===================================================="
  echo
  echo "Estos paquetes de Debian 12 viajan dentro del AppImage. El aviso de"
  echo "copyright y la licencia de cada uno están en usr/share/doc/<paquete>/copyright."
  echo "Su código fuente exacto se puede descargar de Debian:"
  echo "  https://snapshot.debian.org/package/<fuente>/<versión>/"
  echo "  o: apt-get source <fuente>=<versión>"
  echo
  printf '%-40s %-36s %s\n' "PAQUETE" "FUENTE" "VERSIÓN"
  for pkg in $(printf '%s\n' "${!pkgs[@]}" | sort); do
    dpkg-query -W -f='${Package} ${source:Package} ${source:Version}\n' "$pkg" |
      awk '{printf "%-40s %-36s %s\n", $1, $2, $3}'
    src=/usr/share/doc/${pkg%%:*}/copyright
    if [[ -f "$src" ]]; then
      mkdir -p "$appdir/usr/share/doc/${pkg%%:*}"
      cp -L "$src" "$appdir/usr/share/doc/${pkg%%:*}/copyright"
    fi
  done
} > "$notices"
echo "Avisos de terceros: ${#pkgs[@]} paquetes (THIRD_PARTY_SOURCES.txt)"
