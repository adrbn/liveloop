#!/usr/bin/env python3
"""Generate the LiveLoop app icon: a white circular-loop arrow around a play
triangle on a blue->violet gradient squircle. Emits every size the macOS asset
catalog needs plus a 1024 master."""

import math
import os
import sys

from PIL import Image, ImageDraw

try:
    import numpy as np
except ImportError:
    np = None

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
S = 1024

# Brand gradient stops (top-left -> bottom-right).
C0 = (92, 140, 255)    # blue  #5C8CFF
C1 = (140, 92, 255)    # violet #8C5CFF


def gradient(size):
    if np is not None:
        y, x = np.mgrid[0:size, 0:size]
        t = (x + y) / (2 * (size - 1))
        r = (C0[0] + (C1[0] - C0[0]) * t).astype("uint8")
        g = (C0[1] + (C1[1] - C0[1]) * t).astype("uint8")
        b = (C0[2] + (C1[2] - C0[2]) * t).astype("uint8")
        a = np.full((size, size), 255, "uint8")
        return Image.fromarray(np.dstack([r, g, b, a]), "RGBA")
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for j in range(size):
        for i in range(size):
            t = (i + j) / (2 * (size - 1))
            px[i, j] = (int(C0[0] + (C1[0] - C0[0]) * t),
                        int(C0[1] + (C1[1] - C0[1]) * t),
                        int(C0[2] + (C1[2] - C0[2]) * t), 255)
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_glyph(img):
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    R = S * 0.29            # ring radius
    stroke = S * 0.072      # ring thickness
    white = (255, 255, 255, 255)

    # A single clockwise loop arrow with a gap on the right where the
    # arrowhead sits. PIL angles run clockwise from 3 o'clock (screen y-down).
    start_deg, end_deg = 40, 320
    bbox = [cx - R, cy - R, cx + R, cy + R]
    d.arc(bbox, start=start_deg, end=end_deg, fill=white, width=int(stroke))

    def on_circle(deg):
        a = math.radians(deg)
        return (cx + R * math.cos(a), cy + R * math.sin(a)), a

    # Rounded cap on the tail end only.
    (sx, sy), _ = on_circle(start_deg)
    d.ellipse([sx - stroke / 2, sy - stroke / 2, sx + stroke / 2, sy + stroke / 2], fill=white)

    # Arrowhead at the head end, aligned to the (clockwise) tangent.
    (px, py), a = on_circle(end_deg)
    tang = (-math.sin(a), math.cos(a))     # unit tangent, direction of travel
    norm = (math.cos(a), math.sin(a))      # unit radial (outward)
    ah = stroke * 1.5
    tip = (px + tang[0] * ah * 1.15, py + tang[1] * ah * 1.15)
    back = (px - tang[0] * ah * 0.55, py - tang[1] * ah * 0.55)
    wing_l = (back[0] + norm[0] * ah, back[1] + norm[1] * ah)
    wing_r = (back[0] - norm[0] * ah, back[1] - norm[1] * ah)
    d.polygon([tip, wing_l, wing_r], fill=white)

    # Play triangle in the centre (nudged right for optical balance).
    tr = S * 0.135
    dx = tr * 0.18
    pts = [(cx - tr * 0.5 + dx, cy - tr),
           (cx - tr * 0.5 + dx, cy + tr),
           (cx + tr + dx, cy)]
    d.polygon(pts, fill=white)


def main():
    os.makedirs(OUT, exist_ok=True)
    img = gradient(S)
    draw_glyph(img)
    img.putalpha(rounded_mask(S, int(S * 0.2237)))
    master = os.path.join(OUT, "icon_1024.png")
    img.save(master)

    for size in (16, 32, 64, 128, 256, 512, 1024):
        img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"icon_{size}.png"))
    print("wrote icons to", OUT)


if __name__ == "__main__":
    main()
