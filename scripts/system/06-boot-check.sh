#!/usr/bin/env bash
# Comprobación tras el arranque (fase 1, paso 6). NO necesita sudo ni cambia nada.
# Funciona tanto en el sistema normal como arrancando un snapshot desde GRUB:
# /home es otro subvolumen y sigue siendo escribible, así que el informe se guarda en
#   ${DOTFILES_NOTAS:-~/dotfiles-notas}/boot-checks/<fecha>-<normal|snapshot>.txt (notas fuera del repo)
#
# Uso: ~/dotfiles/scripts/system/06-boot-check.sh
set -euo pipefail

DIR="${DOTFILES_NOTAS:-$HOME/dotfiles-notas}/boot-checks"
mkdir -p "$DIR"

fsroot="$(findmnt -no FSROOT /)"
if [[ "$fsroot" == "/root" ]]; then mode="normal"; else mode="snapshot"; fi
OUT="$DIR/$(date +%F-%H%M)-$mode.txt"

# Ejecuta un comando, muestra su salida y nunca aborta el script
run() {
  echo "### \$ $*"
  "$@" 2>&1 || echo "(código de salida: $?)"
  echo
}

{
  echo "# Boot check — $(date '+%F %T %z') — modo: $mode"
  echo
  run findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS /
  run findmnt -o TARGET,SOURCE,OPTIONS /home
  run cat /proc/cmdline
  run uname -r
  run systemctl is-system-running
  run systemctl --failed --no-legend --no-pager
  echo "### Sesión gráfica"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<vacío>}  XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-<vacío>}  tty=$(tty 2>/dev/null || echo '?')"
  echo
  run systemctl status gdm --no-pager -n 5
  run nvidia-smi
  run modinfo -F license nvidia
  run modinfo -F version nvidia
  run cat /sys/module/nvidia_drm/parameters/modeset
  echo "### lsmod (gpu)"; lsmod | grep -E '^(nvidia|nouveau)' || echo "(ninguno)"; echo
  echo "### journalctl -b -p err (últimas 60 líneas)"
  journalctl -b -p err --no-pager 2>&1 | tail -60 || true
} > "$OUT"

echo "Informe guardado en: $OUT"
echo "Modo detectado: $mode (FSROOT=$fsroot)"
