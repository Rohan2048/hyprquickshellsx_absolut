#!/usr/bin/env python3
"""cursor-preview.py <theme folder> <out.png>

Writes the theme's normal arrow cursor (cursors/left_ptr, else default / arrow) as a PNG, for the
Settings > Cursor page. Reads the Xcursor file itself (python3 standard library only, no extra tools).
Exit status 1 when no arrow could be read.
"""
import os, struct, sys, zlib

def read_images(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"Xcur":
        return []
    _, _, ntoc = struct.unpack_from("<III", data, 4)
    out = []
    for i in range(ntoc):
        ctype, nominal, pos = struct.unpack_from("<III", data, 16 + 12 * i)
        if ctype != 0xFFFD0002:
            continue
        _, _, _, _, w, h, xh, yh, delay = struct.unpack_from("<IIIIIIIII", data, pos)
        px = data[pos + 36: pos + 36 + w * h * 4]
        if w > 0 and h > 0 and len(px) == w * h * 4:
            out.append((nominal, w, h, px))
    return out

def to_png(w, h, argb):
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            v = struct.unpack_from("<I", argb, (y * w + x) * 4)[0]
            a, r, g, b = (v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255
            if 0 < a < 255:                      # Xcursor stores premultiplied colour
                r, g, b = min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a)
            row += bytes((r, g, b, a))
        rows.append(bytes(row))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b""))

def main():
    theme, out = sys.argv[1], sys.argv[2]
    for name in ("left_ptr", "default", "arrow", "top_left_arrow"):
        p = os.path.join(theme, "cursors", name)
        if not os.path.exists(p):
            continue
        try:
            imgs = read_images(p)
        except Exception:
            continue
        if not imgs:
            continue
        # the size nearest 32 px reads well in a small tile
        nominal, w, h, px = min(imgs, key=lambda i: abs(i[0] - 32))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out + ".tmp", "wb") as f:
            f.write(to_png(w, h, px))
        os.replace(out + ".tmp", out)
        return 0
    return 1

sys.exit(main())
