#!/usr/bin/env bash
# Instala y configura Snapper para "/" (sin /home):
#  - config "root", sin timeline, como máximo 10 snapshots de dnf (cleanup "number")
#  - snapshots pre/post automáticos en dnf5 mediante libdnf5-plugin-actions
#  - snapper-cleanup.timer activo
#  - snapshot "base fase 1" sin algoritmo de limpieza (no se borra solo)
#
# Uso: sudo ./02-snapper.sh
# Idempotente: cada paso comprueba el estado antes de actuar.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# 1. Paquetes
ensure_pkgs snapper btrfs-assistant libdnf5-plugin-actions inotify-tools

# 2. Config de snapper para "/". /home es otro subvolumen y no se incluye.
if ! { command -v snapper >/dev/null && snapper list-configs 2>/dev/null | awk 'NR>2 {print $1}' | grep -qx root; }; then
  cambio "configuración de Snapper «root» para /"
  ((DRY)) || snapper -c root create-config /
fi

# 3. Ajustes: sin timeline, límite de 10 snapshots "number" (5 importantes)
declare -A WANT=([TIMELINE_CREATE]=no [TIMELINE_CLEANUP]=yes [NUMBER_CLEANUP]=yes [NUMBER_LIMIT]=10
                 [NUMBER_LIMIT_IMPORTANT]=5 [EMPTY_PRE_POST_CLEANUP]=yes)
cur="$(snapper -c root get-config 2>/dev/null || true)"
set_args=()
for k in "${!WANT[@]}"; do
  v="$(awk -F'│' -v k="$k" '{gsub(/ /,"",$1); gsub(/ /,"",$2)} $1==k {print $2}' <<<"$cur")"
  [[ "$v" == "${WANT[$k]}" ]] || set_args+=("$k=${WANT[$k]}")
done
if ((${#set_args[@]})); then
  cambio "ajustes de Snapper: ${set_args[*]}"
  ((DRY)) || snapper -c root set-config "${set_args[@]}"
fi

# 4. Timers: limpieza sí, timeline no
ensure_unit snapper-cleanup.timer
if systemctl is-enabled --quiet snapper-timeline.timer 2>/dev/null; then
  cambio "desactivar snapper-timeline.timer"
  ((DRY)) || systemctl disable --now snapper-timeline.timer
fi

# 5. Hook de dnf5
ensure_file "$REPO/config/system/dnf5-snapper-hook" /usr/local/libexec/dnf5-snapper-hook 0755 || true
ensure_file "$REPO/config/system/snapper.actions" /etc/dnf/libdnf5-plugins/actions.d/snapper.actions 0644 || true

# 6. Snapshot base (sin -c: Snapper nunca lo limpia automáticamente)
if ! snapper -c root list --columns description 2>/dev/null | grep -qx ' *base fase 1 *'; then
  cambio "snapshot «base fase 1»"
  ((DRY)) || snapper -c root create -d "base fase 1"
fi
fin
