#!/usr/bin/env bash
# Fase 3: apariencia estilo macOS (referencia visual: eqSh) sobre GNOME 50.
# Todo se instala en el HOME del usuario destino (~/.local/share, ~/.config); nada en /usr.
# Versiones fijadas en config/visual/pins.env (tag + commit + sha256).
#
#   sudo ./visual.sh <usuario> theme       subpaso 1: tema GTK3 MacTahoe-Dark, iconos y cursor MacTahoe, acento azul
#   sudo ./visual.sh <usuario> gtk4        paso 5: ~/.config/gtk-4.0/gtk.css mínimo (semáforos + tono de barra lateral)
#   sudo ./visual.sh <usuario> shell-theme paso 1 del rediseño: tema de shell GoldenGate (plantilla + tokens) y
#                                          User Themes con name='GoldenGate'
#   sudo ./visual.sh <usuario> cleanup     paso 0 del rediseño: quita widgets, notch y User Themes→MacTahoe;
#                                          restaura el CSS original del shell de MacTahoe (sha256)
#   sudo ./visual.sh <usuario> extensions  subpaso 2: Dash to Dock, Blur my Shell, Just Perfection, Logo Menu
#                                          (zips fijados + parches si existen) + ajustes del dock; fuera background-logo
#   sudo ./visual.sh <usuario> dock        aplica los ajustes de config/visual/dash-to-dock.conf
#   sudo ./visual.sh <usuario> glass       barra y dock con desenfoque: variante de config/visual/glass/variant
#   sudo ./visual.sh <usuario> waywallen  fondo animado (Flatpak --user fijado + extensión); waywallen-remove lo deshace
#   sudo ./visual.sh <usuario> waywallen-profile abierto|restringido
#                                          permisos del Flatpak, audio y biblioteca de Steam (docs/capas.md)
#   sudo ./visual.sh <usuario> appindicator iconos de apps en segundo plano en la barra (AppIndicator v66; estilo en
#                                          config/visual/shell-theme/tray/variant: dentro | propia)
#   sudo ./visual.sh <usuario> mutter-scanout  desactiva el escaneo directo de Mutter (parpadeo del dock en el LG
#                                          tras cambiar de usuario, docs/capas.md); mutter-scanout-remove lo quita
#   sudo ./visual.sh <usuario> panel       subpaso 3: Blur my Shell, Just Perfection, Logo Menu (config/visual/panel.conf)
#   sudo ./visual.sh <usuario> wallpaper   fondo Series of Tubes claro/oscuro (pins.env → ~/.local/share/backgrounds)
#   sudo ./visual.sh <usuario> status      muestra los ajustes actuales (no cambia nada)
#
# Dos modos: como el propio usuario, sin sudo (`./visual.sh $USER <paso>`, lo que usa install.sh user), o
# como root para otro usuario (`sudo ./visual.sh <usuario> <paso>`). Lo creado queda a nombre del usuario.
# Los ajustes (gsettings) se aplican en el bus de sesión del usuario si tiene sesión abierta
# (los cambios se ven al momento); si no, con dbus-run-session.
#
# Idempotente: cada escritura compara antes de actuar (carpetas y archivos por contenido, gsettings por
# valor tipado) y se salta lo que ya está bien. DRY_RUN=1: solo anuncia lo que cambiaría («CAMBIARÍA:»).
# Al final imprime «CAMBIOS: N». Opcionales de Waywallen: WW_OWE=1 (open-wallpaper-engine, biblioteca de
# Steam) y WW_MEDIA=1 (vídeos de prueba).
set -euo pipefail

DRY="${DRY_RUN:-0}"; CAMBIOS=0; LAST_CHANGED=0
# Una sola carpeta temporal por ejecución, borrada siempre al salir (antes cada paso ponía su propio trap y,
# cuando un paso llamaba a otro, la primera carpeta —con ~80 000 archivos de iconos— quedaba en /tmp).
# 755: en modo root, el usuario destino debe poder entrar (el instalador de iconos corre como él).
TMPROOT="$(mktemp -d)"; chmod 755 "$TMPROOT"; trap 'rm -rf "$TMPROOT"' EXIT
SELF=0; [[ $EUID -eq 0 ]] || SELF=1
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/visual/pins.env
source "$REPO/config/visual/pins.env"
source "$REPO/scripts/lib/common.sh"
load_local_env   # MAIN_USER / TEST_USER si existen (config/local.env)

TARGET="${1:-}"; STEP="${2:-}"
id "$TARGET" &>/dev/null || { echo "Uso: sudo $0 <usuario> <theme|gtk4|extensions|dock|panel|glass|appindicator|mutter-scanout|mutter-scanout-remove|waywallen|waywallen-remove|waywallen-profile|wallpaper|shell-theme|cleanup|status>" >&2; exit 1; }
UHOME="$(getent passwd "$TARGET" | cut -d: -f6)"
UID_T="$(id -u "$TARGET")"
[[ "$TARGET" != root && -d "$UHOME" ]] || { echo "Usuario destino no válido" >&2; exit 1; }
((SELF == 0)) || [[ "$TARGET" == "$(id -un)" ]] || { echo "Sin sudo solo puedes aplicarlo a tu usuario ($(id -un))" >&2; exit 1; }

die() { echo "ERROR: $*" >&2; exit 1; }

# Registra un cambio (o lo anuncia en DRY_RUN)
cambio() {
  CAMBIOS=$((CAMBIOS + 1))
  if ((DRY)); then echo "  CAMBIARÍA: $*"; else echo "  cambio: $*"; fi
}

# Ejecuta un comando como el usuario destino, con su HOME
as_user() {
  if ((SELF)); then env HOME="$UHOME" "$@"; else runuser -u "$TARGET" -- env HOME="$UHOME" "$@"; fi
}

# Ejecuta un comando de dconf/gsettings como el usuario destino: en su bus de sesión si la
# tiene abierta; si no, con dbus-run-session y un XDG_RUNTIME_DIR temporal suyo (sudo deja
# /run/user/0, que el usuario no puede usar y dconf no guardaría nada)
user_dbus() {
  local bus="/run/user/$UID_T/bus"
  if [[ -S "$bus" ]]; then
    as_user env XDG_RUNTIME_DIR="/run/user/$UID_T" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" "$@"
  else
    local rt rc=0; rt="$(mktemp -d)"; chown "$TARGET:" "$rt"; chmod 700 "$rt"
    as_user env XDG_RUNTIME_DIR="$rt" dbus-run-session -- "$@" || rc=$?
    rm -rf "$rt"; return $rc
  fi
}

# gsettings con comparación previa en «set»: si la clave ya tiene ese valor (como GVariant de su tipo)
# no hace nada; si no, registra el cambio y, salvo en DRY_RUN, lo aplica
gs() {
  local -a sdir=() a=("$@")
  if [[ "${a[0]}" == --schemadir ]]; then sdir=(--schemadir "${a[1]}"); a=("${a[@]:2}"); fi
  if [[ "${a[0]}" == set ]]; then
    local cur rng
    if [[ ${#sdir[@]} -eq 0 || -d "${sdir[1]}" ]] \
       && cur="$(user_dbus gsettings "${sdir[@]}" get "${a[1]}" "${a[2]}" 2>/dev/null)" \
       && rng="$(user_dbus gsettings "${sdir[@]}" range "${a[1]}" "${a[2]}" 2>/dev/null)" \
       && python3 -I "$REPO/scripts/lib/gvariant_eq.py" "$rng" "$cur" "${a[3]}"; then
      return 0
    fi
    cambio "gsettings ${a[1]#org.gnome.} ${a[2]}"
    ((DRY)) && return 0
  fi
  user_dbus gsettings "$@"
}

# Copia un archivo si su contenido cambia
inst_file() { # origen destino(absoluto) modo
  LAST_CHANGED=0
  [[ -f "$2" ]] && cmp -s "$1" "$2" && return 0
  # .desktop: el texto descriptivo (Comment) no cuenta como cambio
  [[ "$2" == *.desktop && -f "$2" ]] && cmp -s <(grep -v '^Comment' "$1") <(grep -v '^Comment' "$2") && return 0
  LAST_CHANGED=1; cambio "archivo ${2/#$UHOME/\~}"
  ((DRY)) && return 0
  as_user mkdir -p "$(dirname "$2")"
  install -o "$TARGET" -g "$TARGET" -m "$3" "$1" "$2"
}

# Descarga el tarball de un tag de GitHub y verifica sha256 → directorio extraído
fetch_tag() { # repo tag commit sha256 destdir
  local repo="$1" tag="$2" commit="$3" sha="$4" dest="$5" remote
  remote="$(git ls-remote "https://github.com/$repo.git" "refs/tags/$tag" | cut -f1)"
  [[ "$remote" == "$commit" ]] || die "$repo@$tag apunta a '$remote', se esperaba $commit"
  curl -sSfL -o "$dest/src.tar.gz" "https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
  echo "$sha  $dest/src.tar.gz" | sha256sum -c --quiet || die "sha256 de $repo@$tag no coincide"
  tar xzf "$dest/src.tar.gz" -C "$dest"
}

# Copia un directorio a $UHOME/<rel> con renombrado (carpeta nueva → mv), solo si su contenido cambia
install_dir() { # src rel
  local src="$1" dst="$UHOME/$2"
  LAST_CHANGED=0
  [[ -d "$dst" ]] && diff -rq --no-dereference "$src" "$dst" >/dev/null 2>&1 && return 0
  LAST_CHANGED=1; cambio "carpeta ~/$2"
  ((DRY)) && return 0
  as_user mkdir -p "$(dirname "$dst")"
  rm -rf "$dst.new"; cp -r "$src" "$dst.new"; chown -R "$TARGET:" "$dst.new"
  rm -rf "$dst.old"; [[ -e "$dst" ]] && mv "$dst" "$dst.old"
  mv "$dst.new" "$dst"; rm -rf "$dst.old"
}

step_theme() {
  # tmp es global: el trap EXIT se ejecuta fuera de la función
  tmp="$(mktemp -d -p "$TMPROOT")"
  chmod 755 "$tmp"

  # 1. GTK3: tema precompilado de release/ (no se ejecuta install.sh: usaría sudo dnf)
  mkdir "$tmp/gtk"
  fetch_tag vinceliuice/MacTahoe-gtk-theme "$MACTAHOE_GTK_TAG" "$MACTAHOE_GTK_COMMIT" "$MACTAHOE_GTK_SHA256" "$tmp/gtk"
  local rel="$tmp/gtk/MacTahoe-gtk-theme-$MACTAHOE_GTK_TAG/release/$MACTAHOE_GTK_VARIANT.tar.xz"
  echo "$MACTAHOE_GTK_RELEASE_SHA256  $rel" | sha256sum -c --quiet || die "sha256 de $MACTAHOE_GTK_VARIANT.tar.xz no coincide"
  tar xJf "$rel" -C "$tmp/gtk"
  install_dir "$tmp/gtk/$MACTAHOE_GTK_VARIANT" ".local/share/themes/$MACTAHOE_GTK_VARIANT"

  # 2. Iconos: su install.sh, como el usuario (sin root instala en ~/.local/share/icons)
  mkdir "$tmp/icon"
  fetch_tag vinceliuice/MacTahoe-icon-theme "$MACTAHOE_ICON_TAG" "$MACTAHOE_ICON_COMMIT" "$MACTAHOE_ICON_SHA256" "$tmp/icon"
  local isrc="$tmp/icon/MacTahoe-icon-theme-$MACTAHOE_ICON_TAG"
  mkdir "$tmp/icon-out"; chown -R "$TARGET:" "$tmp/icon" "$tmp/icon-out"
  (cd "$isrc" && as_user ./install.sh -d "$tmp/icon-out" >/dev/null)
  local d
  for d in "$tmp/icon-out"/*/; do install_dir "${d%/}" ".local/share/icons/$(basename "$d")"; done

  # 3. Cursores precompilados (dist = claro, dist-dark = oscuro)
  install_dir "$isrc/cursors/dist" ".local/share/icons/MacTahoe-cursors"
  install_dir "$isrc/cursors/dist-dark" ".local/share/icons/MacTahoe-dark-cursors"

  # 4. Ajustes de escritorio
  gs set org.gnome.desktop.interface gtk-theme "$MACTAHOE_GTK_VARIANT"
  gs set org.gnome.desktop.interface icon-theme "MacTahoe-dark"
  gs set org.gnome.desktop.interface cursor-theme "MacTahoe-cursors"
  gs set org.gnome.desktop.interface color-scheme "prefer-dark"
  # Acento: ACCENT_COLOR de config/local.env (azul por defecto)
  local acc="${ACCENT_COLOR:-blue}"
  case "$acc" in blue|teal|green|yellow|orange|red|pink|purple|slate) ;; *) die "ACCENT_COLOR no válido: $acc" ;; esac
  gs set org.gnome.desktop.interface accent-color "$acc"
  gs set org.gnome.desktop.wm.preferences button-layout "close,minimize,maximize:"

  # 5. GTK4 / libadwaita y GNOME Shell overrides
  step_gtk4
  step_status
}

step_gtk4() {
  # Paso 5 del rediseño: ~/.config/gtk-4.0 solo con el gtk.css mínimo del repo (semáforos + tono de
  # barra lateral). Sin redefinir colores: el acento y el modo claro/oscuro de libadwaita siguen
  # funcionando. Sustituye la carpeta entera (antes, copia completa del GTK4 de MacTahoe).
  tmp="$(mktemp -d -p "$TMPROOT")"
  mkdir "$tmp/gtk-4.0"
  install -m 0644 "$REPO/config/visual/gtk4/gtk.css" "$tmp/gtk-4.0/gtk.css"
  install_dir "$tmp/gtk-4.0" ".config/gtk-4.0"
}

step_extensions() {
  # tmp es global: el trap EXIT se ejecuta fuera de la función
  tmp="$(mktemp -d -p "$TMPROOT")"
  local extdir=".local/share/gnome-shell/extensions" entry uuid ver pk sha url d
  local -a uuids=()

  for entry in "${EXTENSIONS[@]}"; do
    IFS='|' read -r uuid ver pk sha <<<"$entry"
    url="https://extensions.gnome.org/download-extension/$uuid.shell-extension.zip?version_tag=$pk"
    curl -sSfL -o "$tmp/$uuid.zip" "$url"
    echo "$sha  $tmp/$uuid.zip" | sha256sum -c --quiet || die "sha256 de $uuid v$ver no coincide"
    d="$tmp/$uuid"; mkdir "$d"; unzip -q "$tmp/$uuid.zip" -d "$d"

    # El metadata.json debe ser el esperado y declarar GNOME 50
    python3 -I - "$d/metadata.json" "$uuid" "$ver" <<'PY' || die "metadata.json de $uuid no es la versión esperada para GNOME 50"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["uuid"] == sys.argv[2] and str(m["version"]) == sys.argv[3] and "50" in m["shell-version"]
PY
    local patch="$REPO/config/visual/patches/$uuid.patch"
    if [[ -f "$patch" ]]; then
      echo "Aplicando parche a $uuid: $(basename "$patch")"
      (cd "$d" && patch -p1 --forward < "$patch") || die "Fallo al aplicar parche en $uuid"
    fi

    [[ -d "$d/schemas" ]] && glib-compile-schemas "$d/schemas"
    install_dir "$d" "$extdir/$uuid"
    uuids+=("$uuid")
  done


  # Activar: las extensiones de EXTENSIONS, conservando las que ya estuvieran activas (Waywallen,
  # AppIndicator…: antes este paso reescribía la lista y las desactivaba)
  local cur list
  cur="$(gs get org.gnome.shell enabled-extensions)"
  # (y sin background-logo, el logo de Fedora sobre el fondo, activo por defecto en usuarios nuevos)
  list="$(python3 -I -c 'import ast,sys; s=sys.argv[1].strip(); c=[] if s.startswith("@as") else ast.literal_eval(s); c=[u for u in c if u != "background-logo@fedorahosted.org"]; c+=[u for u in sys.argv[2:] if u not in c]; print(repr(c))' "$cur" "${uuids[@]}")"
  gs set org.gnome.shell disable-user-extensions false
  gs set org.gnome.shell enabled-extensions "$list"

  # Dash to Dock: ajustes de config/visual/dash-to-dock.conf (esquema de la propia extensión)
  step_dock

  ((DRY)) || step_status
}

step_dock() {
  local extdir="$UHOME/.local/share/gnome-shell/extensions"
  local schemadir="$extdir/dash-to-dock@micxgx.gmail.com/schemas" key val
  if [[ ! -d "$schemadir" ]]; then
    ((DRY)) && { cambio "ajustes de Dash to Dock (la extensión aún no está instalada)"; return 0; }
    die "Falta el esquema de Dash to Dock en $schemadir (ejecuta antes el subpaso extensions)"
  fi
  while read -r key val; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    gs --schemadir "$schemadir" set org.gnome.shell.extensions.dash-to-dock "$key" "$val"
  done < "$REPO/config/visual/dash-to-dock.conf"
  ((DRY)) || echo "Dash to Dock configurado desde $REPO/config/visual/dash-to-dock.conf"
}

# Aplica un archivo con líneas "<uuid> <esquema> <clave> <valor>" (formato de panel.conf)
apply_conf() { # archivo
  local extdir="$UHOME/.local/share/gnome-shell/extensions" uuid schema key val
  while read -r uuid schema key val; do
    [[ -z "$uuid" || "$uuid" == \#* ]] && continue
    if [[ ! -d "$extdir/$uuid/schemas" ]]; then
      ((DRY)) && { cambio "$schema $key (la extensión $uuid aún no está instalada)"; continue; }
      die "Falta $uuid (ejecuta antes el paso extensions)"
    fi
    gs --schemadir "$extdir/$uuid/schemas" set "$schema" "$key" "$val"
  done < "$1"
}

step_glass() {
  # Barra y dock con desenfoque: variante de config/visual/glass/variant (sutil|media|cristal)
  local v
  v="$(grep -vE '^\s*(#|$)' "$REPO/config/visual/glass/variant" | head -1 | tr -d '[:space:]')"
  [[ -f "$REPO/config/visual/glass/$v.conf" ]] || die "Variante de cristal desconocida: '$v'"
  apply_conf "$REPO/config/visual/glass/$v.conf"
  local sd="$UHOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas" s
  ((DRY)) && return 0
  echo "Variante de cristal aplicada: $v"
  for s in panel dash-to-dock; do
    printf '%-14s blur=%s static=%s pipeline=%s override=%s\n' "$s" \
      "$(gs --schemadir "$sd" get org.gnome.shell.extensions.blur-my-shell.$s blur)" \
      "$(gs --schemadir "$sd" get org.gnome.shell.extensions.blur-my-shell.$s static-blur)" \
      "$(gs --schemadir "$sd" get org.gnome.shell.extensions.blur-my-shell.$s pipeline)" \
      "$(gs --schemadir "$sd" get org.gnome.shell.extensions.blur-my-shell.$s override-background)"
  done
}

step_panel() {
  # Ajustes de config/visual/panel.conf: <uuid> <esquema> <clave> <valor>
  local extdir="$UHOME/.local/share/gnome-shell/extensions" uuid schema key val
  while read -r uuid schema key val; do
    [[ -z "$uuid" || "$uuid" == \#* ]] && continue
    if [[ ! -d "$extdir/$uuid/schemas" ]]; then
      ((DRY)) && { cambio "$schema $key (la extensión $uuid aún no está instalada)"; continue; }
      die "Falta $uuid (ejecuta antes el subpaso extensions)"
    fi
    gs --schemadir "$extdir/$uuid/schemas" set "$schema" "$key" "$val"
  done < "$REPO/config/visual/panel.conf"
  ((DRY)) && return 0
  # Mostrar el resultado
  while read -r uuid schema key val; do
    [[ -z "$uuid" || "$uuid" == \#* ]] && continue
    printf '%-45s %-30s %s\n' "${schema#org.gnome.shell.extensions.}" "$key" \
      "$(gs --schemadir "$extdir/$uuid/schemas" get "$schema" "$key")"
  done < "$REPO/config/visual/panel.conf"
}


step_wallpaper() {
  local custom="${3:-}"
  local bgdir="$UHOME/.local/share/backgrounds"
  local dst="" dst_light=""

  if [[ -n "$custom" ]]; then
    if [[ -f "$custom" ]]; then
      dst="$custom"
    else
      die "No se encontró el fondo: $custom"
    fi
  else
    # Fondo fijado en pins.env: versión clara (picture-uri) y oscura (picture-uri-dark)
    local src sha
    for v in LIGHT DARK; do
      src="WALLPAPER_${v}_SRC"; sha="WALLPAPER_${v}_SHA256"; src="${!src}"; sha="${!sha}"
      echo "$sha  $src" | sha256sum -c --quiet || die "sha256 de $src no coincide"
      dst="$bgdir/$(basename "$src")"
      inst_file "$src" "$dst" 0644
      [[ $v == LIGHT ]] && dst_light="$dst"
    done
  fi

  local uri="file://$dst" uri_light="file://$dst"
  [[ -n "${dst_light:-}" ]] && uri_light="file://$dst_light"
  gs set org.gnome.desktop.background picture-uri "$uri_light"
  gs set org.gnome.desktop.background picture-uri-dark "$uri"
  gs set org.gnome.desktop.background picture-options 'zoom'
  gs set org.gnome.desktop.screensaver picture-uri "$uri"
  gs set org.gnome.desktop.screensaver picture-options 'zoom'

  ((DRY)) && return 0
  echo "Fondo aplicado: $dst"
  step_status
}


step_cleanup() {
  # Paso 0 del rediseño (docs/capas.md). Idempotente.
  local extdir="$UHOME/.local/share/gnome-shell/extensions" cur new
  local -a remove=(widgets@distro.com orbit@unmade.space user-theme@gnome-shell-extensions.gcampax.github.com)

  # 1. Desactivar widgets, notch y User Themes (esta queda instalada para el tema propio del paso 1)
  cur="$(gs get org.gnome.shell enabled-extensions)"
  new="$(python3 -I - "$cur" "${remove[@]}" <<'PY'
import ast, sys
s = sys.argv[1].strip()
cur = [] if s.startswith("@as") else ast.literal_eval(s)
print(repr([u for u in cur if u not in sys.argv[2:]]))
PY
)"
  gs set org.gnome.shell enabled-extensions "$new"

  # 2. Ajustes que dejaron en dconf
  user_dbus dconf reset -f /org/gnome/shell/extensions/widgets-distro-com/
  user_dbus dconf reset -f /org/gnome/shell/extensions/user-theme/

  # 3. Borrar las extensiones de widgets y notch
  rm -rf "$extdir/widgets@distro.com" "$extdir/orbit@unmade.space"

  # 4. CSS del shell de MacTahoe: volver al original del release fijado (sha256)
  local css="$UHOME/.local/share/themes/$MACTAHOE_GTK_VARIANT/gnome-shell/gnome-shell.css"
  if [[ -f "$css.orig" ]]; then
    echo "$MACTAHOE_SHELL_CSS_SHA256  $css.orig" | sha256sum -c --quiet || die "$css.orig no es el original"
    mv -f "$css.orig" "$css"
  fi
  if [[ -f "$css" ]]; then
    echo "$MACTAHOE_SHELL_CSS_SHA256  $css" | sha256sum -c --quiet || die "$css no es el original del release"
  fi

  # 5. Enlace ~/.themes que usaba User Themes
  [[ -L "$UHOME/.themes/$MACTAHOE_GTK_VARIANT" ]] && rm -f "$UHOME/.themes/$MACTAHOE_GTK_VARIANT"
  rmdir "$UHOME/.themes" 2>/dev/null || true

  step_status
  ls "$extdir"
}

step_shell_theme() {
  # Paso 1 del rediseño (docs/capas.md). Idempotente.
  local src="$REPO/config/visual/shell-theme" name="GoldenGate"
  local ut_uuid="user-theme@gnome-shell-extensions.gcampax.github.com"
  local ut_schemas="$UHOME/.local/share/gnome-shell/extensions/$ut_uuid/schemas"
  if [[ ! -d "$ut_schemas" ]]; then
    ((DRY)) && { cambio "tema de la shell GoldenGate (User Themes aún no está instalada)"; return 0; }
    die "Falta User Themes en $ut_schemas (ejecuta antes el paso extensions)"
  fi

  # 1. Generar el CSS: plantilla + tokens.env; aborta si queda algún @MARCADOR@
  tmp="$(mktemp -d -p "$TMPROOT")"
  mkdir -p "$tmp/$name/gnome-shell"
  # Variante de la bandeja (AppIndicator): un fragmento que se añade al final de la plantilla
  local tray; tray="$(grep -v '^#' "$src/tray/variant" | grep -m1 .)"
  [[ -f "$src/tray/$tray.css.in" ]] || die "Variante de bandeja desconocida: $tray"
  python3 -I - "$src/tokens.env" "$src/$name/gnome-shell/gnome-shell.css.in" \
    "$tmp/$name/gnome-shell/gnome-shell.css" "$src/tray/$tray.css.in" <<'PY' || die "No se pudo generar el CSS de $name"
import re, shlex, sys
tokens = {}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    key, _, val = line.partition("=")
    tokens[key.strip()] = shlex.split(val)[0]
css = open(sys.argv[2]).read() + open(sys.argv[4]).read()
for key, val in tokens.items():
    css = css.replace(f"@{key}@", val)
left = sorted(set(re.findall(r"@[A-Z_]+@", css)))
if left:
    sys.exit(f"Marcadores sin valor: {left}")
open(sys.argv[3], "w").write(css)
PY
  install_dir "$tmp/$name" ".local/share/themes/$name"
  local css_cambio=$LAST_CHANGED

  # 2. Activar User Themes (si no lo está) y apuntarla a GoldenGate
  local cur new
  cur="$(gs get org.gnome.shell enabled-extensions)"
  new="$(python3 -I - "$cur" "$ut_uuid" <<'PY'
import ast, sys
s = sys.argv[1].strip()
cur = [] if s.startswith("@as") else ast.literal_eval(s)
if sys.argv[2] not in cur:
    cur.append(sys.argv[2])
print(repr(cur))
PY
)"
  gs set org.gnome.shell enabled-extensions "$new"
  # User Themes no relee el CSS si el nombre no cambia: vaciarlo y volver a ponerlo lo recarga en vivo.
  # Solo con la sesión desbloqueada: bloqueada, GNOME desactiva User Themes (no declara el modo
  # unlock-dialog) y su v79 deja un manejador colgado que da JS ERROR al cambiar el nombre.
  # Bloqueada, el CSS nuevo se carga solo al desbloquear (la extensión se reactiva).
  local sess locked=yes
  sess="$(loginctl list-sessions --no-legend | awk -v u="$TARGET" '$3==u && $4=="seat0"{print $1; exit}')"
  [[ -n "$sess" ]] && locked="$(loginctl show-session "$sess" -p LockedHint --value)"
  if ((css_cambio)) && ! ((DRY)) && [[ "$locked" == no && "$(gs --schemadir "$ut_schemas" get org.gnome.shell.extensions.user-theme name)" == "'$name'" ]]; then
    gs --schemadir "$ut_schemas" set org.gnome.shell.extensions.user-theme name ''
    sleep 1
  fi
  gs --schemadir "$ut_schemas" set org.gnome.shell.extensions.user-theme name "$name"

  ((DRY)) && return 0
  sha256sum "$UHOME/.local/share/themes/$name/gnome-shell/gnome-shell.css"
  printf '%-14s %s\n' user-theme "$(gs --schemadir "$ut_schemas" get org.gnome.shell.extensions.user-theme name)"
  step_status
}

step_mutter_scanout() {
  # Evita el parpadeo del dock en el LG tras cambiar de usuario (docs/capas.md): desactiva el escaneo
  # directo de Mutter para la sesión del usuario, con ~/.config/environment.d (sin /etc). El gestor de
  # usuario de systemd sobrevive al cierre de sesión y solo lee environment.d al arrancar o recargar: se
  # recarga y se fija también en vivo, para que el próximo gnome-shell la herede. Efecto al volver a entrar.
  local f="90-mutter-scanout.conf" d="$UHOME/.config/environment.d" x
  inst_file "$REPO/config/visual/environment.d/$f" "$d/$f" 0644
  for x in 90-clutter-prueba.conf 90-clutter-prueba.conf.desactivado; do   # restos de las pruebas del parpadeo
    [[ -e "$d/$x" ]] && { cambio "borrar ~/.config/environment.d/$x"; ((DRY)) || rm -f "$d/$x"; }
  done
  # Gestor de usuario en marcha (sesión abierta): fijar la variable en vivo para el próximo gnome-shell
  if [[ -S "/run/user/$UID_T/bus" ]] && \
     ! user_dbus systemctl --user show-environment 2>/dev/null | grep -qx 'MUTTER_DEBUG_PAINT=disable-direct-scanout'; then
    cambio "MUTTER_DEBUG_PAINT en el gestor de usuario (efecto al volver a iniciar sesión)"
    if ! ((DRY)); then
      user_dbus systemctl --user daemon-reload
      user_dbus systemctl --user unset-environment CLUTTER_PAINT MUTTER_DEBUG_KMS_THREAD_TYPE
      user_dbus systemctl --user set-environment MUTTER_DEBUG_PAINT=disable-direct-scanout
    fi
  fi
}

step_mutter_scanout_remove() {
  local d="$UHOME/.config/environment.d"
  rm -f "$d/90-mutter-scanout.conf"
  rmdir "$d" 2>/dev/null || true
  if [[ -S "/run/user/$UID_T/bus" ]]; then
    user_dbus systemctl --user daemon-reload
    user_dbus systemctl --user unset-environment MUTTER_DEBUG_PAINT
  fi
  echo "Escaneo directo de nuevo activo al volver a iniciar sesión"
}

ww_allowed() {
  # Como el propio usuario, siempre (lo pide él con --waywallen); como root para otro, solo TEST_USER o MAIN_USER
  ((SELF)) || [[ "$TARGET" == "${TEST_USER:-}" || "$TARGET" == "${MAIN_USER:-}" ]] \
    || die "Waywallen: solo TEST_USER o MAIN_USER de config/local.env (aquí: $TARGET)"
}

step_appindicator() {
  # Iconos de apps en segundo plano en la barra (StatusNotifierItem/AppIndicator), docs/capas.md.
  # EGO v66 fijada por sha256; solo la añade a enabled-extensions (no reescribe la lista). Estilo: tema
  # GoldenGate (config/visual/shell-theme/tray/variant). Carga al volver a iniciar sesión.
  tmp="$(mktemp -d -p "$TMPROOT")"
  local uuid="$APPINDICATOR_UUID" d="$tmp/ext" cur new
  local url="https://extensions.gnome.org/download-extension/$uuid.shell-extension.zip?version_tag=$APPINDICATOR_PK"
  curl -sSfL -o "$tmp/ext.zip" "$url"
  echo "$APPINDICATOR_SHA256  $tmp/ext.zip" | sha256sum -c --quiet || die "sha256 de $uuid no coincide"
  mkdir "$d"; unzip -q "$tmp/ext.zip" -d "$d"
  python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["uuid"]==sys.argv[2] and str(m["version"])==sys.argv[3] and "50" in m["shell-version"]' \
    "$d/metadata.json" "$uuid" "$APPINDICATOR_VERSION" || die "metadata.json de $uuid inesperado"
  glib-compile-schemas "$d/schemas"
  install_dir "$d" ".local/share/gnome-shell/extensions/$uuid"

  cur="$(gs get org.gnome.shell enabled-extensions)"
  new="$(python3 -I -c 'import ast,sys; s=sys.argv[1].strip(); c=[] if s.startswith("@as") else ast.literal_eval(s); c+=[sys.argv[2]] if sys.argv[2] not in c else []; print(repr(c))' "$cur" "$uuid")"
  gs set org.gnome.shell enabled-extensions "$new"

  # Ajustes: 16 px (iconos simbólicos de la barra de 28 px), a la derecha junto al estado, compacto;
  # bandeja antigua (XEmbed) activada para apps viejas
  local sd="$UHOME/.local/share/gnome-shell/extensions/$uuid/schemas" sch=org.gnome.shell.extensions.appindicator
  gs --schemadir "$sd" set $sch icon-size 16
  gs --schemadir "$sd" set $sch tray-pos 'right'
  gs --schemadir "$sd" set $sch compact-mode-enabled true
  gs --schemadir "$sd" set $sch legacy-tray-enabled true
  # Waywallen (Flatpak) anuncia IconThemePath=/app/share/icons, que solo existe en su sandbox, y
  # AppIndicator busca el icono SOLO ahí (sale «…»). Una ruta absoluta en custom-icons evita esa búsqueda.
  # Icono: silueta monocroma (gris claro como el de Steam) generada del SVG que Flatpak exporta al host,
  # en ~/.local/share/dotfiles/icons (no va al repo); si el SVG cambia de forma, se usa el de color.
  local wwicon="$UHOME/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/org.waywallen.waywallen.svg"
  local wwmono="$UHOME/.local/share/dotfiles/icons/waywallen-tray-mono.svg"
  if [[ -f "$wwicon" ]]; then
    local mono; mono="$(mktemp)"; chown "$TARGET:" "$mono"
    if as_user python3 -I - "$wwicon" "$mono" '#dcdcdc' <<'PY'
import re, sys
src, dst, color = sys.argv[1:4]
s = open(src).read()
start = s.find('transform="translate(512,512)"')
start = s.rfind("<g", 0, start)
end = s.rfind("</svg>")
if start < 0 or end < 0:
    sys.exit("estructura inesperada")
g = s[start:end]
coral, fondo = {"#D85A30", "#F0997B", "#993C1D"}, "#2A0E07"
def fill(m):
    c = m.group(1).upper()
    if c in coral:
        return 'fill="#ffffff"'      # visible en la máscara
    if c == fondo:
        return 'fill="#000000"'      # recorte (sombra del engranaje, anillos)
    sys.exit(f"color inesperado {c}")
g = re.sub(r'fill="(#[0-9A-Fa-f]{6})"', fill, g)
g = re.sub(r'\sopacity="0\.85"', "", g)
open(dst, "w").write(f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- Generado por visual.sh desde org.waywallen.waywallen.svg: silueta monocroma para la barra. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <mask id="silueta" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <rect width="1024" height="1024" fill="#000000"/>
      {g}
    </mask>
  </defs>
  <rect width="1024" height="1024" fill="{color}" mask="url(#silueta)"/>
</svg>
""")
PY
    then
      inst_file "$mono" "$wwmono" 0644
      wwicon="$wwmono"
    else
      echo "AVISO: no se pudo generar el icono monocromo de Waywallen; se usa el de color" >&2
    fi
    rm -f "$mono"
    gs --schemadir "$sd" set $sch custom-icons "[('waywallen', '$wwicon', '$wwicon')]"
  else
    gs --schemadir "$sd" set $sch custom-icons "@a(sss) []"
  fi
  ((DRY)) && return 0
  for k in icon-size tray-pos tray-order compact-mode-enabled legacy-tray-enabled custom-icons; do
    printf '%-22s %s\n' "$k" "$(gs --schemadir "$sd" get $sch $k)"
  done
}

step_waywallen() {
  # Fondo animado (docs/capas.md). Solo HOME del usuario: Flatpak --user fijado por commit
  # y enmascarado, extensión de GNOME por sha256, configuración y arranque automático del daemon.
  # Opcionales: WW_OWE=1 open-wallpaper-engine (fondos de Wallpaper Engine; requiere Steam con Wallpaper
  # Engine instalado, que este paso NO instala) y WW_MEDIA=1 (vídeos de prueba generados con ffmpeg).
  ww_allowed
  local app="$WAYWALLEN_FLATPAK_APP" fp=(flatpak --user)
  local uuid="$WAYWALLEN_GNOME_UUID" extdir=".local/share/gnome-shell/extensions"

  # 1. Remoto Flathub de usuario (no toca el remoto filtrado del sistema; marca si lo añade este script,
  #    para que la vuelta atrás solo borre un remoto que no existía)
  if ! as_user "${fp[@]}" remotes --columns=name | grep -qx flathub; then
    cambio "remoto flathub de usuario"
    if ! ((DRY)); then
      as_user "${fp[@]}" remote-add flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      as_user touch "$UHOME/.local/share/flatpak/.dotfiles-flathub-added"
    fi
  fi
  # 2. App fijada al commit y enmascarada (sin actualizaciones)
  if [[ "$(as_user "${fp[@]}" info --show-commit "$app" 2>/dev/null)" != "$WAYWALLEN_FLATPAK_COMMIT" ]]; then
    cambio "Flatpak $app en el commit fijado (~3 GB con runtimes la primera vez)"
    if ! ((DRY)); then
      as_user "${fp[@]}" mask --remove "$app" >/dev/null 2>&1 || true
      as_user "${fp[@]}" info "$app" >/dev/null 2>&1 || as_user "${fp[@]}" install -y --noninteractive flathub "$app"
      [[ "$(as_user "${fp[@]}" info --show-commit "$app")" == "$WAYWALLEN_FLATPAK_COMMIT" ]] \
        || as_user "${fp[@]}" update -y --noninteractive --commit="$WAYWALLEN_FLATPAK_COMMIT" "$app"
      [[ "$(as_user "${fp[@]}" info --show-commit "$app")" == "$WAYWALLEN_FLATPAK_COMMIT" ]] || die "$app no está en el commit fijado"
    fi
  fi
  if ! as_user "${fp[@]}" mask 2>/dev/null | grep -qx "\s*$app"; then
    cambio "enmascarar $app (sin actualizaciones automáticas)"
    ((DRY)) || as_user "${fp[@]}" mask "$app"
  fi

  # 3. Extensión de GNOME (zip fijado por sha256; se carga al volver a iniciar sesión)
  tmp="$(mktemp -d -p "$TMPROOT")"
  curl -sSfL -o "$tmp/ext.zip" "$WAYWALLEN_GNOME_URL"
  echo "$WAYWALLEN_GNOME_SHA256  $tmp/ext.zip" | sha256sum -c --quiet || die "sha256 de la extensión de Waywallen no coincide"
  mkdir "$tmp/ext"; unzip -q "$tmp/ext.zip" -d "$tmp/ext"
  python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["uuid"]==sys.argv[2] and "50" in m["shell-version"]' \
    "$tmp/ext/metadata.json" "$uuid" || die "metadata.json de Waywallen inesperado"
  install_dir "$tmp/ext" "$extdir/$uuid"
  local cur new
  cur="$(gs get org.gnome.shell enabled-extensions)"
  new="$(python3 -I -c 'import ast,sys; s=sys.argv[1].strip(); c=[] if s.startswith("@as") else ast.literal_eval(s); c+=[sys.argv[2]] if sys.argv[2] not in c else []; print(repr(c))' "$cur" "$uuid")"
  gs set org.gnome.shell enabled-extensions "$new"

  # 4. Plugin open-wallpaper-engine (zip fijado por sha256): solo con WW_OWE=1
  local plugdir=".var/app/$app/data/waywallen/plugins/$WAYWALLEN_OWE_ID"
  if [[ "${WW_OWE:-0}" == 1 ]]; then
    echo "  AVISO: open-wallpaper-engine lee los fondos de Wallpaper Engine de tu Steam (steamapps, solo lectura)."
    echo "         Steam y Wallpaper Engine (de pago, vía Proton) los instalas tú; no inicies sesión de Steam en Waywallen."
    curl -sSfL -o "$tmp/owe.zip" "$WAYWALLEN_OWE_URL"
    echo "$WAYWALLEN_OWE_SHA256  $tmp/owe.zip" | sha256sum -c --quiet || die "sha256 de open-wallpaper-engine no coincide"
    mkdir "$tmp/owe"; unzip -q "$tmp/owe.zip" -d "$tmp/owe"
    grep -q "^id = \"$WAYWALLEN_OWE_ID\"" "$tmp/owe/plugin.toml" || die "plugin.toml de open-wallpaper-engine inesperado"
    install_dir "$tmp/owe" "$plugdir"
  elif [[ -d "$UHOME/$plugdir" ]]; then
    echo "  (open-wallpaper-engine presente; no se gestiona sin --wallpaper-engine y no se borra)"
  fi

  # 5. Configuración inicial del daemon (solo si no existe: luego la gestionan el daemon y su UI) y autoarranque
  local cfg="$UHOME/.var/app/$app/config/waywallen"
  if [[ ! -f "$cfg/config.toml" ]]; then
    cambio "configuración inicial de Waywallen"
    ((DRY)) || { as_user mkdir -p "$cfg"; install -o "$TARGET" -g "$TARGET" -m 0644 "$REPO/config/visual/waywallen/config.toml" "$cfg/config.toml"; }
  fi
  inst_file "$REPO/config/visual/waywallen/waywallen.desktop" "$UHOME/.config/autostart/waywallen.desktop" 0644

  # 6. Vídeos de prueba propios (no van al repo): solo con WW_MEDIA=1
  if [[ "${WW_MEDIA:-0}" == 1 ]]; then
    local vid; vid="$(as_user xdg-user-dir VIDEOS)/Wallpapers"
    if [[ ! -f "$vid/ondas-1440p60.mp4" || ! -f "$vid/ondas-1080p30.mp4" ]]; then
      cambio "vídeos de prueba en ${vid/#$UHOME/\~}"
      if ! ((DRY)); then
        as_user mkdir -p "$vid"
        [[ -f "$vid/ondas-1440p60.mp4" ]] || as_user ffmpeg -hide_banner -loglevel error -y -f lavfi \
          -i "gradients=s=2560x1440:r=60:d=12:c0=0x0b1f4a:c1=0x1f6feb:c2=0x5b2a86:c3=0x0e4d64:nb_colors=4:speed=0.012:type=radial" \
          -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p -movflags +faststart "$vid/ondas-1440p60.mp4"
        [[ -f "$vid/ondas-1080p30.mp4" ]] || as_user ffmpeg -hide_banner -loglevel error -y -i "$vid/ondas-1440p60.mp4" \
          -vf "scale=1920:1080,fps=30" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart "$vid/ondas-1080p30.mp4"
      fi
    fi
  fi
}

# Permisos del Flatpak de Waywallen por perfil (docs/capas.md). Siempre desde cero
# (override --reset); el manifiesto da Steam en escritura (4 rutas), que se quita en los dos perfiles.
#   abierto:     red; solo ~/.local/share/Steam/steamapps en lectura (Workshop 431960 y
#                common/wallpaper_engine; no config/ ni userdata/, donde Steam guarda la sesión);
#                MPRIS (README de Waywallen) y GameMode (pausa al jugar)
#   restringido: sin red; Steam completo en lectura (el perfil del primer experimento)
waywallen_overrides() { # abierto|restringido → 0 si hubo que cambiarlos
  # Se generan en un FLATPAK_USER_DIR temporal y se comparan con los actuales: solo se aplican si difieren
  local app="$WAYWALLEN_FLATPAK_APP" t
  local steam=(--nofilesystem='~/.steam' --nofilesystem='~/.local/share/Steam'
               --nofilesystem='~/.var/app/com.valvesoftware.Steam/data/Steam' --nofilesystem='~/snap/steam')
  local env=(--env=XDG_VIDEOS_DIR="$(as_user xdg-user-dir VIDEOS)" --env=XDG_PICTURES_DIR="$(as_user xdg-user-dir PICTURES)")
  local -a args
  case "$1" in
    abierto) args=(--share=network "${steam[@]}" --filesystem='~/.local/share/Steam/steamapps:ro'
                   --talk-name='org.mpris.MediaPlayer2.*' --talk-name=com.feralinteractive.GameMode "${env[@]}") ;;
    restringido) args=(--unshare=network "${steam[@]}" --filesystem='~/.steam:ro' --filesystem='~/.local/share/Steam:ro' "${env[@]}") ;;
    *) die "Perfil de Waywallen desconocido: $1" ;;
  esac
  t="$(mktemp -d)"; chown "$TARGET:" "$t"
  as_user env FLATPAK_USER_DIR="$t" flatpak --user override "${args[@]}" "$app" >/dev/null
  if cmp -s "$t/overrides/$app" "$UHOME/.local/share/flatpak/overrides/$app"; then rm -rf "$t"; return 1; fi
  rm -rf "$t"
  cambio "permisos del Flatpak de Waywallen (perfil $1)"
  if ! ((DRY)); then
    as_user flatpak --user override --reset "$app"
    as_user flatpak --user override "${args[@]}" "$app"
  fi
  return 0
}

# Daemon de Waywallen en la sesión viva del usuario (mismo comando que el arranque automático)
ww_env() { user_dbus env WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland "$@"; }
ww_dbus() { user_dbus gdbus call --session -d "$WAYWALLEN_FLATPAK_APP.Daemon" -o /org/waywallen/waywallen/Daemon "$@"; }
ww_port() { ww_dbus -m org.freedesktop.DBus.Properties.Get "$WAYWALLEN_FLATPAK_APP.Daemon1" WsPort 2>/dev/null | grep -oE '[0-9]{4,5}'; }
# Websocket de control (scripts/ww-ws.py), desde el netns del daemon: sirve con y sin red
ww_ws() {
  local pid; pid="$(pgrep -u "$TARGET" -x waywallen | head -1)"
  if [[ "$(readlink "/proc/$pid/ns/net" 2>/dev/null)" == "$(readlink /proc/self/ns/net)" ]]; then
    python3 -I "$REPO/scripts/ww-ws.py" "$(ww_port)" "$@"          # perfil abierto: misma red que el host
  elif ((SELF == 0)); then
    nsenter -t "$pid" -n python3 -I "$REPO/scripts/ww-ws.py" "$(ww_port)" "$@"
  else
    echo "El daemon está en su propia red (perfil restringido): hace falta sudo para consultarlo" >&2; return 1
  fi
}

step_waywallen_profile() {
  # ./visual.sh <usuario> waywallen-profile abierto|restringido
  # Permisos (waywallen_overrides), audio de los renderizadores de escena y web, y bibliotecas (vídeo y, con
  # WW_OWE=1, el Steam del usuario). Si algo cambia y hay sesión, reinicia el daemon para aplicarlo.
  ww_allowed
  local prof="${1:-}" app="$WAYWALLEN_FLATPAK_APP" audio i reiniciar=0
  local cfg="$UHOME/.var/app/$app/config/waywallen/config.toml" steamlib="$UHOME/.local/share/Steam"
  case "$prof" in abierto) audio=true ;; restringido) audio=false ;; *) die "Uso: waywallen-profile abierto|restringido" ;; esac

  # 1. Permisos
  waywallen_overrides "$prof" && reiniciar=1
  # 2. Audio de escena y web (el renderizador de vídeo ya lo tiene); fps y lo demás se ajustan en la UI
  if [[ -f "$cfg" ]]; then
    local want; want="$(mktemp)"; cp "$cfg" "$want"
    for i in weweb-renderer wescene-renderer; do
      sed -i "/^\[plugin\.$i\]/,/^\[/ s/^enable_audio = .*/enable_audio = \"$audio\"/" "$want"
    done
    if ! cmp -s "$want" "$cfg"; then
      cambio "audio de escena y web en config.toml ($audio)"; reiniciar=1
    fi
  fi
  # 3. Aplicar: daemon parado (reescribe config.toml al salir), cambios y daemon de nuevo
  if ((reiniciar)) && ! ((DRY)); then
    local hay_sesion=0; [[ -S "/run/user/$UID_T/bus" ]] && hay_sesion=1
    ((hay_sesion)) && { user_dbus flatpak kill "$app" 2>/dev/null || true; sleep 2; }
    [[ -n "${want:-}" ]] && ! cmp -s "$want" "$cfg" && { cp "$cfg" "$cfg.bak-profile"; install -o "$TARGET" -g "$TARGET" -m 0644 "$want" "$cfg"; }
    if ((hay_sesion)); then
      ww_env setsid -f flatpak run --command=waywallen "$app" --no-ui --display-backend gnome-shell >/dev/null 2>&1
      for i in $(seq 30); do [[ -n "$(ww_port)" ]] && break; sleep 1; done
    fi
  fi
  rm -f "${want:-}"
  # 4. Bibliotecas (necesitan el daemon en marcha): ~/Vídeos/Wallpapers si existe y, con WW_OWE=1, el Steam
  #    del usuario; restringido quita la de Steam
  if [[ -z "$(ww_port)" ]]; then
    echo "  (daemon parado: las bibliotecas se revisan cuando esté en marcha, p. ej. tras iniciar sesión)"
    return 0
  fi
  local vidlib libs; vidlib="$(as_user xdg-user-dir VIDEOS)/Wallpapers"
  libs="$(ww_ws libs 2>/dev/null)" || { echo "  AVISO: no se pudo consultar el daemon de Waywallen"; return 0; }
  if [[ "$prof" == abierto ]]; then
    if [[ -d "$vidlib" ]] && ! grep -q "^[0-9]* video $vidlib$" <<<"$libs"; then
      cambio "biblioteca de vídeo $vidlib"; ((DRY)) || ww_ws "lib-add:video:$vidlib"
    fi
    if [[ "${WW_OWE:-0}" == 1 ]] && ! grep -q "^[0-9]* wallpaper_engine $steamlib$" <<<"$libs"; then
      cambio "biblioteca de Wallpaper Engine $steamlib"; ((DRY)) || ww_ws "lib-add:wallpaper_engine:$steamlib"
    fi
  else
    for i in $(awk '$2=="wallpaper_engine"{print $1}' <<<"$libs"); do
      cambio "quitar biblioteca de Wallpaper Engine ($i)"; ((DRY)) || ww_ws "lib-rm:$i"
    done
  fi
}

step_waywallen_remove() {
  # Vuelta atrás completa (solo HOME del usuario; scripts/rollback-waywallen.sh restaura además la copia)
  ww_allowed
  local app="$WAYWALLEN_FLATPAK_APP" uuid="$WAYWALLEN_GNOME_UUID" cur new
  cur="$(gs get org.gnome.shell enabled-extensions)"
  new="$(python3 -I -c 'import ast,sys; s=sys.argv[1].strip(); c=[] if s.startswith("@as") else ast.literal_eval(s); print(repr([u for u in c if u!=sys.argv[2]]))' "$cur" "$uuid")"
  gs set org.gnome.shell enabled-extensions "$new"
  pkill -u "$TARGET" -f 'waywallen' || true
  rm -f "$UHOME/.config/autostart/waywallen.desktop"
  rm -rf "$UHOME/.local/share/gnome-shell/extensions/$uuid"
  as_user flatpak --user mask --remove "$app" || true
  as_user flatpak --user uninstall -y --noninteractive --delete-data "$app" || true
  as_user flatpak --user uninstall -y --noninteractive --unused || true
  if [[ -f "$UHOME/.local/share/flatpak/.dotfiles-flathub-added" ]]; then
    as_user flatpak --user remote-delete flathub || true
    rm -f "$UHOME/.local/share/flatpak/.dotfiles-flathub-added"
  fi
  echo "Waywallen retirado (los medios de prueba quedan en Vídeos/Imágenes → Wallpapers)"
}

step_status() {
  echo "== $TARGET ($UHOME)"
  for k in gtk-theme icon-theme cursor-theme color-scheme accent-color font-name; do
    printf '%-14s %s\n' "$k" "$(gs get org.gnome.desktop.interface "$k")"
  done
  printf '%-14s %s\n' button-layout "$(gs get org.gnome.desktop.wm.preferences button-layout)"
  printf '%-14s %s\n' extensions "$(gs get org.gnome.shell enabled-extensions)"
  printf '%-14s %s\n' bg-uri "$(gs get org.gnome.desktop.background picture-uri)"
  printf '%-14s %s\n' bg-uri-dark "$(gs get org.gnome.desktop.background picture-uri-dark)"
  ls "$UHOME/.local/share/themes" "$UHOME/.local/share/icons" "$UHOME/.local/share/backgrounds" 2>/dev/null || true
}

case "$STEP" in
  theme)           step_theme ;;
  gtk4)            step_gtk4; step_status ;;
  extensions)      step_extensions ;;
  dock)            step_dock ;;
  panel)           step_panel ;;
  glass)           step_glass ;;
  appindicator)    step_appindicator ;;
  mutter-scanout)  step_mutter_scanout ;;
  mutter-scanout-remove) step_mutter_scanout_remove ;;
  waywallen)       step_waywallen ;;
  waywallen-remove) step_waywallen_remove ;;
  waywallen-profile) step_waywallen_profile "${3:-}" ;;
  wallpaper)       step_wallpaper "$@" ;;
  shell-theme)     step_shell_theme ;;
  cleanup)         step_cleanup ;;
  status)          step_status ;;
  *) sed -n '2,19p' "$0"; exit 1 ;;
esac
echo "CAMBIOS: $CAMBIOS"

