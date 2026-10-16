#!/usr/bin/env bash
# Respaldo de TODA la configuración para llevar en un USB (docs/restauracion.md).
# Genera ~/respaldo-config-AAAA-MM-DD.tar.zst y su .sha256. Idempotente: el mismo día rehace el mismo archivo.
#
#   sudo ~/dotfiles/scripts/backup-usb.sh root-extra   (1º, opcional) lecturas que exigen root, a
#                                                      ~/.cache/respaldo-config/root-extra (del usuario)
#   ~/dotfiles/scripts/backup-usb.sh                   (2º, como el usuario, sin sudo) arma el archivo y lo
#                                                      CIFRA con gpg --symmetric: incluye config/local.env y
#                                                      ~/dotfiles-notas (datos personales). La contraseña la
#                                                      pide gpg/pinentry; este script nunca la pide ni la lee
#   ~/dotfiles/scripts/backup-usb.sh --sin-personal    sin local.env ni notas: el cifrado pasa a ser opcional
#                                                      (--cifrar)
#
# Contenido: git bundle de ~/dotfiles (todo el historial y ramas, verificado); dconf del usuario,
# extensiones, paquetes instalados por el usuario, Flatpaks y permisos de Waywallen; archivos de
# sistema creados o modificados en el proyecto; el tar de la ESP más reciente con su sha256;
# ~/Vídeos/Wallpapers, config/local.env y ~/dotfiles-notas. Excluye ~/.gemini, Antigravity, backups/ (salvo el tar de la ESP), Steam,
# navegadores, claves SSH, llaveros y tokens; al final escanea el resultado en busca de secretos.
# Patrones extra para el escaneo (p. ej. una contraseña conocida) solo por entorno, nunca en archivos:
#   EXTRA_SECRET_RE='...' ~/dotfiles/scripts/backup-usb.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${SUDO_USER:-$(id -un)}"; OHOME="$(getent passwd "$OWNER" | cut -d: -f6)"
EXTRA_DIR="$OHOME/.cache/respaldo-config/root-extra"
die() { echo "ERROR: $*" >&2; exit 1; }

# --- Parte con root: solo lecturas, a un directorio del usuario ---
if [[ "${1:-}" == root-extra ]]; then
  [[ $EUID -eq 0 ]] || die "root-extra se ejecuta con sudo"
  rm -rf "$EXTRA_DIR"; install -d -o "$OWNER" -g "$OWNER" -m 0700 "$EXTRA_DIR"
  install -o "$OWNER" -g "$OWNER" -m 0600 /etc/snapper/configs/root "$EXTRA_DIR/snapper-configs-root"
  blkid > "$EXTRA_DIR/blkid.txt"; chown "$OWNER:" "$EXTRA_DIR/blkid.txt"
  echo "OK: $(ls "$EXTRA_DIR" | paste -sd' ') en $EXTRA_DIR"
  exit 0
fi

[[ "$(id -un)" == "$OWNER" ]] || die "Ejecuta como $OWNER (sin sudo)"
CIFRAR=1; PERSONAL=1
for a in "$@"; do
  case "$a" in
    --sin-personal) PERSONAL=0; CIFRAR=0 ;;
    --cifrar) CIFRAR=1 ;;
    *) die "Opción desconocida: $a" ;;
  esac
done
((PERSONAL == 0 || CIFRAR == 1)) || die "con datos personales (local.env, notas) el archivo va siempre cifrado"
command -v gpg >/dev/null || ((CIFRAR == 0)) || die "falta gpg"
FECHA="$(date +%F)"; NAME="respaldo-config-$FECHA"
OUT="$HOME/$NAME.tar.zst"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
R="$WORK/$NAME"; mkdir -p "$R"/{repo,usuario,sistema,esp,personal}

# a. Repositorio: bundle con todas las ramas y etiquetas, verificado
git -C "$REPO" bundle create "$R/repo/dotfiles.bundle" --all 2>/dev/null
git -C "$REPO" bundle verify "$R/repo/dotfiles.bundle" > "$R/repo/bundle-verify.txt" 2>&1 \
  || die "git bundle verify falló"
git -C "$REPO" log -1 --format='%H %ci %s' > "$R/repo/HEAD.txt"

# b. Usuario
dconf dump / > "$R/usuario/dconf-$OWNER.ini"
{
  echo "# uuid | versión | activa | ubicación"
  enabled="$(gsettings get org.gnome.shell enabled-extensions)"
  for d in "$HOME"/.local/share/gnome-shell/extensions/*/ /usr/share/gnome-shell/extensions/*/; do
    [[ -f "$d/metadata.json" ]] || continue
    python3 -I - "$d/metadata.json" "$enabled" "$d" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); u = m.get("uuid", "?")
v = m.get("version-name") or m.get("version", "?")
on = "sí" if f"'{u}'" in sys.argv[2] else "no"
print(f"{u} | {v} | {on} | {'usuario' if '/.local/' in sys.argv[3] else 'sistema'}")
PY
  done
} > "$R/usuario/extensiones.txt"
dnf repoquery --userinstalled -q --qf '%{name}-%{evr}.%{arch}\n' 2>/dev/null | sort > "$R/usuario/rpm-instalados-por-usuario.txt"
rpm -qa --qf '%{NAME}-%{EVR}.%{ARCH}\n' | sort > "$R/usuario/rpm-todos.txt"
flatpak list --system --columns=application,branch,version,origin > "$R/usuario/flatpak-sistema.txt" 2>/dev/null || true
flatpak list --user --columns=application,branch,version,origin > "$R/usuario/flatpak-usuario.txt" 2>/dev/null || true
flatpak --user remotes --columns=name,url > "$R/usuario/flatpak-remotos-usuario.txt" 2>/dev/null || true
flatpak info --show-permissions org.waywallen.waywallen > "$R/usuario/waywallen-permisos.txt" 2>/dev/null \
  || echo "Waywallen no instalado" > "$R/usuario/waywallen-permisos.txt"

# c. Sistema (solo lecturas sin root; lo de root sale de root-extra si se ejecutó)
for f in /etc/dnf/dnf.conf /etc/dnf/repos.override.d /etc/xdg/monitors.xml /etc/default/grub-btrfs \
         /etc/default/grub /etc/systemd/system/grub-btrfs-regen.path /etc/systemd/system/grub-btrfs-regen.service \
         /usr/local/bin/grub-btrfs-regen /usr/local/bin/grub-btrfs-regen-auto /etc/sysconfig/snapper \
         /etc/dnf/libdnf5-plugins/actions.d/snapper.actions /etc/fstab; do
  [[ -e "$f" ]] && cp -a --parents "$f" "$R/sistema/"
done
efibootmgr -v > "$R/sistema/efibootmgr-v.txt" 2>&1 || true
lsblk -f -o +PARTUUID > "$R/sistema/lsblk-f.txt"
if [[ -d "$EXTRA_DIR" ]]; then
  cp -a "$EXTRA_DIR/." "$R/sistema/"
else
  echo "Sin root-extra: faltan /etc/snapper/configs/root y blkid (sudo $0 root-extra)" > "$R/sistema/FALTA-root-extra.txt"
fi

# d. ESP: el tar más reciente de backups/ con su sha256 (comprobado)
esp="$(ls -1 "$REPO"/backups/esp-efi-*.tar.gz 2>/dev/null | sort | tail -1)"
[[ -n "$esp" && -f "$esp.sha256" ]] || die "No hay tar de la ESP con .sha256 en backups/"
( cd "$(dirname "$esp")" && sha256sum -c --quiet "$(basename "$esp").sha256" ) || die "sha256 del tar de la ESP no coincide"
cp -a "$esp" "$esp.sha256" "$R/esp/"

# e. Recursos personales fuera del repo
vid="$(xdg-user-dir VIDEOS)/Wallpapers"
[[ -d "$vid" ]] && cp -a "$vid" "$R/personal/Videos-Wallpapers"
if ((PERSONAL)); then
  if [[ -f "$REPO/config/local.env" ]]; then cp -a "$REPO/config/local.env" "$R/personal/"
  else echo "config/local.env no existe" > "$R/personal/FALTA-local.env.txt"; fi
  # Notas de trabajo fuera del repo (estado, pendientes, informes, registros de pruebas)
  [[ -d "$OHOME/dotfiles-notas" ]] && cp -a "$OHOME/dotfiles-notas" "$R/personal/dotfiles-notas"
fi

# f. Escaneo: rutas prohibidas y contenido con aspecto de secreto (no se imprime el secreto)
bad_paths="$(cd "$R" && find . \( -ipath '*gemini*' -o -ipath '*antigravity*' -o -ipath '*/steam/*' \
  -o -ipath '*mozilla*' -o -ipath '*zen*' -o -ipath '*chrom*' -o -ipath '*/.ssh*' -o -ipath '*keyring*' \
  -o -name 'id_*' -o -name '*.pem' -o -name '*.key' \) -print)"
[[ -z "$bad_paths" ]] || die "rutas excluidas dentro del respaldo: $bad_paths"
re='BEGIN [A-Z ]*PRIVATE KEY|(password|passwd|contraseña|secret|api[_-]?key|access_token|refresh_token)[[:space:]]*[=:][[:space:]]*[^[:space:]]{4,}'
[[ -n "${EXTRA_SECRET_RE:-}" ]] && re="$re|$EXTRA_SECRET_RE"
# (personal/local.env contiene a propósito los valores propios del equipo: no se escanea)
hits="$(cd "$R" && grep -rIlEi --exclude=local.env -- "$re" . || true)"
if [[ -n "$hits" ]]; then
  echo "Posibles secretos (solo archivos, sin contenido):" >&2; echo "$hits" >&2
  die "revisar antes de generar el archivo"
fi

{
  echo "Respaldo de configuración ($FECHA, $(hostname)). Restaurar: docs/restauracion.md (dentro del bundle)."
  echo "repo/ git bundle de ~/dotfiles · usuario/ dconf, extensiones, rpm, Flatpak · sistema/ /etc, /usr/local, EFI, discos"
  echo "esp/ tar de la ESP (NO restaurar a ciegas en otro disco) · personal/ Vídeos/Wallpapers"
} > "$R/LEEME.txt"
( cd "$R" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256 )

# g. Un archivo + sha256 (y cifrado opcional)
tar -C "$WORK" --zstd -cf "$OUT.tmp" "$NAME" && mv "$OUT.tmp" "$OUT"
FINAL="$OUT"
if (( CIFRAR )); then
  echo "Cifrando con gpg --symmetric: escribe la contraseña en la ventana de gpg (este script no la ve)."
  if gpg --symmetric --cipher-algo AES256 --yes -o "$OUT.gpg" "$OUT"; then
    rm -f "$OUT"; FINAL="$OUT.gpg"
  else
    rm -f "$OUT" "$OUT.gpg"; die "gpg falló: no queda ningún archivo sin cifrar"
  fi
fi
( cd "$(dirname "$FINAL")" && sha256sum "$(basename "$FINAL")" > "$(basename "$FINAL").sha256" )
echo "OK: $FINAL ($(du -h "$FINAL" | cut -f1))"; cat "$FINAL.sha256"
