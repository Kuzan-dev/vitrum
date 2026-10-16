#!/usr/bin/env bash
# Instala grub-btrfs desde el tag oficial (no desde main), verificado por commit y
# sha256, y genera el submenú "Fedora snapshots" en GRUB de forma atómica.
#
# Se instala solo lo necesario, fuera de rutas de rpm:
#   /etc/grub.d/41_snapshots-btrfs       generador del submenú (llamado por grub2-mkconfig)
#   /etc/default/grub-btrfs/config       config de Fedora (config/system/grub-btrfs.config)
#   /usr/local/sbin/grub-btrfs-regen     regeneración atómica (config/system/grub-btrfs-regen)
#   /usr/local/share/man/man8/           páginas man
#   /usr/local/share/grub-btrfs/VERSION  tag, commit y sha256 instalados
# NO se instala grub-btrfsd: sobrescribe grub.cfg/grub-btrfs.cfg en sitio (ver docs).
#
# Actualizar: cambiar VERSION/COMMIT/SHA256 y volver a ejecutar (ver docs/capas.md).
# Uso: sudo ./05-grub-btrfs.sh
# Idempotente: reinstala los mismos archivos y regenera el menú.
# DRY_RUN=1: solo muestra lo que cambiaría (también con sudo: algunas lecturas lo requieren).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
VERSION="v4.14"
COMMIT="2fcfbe967637166b88dadd49c834807243a941bf"
SHA256="4fe2f8a49b39e3e561fc51bbc5a0f81a7222c1e9ef8672e014e0ba3bedad20c6"
REPO_URL="https://github.com/Antynea/grub-btrfs"
need_root
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

remote="$(git ls-remote "$REPO_URL.git" "refs/tags/$VERSION" | cut -f1)"
[[ "$remote" == "$COMMIT" ]] || die "El tag $VERSION apunta a '$remote', se esperaba $COMMIT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -sSfL -o "$tmp/src.tar.gz" "$REPO_URL/archive/refs/tags/$VERSION.tar.gz"
echo "$SHA256  $tmp/src.tar.gz" | sha256sum -c --quiet
tar xzf "$tmp/src.tar.gz" -C "$tmp"
SRC="$tmp/grub-btrfs-${VERSION#v}"
printf 'version=%s\ncommit=%s\nsha256=%s\nsource=%s\n' "$VERSION" "$COMMIT" "$SHA256" "$REPO_URL" > "$tmp/VERSION"

regen=0
ensure_file "$SRC/41_snapshots-btrfs" /etc/grub.d/41_snapshots-btrfs 0755 && regen=1
ensure_file "$REPO/config/system/grub-btrfs.config" /etc/default/grub-btrfs/config 0644 && regen=1
ensure_file "$REPO/config/system/grub-btrfs-regen" /usr/local/sbin/grub-btrfs-regen 0755 && regen=1
ensure_file "$SRC/manpages/grub-btrfs.8.man" /usr/local/share/man/man8/grub-btrfs.8 0644 || true
ensure_file "$SRC/manpages/grub-btrfsd.8.man" /usr/local/share/man/man8/grub-btrfsd.8 0644 || true
ensure_file "$tmp/VERSION" /usr/local/share/grub-btrfs/VERSION 0644 || true

# Submenú «Fedora snapshots» (regeneración atómica) si cambió algo o si aún no existe
if ((regen)) || ! grep -q 'snapshots' /boot/grub2/grub-btrfs.cfg 2>/dev/null; then
  cambio "regenerar el submenú de snapshots de GRUB"
  ((DRY)) || /usr/local/sbin/grub-btrfs-regen --full
fi
fin
