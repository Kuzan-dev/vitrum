#!/usr/bin/env bash
# Deshace la instalación de Waywallen en el usuario que lo ejecuta (docs/vuelta-atras.md). COMO ese usuario,
# sin sudo (también desde una TTY: Ctrl+Alt+F3):
#
#   ~/dotfiles/scripts/rollback-waywallen.sh                          dirigido, copia más reciente
#   ~/dotfiles/scripts/rollback-waywallen.sh [AAAA-MM-DD-HHMM] [--completo]
#
# Dirigido (por defecto): quita solo lo que instaló la migración.
# 1. Extensión fuera de enabled-extensions (valor de la copia) y borrada.
# 2. Daemon parado, arranque automático borrado.
# 3. Flatpak de usuario desinstalado con sus datos y runtimes sin uso; el remoto flathub de usuario
#    solo si lo añadió visual.sh (marca ~/.local/share/flatpak/.dotfiles-flathub-added).
# 4. Vídeos de prueba ondas-*.mp4 de ~/Vídeos/Wallpapers (y la carpeta si queda vacía).
# --completo: además restaura ~/.config y ~/.var enteros desde los tar y carga el volcado dconf
#   entero (pierde cambios hechos después de la copia en esas rutas).
# No toca Steam, el HDR, monitors.xml ni nada fuera del HOME. Cerrar sesión y volver a entrar al final.
set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "Ejecuta como el usuario (sin sudo)" >&2; exit 1; }
U="$(id -un)"
BK="$(cd "$(dirname "$0")/.." && pwd)/backups"
TS=""; FULL=0
for a in "$@"; do case "$a" in --completo) FULL=1 ;; *) TS="$a" ;; esac; done
[[ -n "$TS" ]] || TS="$(find "$BK" -maxdepth 1 -name "dconf-$U-*-pre-waywallen.ini" -printf '%f\n' | sort | tail -1 |
                      sed "s/^dconf-$U-//; s/-pre-waywallen.ini\$//")"
INI="$BK/dconf-$U-$TS-pre-waywallen.ini"
CFG_TAR="$BK/$U-$TS-pre-waywallen-config.tar.gz"; VAR_TAR="$BK/$U-$TS-pre-waywallen-var.tar.gz"
[[ -f "$INI" ]] || { echo "No encuentro $INI" >&2; exit 1; }
(( FULL == 0 )) || [[ -f "$CFG_TAR" && -f "$VAR_TAR" ]] || { echo "Faltan $CFG_TAR o $VAR_TAR" >&2; exit 1; }
echo "Restaurando desde la copia $TS ($( ((FULL)) && echo completo || echo dirigido))"

APP=org.waywallen.waywallen UUID=org.waywallen.gnome@waywallen.io
# Sin sesión gráfica (TTY) dconf necesita un bus propio
run() { if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then "$@"; else dbus-run-session -- "$@"; fi; }

# 1. Extensión: enabled-extensions como estaba en la copia
prev="$(python3 -I - "$INI" <<'PY'
import configparser, sys
c = configparser.RawConfigParser(interpolation=None); c.optionxform = str; c.read(sys.argv[1])
print(c.get("org/gnome/shell", "enabled-extensions", fallback="@as []"))
PY
)"
run gsettings set org.gnome.shell enabled-extensions "$prev"
rm -rf "$HOME/.local/share/gnome-shell/extensions/$UUID"

# 2. Daemon y arranque automático
flatpak kill "$APP" 2>/dev/null || true
pkill -u "$(id -u)" -x waywallen 2>/dev/null || true
rm -f "$HOME/.config/autostart/waywallen.desktop"
rmdir "$HOME/.config/autostart" 2>/dev/null || true

# 3. Flatpak de usuario
flatpak --user mask --remove "$APP" 2>/dev/null || true
flatpak --user uninstall -y --noninteractive --delete-data "$APP" 2>/dev/null || true
flatpak --user uninstall -y --noninteractive --unused 2>/dev/null || true
if [[ -f "$HOME/.local/share/flatpak/.dotfiles-flathub-added" ]]; then
  flatpak --user remote-delete flathub 2>/dev/null || true
  rm -f "$HOME/.local/share/flatpak/.dotfiles-flathub-added"
fi
rm -rf "$HOME/.var/app/$APP"

# 4. Vídeos de prueba
VID="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Vídeos")/Wallpapers"
rm -f "$VID/ondas-1080p30.mp4" "$VID/ondas-1440p60.mp4"
rmdir "$VID" 2>/dev/null || true

if (( FULL )); then
  tar -C "$HOME" -xzf "$CFG_TAR"
  tar -C "$HOME" -xzf "$VAR_TAR"
  # Sin las claves bloqueadas por el sistema (login-screen de authselect): con una sola, dconf load
  # rechaza el volcado entero
  python3 -I - "$INI" /etc/dconf/db/*.d/locks/* <<'PY' | run dconf load /
import configparser, sys
locks = set()
for f in sys.argv[2:]:
    try:
        locks |= {l.strip() for l in open(f) if l.startswith("/")}
    except OSError:
        pass
c = configparser.RawConfigParser(interpolation=None); c.optionxform = str; c.read(sys.argv[1])
for s in c.sections():
    keys = [k for k in c[s] if f"/{s}/{k}" not in locks]
    if keys:
        print(f"[{s}]")
        for k in keys:
            print(f"{k}={c[s][k]}")
        print()
PY
fi
echo "Hecho. Cierra sesión y vuelve a entrar."
