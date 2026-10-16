#!/usr/bin/env python3
"""Escaneo de datos personales y secretos antes de publicar.

Usos:
  escanear-datos.py --staged          líneas añadidas en el índice de git (hook pre-commit)
  escanear-datos.py --mensaje ARCHIVO mensaje de commit (hook commit-msg)
  escanear-datos.py --arbol [DIR]     todos los archivos versionados (revisión antes de un push, CI)
  --generico                          sin config/local.env (CI): solo patrones genéricos

Valores del equipo: config/local.env (FEDORA_ESP_PARTUUID, WINDOWS_ESP_PARTUUID, MONITOR_SERIALS,
MAIN_USER, TEST_USER, PERSONAL_EMAILS, LOCAL_IPS, SECRET_LITERALS; ruta alternativa: VITRUM_LOCAL_ENV o
`git config vitrum.localenv`), buscados con límites de palabra
(un literal «abc» no salta dentro de «abcd»). Nunca imprime un valor completo: lo enmascara. Sale 1 si encuentra algo.
"""
import os
import re
import shlex
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYS = ["FEDORA_ESP_PARTUUID", "WINDOWS_ESP_PARTUUID", "MONITOR_SERIALS", "MAIN_USER", "TEST_USER",
        "PERSONAL_EMAILS", "LOCAL_IPS", "SECRET_LITERALS"]
GENERIC = [
    ("clave privada", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("token de GitHub", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("token/clave asignada", re.compile(
        r"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|passwd|contraseña)\b\s*[=:]\s*['\"]?[^\s'\"<>{}$]{6,}")),
    ("IP privada", re.compile(r"\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b")),
    # Cualquier correo; los permitidos (UUID de extensiones, el noreply del autor) van en escaneo-permitidos.txt
    ("correo", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
]


def allowed_literals():
    """UUID de extensiones (config/visual/pins.env) y literales de tools/escaneo-permitidos.txt."""
    out = set()
    pins = os.path.join(REPO, "config", "visual", "pins.env")
    if os.path.exists(pins):
        txt = open(pins, encoding="utf-8").read()
        out |= set(re.findall(r'"([A-Za-z0-9._-]+@[A-Za-z0-9._-]+)\|', txt))       # EXTENSIONS=("uuid|…")
        out |= set(re.findall(r'_UUID="([^"]+)"', txt))
    f = os.path.join(REPO, "tools", "escaneo-permitidos.txt")
    if os.path.exists(f):
        out |= {l.strip() for l in open(f, encoding="utf-8") if l.strip() and not l.startswith("#")}
    return out


ALLOWED = set()


def mask(v):
    return (v[:2] + "…") if len(v) > 2 else "…"


def local_env_path():
    """config/local.env del repo; en una copia publicable (sin local.env), la ruta de VITRUM_LOCAL_ENV o de
    `git config vitrum.localenv` (configuración local, no se publica)."""
    f = os.environ.get("VITRUM_LOCAL_ENV")
    if not f:
        try:
            f = subprocess.run(["git", "-C", REPO, "config", "--get", "vitrum.localenv"],
                               capture_output=True, text=True).stdout.strip()
        except OSError:
            f = ""
    return f or os.path.join(REPO, "config", "local.env")


def local_values():
    f = local_env_path()
    vals = []
    if not os.path.exists(f):
        return vals
    env = {}
    for line in open(f, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        try:
            env[k.strip()] = " ".join(shlex.split(v))
        except ValueError:
            env[k.strip()] = v.strip().strip('"')
    for k in KEYS:
        for v in env.get(k, "").split():
            if len(v) >= 3:
                vals.append((k, v, re.compile(r"(?<![A-Za-z0-9_])" + re.escape(v) + r"(?![A-Za-z0-9_])")))
    return vals


def scan_line(text, vals):
    hits = []
    for k, v, rx in vals:
        if rx.search(text):
            hits.append((k, v))
    for name, rx in GENERIC:
        for m in rx.finditer(text):
            v = m.group(0)
            # UUID de extensiones (también en nombres de archivo «<uuid>.patch») y literales permitidos
            if name in ("correo", "IP privada") and any(a in v for a in ALLOWED):
                continue
            hits.append((name, v))
            break
    return hits


def report(where, text, hits):
    shown = text
    for _, v in hits:
        shown = shown.replace(v, mask(v))
    for k, v in hits:
        print(f"{where}: {k} «{mask(v)}» ({len(v)} caracteres)")
    print(f"    {shown.strip()[:160]}")


def staged_lines():
    out = subprocess.run(["git", "-C", REPO, "diff", "--cached", "-U0", "--no-color", "--no-ext-diff"],
                         capture_output=True, text=True, check=True).stdout
    path, ln = None, 0
    for line in out.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            ln = int(m.group(1)) if m else 0
        elif line.startswith("+") and path:
            yield path, ln, line[1:]
            ln += 1
    names = subprocess.run(["git", "-C", REPO, "diff", "--cached", "--name-only"],
                           capture_output=True, text=True, check=True).stdout
    for n in names.splitlines():
        yield "(nombre de archivo)", 0, n


def tree_lines(root):
    files = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, check=True).stdout
    for rel in files.splitlines():
        yield "(nombre de archivo)", 0, rel
        p = os.path.join(root, rel)
        if not os.path.isfile(p) or os.path.islink(p):
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                for i, line in enumerate(fh, 1):
                    yield rel, i, line
        except (UnicodeDecodeError, OSError):
            continue  # binarios


def main():
    args = sys.argv[1:]
    generic = "--generico" in args
    args = [a for a in args if a != "--generico"]
    vals = [] if generic else local_values()
    global ALLOWED
    ALLOWED = allowed_literals() - {v for _, v, _ in vals}   # lo de local.env nunca se permite
    if not generic and not vals:
        print("AVISO: sin config/local.env: solo patrones genéricos", file=sys.stderr)
    if not args:
        print(__doc__)
        return 2
    if args[0] == "--staged":
        src = staged_lines()
    elif args[0] == "--mensaje":
        src = (("(mensaje)", i, l) for i, l in enumerate(open(args[1], encoding="utf-8"), 1) if not l.startswith("#"))
    elif args[0] == "--arbol":
        src = tree_lines(args[1] if len(args) > 1 else REPO)
    else:
        print(__doc__)
        return 2
    found = 0
    for path, ln, text in src:
        hits = scan_line(text, vals)
        if hits:
            found += len(hits)
            report(f"{path}:{ln}" if ln else path, text, hits)
    if found:
        print(f"== {found} coincidencia(s): revisar antes de continuar", file=sys.stderr)
        return 1
    print("== Escaneo limpio", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
