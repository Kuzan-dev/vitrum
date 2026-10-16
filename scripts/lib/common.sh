#!/usr/bin/env bash
# Funciones compartidas por los scripts del repo. Uso: source "$REPO/scripts/lib/common.sh"

# Carga config/local.env (valores propios del equipo, ignorado por git; plantilla en local.env.example).
# Sin argumentos solo carga; con nombres de variables, exige que existan y no estén vacías.
load_local_env() { # [VAR...]
  local f="$REPO/config/local.env" v
  if [[ -f "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
  fi
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || {
      echo "ERROR: falta $v en config/local.env (cópialo de config/local.env.example o usa ./install.sh check --sugerir)" >&2
      exit 1
    }
  done
}
