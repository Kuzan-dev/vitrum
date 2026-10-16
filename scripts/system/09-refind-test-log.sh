#!/usr/bin/env bash
# Registra una prueba de arranque de la fase 1.5 (rEFInd). NO necesita sudo ni cambia nada.
# Añade a ${DOTFILES_NOTAS:-~/dotfiles-notas}/boot-checks/refind-tests.md (notas fuera del repo): hora, nota, BootCurrent/BootNext/BootOrder,
# kernel y raíz montada. Así se puede repetir la prueba varias veces y comparar.
#
# Uso: ~/dotfiles/scripts/system/09-refind-test-log.sh "A1: Shift sostenido → menú GRUB sí/no"
set -euo pipefail

OUT="${DOTFILES_NOTAS:-$HOME/dotfiles-notas}/boot-checks/refind-tests.md"; mkdir -p "$(dirname "$OUT")"
mkdir -p "$(dirname "$OUT")"
[[ -f "$OUT" ]] || printf '# Pruebas de arranque con rEFInd (fase 1.5, paso 6)\n\n' > "$OUT"

efi="$(efibootmgr 2>&1)"
current="$(sed -n 's/^BootCurrent: //p' <<<"$efi")"
label="$(sed -n "s/^Boot${current}\*\? \([^\t]*\).*/\1/p" <<<"$efi")"
{
  echo "## $(date '+%F %T') — ${1:-sin nota}"
  echo
  echo "- BootCurrent: \`$current\` ($label)"
  echo "- BootNext: \`$(sed -n 's/^BootNext: //p' <<<"$efi" || true)\`"
  echo "- BootOrder: \`$(sed -n 's/^BootOrder: //p' <<<"$efi")\`"
  echo "- Kernel: \`$(uname -r)\` · raíz: \`$(findmnt -no SOURCE /)\`"
  echo
} >> "$OUT"
tail -8 "$OUT"
