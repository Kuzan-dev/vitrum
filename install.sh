#!/usr/bin/env bash
# Instalador del escritorio (docs/capas.md). Se ejecuta como el usuario, no con sudo:
# las capas de sistema piden sudo y confirmación por su cuenta.
#
#   ./install.sh check [--sugerir]   solo lectura: versiones, hardware y qué capas aplican;
#                                    --sugerir imprime valores detectados para config/local.env
#   ./install.sh user [--dry-run] [--waywallen [--wallpaper-engine] [--medios-prueba]]
#                                    escritorio del usuario (tema, extensiones, cristal, fondo, bandeja…), sin sudo;
#                                    copia previa, verificación (segunda pasada sin cambios) y vuelta atrás
#   ./install.sh verify user [flags] comprueba que no queda nada por aplicar (= user --dry-run con 0 cambios)
#   ./install.sh rollback user [copia] restaura una copia previa (la más reciente si no se indica)
#   ./install.sh system|nvidia|gaming|login [--dry-run] [--yes]
#                                    capas de sistema: plan (simulación con sudo), confirmación, snapshot de Snapper
#                                    «pre-capa-<capa>», ejecución y verificación (segunda simulación sin cambios)
#   ./install.sh rollback system|nvidia|gaming|login   deshace la capa con «snapper undochange» desde su
#                                    snapshot «pre-capa-<capa>» (la capa system, sin Snapper previo: snapshot de
#                                    seguridad de btrfs o arrancar un snapshot desde GRUB)
#   ./install.sh all [--dry-run] [--yes] [flags de user]   check → system → nvidia → gaming → login → user
#   ./install.sh boot [--dry-run]    rEFInd + tema rEFInd-lite: opt-in, nunca dentro de «all». Plan, confirmación,
#                                    copia de la ESP, entrada en el firmware SIN cambiar BootOrder y BootNext para
#                                    probar en el próximo arranque
#   ./install.sh boot --fijar-orden  tras arrancar bien por rEFInd: rEFInd primero en BootOrder, Fedora detrás
#   --forzar-version                 continuar aunque no sea Fedora 44 / GNOME 50 (bajo tu responsabilidad)
#   --yes                            no preguntar (vuelta atrás)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
source "$REPO/scripts/lib/common.sh"
FEDORA_OK=44; GNOME_OK=50
CMD="${1:-}"; shift || true
FORZAR=0; SUGERIR=0; DRY=0; WW=0; OWE=0; MEDIA=0; YES=0; ORDEN=0; POS=()
for a in "$@"; do
  case "$a" in
    --forzar-version) FORZAR=1 ;;
    --sugerir) SUGERIR=1 ;;
    --dry-run) DRY=1 ;;
    --waywallen) WW=1 ;;
    --wallpaper-engine) OWE=1 ;;
    --medios-prueba) MEDIA=1 ;;
    --yes) YES=1 ;;
    --fijar-orden) ORDEN=1 ;;
    -*) echo "Opción desconocida: $a" >&2; exit 1 ;;
    *) POS+=("$a") ;;
  esac
done
((OWE == 0 && MEDIA == 0)) || ((WW)) || { echo "--wallpaper-engine y --medios-prueba requieren --waywallen" >&2; exit 1; }

[[ $EUID -ne 0 ]] || { echo "Ejecuta install.sh como tu usuario, sin sudo (pedirá sudo cuando haga falta)" >&2; exit 1; }

ok()   { printf '  \e[32mOK\e[0m     %s\n' "$*"; }
aviso(){ printf '  \e[33mAVISO\e[0m  %s\n' "$*"; AVISOS=$((AVISOS + 1)); }
fallo(){ printf '  \e[31mFALLO\e[0m  %s\n' "$*"; FALLOS=$((FALLOS + 1)); }
info() { printf '  --     %s\n' "$*"; }
AVISOS=0; FALLOS=0

# --- Versiones validadas (se aplica a todas las capas) ---
fedora_ver() { . /etc/os-release; echo "${ID:-?} ${VERSION_ID:-?}"; }
gnome_ver()  { gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "?"; }
version_gate() {
  local f g; f="$(fedora_ver)"; g="$(gnome_ver)"
  if [[ "$f" != "fedora $FEDORA_OK" || "$g" != "$GNOME_OK" ]]; then
    echo "Este instalador está validado en Fedora $FEDORA_OK / GNOME $GNOME_OK; este sistema es ${f^} / GNOME $g." >&2
    echo "Las extensiones, los parches y el tema pueden no funcionar." >&2
    if ((FORZAR)); then
      echo "Continuando por --forzar-version (bajo tu responsabilidad)." >&2
    else
      echo "Usa --forzar-version para continuar bajo tu responsabilidad." >&2
      exit 2
    fi
  fi
}

esp_partuuid() { lsblk -no PARTUUID "$(findmnt -no SOURCE /boot/efi 2>/dev/null)" 2>/dev/null || true; }
other_esps() { # PARTUUID de otras particiones de sistema EFI
  local mine; mine="$(esp_partuuid)"
  lsblk -rno PARTUUID,PARTTYPE | awk -v m="$mine" 'tolower($2)=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && $1!=m {print $1}'
}
fedora_bootnum() { # entrada del firmware que arranca shimx64.efi desde la ESP montada
  local p; p="$(esp_partuuid)"
  efibootmgr -v 2>/dev/null | grep -i "$p" | grep -i 'fedora\\shimx64' | grep -v -i refind | sed -n 's/^Boot\([0-9A-F]\{4\}\).*/\1/p' | head -1
}

cmd_sugerir() {
  echo "# Valores detectados para config/local.env (revisar antes de usar)"
  echo "MAIN_USER=\"$(id -un)\""
  echo "TEST_USER=\"\"   # usuario de pruebas, si existe"
  echo "FEDORA_ESP_PARTUUID=\"$(esp_partuuid)\""
  echo "WINDOWS_ESP_PARTUUID=\"$(other_esps | head -1)\"   # otra ESP detectada: comprobar que es la de Windows"
  echo "FEDORA_BOOTNUM=\"$(fedora_bootnum)\""
  echo "MONITOR_SERIALS=\"$(grep -oE '<serial>[^<]+' ~/.config/monitors.xml 2>/dev/null | sed 's/<serial>//' | sort -u | paste -sd' ')\""
  echo "PERSONAL_EMAILS=\"$(git -C "$REPO" config user.email 2>/dev/null || true)\""
  echo "LOCAL_IPS=\"$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | paste -sd' ')\""
  echo "SECRET_LITERALS=\"\"   # contraseñas temporales u otros literales que nunca deben publicarse"
}

cmd_check() {
  local f g
  echo "== Sistema"
  f="$(fedora_ver)"; g="$(gnome_ver)"
  [[ "$f" == "fedora $FEDORA_OK" ]] && ok "${f^}" || fallo "${f^} (validado: Fedora $FEDORA_OK)"
  [[ "$g" == "$GNOME_OK" ]] && ok "GNOME $g" || fallo "GNOME $g (validado: GNOME $GNOME_OK)"
  [[ "${XDG_SESSION_TYPE:-}" == wayland ]] && ok "sesión Wayland" || aviso "sesión ${XDG_SESSION_TYPE:-desconocida} (validado en Wayland)"
  [[ -d /sys/firmware/efi ]] && ok "arranque UEFI" || fallo "no es UEFI (rEFInd y la capa boot no aplican)"
  info "Secure Boot: $(mokutil --sb-state 2>/dev/null | head -1 || echo 'desconocido')"
  [[ "$(findmnt -no FSTYPE /)" == btrfs ]] && ok "raíz en btrfs" || fallo "la raíz no es btrfs (Snapper y grub-btrfs no aplican)"
  if snapper list-configs 2>/dev/null | grep -qw root; then ok "Snapper: configuración root"; else info "Snapper: sin configuración root (la crea la capa system)"; fi
  rpm -q rpmfusion-free-release rpmfusion-nonfree-release &>/dev/null && ok "RPM Fusion instalado" || info "RPM Fusion no instalado (lo instala la capa system)"
  info "espacio libre: / $(df -h --output=avail / | tail -1 | tr -d ' '), HOME $(df -h --output=avail "$HOME" | tail -1 | tr -d ' ')"
  getent hosts extensions.gnome.org >/dev/null && ok "red (extensions.gnome.org resuelve)" || aviso "sin red: las capas que descargan fallarán"

  local m; m="$(user_tools_missing | paste -sd' ')"
  [[ -z "$m" ]] && ok "herramientas de la capa de usuario" || aviso "faltan herramientas: $m (las instala la capa system)"

  echo "== NVIDIA"
  if lspci 2>/dev/null | grep -qiE '(VGA|3D).*NVIDIA'; then
    local rpmv modv smiv repo
    rpmv="$(rpm -q --qf '%{version}' xorg-x11-drv-nvidia 2>/dev/null || true)"
    repo="$(dnf repoquery --installed --qf '%{from_repo}' akmod-nvidia 2>/dev/null | head -1 || true)"
    modv="$(modinfo -F version nvidia 2>/dev/null || true)"
    smiv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
    if [[ -z "$rpmv" ]]; then
      [[ -x /usr/bin/nvidia-installer ]] && aviso "driver instalado con .run (no soportado; requisito: akmod-nvidia de rpmfusion-nonfree-nvidia-driver)" \
                                          || aviso "sin driver NVIDIA en RPM (requisito previo: akmod-nvidia de rpmfusion-nonfree-nvidia-driver)"
    else
      [[ "$repo" == rpmfusion-nonfree-nvidia-driver || "$repo" == rpmfusion-nonfree* ]] && ok "driver $rpmv desde $repo" \
        || aviso "driver $rpmv desde «$repo» (requisito: rpmfusion-nonfree-nvidia-driver; no se cambia el origen)"
      [[ "$rpmv" == "$modv" && "$modv" == "$smiv" ]] && ok "paquete = módulo = nvidia-smi ($smiv)" \
        || aviso "paquete $rpmv, módulo ${modv:-?}, nvidia-smi ${smiv:-?}: reinicia o espera a que akmods construya el módulo"
      local gl="org.freedesktop.Platform.GL.nvidia-${smiv//./-}" inst
      for inst in system user; do
        if flatpak list --"$inst" --columns=application 2>/dev/null | grep -q '^org\.freedesktop\.Platform\.GL\.nvidia-'; then
          flatpak list --"$inst" --columns=application | grep -qx "$gl" && ok "Flatpak ($inst): $gl" \
            || aviso "Flatpak ($inst): extensión GL de NVIDIA de otra versión (ejecuta «flatpak update»; no se instala aquí)"
        else
          info "Flatpak ($inst): sin extensión GL de NVIDIA"
        fi
      done
    fi
  else
    info "sin GPU NVIDIA: se saltan VA-API NVIDIA y la extensión GL"
  fi

  echo "== Pantallas"
  local mx="$HOME/.config/monitors.xml" n
  if [[ -f "$mx" ]]; then
    n="$(grep -c '<connector>' "$mx")"; info "monitors.xml: $n conector(es) en la configuración del usuario"
    grep -q '<colormode>bt2100</colormode>' "$mx" && ok "HDR activo en algún monitor: la capa login lo llevará a GDM" \
                                                  || info "sin HDR: la capa login lo salta"
  else
    info "sin ~/.config/monitors.xml: la capa login salta el HDR"
  fi
  [[ -f /etc/xdg/monitors.xml ]] && info "/etc/xdg/monitors.xml ya existe" || true
  if command -v ddcutil >/dev/null; then
    n="$(timeout 20 ddcutil detect --brief 2>/dev/null | grep -c '^Display' || true)"
    ((n > 0)) && ok "DDC/CI: $n monitor(es) con brillo controlable" || info "DDC/CI: ningún monitor (el control de brillo no aplica)"
  else
    info "ddcutil no instalado (el control de brillo por DDC no aplica)"
  fi

  echo "== Arranque (capa boot, opt-in)"
  local mine others
  mine="$(esp_partuuid)"; others="$(other_esps | paste -sd' ')"
  [[ -n "$mine" ]] && ok "ESP de Fedora en /boot/efi" || aviso "/boot/efi no está montada"
  [[ -n "$others" ]] && info "otra(s) ESP: $(wc -w <<<"$others") (posible Windows)" || info "sin otra ESP: no hay arranque dual"
  [[ -n "$(fedora_bootnum)" ]] && ok "entrada del firmware para Fedora presente" || aviso "no se encuentra la entrada de Fedora en el firmware"

  echo "== config/local.env"
  if [[ -f "$REPO/config/local.env" ]]; then
    load_local_env
    if git -C "$REPO" rev-parse --git-dir &>/dev/null; then
      git -C "$REPO" check-ignore -q config/local.env && ok "presente e ignorado por git" || fallo "config/local.env NO está ignorado por git"
    else
      info "presente (copia sin git: no se comprueba el .gitignore)"
    fi
    [[ "$(stat -c %a "$REPO/config/local.env")" == 600 ]] || aviso "permisos de config/local.env distintos de 600"
    local u
    for u in MAIN_USER TEST_USER; do
      [[ -z "${!u:-}" ]] && { info "$u vacío"; continue; }
      id "${!u}" &>/dev/null && ok "$u existe" || fallo "$u no existe en este sistema"
    done
    [[ -z "${FEDORA_ESP_PARTUUID:-}" || "$FEDORA_ESP_PARTUUID" == "$mine" ]] && ok "FEDORA_ESP_PARTUUID coincide con /boot/efi" \
      || fallo "FEDORA_ESP_PARTUUID no coincide con la ESP montada"
    if [[ -n "${WINDOWS_ESP_PARTUUID:-}" ]]; then
      [[ -e "/dev/disk/by-partuuid/$WINDOWS_ESP_PARTUUID" ]] && ok "WINDOWS_ESP_PARTUUID existe" || fallo "WINDOWS_ESP_PARTUUID no existe"
    fi
    [[ -z "${FEDORA_BOOTNUM:-}" || "$FEDORA_BOOTNUM" == "$(fedora_bootnum)" ]] && ok "FEDORA_BOOTNUM coincide con el firmware" \
      || aviso "FEDORA_BOOTNUM ($FEDORA_BOOTNUM) distinto del detectado ($(fedora_bootnum))"
  else
    aviso "no existe config/local.env: cópialo de config/local.env.example o usa «./install.sh check --sugerir»"
  fi

  echo "== Resumen: $FALLOS fallo(s), $AVISOS aviso(s)"
  ((FALLOS == 0))
}

# --- Capas de sistema ---
confirmar() { # pregunta
  ((YES)) && return 0
  [[ -t 0 ]] || { echo "Sin terminal para confirmar: usa --yes" >&2; exit 1; }
  local r; read -r -p "$1 [s/N] " r; [[ "$r" == [sS] ]]
}

# Ejecuta un script de sistema con sudo (DRY_RUN=$1) y suma sus cambios a TOTAL
sys_run() { # dry silencioso script [args]
  local dry="$1" quiet="$2" out n; shift 2
  out="$(mktemp)"
  # La salida la guarda el usuario (no root): la redirección fuera de sudo es intencionada
  # shellcheck disable=SC2024
  sudo env DRY_RUN="$dry" "$@" >"$out" 2>&1 || { cat "$out" >&2; rm -f "$out"; echo "ERROR en $(basename "$1")" >&2; exit 1; }
  if ((quiet)); then grep -E 'CAMBIARÍA:' "$out" || true
  elif ((dry)); then grep -E 'CAMBIARÍA:|^\s+\(' "$out" || true
  else grep -vE '^CAMBIOS:' "$out" || true; fi
  n="$(sed -n 's/^CAMBIOS: //p' "$out" | tail -1)"; TOTAL=$((TOTAL + ${n:-0}))
  rm -f "$out"
}

nvidia_driver() { rpm -q xorg-x11-drv-nvidia &>/dev/null; }

layer_scripts() { # capa → SCRIPTS (un elemento por orden, con sus argumentos separados por |)
  local S="$REPO/scripts/system"
  case "$1" in
    system) SCRIPTS=("$S/00-dependencias.sh" "$S/01-safety-snapshot.sh" "$S/02-snapper.sh" "$S/03-installonly-limit.sh" "$S/04a-rpmfusion.sh"
                     "$S/04b-ffmpeg.sh" "$S/04c-multimedia.sh" "$S/05-grub-btrfs.sh" "$S/07-grub-btrfs-path.sh") ;;
    nvidia) SCRIPTS=(); nvidia_driver && SCRIPTS=("$S/04d-vaapi-nvidia.sh") ;;
    gaming) SCRIPTS=("$REPO/scripts/gaming.sh") ;;
    login)  SCRIPTS=("$S/10-login-hdr.sh|$HOME/.config/monitors.xml") ;;
  esac
}

run_layer_scripts() { # dry silencioso
  local c; TOTAL=0
  for c in "${SCRIPTS[@]}"; do
    IFS='|' read -r -a cmd <<<"$c"
    ((${2:-0})) || echo "-- $(basename "${cmd[0]}")"
    sys_run "$1" "${2:-0}" "${cmd[@]}"
  done
}

run_sys_layer() { # capa
  local capa="$1"
  echo "==== Capa $capa"
  if [[ "$capa" == nvidia ]]; then
    if lspci 2>/dev/null | grep -qiE '(VGA|3D).*NVIDIA'; then
      nvidia_driver || { echo "  GPU NVIDIA sin el driver requerido (ver docs/capas.md §4): se salta VA-API"; return 0; }
    else
      echo "  sin GPU NVIDIA: nada que hacer"; return 0
    fi
  fi
  layer_scripts "$capa"
  ((${#SCRIPTS[@]})) || { echo "  no aplica"; return 0; }
  run_layer_scripts 1
  if ((DRY)); then echo "== Simulación de $capa: $TOTAL cambio(s)"; return 0; fi
  ((TOTAL)) || { echo "  nada que hacer"; return 0; }
  confirmar "¿Aplicar la capa $capa ($TOTAL cambio(s), con sudo)?" || { echo "Capa $capa cancelada"; exit 1; }
  if sudo snapper -c root list-configs 2>/dev/null | awk 'NR>2 {print $1}' | grep -qx root; then
    sudo snapper -c root create -c number -d "pre-capa-$capa" && echo "  snapshot de Snapper «pre-capa-$capa» creado"
  else
    echo "  (Snapper aún no está configurado: la capa empieza por el snapshot de seguridad de btrfs)"
  fi
  run_layer_scripts 0
  run_layer_scripts 1 1
  if ((TOTAL)); then echo "AVISO: tras aplicar $capa quedan $TOTAL cambio(s) pendientes (arriba)" >&2; exit 1; fi
  echo "== Capa $capa aplicada y verificada"
}

cmd_rollback_sys() { # capa
  local capa="$1" n
  n="$(sudo snapper -c root list --columns number,description 2>/dev/null | awk -F'│' -v d="pre-capa-$capa" '{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$2)} $2==d {n=$1} END{print n}')"
  [[ -n "$n" ]] || { echo "No hay snapshot «pre-capa-$capa» (ver docs/capas.md §6)" >&2; exit 1; }
  echo "Se deshará la capa $capa: cambios desde el snapshot $n («pre-capa-$capa») hasta ahora:"
  sudo snapper -c root status "$n..0" | awk '{print substr($1,1,1)}' | sort | uniq -c \
    | sed 's/ c$/ modificados/; s/ +$/ creados (se borrarán)/; s/ -$/ borrados (se restaurarán)/'
  echo "(incluye cualquier otro cambio en / desde entonces; /home no se toca)"
  confirmar "¿Deshacer con «snapper undochange $n..0»?" || exit 1
  sudo snapper -c root undochange "$n..0"
  echo "Hecho. Si la capa instaló paquetes o servicios, reinicia."
}

cmd_boot() {
  local S="$REPO/scripts/system" mine bn falta=()
  [[ -d /sys/firmware/efi ]] || { echo "No es UEFI: la capa boot no aplica" >&2; exit 1; }
  load_local_env FEDORA_ESP_PARTUUID FEDORA_BOOTNUM
  mine="$(esp_partuuid)"; bn="$(fedora_bootnum)"
  [[ "$mine" == "$FEDORA_ESP_PARTUUID" ]] || { echo "FEDORA_ESP_PARTUUID de local.env no es la ESP montada en /boot/efi" >&2; exit 1; }
  [[ "$bn" == "$FEDORA_BOOTNUM" ]] || { echo "FEDORA_BOOTNUM ($FEDORA_BOOTNUM) no es la entrada de Fedora del firmware ($bn)" >&2; exit 1; }
  if ((ORDEN)); then
    echo "BootOrder actual: $(efibootmgr | sed -n 's/^BootOrder: //p') · BootCurrent: $(efibootmgr | sed -n 's/^BootCurrent: //p')"
    confirmar "¿Poner rEFInd primero en BootOrder (Fedora $FEDORA_BOOTNUM justo detrás)?" || exit 1
    sudo "$S/08-refind.sh" set-order; return 0
  fi
  for p in rEFInd rEFInd-unsigned-x64; do rpm -q "$p" &>/dev/null || falta+=("$p"); done
  echo "==== Capa boot (rEFInd) — plan"
  ((${#falta[@]})) && echo "  - instalar ${falta[*]} (dnf)"
  echo "  - copia previa: tar de /boot/efi/EFI + efibootmgr -v en backups/"
  echo "  - /boot/efi/EFI/refind nuevo (carpeta nueva + renombrado; el anterior queda en refind.old):"
  echo "    Fedora por PARTUUID ${FEDORA_ESP_PARTUUID:0:8}…$( [[ -n "${WINDOWS_ESP_PARTUUID:-}" ]] && echo ", Windows por PARTUUID ${WINDOWS_ESP_PARTUUID:0:8}…" || echo ', sin Windows')"
  echo "  - tema rEFInd-lite con fondo negro"
  echo "  - entrada «rEFInd» en el firmware SIN cambiar BootOrder ($(efibootmgr | sed -n 's/^BootOrder: //p')) y BootNext a ella"
  echo "  - después, si arranca bien: ./install.sh boot --fijar-orden"
  ((DRY)) && return 0
  confirmar "¿Aplicar la capa boot (ESP y firmware)?" || exit 1
  if sudo snapper -c root list-configs 2>/dev/null | awk 'NR>2 {print $1}' | grep -qx root; then
    sudo snapper -c root create -c number -d "pre-capa-boot" >/dev/null && echo "  snapshot de Snapper «pre-capa-boot» creado (la ESP no entra: copia aparte)"
  fi
  ((${#falta[@]})) && sudo dnf install -y "${falta[@]}"
  sudo "$S/08-refind-backup.sh" | grep -E 'esp-efi|efibootmgr' | head -3
  sudo "$S/08-refind.sh" install-esp | grep -E '^OK|ERROR'
  sudo "$S/08-refind.sh" create-entry | grep -E 'BootOrder|rEFInd|Ya existe'
  sudo "$S/08-refind.sh" install-theme | grep -E '^OK|ERROR|BootOrder'
  sudo "$S/08-refind.sh" bootnext
  echo "== Reinicia para probar rEFInd (BootNext). Si arranca bien: ./install.sh boot --fijar-orden"
}

cmd_all() {
  version_gate
  cmd_check || { echo "check con fallos: corrígelos antes de «all»" >&2; exit 1; }
  local c; for c in system nvidia gaming login; do run_sys_layer "$c"; done
  cmd_user
}

# --- Capa de usuario ---
# Rutas del HOME que gestiona la capa (copia previa y vuelta atrás) y ramas de dconf que toca
USER_PATHS=(.local/share/gnome-shell/extensions .local/share/themes .local/share/icons/MacTahoe
  .local/share/icons/MacTahoe-dark .local/share/icons/MacTahoe-light .local/share/icons/MacTahoe-cursors
  .local/share/icons/MacTahoe-dark-cursors .local/share/backgrounds .config/gtk-4.0 .config/environment.d
  .config/autostart/waywallen.desktop .local/share/dotfiles .local/share/flatpak/overrides
  .var/app/org.waywallen.waywallen/config)
USER_DCONF=(/org/gnome/shell/ /org/gnome/desktop/interface/ /org/gnome/desktop/background/
  /org/gnome/desktop/screensaver/ /org/gnome/desktop/wm/preferences/)
COPIAS="$HOME/.local/state/dotfiles/copias"

user_steps() {
  STEPS=(theme extensions panel glass shell-theme wallpaper mutter-scanout)
  ((WW)) && STEPS+=(waywallen "waywallen-profile abierto")
  STEPS+=(appindicator)   # al final: su icono de Waywallen depende de que Waywallen esté instalado
}

# Ejecuta los pasos (DRY_RUN=$1) y deja el total de cambios en TOTAL; $2=silencioso
run_user_steps() {
  local dry="$1" quiet="${2:-0}" st out n
  TOTAL=0
  for st in "${STEPS[@]}"; do
    out="$(mktemp)"
    ((quiet)) || echo "== $st"
    # shellcheck disable=SC2086
    DRY_RUN="$dry" WW_OWE="$OWE" WW_MEDIA="$MEDIA" "$REPO/scripts/visual.sh" "$(id -un)" $st >"$out" 2>&1 || {
      cat "$out" >&2; rm -f "$out"; echo "ERROR en el paso «$st»" >&2; exit 1; }
    if ((quiet)); then grep -E '^\s*CAMBIARÍA:' "$out" || true
    elif ((dry)); then grep -E 'CAMBIARÍA:|AVISO|^  \(' "$out" || true
    else grep -vE '^CAMBIOS:' "$out" || true; fi
    n="$(sed -n 's/^CAMBIOS: //p' "$out" | tail -1)"; TOTAL=$((TOTAL + ${n:-0}))
    rm -f "$out"
  done
}

copia_previa() {
  local d p; d="$COPIAS/$(date +%F-%H%M%S)-user"; mkdir -p "$d"
  local -a existe=()
  for p in "${USER_PATHS[@]}"; do [[ -e "$HOME/$p" ]] && existe+=("$p"); done
  ((${#existe[@]})) && tar -C "$HOME" -czf "$d/archivos.tar.gz" "${existe[@]}"
  printf '%s\n' "${existe[@]}" > "$d/rutas-existentes.txt"
  dconf dump / > "$d/dconf.ini"
  { echo "fecha=$(date -Is)"; echo "commit=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"
    echo "flags=ww=$WW owe=$OWE media=$MEDIA"; } > "$d/info.txt"
  echo "Copia previa: $d ($(du -sh "$d" | cut -f1))"
  # Se conservan las tres copias más recientes de la capa (cada una ocupa ~300 MB, sobre todo iconos)
  ls -1d "$COPIAS"/*-user 2>/dev/null | sort | head -n -3 | xargs -r rm -rf
}

# Herramientas de la capa de usuario (las instala la capa system: scripts/system/00-dependencias.sh)
USER_TOOLS=(patch unzip curl git glib-compile-schemas python3 gsettings dconf flatpak xdg-user-dir gdbus)
user_tools_missing() { local t; for t in "${USER_TOOLS[@]}"; do command -v "$t" >/dev/null || echo "$t"; done; }

cmd_user() {
  version_gate
  local m; m="$(user_tools_missing | paste -sd' ')"
  [[ -z "$m" ]] || { echo "Faltan herramientas: $m. Ejecuta antes «./install.sh system» (o: sudo dnf install $m)" >&2; exit 1; }
  user_steps
  if ((DRY)); then
    echo "Simulación de la capa de usuario para $(id -un) (no cambia nada)"
    run_user_steps 1
    echo "== Simulación: $TOTAL cambio(s) propuesto(s)"
    return 0
  fi
  ((WW)) && echo "Waywallen: Flatpak de usuario desde Flathub (~3 GB la primera vez)$( ((OWE)) && echo ', con open-wallpaper-engine')."
  copia_previa
  run_user_steps 0
  echo "== Aplicados $TOTAL cambio(s). Verificación (segunda pasada en simulación):"
  run_user_steps 1 1
  if ((TOTAL == 0)); then
    echo "Verificado: nada pendiente."
  else
    echo "AVISO: la segunda pasada propone $TOTAL cambio(s) (arriba)" >&2; exit 1
  fi
  echo "Cierra sesión y vuelve a entrar para cargar extensiones, tema y variables de sesión."
}

cmd_verify_user() {
  user_steps
  run_user_steps 1 1
  if ((TOTAL == 0)); then echo "Capa de usuario verificada: nada pendiente"; else echo "Pendiente: $TOTAL cambio(s)"; exit 1; fi
}

cmd_rollback_user() {
  local d="${1:-}" p
  [[ -n "$d" ]] || d="$(ls -1d "$COPIAS"/*-user 2>/dev/null | sort | tail -1)"
  [[ "$d" == /* ]] || d="$COPIAS/$d"
  [[ -f "$d/dconf.ini" ]] || { echo "No hay copia en $d" >&2; exit 1; }
  echo "Se restaurará la copia $d:"
  echo "  - se borran y se restauran de la copia: ${USER_PATHS[*]}"
  echo "  - se reinician y se cargan de la copia las ramas de dconf: ${USER_DCONF[*]}"
  echo "  (el Flatpak de Waywallen no se desinstala: scripts/rollback-waywallen.sh)"
  if ((YES == 0)); then read -r -p "¿Continuar? [s/N] " r; [[ "$r" == [sS] ]] || exit 1; fi
  for p in "${USER_PATHS[@]}"; do rm -rf "${HOME:?}/$p"; done
  [[ -f "$d/archivos.tar.gz" ]] && tar -C "$HOME" -xzf "$d/archivos.tar.gz"
  for p in "${USER_DCONF[@]}"; do dconf reset -f "$p"; done
  # Sin las claves bloqueadas por el sistema (con una sola, dconf load rechaza el volcado entero)
  python3 -I - "$d/dconf.ini" /etc/dconf/db/*.d/locks/* <<'PY' | dconf load /
import configparser, sys
locks = set()
for f in sys.argv[2:]:
    try:
        locks |= {l.strip() for l in open(f) if l.startswith("/")}
    except OSError:
        pass
c = configparser.RawConfigParser(interpolation=None); c.optionxform = str; c.read(sys.argv[1])
for s in c.sections():
    keys = [k for k in c[s] if f"/{s}/{k}" not in locks]
    if keys:
        print(f"[{s}]")
        for k in keys:
            print(f"{k}={c[s][k]}")
        print()
PY
  echo "Restaurado. Cierra sesión y vuelve a entrar."
}

case "$CMD" in
  check)
    if ((SUGERIR)); then cmd_sugerir; else cmd_check; fi ;;
  user) cmd_user ;;
  verify)
    [[ "${POS[0]:-}" == user ]] || { echo "Uso: ./install.sh verify user [flags]" >&2; exit 1; }
    cmd_verify_user ;;
  rollback)
    case "${POS[0]:-}" in
      user) cmd_rollback_user "${POS[1]:-}" ;;
      system|nvidia|gaming|login) cmd_rollback_sys "${POS[0]}" ;;
      *) echo "Uso: ./install.sh rollback user [copia] | rollback system|nvidia|gaming|login" >&2; exit 1 ;;
    esac ;;
  system|nvidia|gaming|login) version_gate; run_sys_layer "$CMD" ;;
  all) cmd_all ;;
  boot) version_gate; cmd_boot ;;
  waywallen)
    version_gate
    echo "La capa «$CMD» aún no está implementada en install.sh (siguientes bloques de la fase 4)." >&2
    exit 1 ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
