#!/usr/bin/env bash
# Actualiza el grupo @multimedia con los paquetes que añade RPM Fusion
# (plugins GStreamer "freeworld"/ugly, libheif-freeworld, aptX).
# Opciones recomendadas por RPM Fusion: sin dependencias débiles y sin
# tocar PackageKit-gstreamer-plugin. Requiere 04a-rpmfusion.sh.
#
# Uso: sudo ./04c-multimedia.sh
# Idempotente: si no hay nada nuevo, dnf responde "Nada que hacer".
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
# Estado buscado: los paquetes de RPM Fusion del grupo instalados (las actualizaciones de versión del grupo son
# cosa de «dnf upgrade», no de esta capa)
CLAVE=(gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly libheif-freeworld pipewire-codec-aptx)
falta=0; for p in "${CLAVE[@]}"; do rpm -q "$p" &>/dev/null || falta=1; done
if ((falta)); then
  cambio "grupo multimedia con los paquetes de RPM Fusion"
  ((DRY)) || dnf group upgrade -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
fi
fin
