#!/usr/bin/env bash
# Primitivas de las capas de sistema (scripts/system/*, gaming.sh): comparan antes de actuar.
# DRY_RUN=1: solo anuncian («CAMBIARÍA: …»); al final, `fin` imprime «CAMBIOS: N» (lo lee install.sh).
# Se ejecutan con sudo también en simulación (algunas lecturas, como los subvolúmenes, requieren root).

DRY="${DRY_RUN:-0}"; CAMBIOS=0
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "Ejecuta con sudo"; }
cambio() {
  CAMBIOS=$((CAMBIOS + 1))
  if ((DRY)); then echo "  CAMBIARÍA: $*"; else echo "  cambio: $*"; fi
}
fin() { echo "CAMBIOS: $CAMBIOS"; }

# Paquetes que faltan → dnf install (Snapper crea pre/post)
ensure_pkgs() { # paquete...
  local -a falta=(); local p
  for p in "$@"; do rpm -q "$p" &>/dev/null || falta+=("$p"); done
  ((${#falta[@]})) || return 0
  cambio "instalar ${falta[*]}"
  ((DRY)) || dnf install -y "${falta[@]}"
}

# Archivo con contenido y modo; devuelve 0 si cambió (para recargar lo que dependa de él)
ensure_file() { # origen destino modo
  if [[ -f "$2" ]] && cmp -s "$1" "$2" && [[ "$(stat -c %a "$2")" == "${3#0}" ]]; then return 1; fi
  cambio "archivo $2"
  if ! ((DRY)); then install -D -m "$3" "$1" "$2"; restorecon "$2" 2>/dev/null || true; fi
  return 0
}

# Unidad habilitada y activa
ensure_unit() { # unidad
  systemctl is-enabled --quiet "$1" 2>/dev/null && systemctl is-active --quiet "$1" && return 0
  cambio "habilitar y arrancar $1"
  ((DRY)) || systemctl enable --now "$1"
}
