#!/usr/bin/env bash
# Decodificación de vídeo por hardware (VA-API → NVDEC) para la GPU NVIDIA:
#  - libva-nvidia-driver: backend VA-API sobre NVDEC
#  - libva-utils: aporta vainfo para verificar
# No fija NVD_BACKEND ni otras variables de entorno (se prueba a mano en el paso 6).
#
# Uso: sudo ./04d-vaapi-nvidia.sh
# Idempotente: dnf no reinstala lo que ya está.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
ensure_pkgs libva-nvidia-driver libva-utils
fin
