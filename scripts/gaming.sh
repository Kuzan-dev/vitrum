#!/usr/bin/env bash
# Fase 2 (gaming, versión rápida): Steam (RPM de RPM Fusion), GameMode, MangoHud y
# vulkan-tools (vulkaninfo). Requiere system (RPM Fusion nonfree activo).
#
# Steam arrastra ~200 librerías i686 (multilib) y, por dependencia de
# xorg-x11-drv-nvidia-libs.x86_64, las variantes i686 del driver
# (xorg-x11-drv-nvidia-libs, -cuda-libs) desde rpmfusion-nonfree-nvidia-driver, a la MISMA
# versión que el driver instalado. Los paquetes x86_64 del driver no cambian: el script lo
# comprueba antes y después, y aborta si la transacción los fuera a tocar.
#
# Uso: sudo ./gaming.sh
# Idempotente: dnf no reinstala lo que ya está.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/sys.sh"
need_root
PKGS=(steam gamemode mangohud vulkan-tools)
# La extensión AppIndicator la instala la capa de usuario (EGO, versión fijada), no el RPM
EXCLUDE=(--exclude=gnome-shell-extension-appindicator)
DRIVER=(akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs.x86_64)
NVIDIA_REPO=rpmfusion-nonfree-nvidia-driver

falta=()
for p in "${PKGS[@]}"; do rpm -q "$p" &>/dev/null || falta+=("$p"); done
((${#falta[@]})) || { fin; exit 0; }
rpm -q rpmfusion-nonfree-release &>/dev/null || die "Steam necesita RPM Fusion nonfree (capa system)"

nvidia=0; rpm -q xorg-x11-drv-nvidia-libs.x86_64 &>/dev/null && nvidia=1
driver_state() {
  ((nvidia)) || return 0
  rpm -q "${DRIVER[@]}" --qf '%{name}.%{arch} %{epoch}:%{version}-%{release}\n'
  rpm -qa 'kmod-nvidia-*' --qf '%{name} %{epoch}:%{version}-%{release}\n' | sort
}
before="$(driver_state)"
preview="$(LC_ALL=C dnf install --assumeno "${falta[@]}" "${EXCLUDE[@]}" 2>&1 || true)"
if ((nvidia)); then
  # 1. La transacción no debe actualizar, quitar ni degradar paquetes del driver
  if grep -A1000 -E '^(Upgrading|Replacing|Removing|Downgrading)' <<<"$preview" \
       | grep -qE '^ (akmod-nvidia|kmod-nvidia|xorg-x11-drv-nvidia) '; then
    die "ABORTADO: la transacción modificaría paquetes del driver NVIDIA"
  fi
  # 2. Las variantes i686 del driver deben ser la MISMA versión y del repo del driver
  drv_evr="$(rpm -q --qf '%{epoch}:%{version}-%{release}' xorg-x11-drv-nvidia-libs.x86_64)"
  while read -r name arch evr repo _; do
    [[ "$evr" == "$drv_evr" && "$repo" == "$NVIDIA_REPO" ]] || die "ABORTADO: $name.$arch $evr ($repo) no es $drv_evr de $NVIDIA_REPO"
  done < <(grep -E '^ xorg-x11-drv-nvidia[^ ]* +i686 ' <<<"$preview")
fi
cambio "instalar ${falta[*]} (Steam arrastra ~200 librerías i686)"
if ! ((DRY)); then
  dnf install -y "${falta[@]}" "${EXCLUDE[@]}"
  after="$(driver_state)"
  if [[ "$before" != "$after" ]]; then
    diff <(echo "$before") <(echo "$after") >&2 || true
    die "cambió el estado del driver NVIDIA"
  fi
fi
fin
