#!/usr/bin/env bash
# Snapshot manual de solo lectura del subvolumen "root", creado en el nivel
# superior del btrfs (junto a root/ y home/), fuera del árbol de Snapper.
# Sirve como red de seguridad antes de instalar Snapper.
#
# Uso: sudo ./01-safety-snapshot.sh [nombre]
# Idempotente: si el snapshot ya existe, no hace nada.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
NAME="${1:-root-pre-fase1}"
MNT="/run/btrfs-top"

SRC="$(findmnt -no SOURCE /)"          # p. ej. /dev/nvme1n1p3[/root]
DEV="${SRC%%[*}"
SUBVOL="$(findmnt -no FSROOT /)"       # p. ej. /root
SUBVOL="${SUBVOL#/}"
[[ "$(findmnt -no FSTYPE /)" == btrfs ]] || die "/ no es btrfs"

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount -o subvolid=5,ro "$DEV" "$MNT"
trap 'umount "$MNT" && rmdir "$MNT"' EXIT
if [[ ! -e "$MNT/$NAME" ]]; then
  cambio "snapshot de seguridad de solo lectura «$NAME»"
  if ! ((DRY)); then
    mount -o remount,rw "$MNT"
    btrfs subvolume snapshot -r "$MNT/$SUBVOL" "$MNT/$NAME"
  fi
fi
fin
