#!/usr/bin/env bash
# Pasa la app de una instalación vieja a la definitiva (cloud.templo.crotowave,
# clave propia) sin perder datos: perfiles de servidor, ajustes, caché offline,
# estadísticas…
#
#   tool/migrate_android_signing.sh <id> phone|tv backup
#   tool/migrate_android_signing.sh <id> phone|tv restore
#
# Instalación vieja: por defecto com.example.navidrome_client (clave debug).
# Otra: FROM_APP=<id> y, si no se firmó con la clave debug, FROM_KEY=<su
# key.properties>.
#
# backup:  instala ENCIMA de la vieja el mismo APK pero depurable y en modo
#          migración (misma firma: conserva los datos), le pide exportar el
#          almacén seguro y copia todo a migration-backup/<serie>/.
# restore: instala la nueva en modo migración, le copia los datos, importa el
#          almacén seguro, le da los mismos permisos y la actualiza al release
#          normal (no depurable). Necesita android/key.properties.
#
# La app vieja NO se desinstala: se borra a mano cuando la nueva esté bien.
# Ver docs/SIGNING.md («Migrar una instalación existente»).
set -euo pipefail

ADB=${ADB:-/opt/android-sdk/platform-tools/adb}
OLD=${FROM_APP:-com.example.navidrome_client}
OLD_KEY=${FROM_KEY:-}
NEW=cloud.templo.crotowave
[[ -z $OLD_KEY || -f $OLD_KEY ]] || { echo "ERROR: no existe $OLD_KEY" >&2; exit 1; }
DEVICE=${1:-}
FLAVOR=${2:-}
STEP=${3:-}

fail() { echo "ERROR: $*" >&2; exit 1; }
if [[ -z "$DEVICE" || ( "$FLAVOR" != phone && "$FLAVOR" != tv ) ||
      ( "$STEP" != backup && "$STEP" != restore ) ]]; then
  echo "Uso: $0 <id-del-dispositivo> phone|tv backup|restore" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
adb() { "$ADB" -s "$DEVICE" "$@"; }
adb get-state >/dev/null 2>&1 || fail "no hay ningún dispositivo '$DEVICE' conectado"

abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
case "$abi" in
  arm64-v8a) platform=android-arm64 ;;
  armeabi-v7a) platform=android-arm ;;
  x86_64) platform=android-x64 ;;
  *) fail "arquitectura no soportada: $abi" ;;
esac
serial=$(adb shell getprop ro.serialno | tr -d '\r')
dir="migration-backup/$serial-$FLAVOR-$OLD"
mkdir -p "$dir"
chmod 700 migration-backup "$dir"

ver=$(grep -E '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
commit=$(git rev-parse --short HEAD)
[[ -n "$(git status --porcelain --untracked-files=no)" ]] && commit="$commit-mod"
build_number=$((10000 + $(git rev-list --count HEAD)))

# build_apk <salida> migration|normal [VAR=valor de Gradle...]
build_apk() {
  local out=$1 mode=$2
  shift 2
  local extra=() apks=build/app/outputs/flutter-apk build=release
  # `run-as` solo entra en apps depurables: los de migración son builds debug.
  # El que queda instalado al final es el release normal.
  [[ $mode == migration ]] && { extra+=(--dart-define=CROTOWAVE_SIGNING_MIGRATION=true); build=debug; }
  [[ $FLAVOR == tv ]] && extra+=(--dart-define=FORCE_TV=true)
  rm -f "$apks/app-$abi-$FLAVOR-"*.apk   # que no se copie uno viejo
  env "$@" flutter build apk "--$build" --flavor "$FLAVOR" --split-per-abi \
    --target-platform "$platform" --build-number "$build_number" \
    --dart-define=CROTOWAVE_VERSION="$ver" \
    --dart-define=CROTOWAVE_COMMIT="$commit" \
    --dart-define=CROTOWAVE_BUILD_DATE="$(date +%F)" \
    "${extra[@]}"
  cp "$apks/app-$abi-$FLAVOR-$build.apk" "$out"
  # Debe llevar el motor de Flutter de la arquitectura del dispositivo.
  unzip -l "$out" "lib/$abi/libflutter.so" >/dev/null || fail "$out no trae libflutter.so para $abi"
}

installed() { adb shell pm path "$1" 2>/dev/null | grep package:; } >/dev/null

# wait_file <paquete> <ruta> present|absent
wait_file() {
  local i
  for i in $(seq 60); do
    if adb shell run-as "$1" ls "$2" >/dev/null 2>&1; then
      [[ $3 == present ]] && return 0
    else
      [[ $3 == absent ]] && return 0
    fi
    sleep 1
  done
  return 1
}

launch() {
  adb shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

if [[ $STEP == backup ]]; then
  installed "$OLD" || fail "$OLD no está instalada en $DEVICE"
  legacy=(ORG_GRADLE_PROJECT_legacyAppId="$OLD")
  [[ -n $OLD_KEY ]] && legacy+=(ORG_GRADLE_PROJECT_legacyKeyProperties="$OLD_KEY")
  build_apk "$dir/legacy-migration.apk" migration "${legacy[@]}"
  # Misma clave que la instalada: es una actualización y conserva datos. Si la
  # clave no coincide (p. ej. otra clave debug de otra PC) esto falla sin
  # tocar nada.
  adb install -r "$dir/legacy-migration.apk"
  adb shell am force-stop "$OLD"
  # Un arranque para que el build de migración deje su carpeta de datos en 700:
  # `run-as` no entra si es legible por otros.
  if ! adb shell run-as "$OLD" true >/dev/null 2>&1; then
    launch "$OLD"
    for _ in $(seq 30); do
      sleep 2
      adb shell run-as "$OLD" true >/dev/null 2>&1 && break
    done
    adb shell am force-stop "$OLD"
    adb shell run-as "$OLD" true || fail "run-as no puede entrar en $OLD"
  fi

  # Permisos que tenía, para dárselos igual a la nueva.
  {
    adb shell dumpsys package "$OLD" | tr -d '\r' |
      sed -n 's/^ *\(android\.permission\.[A-Z_]*\): granted=true.*/perm \1/p' | sort -u
    adb shell appops get "$OLD" MANAGE_EXTERNAL_STORAGE | tr -d '\r' |
      grep ': allow' >/dev/null && echo "appop MANAGE_EXTERNAL_STORAGE"
    adb shell dumpsys deviceidle whitelist | tr -d '\r' | grep ",$OLD," >/dev/null &&
      echo "deviceidle"
  } > "$dir/permissions.txt" || true

  adb shell run-as "$OLD" touch files/signing_migration.export
  launch "$OLD"
  wait_file "$OLD" files/signing_migration_export.json present ||
    fail "la app no exportó el almacén seguro (¿abrió bien?)"
  sleep 2
  adb shell am force-stop "$OLD"

  echo "Tamaño de los datos:"
  adb shell run-as "$OLD" du -sh . | tr -d '\r'
  adb exec-out run-as "$OLD" sh -c \
    'tar -cf - $(ls -A | grep -vxE "cache|code_cache")' > "$dir/data.tar"
  tar -tf "$dir/data.tar" | grep 'files/signing_migration_export.json' >/dev/null ||
    fail "la copia no tiene el almacén seguro exportado"
  chmod 600 "$dir/data.tar"
  # Archivos de la app en /sdcard/Android/data (se borran al desinstalar).
  rm -rf "$dir/external"
  adb pull "/sdcard/Android/data/$OLD" "$dir/external" >/dev/null 2>&1 || true
  echo "Copia lista en $dir ($(du -sh "$dir" | cut -f1))."
  echo "Contiene tus contraseñas en claro: no la compartas."
  exit 0
fi

# ---- restore ----
[[ -f android/key.properties ]] || fail "falta android/key.properties (ver docs/SIGNING.md)"
[[ -f "$dir/data.tar" ]] || fail "no hay copia en $dir: corre antes el paso backup"
installed "$NEW" && fail "$NEW ya está instalada: restore la pisaría. Desinstálala antes si es una prueba."

build_apk "$dir/new-migration.apk" migration ORG_GRADLE_PROJECT_signingMigration=true
build_apk "$dir/new-release.apk" normal

work=$(mktemp -d)
trap 'rm -rf "$work"; adb shell rm -f /data/local/tmp/crotowave-migration.tar >/dev/null 2>&1 || true' EXIT
mkdir "$work/data"
tar -xf "$dir/data.tar" -C "$work/data"
mv "$work/data/files/signing_migration_export.json" "$work/data/files/signing_migration_import.json"
# El almacén seguro viejo está cifrado con claves del Keystore de la otra
# instalación: no sirve. Se recrea desde el JSON importado.
rm -f "$work/data/shared_prefs/FlutterSecure"*
# Lo que extrajo el build debug de migración (motor y kernel): la app nueva lo
# regenera, y un res_timestamp ajeno le impediría extraer los suyos.
rm -rf "$work/data/app_flutter/flutter_assets" "$work/data/app_flutter/res_timestamp-"* \
  "$work/data/app_lib"
# Cola de telemetría de ML Kit (escáner QR): sin valor y atada al paquete viejo.
rm -f "$work/data/databases/com.google.android.datatransport.events"*
# Rutas absolutas guardadas en archivos de texto (JSON, prefs).
grep -rlI "/$OLD" "$work/data" 2>/dev/null | while read -r f; do
  sed -i "s#/$OLD#/$NEW#g" "$f"
done
# …y en las bases SQLite, si las hubiera.
find "$work/data" -name '*.db' -o -name '*.sqlite' | while read -r db; do
  grep -qa "/$OLD" "$db" || continue
  command -v sqlite3 >/dev/null || fail "$db guarda rutas viejas y falta sqlite3"
  sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table'" | while read -r t; do
    sqlite3 "$db" "PRAGMA table_info('$t')" | awk -F'|' '$3 ~ /TEXT|^$/ {print $2}' |
      while read -r c; do
        sqlite3 "$db" "UPDATE \"$t\" SET \"$c\" = replace(\"$c\", '/$OLD', '/$NEW') WHERE \"$c\" LIKE '%/$OLD%'"
      done
  done
done
# Sin la entrada «.»: tar le pondría a la carpeta de datos los permisos de
# la copia local y run-as dejaría de entrar.
(cd "$work/data" && tar -cf "$work/data.tar" -- $(ls -A))

adb install "$dir/new-migration.apk"
adb push "$work/data.tar" /data/local/tmp/crotowave-migration.tar >/dev/null
adb shell chmod 644 /data/local/tmp/crotowave-migration.tar
adb shell run-as "$NEW" sh -c "'tar -xf /data/local/tmp/crotowave-migration.tar && chmod 700 .'"
adb shell rm -f /data/local/tmp/crotowave-migration.tar

# Por el descriptor 3: `adb shell` lee stdin y se comería el resto del archivo.
while read -r kind name <&3; do
  case "$kind" in
    perm) adb shell pm grant "$NEW" "$name" >/dev/null 2>&1 || true ;;
    appop) adb shell appops set "$NEW" "$name" allow || true ;;
    deviceidle) adb shell dumpsys deviceidle whitelist "+$NEW" >/dev/null || true ;;
  esac
done 3< "$dir/permissions.txt"

launch "$NEW"
wait_file "$NEW" files/signing_migration_import.json absent ||
  fail "la app nueva no importó el almacén seguro"
sleep 2
adb shell am force-stop "$NEW"

# Misma clave: actualiza encima, conserva datos y deja de ser depurable.
adb install -r "$dir/new-release.apk"
if [[ -n "$(ls -A "$dir/external" 2>/dev/null)" ]]; then
  adb push "$dir/external/." "/sdcard/Android/data/$NEW/" >/dev/null ||
    echo "AVISO: no se pudieron copiar los archivos de /sdcard/Android/data" >&2
fi
launch "$NEW"
sleep 6
adb shell pidof "$NEW" >/dev/null || fail "la app nueva no sigue abierta tras arrancar"

# La copia ya no necesita los secretos en claro. Se reempaqueta sin el JSON
# (`tar --delete` de GNU deja dañados los tar que genera Android).
mkdir "$work/clean"
tar -xf "$dir/data.tar" -C "$work/clean"
rm -f "$work/clean/files/signing_migration_export.json"
clean="$PWD/$dir/data.tar.new"
(cd "$work/clean" && tar -cf "$clean" -- $(ls -A))
chmod 600 "$dir/data.tar.new"
mv "$dir/data.tar.new" "$dir/data.tar"
echo "Listo: $NEW instalada con tus datos. Revisa que todo esté bien y luego"
echo "desinstala la vieja: $ADB -s $DEVICE uninstall $OLD"
