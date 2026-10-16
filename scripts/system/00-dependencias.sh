#!/usr/bin/env bash
# Herramientas que necesitan el instalador y la capa de usuario y que no siempre trae Fedora Workstation
# (p. ej. «patch», para los parches de las extensiones). La capa de usuario corre sin sudo: por eso van aquí.
#
# Uso: sudo ./00-dependencias.sh
# DRY_RUN=1: solo muestra lo que cambiaría.
# Idempotente: solo instala lo que falta.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/sys.sh"
need_root
ensure_pkgs patch unzip curl git-core glib2 libxml2 python3-gobject
fin
