#!/usr/bin/env bash
# VM de pruebas de las capas de sistema (Fedora 44 Workstation, UEFI, btrfs), en el HOME y sin root
# (qemu-kvm + OVMF; red de usuario de qemu). Nada en /etc, dnf ni /boot del equipo.
#
#   tools/vm/vm-prueba.sh descargar     ISO netinstall + CHECKSUM: firma con la clave de Fedora 44 del sistema y sha256
#   tools/vm/vm-prueba.sh instalar      instalación desatendida (kickstart), se apaga al terminar (~30-60 min)
#   tools/vm/vm-prueba.sh foto <nombre> instantánea del disco (VM apagada)
#   tools/vm/vm-prueba.sh volver <nombre>  vuelve a una instantánea (VM apagada)
#   tools/vm/vm-prueba.sh arrancar [--ventana]  arranca la VM (sin ventana: solo SSH)
#   tools/vm/vm-prueba.sh ssh [comando] SSH como «prueba» (puerto 2222 en 127.0.0.1, clave propia de la VM)
#   tools/vm/vm-prueba.sh copiar        copia el árbol del repo (sin backups/ ni local.env) a ~/dotfiles en la VM
#   tools/vm/vm-prueba.sh apagar | borrar
# Datos en ~/.local/share/dotfiles-vm (disco, ISO, claves; fuera del repo).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
D="$HOME/.local/share/dotfiles-vm"
REL=44; VER=1.7
ISO="Fedora-Everything-netinst-x86_64-$REL-$VER.iso"
SUMS="Fedora-Everything-$REL-$VER-x86_64-CHECKSUM"
BASE="https://dl.fedoraproject.org/pub/fedora/linux/releases/$REL/Everything/x86_64/iso"
KEY=/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$REL-primary
OVMF=/usr/share/edk2/ovmf/OVMF_CODE.fd; OVMF_VARS=/usr/share/edk2/ovmf/OVMF_VARS.fd
DISK="$D/disco.qcow2"; PORT=2222
die() { echo "ERROR: $*" >&2; exit 1; }
mkdir -p "$D"; chmod 700 "$D"

qemu_base() { # args extra...
  qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 6144 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" -drive if=pflash,format=raw,file="$D/OVMF_VARS.fd" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0 \
    -device virtio-vga -usb -device usb-tablet "$@"
}
ssh_vm() { ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile="$D/known_hosts" -i "$D/clave" -p $PORT prueba@127.0.0.1 "$@"; }

cmd_descargar() {
  cd "$D"
  [[ -f "$SUMS" ]] || curl -sSfLO "$BASE/$SUMS"
  local kr; kr="$(mktemp)"; gpg --dearmor < "$KEY" > "$kr"
  gpgv --keyring "$kr" "$SUMS" 2>&1 | grep -q 'Good signature\|Firma correcta' || { rm -f "$kr"; die "firma del CHECKSUM no válida"; }
  rm -f "$kr"; echo "OK: CHECKSUM firmado por Fedora $REL"
  [[ -f "$ISO" ]] || curl -sSfL -C - -o "$ISO.part" "$BASE/$ISO" && { [[ -f "$ISO.part" ]] && mv "$ISO.part" "$ISO" || true; }
  grep -E "^SHA256 \($ISO\)" "$SUMS" | sed -E 's/^SHA256 \((.*)\) = (.*)$/\2  \1/' | sha256sum -c --quiet && echo "OK: sha256 de $ISO"
}

cmd_instalar() {
  [[ -f "$D/$ISO" ]] || die "primero: descargar"
  [[ ! -f "$DISK" ]] || die "ya existe $DISK (borrar o volver a una foto)"
  cd "$D"
  7z e -y -o"$D/boot" "$ISO" images/pxeboot/vmlinuz images/pxeboot/initrd.img >/dev/null
  [[ -f "$D/clave" ]] || ssh-keygen -q -t ed25519 -N '' -C vm-prueba -f "$D/clave"
  [[ -f "$D/contraseña" ]] || { umask 077; head -c 18 /dev/urandom | base64 | tr -d '/+=' > "$D/contraseña"; }
  local hash; hash="$(openssl passwd -6 -stdin < "$D/contraseña")"
  mkdir -p "$D/ks"
  cat > "$D/ks/ks.cfg" <<EOF
text
url --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$REL&arch=x86_64"
repo --name=updates --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f$REL&arch=x86_64"
lang es_PE.UTF-8
keyboard --vckeymap=us-intl --xlayouts='us(intl)'
timezone America/Lima --utc
network --bootproto=dhcp --hostname=vitrum-vm
zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs
bootloader
rootpw --lock
user --name=prueba --groups=wheel --iscrypted --password=$hash
sshkey --username=prueba "$(cat "$D/clave.pub")"
services --enabled=sshd
%packages
@^workstation-product-environment
openssh-server
%end
poweroff
EOF
  cp "$OVMF_VARS" "$D/OVMF_VARS.fd"
  qemu-img create -q -f qcow2 "$DISK" 80G
  # Servidor HTTP efímero para el kickstart (la VM ve el host en 10.0.2.2)
  python3 -m http.server 8765 --bind 127.0.0.1 --directory "$D/ks" >/dev/null 2>&1 & WEB=$!
  trap 'kill "${WEB:-}" 2>/dev/null || true' EXIT
  echo "Instalando (desatendido; la VM se apaga al terminar). Registro de la consola: $D/instalacion.log"
  qemu_base -display none -serial file:"$D/instalacion.log" -no-reboot \
    -kernel "$D/boot/vmlinuz" -initrd "$D/boot/initrd.img" \
    -append "inst.ks=http://10.0.2.2:8765/ks.cfg inst.stage2=hd:LABEL=Fedora-E-dvd-x86_64-$REL inst.text console=ttyS0" \
    -cdrom "$D/$ISO"
  kill "$WEB" 2>/dev/null || true
  echo "Instalación terminada. Siguiente: «foto base» y «arrancar»."
}

case "${1:-}" in
  descargar) cmd_descargar ;;
  instalar) cmd_instalar ;;
  foto) [[ -n "${2:-}" ]] || die "nombre"; qemu-img snapshot -c "$2" "$DISK"; cp "$D/OVMF_VARS.fd" "$D/OVMF_VARS.$2.fd"; qemu-img snapshot -l "$DISK" ;;
  volver) [[ -n "${2:-}" ]] || die "nombre"; qemu-img snapshot -a "$2" "$DISK"; cp "$D/OVMF_VARS.$2.fd" "$D/OVMF_VARS.fd"; echo "VM en «$2»" ;;
  arrancar)
    if [[ "${2:-}" == --ventana ]]; then qemu_base -display gtk & else qemu_base -display none -daemonize -pidfile "$D/qemu.pid"; fi
    for _ in $(seq 90); do ssh_vm true 2>/dev/null && { echo "VM lista (ssh)"; exit 0; }; sleep 2; done; die "la VM no responde por SSH" ;;
  ssh) shift; ssh_vm "$@" ;;
  copiar)
    { git -C "$REPO" ls-files; git -C "$REPO" ls-files --others --exclude-standard; } | grep -vE '^(backups/|config/local\.env$)' \
      | tar -C "$REPO" -czf - -T - | ssh_vm 'rm -rf ~/dotfiles && mkdir ~/dotfiles && tar -C ~/dotfiles -xzf -' && echo "copiado a la VM: ~/dotfiles" ;;
  apagar) ssh_vm 'sudo -S poweroff' < "$D/contraseña" 2>/dev/null || true; [[ -f "$D/qemu.pid" ]] && kill "$(cat "$D/qemu.pid")" 2>/dev/null || true ;;
  borrar) rm -rf "$D"; echo "VM borrada" ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
