#!/usr/bin/env python3
# Cliente mínimo del websocket de control de Waywallen (protobuf crudo, sin dependencias).
# El daemon escucha en 127.0.0.1 dentro de SU netns (Flatpak sin red): ejecutar con
#   nsenter -t <pid de waywallen> -n python3 -I ww-ws.py <puerto> <petición>...
# Peticiones: renderers | libraries | hex:<Request protobuf en hex>: árbol de campos (número=valor)
#             estado: una línea por renderizador «nombre fps estado» (playing/paused/stopped...)
#             libs: una línea por biblioteca «id plugin ruta»
#             lib-add:<plugin>:<ruta> | lib-rm:<id>
import base64, os, socket, struct, sys

REQ = {"renderers": "08016200", "estado": "08016200", "libraries": "0801d20100", "libs": "0801d20100"}
# renderer_list=12, library_list=26, library_add=27 (path=1, plugin_name=2), library_remove=28 (id=1)


def enc_varint(n):
    out = b""
    while True:
        c = n & 0x7F; n >>= 7
        out += bytes([c | (0x80 if n else 0)])
        if not n:
            return out


def ld(field, b):
    return enc_varint(field << 3 | 2) + enc_varint(len(b)) + b


def request(arg):
    if arg.startswith("hex:"):
        return bytes.fromhex(arg[4:])
    if arg.startswith("lib-add:"):
        _, plugin, path = arg.split(":", 2)
        return b"\x08\x01" + ld(27, ld(1, path.encode()) + ld(2, plugin.encode()))
    if arg.startswith("lib-rm:"):
        return b"\x08\x01" + ld(28, b"\x08" + enc_varint(int(arg[7:])))
    return bytes.fromhex(REQ[arg])


def frame(p):
    m = os.urandom(4); n = len(p)
    h = bytes([0x82]) + (bytes([0x80 | n]) if n < 126 else bytes([0xFE]) + struct.pack(">H", n))
    return h + m + bytes(b ^ m[i % 4] for i, b in enumerate(p))


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7F) << s; s += 7
        if c < 0x80:
            return r, i


def parse(b):
    out, i = [], 0
    while i < len(b):
        k, i = varint(b, i); f, t = k >> 3, k & 7
        if f == 0:
            raise ValueError
        if t == 0:
            v, i = varint(b, i)
        elif t == 2:
            n, i = varint(b, i); v = b[i:i + n]; i += n
            if i > len(b):
                raise ValueError
        elif t == 5:
            v = struct.unpack("<I", b[i:i + 4])[0]; i += 4
        elif t == 1:
            v = struct.unpack("<Q", b[i:i + 8])[0]; i += 8
        else:
            raise ValueError
        out.append((f, v))
    return out


def dump(b, ind=0):
    for f, v in parse(b):
        if isinstance(v, bytes):
            try:
                sub = parse(v) if v else None
            except (ValueError, IndexError, struct.error):
                sub = None
            txt = v.decode("utf-8", "replace")
            if sub and not txt.isprintable():
                print(" " * ind + f"{f}:"); dump(v, ind + 2); continue
            print(" " * ind + f"{f}={txt!r}")
        else:
            print(" " * ind + f"{f}={v}")


STATES = {1: "starting", 2: "running", 3: "stopping", 4: "stopped", 5: "killed", 6: "failed"}
ACTIVITY = {0: "running", 1: "playing", 2: "paused", 3: "muted"}


def libs(resp):  # Response.library_list(26).libraries(1): id(1) path(2) plugin(3)
    for f, lst in parse(resp):
        if f == 26:
            for g, lib in parse(lst):
                d = dict(parse(lib))
                print(d.get(1, 0), d.get(3, b"").decode(), d.get(2, b"").decode())


def summary(resp):  # Response.renderer_list(12).instances(2): nombre(4) fps(2) state(17)
    for f, lst in parse(resp):
        if f != 12:
            continue
        for g, inst in parse(lst):
            if g != 2:
                continue
            d = dict(parse(inst)); st = parse(d.get(17, b""))
            kind, body = st[0] if st else (0, b"")
            name = STATES.get(kind, "?")
            if kind == 2:
                name = ACTIVITY.get(dict(parse(body)).get(2, 0), "?")
            print(d.get(4, b"?").decode(), d.get(2, 0), name)


port = int(sys.argv[1])
s = socket.create_connection(("127.0.0.1", port), timeout=3)
k = base64.b64encode(os.urandom(16)).decode()
s.sendall(f"GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
          f"Sec-WebSocket-Key: {k}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode())
h = b""
while b"\r\n\r\n" not in h:
    h += s.recv(1)


def rd(n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise ConnectionError
        b += c
    return b


for arg in sys.argv[2:]:
    s.sendall(frame(request(arg)))
    while True:  # se descartan los eventos (ServerFrame campo 2) hasta la respuesta (campo 1)
        a, b = rd(2); n = b & 127
        n = struct.unpack(">H", rd(2))[0] if n == 126 else struct.unpack(">Q", rd(8))[0] if n == 127 else n
        d = rd(n)
        if d[:1] == b"\x0a":
            resp = parse(d)[0][1]
            st = dict((f, v) for f, v in parse(resp) if f in (2, 3))
            if st.get(2, 1) != 1:  # Response.status: 1 = OK
                print("error:", st.get(3, b"").decode(errors="replace"), file=sys.stderr); sys.exit(1)
            if arg == "estado":
                summary(resp)
            elif arg == "libs":
                libs(resp)
            elif arg.startswith("lib-"):
                print("ok", arg)
            else:
                dump(resp)
            break
s.close()
