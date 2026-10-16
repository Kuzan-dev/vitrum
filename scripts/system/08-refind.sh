#!/usr/bin/env bash
# Fase 1.5: rEFInd como capa por encima de GRUB (no lo reemplaza). Instalación manual,
# SIN refind-install (ver docs/vuelta-atras.md). Cada subcomando es un paso del plan
# y se ejecuta por separado, con confirmación:
#
#   sudo ./08-refind.sh install-esp    paso 3: copia rEFInd + tema + refind.conf a la ESP de Fedora
#   sudo ./08-refind.sh create-entry   paso 5: crea la entrada "rEFInd" en el firmware SIN cambiar BootOrder
#   sudo ./08-refind.sh bootnext       paso 6: arranca rEFInd solo en el próximo reinicio (BootNext)
#   sudo ./08-refind.sh set-order      paso 7: rEFInd primero, Fedora (0004) segunda como respaldo
#   sudo ./08-refind.sh rollback       quita rEFInd: BootOrder sin él, borra la entrada y /EFI/refind
#   sudo ./08-refind.sh install-theme  tema rEFInd-lite con fondo negro liso: copia de /EFI/refind a
#                                      refind.new + tema + refind.conf del repo, y renombrado (refind.old se
#                                      conserva; el tema rEFInd-minimal queda en themes/ como respaldo)
#   sudo ./08-refind.sh theme-rollback vuelve a refind.old (estado anterior a install-theme)
#   sudo ./08-refind.sh status         solo muestra el estado (no cambia nada)
#
# Idempotente: cada subcomando comprueba el estado antes de actuar.
set -euo pipefail

# --- Identificadores del equipo (por PARTUUID, independientes del orden de discos) ---
# En config/local.env (ignorado por git): FEDORA_ESP_PARTUUID (montada en /boot/efi), WINDOWS_ESP_PARTUUID
# y FEDORA_BOOTNUM (entrada de respaldo, no se toca nunca). `./install.sh check --sugerir` los propone.
FEDORA_LOADER="EFI/fedora/shimx64.efi"
WINDOWS_LOADER="EFI/Microsoft/Boot/bootmgfw.efi"

# --- Tema fijado a commit + sha256 ---
THEME_NAME="rEFInd-minimal"
THEME_COMMIT="56a06a4bd9ed76c05523a22017056dbecca4145d"
THEME_SHA256="787bd81fbb16572a053437a855067b3b10b71e2840b3bff0b059619e2645436d"
THEME_URL="https://github.com/EvanPurkhiser/rEFInd-minimal/archive/$THEME_COMMIT.tar.gz"

# Tema activo desde 2026-10-15: rEFInd-lite (MIT; iconos de darkmini, MIT), fondo propio negro liso
LITE_NAME="rEFInd-lite"
LITE_COMMIT="e600b8c2dec13a9525318bb2a68bf0d174fe9c0b"
LITE_SHA256="aeee6c3b7ee4ef2cd3b5cbb5169ee1b4fb48cac99017d1b70eaed2a64f841c1e"
LITE_URL="https://github.com/Littlebanbrick/rEFInd-lite/archive/$LITE_COMMIT.tar.gz"

ESP=/boot/efi
DEST="$ESP/EFI/refind"
LABEL="rEFInd"
LOADER_EFI='\EFI\refind\refind_x64.efi'
PKG_DIR=/usr/share/rEFInd/refind

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo" >&2; exit 1; }
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/scripts/lib/common.sh"
load_local_env FEDORA_ESP_PARTUUID FEDORA_BOOTNUM   # WINDOWS_ESP_PARTUUID es opcional (sin arranque dual)

# refind.conf del equipo: plantilla del repo con los PARTUUID de local.env
render_refind_conf() { # destino
  if [[ -n "${WINDOWS_ESP_PARTUUID:-}" ]]; then
    sed -e "s/@FEDORA_ESP_PARTUUID@/$FEDORA_ESP_PARTUUID/g" -e "s/@WINDOWS_ESP_PARTUUID@/$WINDOWS_ESP_PARTUUID/g" \
      "$REPO/config/refind/refind.conf.in" > "$1"
  else   # sin Windows: fuera su menuentry
    sed -e "s/@FEDORA_ESP_PARTUUID@/$FEDORA_ESP_PARTUUID/g" -e '/^menuentry "Windows" {/,/^}/d' \
      "$REPO/config/refind/refind.conf.in" > "$1"
  fi
  ! grep -q '@[A-Z_]*@' "$1" || die "quedan marcadores sin sustituir en refind.conf"
  chmod 0700 "$1"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Número de la entrada "rEFInd" en el firmware (vacío si no existe)
refind_bootnum() {
  efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\? $LABEL\s*\(HD(.*)\)\?.*/\1/p" | head -1
}
current_order() { efibootmgr | sed -n 's/^BootOrder: //p'; }

# La ESP montada en /boot/efi debe ser la de Fedora (por PARTUUID)
check_esp() {
  mountpoint -q "$ESP" || die "$ESP no está montado"
  local src; src="$(findmnt -no SOURCE "$ESP")"
  [[ "$(lsblk -no PARTUUID "$src")" == "$FEDORA_ESP_PARTUUID" ]] \
    || die "$ESP ($src) no es la ESP de Fedora ($FEDORA_ESP_PARTUUID)"
  [[ -f "$ESP/$FEDORA_LOADER" ]] || die "No existe $ESP/$FEDORA_LOADER"
}

# Comprueba en SOLO LECTURA que el cargador de Windows existe en su ESP
check_windows_loader() {
  [[ -n "${WINDOWS_ESP_PARTUUID:-}" ]] || { echo "Sin Windows (WINDOWS_ESP_PARTUUID vacío): solo la entrada de Fedora"; return 0; }
  local dev mnt; dev="/dev/disk/by-partuuid/$WINDOWS_ESP_PARTUUID"
  [[ -e "$dev" ]] || die "No se encuentra la ESP de Windows ($WINDOWS_ESP_PARTUUID)"
  mnt="$(mktemp -d)"
  mount -o ro "$dev" "$mnt"
  local found=0
  # FAT no distingue mayúsculas; find -ipath para no depender de cómo esté escrito
  [[ -n "$(find "$mnt" -ipath "$mnt/$WINDOWS_LOADER" -print -quit)" ]] && found=1
  umount "$mnt"; rmdir "$mnt"
  ((found)) || die "No existe $WINDOWS_LOADER en la ESP de Windows"
  echo "OK: cargador de Windows presente (comprobado en solo lectura)"
}

cmd_install_esp() {
  check_esp
  check_windows_loader
  [[ -f "$PKG_DIR/refind_x64.efi" ]] || die "Falta $PKG_DIR/refind_x64.efi (dnf install rEFInd)"

  # Tema: descargar el commit fijado y verificar sha256
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -sSfL -o "$tmp/theme.tar.gz" "$THEME_URL"
  echo "$THEME_SHA256  $tmp/theme.tar.gz" | sha256sum -c --quiet || die "sha256 del tema no coincide"
  tar xzf "$tmp/theme.tar.gz" -C "$tmp"
  local tsrc="$tmp/$THEME_NAME-$THEME_COMMIT"

  # Preparar en un directorio aparte de la ESP y sustituir con rename
  local stage="$ESP/EFI/refind.new"
  rm -rf "$stage"
  install -d "$stage/themes/$THEME_NAME"
  install -m 0700 "$PKG_DIR/refind_x64.efi" "$stage/refind_x64.efi"
  render_refind_conf "$stage/refind.conf"
  cp -r "$PKG_DIR/icons" "$stage/icons"                      # iconos por defecto (respaldo del tema)
  cp -r "$tsrc/icons" "$tsrc/theme.conf" "$tsrc/background.png" \
        "$tsrc/selection_big.png" "$tsrc/selection_small.png" "$tsrc/LICENSE" \
        "$stage/themes/$THEME_NAME/"
  printf 'refind=%s\ntheme=%s@%s\ntheme_sha256=%s\n' \
    "$(rpm -q --qf '%{version}-%{release}' rEFInd-unsigned-x64)" \
    "$THEME_NAME" "$THEME_COMMIT" "$THEME_SHA256" > "$stage/VERSION"

  if [[ -d "$DEST" ]]; then
    rm -rf "$ESP/EFI/refind.old"
    mv "$DEST" "$ESP/EFI/refind.old"
  fi
  mv "$stage" "$DEST"
  rm -rf "$ESP/EFI/refind.old"
  sync -f "$ESP"

  echo "OK: rEFInd instalado en $DEST"
  ls "$ESP/EFI"
  find "$DEST" -maxdepth 2 -not -path '*/icons/*' | sort
  du -sh "$DEST"
  echo "BootOrder (sin cambios): $(current_order)"
}

# PNG negro liso (RGB, 1920x1080) solo con la biblioteca estándar: rEFInd rellena con el color de la
# esquina del banner si la pantalla es mayor, así que vale para cualquier resolución
black_png() { # destino
  python3 -I - "$1" <<'PY'
import struct, sys, zlib
w, h = 1920, 1080
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
raw = (b"\x00" + b"\x00" * (w * 3)) * h
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
PY
}

# Todas las rutas de imagen que usan refind.conf y el tema deben existir en el árbol preparado
check_paths() { # árbol (equivale a /EFI/refind)
  local tree="$1" rel miss=0
  while read -r rel; do
    rel="${rel#/EFI/refind/}"
    [[ -e "$tree/$rel" ]] || { echo "FALTA: $rel" >&2; miss=1; }
  done < <(cat "$tree/refind.conf" "$tree/themes/$LITE_NAME/theme.conf" |
           sed -n -E 's/^\s*(icon|icons_dir|banner|selection_big|selection_small)\s+(\S+).*/\2/p')
  grep -q "^include themes/$LITE_NAME/theme.conf" "$tree/refind.conf" || { echo "FALTA: include del tema" >&2; miss=1; }
  ((miss == 0)) || die "rutas del tema o de refind.conf sin resolver"
  echo "OK: rutas de iconos, selección y fondo presentes"
}

cmd_install_theme() {
  check_esp
  check_windows_loader
  [[ -f "$DEST/refind_x64.efi" ]] || die "rEFInd no está instalado en $DEST"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -sSfL -o "$tmp/lite.tar.gz" "$LITE_URL"
  echo "$LITE_SHA256  $tmp/lite.tar.gz" | sha256sum -c --quiet || die "sha256 de rEFInd-lite no coincide"
  tar xzf "$tmp/lite.tar.gz" -C "$tmp"
  local lsrc="$tmp/$LITE_NAME-$LITE_COMMIT"
  black_png "$tmp/background.png"

  # Copia del árbol actual (rEFInd, vars, tema rEFInd-minimal de respaldo) y tema nuevo al lado
  local stage="$ESP/EFI/refind.new"
  rm -rf "$stage"
  cp -a "$DEST" "$stage"
  rm -rf "$stage/themes/$LITE_NAME"
  install -d "$stage/themes/$LITE_NAME/bg"
  cp -r "$lsrc/icons" "$lsrc/theme.conf" "$lsrc/LICENSE" "$stage/themes/$LITE_NAME/"
  install -m 0644 "$tmp/background.png" "$stage/themes/$LITE_NAME/bg/background.png"   # sin el fondo por defecto
  render_refind_conf "$stage/refind.conf"
  printf 'theme_active=%s@%s\ntheme_active_sha256=%s\nbackground=negro 1920x1080 (generado)\n' \
    "$LITE_NAME" "$LITE_COMMIT" "$LITE_SHA256" >> "$stage/VERSION"
  check_paths "$stage"

  rm -rf "$ESP/EFI/refind.old"
  mv "$DEST" "$ESP/EFI/refind.old"
  mv "$stage" "$DEST"
  sync -f "$ESP"
  echo "OK: tema $LITE_NAME activo; estado anterior en $ESP/EFI/refind.old"
  ls "$ESP/EFI" "$DEST/themes"
  echo "BootOrder (sin cambios): $(current_order)"
}

cmd_theme_rollback() {
  check_esp
  [[ -d "$ESP/EFI/refind.old" ]] || die "No existe $ESP/EFI/refind.old"
  rm -rf "$ESP/EFI/refind.bad"
  mv "$DEST" "$ESP/EFI/refind.bad"
  mv "$ESP/EFI/refind.old" "$DEST"
  rm -rf "$ESP/EFI/refind.bad"
  sync -f "$ESP"
  echo "OK: vuelto al estado anterior"; grep '^include' "$DEST/refind.conf"
}

cmd_create_entry() {
  check_esp
  [[ -f "$DEST/refind_x64.efi" ]] || die "Primero: install-esp"
  local num; num="$(refind_bootnum)"
  if [[ -n "$num" ]]; then
    echo "Ya existe la entrada Boot$num ($LABEL); no se crea otra"
  else
    local before dev disk part
    before="$(current_order)"
    dev="$(readlink -f "/dev/disk/by-partuuid/$FEDORA_ESP_PARTUUID")"   # p. ej. /dev/nvme1n1p1
    disk="/dev/$(lsblk -no PKNAME "$dev")"                               # p. ej. /dev/nvme1n1
    part="$(cat "/sys/class/block/$(basename "$dev")/partition")"        # p. ej. 1
    echo "Creando entrada: disk=$disk part=$part loader=$LOADER_EFI"
    efibootmgr --create-only --disk "$disk" --part "$part" --label "$LABEL" --loader "$LOADER_EFI" >/dev/null
    num="$(refind_bootnum)"
    [[ -n "$num" ]] || die "No se encontró la entrada recién creada"
    [[ "$(current_order)" == "$before" ]] || die "BootOrder cambió inesperadamente (antes: $before)"
  fi
  efibootmgr -v | grep -E "^BootOrder|^Boot$num|^Boot$FEDORA_BOOTNUM" | cut -c1-140
}

cmd_bootnext() {
  local num; num="$(refind_bootnum)"
  [[ -n "$num" ]] || die "No existe la entrada $LABEL (create-entry)"
  efibootmgr --bootnext "$num" >/dev/null
  efibootmgr | grep -E '^(BootNext|BootOrder)'
}

cmd_set_order() {
  local num rest; num="$(refind_bootnum)"
  [[ -n "$num" ]] || die "No existe la entrada $LABEL (create-entry)"
  # rEFInd primero; el resto en su orden actual (Fedora 0004 queda inmediatamente después)
  rest="$(current_order | tr ',' '\n' | grep -vx "$num" | paste -sd,)"
  [[ "$rest" == "$FEDORA_BOOTNUM"* ]] || die "Se esperaba $FEDORA_BOOTNUM al principio del resto: $rest"
  efibootmgr --bootorder "$num,$rest" >/dev/null
  efibootmgr | grep -E '^BootOrder'
}

cmd_rollback() {
  local num rest; num="$(refind_bootnum)"
  if [[ -n "$num" ]]; then
    rest="$(current_order | tr ',' '\n' | grep -vx "$num" | paste -sd,)"
    efibootmgr --bootorder "$rest" >/dev/null
    efibootmgr --bootnum "$num" --delete-bootnum >/dev/null
    echo "Entrada Boot$num eliminada"
  fi
  rm -rf "$DEST" "$ESP/EFI/refind.new" "$ESP/EFI/refind.old"
  efibootmgr | grep -E '^(BootNext|BootOrder|Boot[0-9A-F]{4})'
  ls "$ESP/EFI"
}

cmd_status() {
  echo "ESP $ESP: $(findmnt -no SOURCE "$ESP")"; ls "$ESP/EFI"
  [[ -f "$DEST/VERSION" ]] && cat "$DEST/VERSION"
  efibootmgr | grep -E '^(BootCurrent|BootNext|BootOrder|Boot[0-9A-F]{4})'
}

case "${1:-}" in
  install-esp)  cmd_install_esp ;;
  create-entry) cmd_create_entry ;;
  bootnext)     cmd_bootnext ;;
  set-order)    cmd_set_order ;;
  rollback)     cmd_rollback ;;
  install-theme) cmd_install_theme ;;
  theme-rollback) cmd_theme_rollback ;;
  status)       cmd_status ;;
  *) sed -n '2,19p' "$0"; exit 1 ;;
esac
