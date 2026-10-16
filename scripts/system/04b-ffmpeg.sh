#!/usr/bin/env bash
# Cambia ffmpeg-free (Fedora, códecs recortados) por ffmpeg completo de RPM Fusion.
# Requiere 04a-rpmfusion.sh. Dnf crea un par pre/post de Snapper.
#
# Uso: sudo ./04b-ffmpeg.sh
# Idempotente: solo hace el swap si ffmpeg-free sigue instalado.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
if rpm -q ffmpeg-free >/dev/null 2>&1; then
  cambio "ffmpeg-free → ffmpeg (RPM Fusion)"
  ((DRY)) || dnf swap -y ffmpeg-free ffmpeg --allowerasing
else
  ensure_pkgs ffmpeg
fi
fin
