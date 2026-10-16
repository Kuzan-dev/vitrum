#!/usr/bin/env bash
# Instala la regeneración automática del submenú de grub-btrfs:
#   grub-btrfs-regen.path (vigila /.snapshots) → grub-btrfs-regen.service →
#   /usr/local/sbin/grub-btrfs-regen-auto (debounce + solo si cambia el menú) →
#   /usr/local/sbin/grub-btrfs-regen (temporal + grub2-script-check + mv)
# Sustituye a grub-btrfsd, que sobrescribe los archivos en sitio.
# Requiere 05-grub-btrfs.sh.
#
# Uso: sudo ./07-grub-btrfs-path.sh
# Idempotente: reinstala los mismos archivos y deja la unidad activa.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -x /usr/local/sbin/grub-btrfs-regen ]] || ((DRY)) || die "Falta grub-btrfs-regen: ejecuta antes 05-grub-btrfs.sh"

reload=0
ensure_file "$REPO/config/system/grub-btrfs-regen-auto" /usr/local/sbin/grub-btrfs-regen-auto 0755 && reload=1
ensure_file "$REPO/config/system/grub-btrfs-regen.service" /etc/systemd/system/grub-btrfs-regen.service 0644 && reload=1
ensure_file "$REPO/config/system/grub-btrfs-regen.path" /etc/systemd/system/grub-btrfs-regen.path 0644 && reload=1
((reload)) && ! ((DRY)) && systemctl daemon-reload
ensure_unit grub-btrfs-regen.path
fin
