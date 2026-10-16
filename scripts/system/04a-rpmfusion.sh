#!/usr/bin/env bash
# Activa RPM Fusion free + nonfree y, acto seguido, excluye los paquetes del
# driver NVIDIA de rpmfusion-nonfree y rpmfusion-nonfree-updates. Así el driver
# solo puede venir de rpmfusion-nonfree-nvidia-driver (repo de
# fedora-workstation-repositories), como en la instalación original.
#
# La exclusión se guarda con "dnf config-manager setopt" en
# /etc/dnf/repos.override.d/ (no se tocan los .repo de los paquetes).
#
# Uso: sudo ./04a-rpmfusion.sh
# Idempotente: no reinstala los release si ya están y setopt sobrescribe el valor.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
FEDORA="$(rpm -E %fedora)"
# Lista explícita de paquetes del driver (sin comodín nvidia-*)
DRIVER_PKGS="akmod-nvidia*,kmod-nvidia*,nvidia-kmod-common*,xorg-x11-drv-nvidia*,nvidia-settings*,nvidia-persistenced*,nvidia-modprobe*,nvidia-xconfig*"

# 1. Paquetes release, con la firma comprobada contra las claves de RPM Fusion
to_install=()
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for r in free nonfree; do
  rpm -q "rpmfusion-$r-release" >/dev/null 2>&1 && continue
  cambio "RPM Fusion $r (paquete release firmado)"
  ((DRY)) && continue
  rpm --import "/usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-$r-fedora-$FEDORA"
  f="$tmp/rpmfusion-$r-release-$FEDORA.noarch.rpm"
  curl -sSfL -o "$f" "https://mirrors.rpmfusion.org/$r/fedora/rpmfusion-$r-release-$FEDORA.noarch.rpm"
  LC_ALL=C rpm -K "$f" | grep -q ': digests signatures OK$' || die "Firma inválida: $f"
  to_install+=("$f")
done
((${#to_install[@]})) && dnf install -y "${to_install[@]}"

# 2. Driver NVIDIA excluido de los repos generales de RPM Fusion (solo desde rpmfusion-nonfree-nvidia-driver)
ov=/etc/dnf/repos.override.d/99-config_manager.repo
ok=1
for repo in rpmfusion-nonfree rpmfusion-nonfree-updates; do
  # dnf5 escribe «excludepkgs=…» (sin espacios); se compara ignorándolos
  awk -v r="[$repo]" -v want="excludepkgs=$DRIVER_PKGS" '$0==r{s=1;next} /^\[/{s=0} {l=$0; gsub(/ /,"",l)} s && l==want{f=1} END{exit !f}' "$ov" 2>/dev/null || ok=0
done
if ((ok == 0)); then
  cambio "excluir el driver NVIDIA de rpmfusion-nonfree y -updates"
  ((DRY)) || dnf config-manager setopt "rpmfusion-nonfree.excludepkgs=$DRIVER_PKGS" "rpmfusion-nonfree-updates.excludepkgs=$DRIVER_PKGS"
fi
fin
