#!/usr/bin/env bash
# Verifica y firma los binarios de un release (ver docs/SIGNING.md).
#   scripts/sign_release.sh [carpeta]        (por defecto dist/)
#   scripts/sign_release.sh --init           crea la clave minisign (una vez)
#
# 1. Comprueba que cada APK esté firmado con la clave de CrotoWave (no la debug).
# 2. Genera <carpeta>/SHA256SUMS con todos los binarios.
# 3. Lo firma con minisign: SHA256SUMS.minisig. Se verifica con la clave
#    pública versionada en crotowave-release.pub:
#      minisign -Vm SHA256SUMS -p crotowave-release.pub && sha256sum -c SHA256SUMS
#
# La contraseña de la clave minisign se pide en una ventana (kdialog o zenity)
# o, sin escritorio, en la terminal. Nunca se guarda ni pasa por argumentos.
set -euo pipefail
cd "$(dirname "$0")/.."

key=${MINISIGN_KEY:-$HOME/.config/crotowave-signing/minisign.key}
pub=crotowave-release.pub
# Huella SHA-256 del certificado de la clave Android (docs/SIGNING.md).
expected=0637e6e76df2e78d3bc83f70f3cd48baccb22a52d95cee9391675c9bbd3b4f7d

# ask_password <texto> [nueva]: imprime la contraseña escrita por el usuario.
# Con «nueva» la pide dos veces y exige que coincidan.
ask_password() {
  local text=$1 new=${2:-} p q
  local gui=${DISPLAY:-}${WAYLAND_DISPLAY:-}
  if [[ -n $gui ]] && command -v kdialog >/dev/null; then
    if [[ -n $new ]]; then
      p=$(kdialog --title CrotoWave --newpassword "$text") || return 1
    else
      p=$(kdialog --title CrotoWave --password "$text") || return 1
    fi
  elif [[ -n $gui ]] && command -v zenity >/dev/null; then
    p=$(zenity --password --title="$text") || return 1
    if [[ -n $new ]]; then
      q=$(zenity --password --title="Repetí la contraseña") || return 1
      [[ $p == "$q" ]] || { echo "Las contraseñas no coinciden" >&2; return 1; }
    fi
  else
    read -rsp "$text: " p </dev/tty; echo >&2
    if [[ -n $new ]]; then
      read -rsp "Repetí la contraseña: " q </dev/tty; echo >&2
      [[ $p == "$q" ]] || { echo "Las contraseñas no coinciden" >&2; return 1; }
    fi
  fi
  [[ -n $p ]] || { echo "La contraseña no puede estar vacía" >&2; return 1; }
  printf '%s\n' "$p"
}

command -v minisign >/dev/null || { echo "Falta minisign (sudo pacman -S minisign)" >&2; exit 1; }

if [[ ${1:-} == --init ]]; then
  [[ -e $key ]] && { echo "Ya existe $key: no se pisa" >&2; exit 1; }
  mkdir -p "$(dirname "$key")"; chmod 700 "$(dirname "$key")"
  pw=$(ask_password "Elegí la contraseña de la clave de firma de CrotoWave" new)
  # minisign la pide dos veces; la lee de la entrada estándar.
  printf '%s\n%s\n' "$pw" "$pw" | minisign -G -p "$pub" -s "$key" >/dev/null
  unset pw
  chmod 600 "$key"
  echo "Clave creada: $key (privada, haz copia) y $pub (pública, se versiona)."
  exit 0
fi

dir=${1:-dist}
ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')

shopt -s nullglob
apks=("$dir"/*.apk)
files=("${apks[@]}" "$dir"/*.AppImage "$dir"/*.exe "$dir"/*.zip)
(( ${#files[@]} )) || { echo "No hay binarios en $dir" >&2; exit 1; }

apksigner=$(ls /opt/android-sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
if (( ${#apks[@]} )); then
  [[ -n "$apksigner" ]] || { echo "Falta apksigner para verificar los APK" >&2; exit 1; }
  for apk in "${apks[@]}"; do
    digest=$("$apksigner" verify --print-certs "$apk" 2>/dev/null |
      sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
    if [[ "$digest" != "$expected" ]]; then
      echo "ERROR: $apk no está firmado con la clave de CrotoWave (${digest:-sin firma})" >&2
      exit 1
    fi
  done
  echo "APK firmados con la clave de CrotoWave: ${#apks[@]}"
fi

(cd "$dir" && sha256sum -- "${files[@]##*/}" > SHA256SUMS)
echo "Sumas: $dir/SHA256SUMS (${#files[@]} archivos)"

[[ -f "$key" ]] || { echo "Falta la clave minisign en $key: crea una con $0 --init" >&2; exit 1; }
rm -f "$dir/SHA256SUMS.minisig"
pw=$(ask_password "Contraseña de la clave de firma de CrotoWave")
printf '%s\n' "$pw" | minisign -S -s "$key" -m "$dir/SHA256SUMS" -t "CrotoWave $ver" >/dev/null
unset pw
minisign -V -p "$pub" -m "$dir/SHA256SUMS" >/dev/null
echo "Firma: $dir/SHA256SUMS.minisig"
