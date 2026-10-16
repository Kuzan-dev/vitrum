#!/usr/bin/env bash
# Mide GPU (nvidia-smi) y CPU con Waywallen en el usuario de pruebas (TEST_USER de config/local.env) y comprueba la pausa (docs/capas.md).
# Ejecutar desde el usuario principal; espera a que la sesión de pruebas esté en primer plano y desbloqueada, y avisa
# en esa sesión con una notificación al terminar (no tocar el ratón mientras tanto):
#   sudo ~/dotfiles/scripts/medir-waywallen.sh [segundos_por_fase] [ondas|we] > resultados.csv
# ondas (medios de prueba propios): base (sin daemon), video1080p30, video1440p60 (fps 60), maximizada
#   (una ventana), pantalla_completa (una ventana en cada monitor), juego_gamemode (vkcube con gamemoderun).
# we (Wallpaper Engine, ids del Workshop en WE_*): base, escena, maximizada y juego_gamemode con la
#   escena, web, video1080p y video4k, con los fps de config.toml.
# Columnas: medias de GPU y potencia, CPU (% de un núcleo) y estado de los renderizadores según el daemon.
# Al final restaura config.toml (fps y fondos elegidos) y arranca el daemon como el autoarranque.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo" >&2; exit 1; }
SECS="${1:-30}"; SET="${2:-ondas}"; SETTLE=10
# Fondos de Wallpaper Engine (ids del Workshop) para el conjunto we
WE_SCENE=1959836574 WE_WEB=1081733658 WE_V1080=1289832516 WE_V4K=3633510045
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
source "$REPO/scripts/lib/common.sh"; load_local_env TEST_USER MAIN_USER
U="$TEST_USER"; UIDN=$(id -u "$U"); UH="$(getent passwd "$U" | cut -d: -f6)"; APP=org.waywallen.waywallen
CFG=$UH/.var/app/$APP/config/waywallen/config.toml
DB=$UH/.var/app/$APP/data/waywallen/waywallen-v2.db
ENV=(env "HOME=$UH" "XDG_RUNTIME_DIR=/run/user/$UIDN" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UIDN/bus" WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland)
as_u() { runuser -u $U -- "${ENV[@]}" "$@"; }
dbus_d() { as_u gdbus call --session -d $APP.Daemon -o /org/waywallen/waywallen/Daemon "$@"; }

sess=$(loginctl list-sessions --no-legend | awk -v u=$U '$3==u && $4=="seat0"{print $1; exit}')
echo "Esperando a que la sesión de $U esté en primer plano y desbloqueada..." >&2
for _ in $(seq 450); do
  [[ "$(loginctl show-session "$sess" -p Active --value)" == yes &&
     "$(loginctl show-session "$sess" -p LockedHint --value)" == no ]] && break
  sleep 2
done
[[ "$(loginctl show-session "$sess" -p Active --value)" == yes ]] || { echo "La sesión de $U no pasó a primer plano" >&2; exit 1; }
sleep "$SETTLE"

item() { python3 -I -c 'import sqlite3,sys; c=sqlite3.connect(f"file:{sys.argv[1]}?mode=ro",uri=True)
print(c.execute("select id from item where display_name=?",(sys.argv[2],)).fetchone()[0])' "$DB" "$1"; }
by_ws() { python3 -I -c 'import sqlite3,sys; c=sqlite3.connect(f"file:{sys.argv[1]}?mode=ro",uri=True)
print(c.execute("select id from item where path like ?",(f"%/431960/{sys.argv[2]}%",)).fetchone()[0])' "$DB" "$1"; }

daemon_stop() { as_u flatpak kill $APP 2>/dev/null || true; sleep 3; }
daemon_start() { as_u setsid -f flatpak run --command=waywallen $APP --no-ui --display-backend gnome-shell >/dev/null 2>&1; sleep "$SETTLE"; }
set_fps() { sed -i "/^\[plugin.waywallen-video\]/,/^\[/ s/^fps = .*/fps = \"$1\"/" "$CFG"; }
apply() { dbus_d -m $APP.Daemon1.ApplyById "$1" >/dev/null; sleep "$SETTLE"; }
estado() { # «nombre fps estado; ...» de los renderizadores vivos
  local pid port; pid=$(pgrep -u $U -x waywallen) || { echo "sin daemon"; return; }
  port=$(dbus_d -m org.freedesktop.DBus.Properties.Get $APP.Daemon1 WsPort | grep -oE '[0-9]{4,5}')
  nsenter -t "$pid" -n python3 -I "$HERE/ww-ws.py" "$port" estado | { grep -v ' stopped$' || true; } | paste -sd ';'
}

# CPU (% de un núcleo) de un conjunto de procesos durante $SECS, en segundo plano
cpu_of() { # patrón-pgrep salida
  local hz; hz=$(getconf CLK_TCK)
  sum() { local t=0 p; for p in $(pgrep -u $U -f "$1"); do
            [[ -r /proc/$p/stat ]] && t=$((t + $(awk '{print $14+$15}' /proc/$p/stat 2>/dev/null || echo 0))); done; echo $t; }
  local a b; a=$(sum "$1"); sleep "$SECS"; b=$(sum "$1")
  echo "scale=1; ($b-$a)*100/$hz/$SECS" | bc > "$2"
}

measure() { # fase
  local d e; d=$(mktemp -d)
  cpu_of '^/usr/bin/gnome-shell( |$)' "$d/shell" &
  cpu_of 'waywallen' "$d/ww" &
  cpu_of 'waywallen-video|wescene|weweb' "$d/vid" &
  nvidia-smi --query-gpu=utilization.gpu,power.draw --format=csv,noheader,nounits -lms 1000 > "$d/gpu" &
  local np=$!; sleep $((SECS / 2)); e=$(estado || true); sleep $((SECS - SECS / 2)); kill $np; wait 2>/dev/null || true
  awk -F', ' -v f="$1" -v s="$(cat "$d/shell")" -v w="$(cat "$d/ww")" -v v="$(cat "$d/vid")" -v e="$e" \
    '{g+=$1; p+=$2; if($1>m)m=$1; n++} END{printf "%s,%.1f,%d,%.1f,%s,%s,%s,%s\n", f, g/n, m, p/n, s, w, v, e}' "$d/gpu"
  rm -rf "$d"
}

# Ventanas de prueba GTK4 que se cierran solas: maximize (una) | fullscreen (una por monitor)
testwin() { # modo segundos
  as_u setsid -f python3 -I -c '
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib
app = Gtk.Application(application_id="io.dotfiles.medir")
def on(a):
    if sys.argv[1] == "maximize":
        w = Gtk.ApplicationWindow(application=a, title="prueba"); w.maximize(); w.present()
    else:
        mons = Gdk.Display.get_default().get_monitors()
        for i in range(mons.get_n_items()):
            w = Gtk.ApplicationWindow(application=a, title="prueba")
            w.fullscreen_on_monitor(mons.get_item(i)); w.present()
    GLib.timeout_add_seconds(int(sys.argv[2]), a.quit)
app.connect("activate", on); app.run([])' "$1" "$2" >/dev/null 2>&1
}

echo "fase,gpu_media_%,gpu_max_%,potencia_W,cpu_shell_%,cpu_waywallen_%,cpu_renderer_%,renderizadores"
cp "$CFG" "$CFG.medir.bak"
game() { as_u setsid -f gamemoderun vkcube >/dev/null 2>&1; sleep "$SETTLE"; measure juego_gamemode; pkill -u $U -x vkcube 2>/dev/null || true; sleep 3; }
if [[ "$SET" == we ]]; then
  daemon_stop;                       measure base
  daemon_start; apply "$(by_ws $WE_SCENE)"; measure escena
  testwin maximize $((SECS + SETTLE)); sleep "$SETTLE"; measure maximizada; sleep 3
  game
  apply "$(by_ws $WE_WEB)";          measure web
  apply "$(by_ws $WE_V1080)";        measure video1080p
  apply "$(by_ws $WE_V4K)";          measure video4k
else
  I30=$(item ondas-1080p30); I60=$(item ondas-1440p60)
  daemon_stop;                                   measure base
  set_fps 30; daemon_start; apply "$I30";        measure video1080p30
  daemon_stop; set_fps 60; daemon_start; apply "$I60"; measure video1440p60
  testwin maximize $((SECS + SETTLE)); sleep "$SETTLE";   measure maximizada; sleep 3
  testwin fullscreen $((SECS + SETTLE)); sleep "$SETTLE"; measure pantalla_completa; sleep 3
  game
fi
daemon_stop; cp "$CFG.medir.bak" "$CFG"; daemon_start
as_u notify-send "Medición de Waywallen terminada" "Puedes volver a $MAIN_USER." || true
