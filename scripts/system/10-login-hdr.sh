#!/usr/bin/env bash
# HDR también en la pantalla de acceso (GDM): copia la configuración de monitores del usuario que instala
# (~/.config/monitors.xml, con HDR activo en algún monitor) a /etc/xdg/monitors.xml, que GDM y los usuarios
# sin configuración propia usan. Si no hay HDR o no hay monitors.xml, no hace nada (aviso).
# Validado con xmllint; el /etc/xdg/monitors.xml anterior se guarda como .bak-<fecha> si cambia.
#
# Uso: sudo ./10-login-hdr.sh /home/<usuario>/.config/monitors.xml
# DRY_RUN=1: solo muestra lo que cambiaría.
# Idempotente: si el archivo ya es igual, no hace nada. Revisar tras cualquier cambio de monitores.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
SRC="${1:-}"; DST=/etc/xdg/monitors.xml

if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "  (sin monitors.xml del usuario: se salta el HDR en el login)"; fin; exit 0
fi
if ! grep -q '<colormode>bt2100</colormode>' "$SRC"; then
  echo "  (sin HDR activo en ningún monitor: se salta)"; fin; exit 0
fi
xmllint --noout "$SRC" || die "$SRC no es XML válido"
if [[ -f "$DST" ]] && cmp -s "$SRC" "$DST"; then fin; exit 0; fi
cambio "$DST desde $SRC (HDR en la pantalla de acceso; efecto en el próximo inicio de GDM)"
if ! ((DRY)); then
  [[ -f "$DST" ]] && cp -a "$DST" "$DST.bak-$(date +%F-%H%M%S)"
  install -D -m 0644 "$SRC" "$DST"
  restorecon "$DST" 2>/dev/null || true
fi
fin
