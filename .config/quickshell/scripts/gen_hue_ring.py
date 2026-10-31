#!/usr/bin/env python3
"""Generate a rainbow hue-ring PNG for the annotation color picker.

Run once (re-run only if size/thickness needs to change):
    python3 gen_hue_ring.py [output_path] [size]

Default output: ../assets/hue_ring.png (relative to this script), size 256.
"""
import sys
import os
import math
import colorsys
from PIL import Image


def generate(size=256, thickness_ratio=0.18, supersample=4):
    ss = size * supersample
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    px = img.load()
    cx = cy = ss / 2
    outer = ss / 2
    inner = outer * (1 - thickness_ratio * 2)

    for y in range(ss):
        for x in range(ss):
            dx = x - cx
            dy = y - cy
            dist = math.sqrt(dx * dx + dy * dy)
            if inner <= dist <= outer:
                angle = math.degrees(math.atan2(dy, dx))
                if angle < 0:
                    angle += 360
                r, g, b = colorsys.hsv_to_rgb(angle / 360.0, 1.0, 1.0)
                edge = min(dist - inner, outer - dist)
                alpha = 255 if edge > supersample else int(255 * max(0, edge) / supersample)
                px[x, y] = (int(r * 255), int(g * 255), int(b * 255), alpha)

    return img.resize((size, size), Image.LANCZOS)


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(script_dir, "..", "assets", "hue_ring.png")
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    os.makedirs(os.path.dirname(out), exist_ok=True)
    generate(size=size).save(out)
    print(f"Saved {out} ({size}x{size})")


if __name__ == "__main__":
    main()
