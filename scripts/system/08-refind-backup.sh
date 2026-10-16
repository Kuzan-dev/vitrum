#!/usr/bin/env bash
# Fase 1.5, paso 1: copias de seguridad antes de instalar rEFInd. Solo LEE /boot/efi
# y el firmware; escribe en ~/dotfiles/backups/ (fuera de git).
#   - efibootmgr -v            → backups/efibootmgr-<fecha>.txt
#   - tar de /boot/efi/EFI     → backups/esp-efi-<fecha>.tar.gz (+ .sha256)
#
# Uso: sudo ./08-refind-backup.sh
# Idempotente: cada ejecución crea copias nuevas con fecha; no borra las anteriores.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo" >&2; exit 1; }
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/backups"
OWNER="$(stat -c %U:%G "$REPO")"
TS="$(date +%F-%H%M)"

mkdir -p "$OUT"; chown "$OWNER" "$OUT"
mountpoint -q /boot/efi || { echo "/boot/efi no está montado" >&2; exit 1; }

efibootmgr -v > "$OUT/efibootmgr-$TS.txt"
tar -C /boot/efi -czf "$OUT/esp-efi-$TS.tar.gz" EFI
(cd "$OUT" && sha256sum "esp-efi-$TS.tar.gz" > "esp-efi-$TS.tar.gz.sha256")
chown "$OWNER" "$OUT/efibootmgr-$TS.txt" "$OUT/esp-efi-$TS.tar.gz" "$OUT/esp-efi-$TS.tar.gz.sha256"

echo "== Copias creadas"
ls -la "$OUT"/*"$TS"*
echo "== Contenido del tar"
tar -tzvf "$OUT/esp-efi-$TS.tar.gz"
echo "== BootOrder guardado"
grep -E '^(BootCurrent|BootOrder|Boot[0-9A-F]{4})' "$OUT/efibootmgr-$TS.txt" | cut -c1-110
