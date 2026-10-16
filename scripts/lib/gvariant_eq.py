#!/usr/bin/env python3
# ¿El valor actual de una clave de gsettings es ya el deseado? Compara como GVariant del tipo de la clave,
# no como texto (16 = uint32 16, 'right' = right). Uso: gvariant_eq.py "<salida de gsettings range>"
# "<salida de gsettings get>" "<valor que se pasaría a gsettings set>". Sale 0 si son iguales.
import sys

import gi

gi.require_version("GLib", "2.0")
from gi.repository import GLib  # noqa: E402


def key_type(rng):
    lines = rng.strip().splitlines()
    head = lines[0].split()
    if head[0] == "type":
        return head[1]
    if head[0] == "enum":
        return "s"
    if head[0] == "flags":
        return "as"
    if head[0] == "range":
        return head[1]
    raise ValueError(rng)


def parse(vt, text):
    try:
        return GLib.Variant.parse(GLib.VariantType(vt), text, None, None)
    except GLib.Error:
        if vt == "s":  # gsettings set acepta cadenas sin comillas
            return GLib.Variant("s", text)
        raise


try:
    vt = key_type(sys.argv[1])
    sys.exit(0 if parse(vt, sys.argv[2]).equal(parse(vt, sys.argv[3])) else 1)
except Exception:  # noqa: BLE001 - ante la duda, «distinto» (se aplicará el valor)
    sys.exit(1)
