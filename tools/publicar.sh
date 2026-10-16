#!/usr/bin/env bash
# Regenera el árbol publicable de vitrum desde este repositorio de trabajo (último commit) y lo publica.
#
#   tools/publicar.sh            prepara ~/vitrum-publicar, escanea y hace commit local (no envía nada)
#   tools/publicar.sh --push     además envía la rama main (sin tags) a GitHub
#
# El repositorio de trabajo conserva todo el historial; el publicable es otro repo git (rama main) cuyo primer
# commit es único (sin el historial ni sus objetos) y cada publicación añade un commit normal encima.
# Antes de cada commit: escaneo del árbol de archivos con los valores de config/local.env (hook pre-commit
# incluido) y lista de archivos y resultado guardados en las notas. El push exige que el repo sea privado salvo
# VITRUM_PERMITIR_PUBLICO=1 (decisión explícita del usuario cuando lo haga público). Nunca cambia la visibilidad.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PUB="${VITRUM_PUBLICAR:-$HOME/vitrum-publicar}"
NOTAS="${DOTFILES_NOTAS:-$HOME/dotfiles-notas}"
GH_REPO="Kuzan-dev/vitrum"
NOMBRE="Kuzan-dev"; CORREO="116390770+Kuzan-dev@users.noreply.github.com"
LOCAL_ENV="$REPO/config/local.env"
die() { echo "ERROR: $*" >&2; exit 1; }
PUSH=0; [[ "${1:-}" == --push ]] && PUSH=1

git -C "$REPO" diff --quiet HEAD && [[ -z "$(git -C "$REPO" ls-files --others --exclude-standard)" ]] \
  || die "hay cambios sin commit en $REPO: publica solo estados con commit"
[[ -f "$LOCAL_ENV" ]] || die "falta $LOCAL_ENV (el escaneo de datos personales lo necesita)"

# Fuera aunque estuvieran en git: copias, valores del equipo, medios, archivos, discos, scripts de una migración concreta
EXCLUIR='^(backups/|config/local\.env$|scripts/rollback-visual\.sh$)|\.(jxl|jpe?g|png|webp|gif|mp4|mkv|webm|tar|gz|zst|xz|gpg|iso|qcow2|img)$'

stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
git -C "$REPO" archive HEAD | tar -x -C "$stage"
git -C "$REPO" ls-files | grep -E "$EXCLUIR" | while read -r f; do rm -f "$stage/$f"; done
find "$stage" -type d -empty -delete

# Repo publicable: se crea la primera vez (hooks y ruta de local.env solo en su configuración local)
if [[ ! -d "$PUB/.git" ]]; then
  mkdir -p "$PUB"
  git -C "$PUB" init -q -b main
  git -C "$PUB" config user.name "$NOMBRE"
  git -C "$PUB" config user.email "$CORREO"
  git -C "$PUB" config core.hooksPath tools/hooks
  git -C "$PUB" config vitrum.localenv "$LOCAL_ENV"
fi
rsync -a --delete --exclude=.git "$stage/" "$PUB/"
git -C "$PUB" add -A

# Escaneo del árbol de archivos y registro en las notas
mkdir -p "$NOTAS"
reg="$NOTAS/publicacion-$(date +%F-%H%M%S).txt"
{
  echo "Publicación desde $(git -C "$REPO" rev-parse --short HEAD) ($(date -Is))"
  echo "== Archivos ($(git -C "$PUB" ls-files | wc -l))"; git -C "$PUB" ls-files
  echo "== Escaneo del árbol"
} > "$reg"
if ! (cd "$PUB" && VITRUM_LOCAL_ENV="$LOCAL_ENV" python3 -I tools/escanear-datos.py --arbol) >>"$reg" 2>&1; then
  tail -20 "$reg" >&2; die "el escaneo encontró datos personales o secretos (detalle en $reg); no se hace commit"
fi
echo "Lista y escaneo: $reg"

if git -C "$PUB" diff --cached --quiet && git -C "$PUB" rev-parse -q --verify HEAD >/dev/null; then
  echo "Nada nuevo que publicar"
else
  if git -C "$PUB" rev-parse -q --verify HEAD >/dev/null; then
    msg="Actualización desde el repositorio de trabajo ($(git -C "$REPO" log -1 --format=%cs))"
  else
    msg="vitrum: escritorio GNOME para Fedora 44 / GNOME 50"
  fi
  # En el repo publicado solo figura el autor del proyecto (nombre y noreply), también en los mensajes
  git -C "$PUB" commit -q -m "$msg"
  echo "Commit: $(git -C "$PUB" log -1 --format='%h %an <%ae> %s')"
fi

if ((PUSH)); then
  vis="$(gh repo view "$GH_REPO" --json visibility -q .visibility)"
  [[ "$vis" == PRIVATE || "${VITRUM_PERMITIR_PUBLICO:-0}" == 1 ]] || die "el repo es $vis: no se envía (VITRUM_PERMITIR_PUBLICO=1 para un repo público)"
  git -C "$PUB" remote get-url origin &>/dev/null || git -C "$PUB" remote add origin "https://github.com/$GH_REPO.git"
  git -C "$PUB" -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main
  echo "Enviado main a https://github.com/$GH_REPO ($vis)"
fi
