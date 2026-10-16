#!/usr/bin/env bash
# Prueba de grub-btrfs-regen.path: simula una transacción dnf (par pre/post), comprueba
# que hay UNA sola regeneración y que el submenú incluye el snapshot pre; luego borra el
# par y comprueba que desaparece. Limpia lo que crea.
#
# Uso: sudo ./07-test-grub-btrfs-path.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo" >&2; exit 1; }
CFG=/boot/grub2/grub-btrfs.cfg
WAIT=40   # > QUIET (15 s) + tiempo de regeneración

since="$(date '+%F %T')"
pre="$(snapper -c root create -t pre -p -c number -d 'prueba path pre')"
sleep 5
post="$(snapper -c root create -t post --pre-number "$pre" -p -c number -d 'prueba path post')"
echo "Creado par de prueba: pre #$pre / post #$post. Esperando ${WAIT}s..."
sleep "$WAIT"

echo "== Journal de grub-btrfs-regen.service"
journalctl -u grub-btrfs-regen.service --since "$since" --no-pager -o cat | grep -E 'OK:|Sin cambios|Found [0-9]|repite|Debounce|Finished|Failed' || true
echo "Regeneraciones: $(journalctl -u grub-btrfs-regen.service --since "$since" --no-pager -o cat | grep -c '^OK:' || true)"
echo "pre #$pre en el submenú:  $(grep -c "snapshots/$pre/snapshot" "$CFG" || true) líneas (esperado > 0)"
echo "post #$post en el submenú: $(grep -c "snapshots/$post/snapshot" "$CFG" || true) líneas (esperado 0)"
echo "root-pre-fase1:          $(grep -c 'root-pre-fase1' "$CFG" || true) líneas (esperado > 0)"
grub2-script-check /boot/grub2/grub.cfg && grub2-script-check "$CFG" && echo "grub2-script-check: OK"

echo "== Limpieza: borrando #$pre y #$post"
since="$(date '+%F %T')"
snapper -c root delete "$pre" "$post"
sleep "$WAIT"
journalctl -u grub-btrfs-regen.service --since "$since" --no-pager -o cat | grep -E 'OK:|Sin cambios|Found [0-9]' || true
echo "pre #$pre tras borrar: $(grep -c "snapshots/$pre/snapshot" "$CFG" || true) líneas (esperado 0)"
grub2-script-check /boot/grub2/grub.cfg && grub2-script-check "$CFG" && echo "grub2-script-check: OK"
tmps=(/boot/grub2/*grub-btrfs-tmp*); [[ -e "${tmps[0]}" ]] || tmps=()
echo "temporales restantes: ${#tmps[@]}"
