#!/usr/bin/env bash
# Fija installonly_limit=4 en /etc/dnf/dnf.conf (sección [main]) para conservar
# más kernels en /boot (que está fuera de btrfs y no entra en los snapshots).
# Cada kernel + initramfs con NVIDIA ocupa ~170 MB; 4 caben con margen en /boot (2 GB).
#
# Uso: sudo ./03-installonly-limit.sh
# Idempotente: reemplaza la línea si existe; si no, la añade tras [main].
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
CONF=/etc/dnf/dnf.conf
LIMIT=4
if ! grep -qxE "\s*installonly_limit\s*=\s*$LIMIT\s*" "$CONF"; then
  cambio "installonly_limit=$LIMIT en $CONF"
  if ! ((DRY)); then
    if grep -qE '^\s*installonly_limit\s*=' "$CONF"; then
      sed -i -E "s/^\s*installonly_limit\s*=.*/installonly_limit=$LIMIT/" "$CONF"
    else
      sed -i "/^\[main\]/a installonly_limit=$LIMIT" "$CONF"
    fi
  fi
fi
fin
