#!/usr/bin/env python3
"""Generate the LiveLoop app icon: a white loop arrow around a play triangle on
a blue->violet squircle, laid out on Apple's macOS icon grid (an 824 px tile
centred on a 1024 px canvas, with a soft drop shadow).

Every shape is a signed distance field, so each size is drawn directly with
exact anti-aliasing instead of being scaled down from the master, and the arrow
head, ring and play triangle share one geometry at every size.

  python3 scripts/make_icon.py LiveLoop/Resources/Assets.xcassets/AppIcon.appiconset
  python3 scripts/make_icon.py --docs docs/assets    # icon.png (256) + icon-1024.png
  python3 scripts/make_icon.py --tile LiveLoopExtension/PlaceholderIcon.png --tile-size 368
                                                     # the bare tile, full bleed: camera card, video
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageFilter

try:
    import numpy as np
except ImportError:
    sys.exit("make_icon.py needs numpy: pip3 install numpy pillow")

CANVAS = 1024
TILE = 824                 # Apple's macOS grid: 824 px tile, 100 px margin all round
CORNER = 0.24 * TILE       # corner size and shape fitted to Apple's macOS icon template
CORNER_EXP = 2.2           # a touch squarer than a circle, so it eases into the sides

C0 = np.array([56, 150, 255]) / 255.0    # #3896FF, top left
C1 = np.array([166, 77, 255]) / 255.0    # #A64DFF, bottom right
GLYPH_SHADOW = np.array([38, 22, 130]) / 255.0

# Glyph, in 1024-canvas pixels around the tile centre. Angles run clockwise
# from 3 o'clock (screen y points down).
STROKE = 64
RING_R = 214               # centre line of the ring
TAIL_DEG = -32             # the ring runs clockwise from here...
HEAD_DEG = -90             # ...to 12 o'clock, where the head points right
HEAD_W = 2.25 * STROKE     # across the ring
HEAD_L = 1.5 * STROKE      # along the ring
HEAD_BEND = 0.3            # how far the tip follows the curve (0 = straight along the tangent)
HEAD_ROUND = 7
PLAY_R = 128               # circumradius of the play triangle
PLAY_ROUND = 17
PLAY_DX = 10               # optical nudge: a triangle's mass sits left of its box

Array = np.ndarray
Point = tuple[float, float]


def sd_squircle(x: Array, y: Array, half: float) -> Array:
    """Approximate signed distance to a square with continuous (superellipse) corners."""
    n = CORNER_EXP
    qx, qy = np.abs(x) - (half - CORNER), np.abs(y) - (half - CORNER)
    cx, cy = np.maximum(qx, 0) + 1e-6, np.maximum(qy, 0) + 1e-6
    g = (cx ** n + cy ** n) ** (1 / n)
    grad = np.sqrt(cx ** (2 * n - 2) + cy ** (2 * n - 2)) * g ** (1 - n)
    return (g + np.minimum(np.maximum(qx, qy), 0) - CORNER) / np.clip(grad, 0.95, 1.0)


def sd_arc(x: Array, y: Array, radius: float, width: float, start: float, span: float) -> Array:
    """Ring segment with round caps, running clockwise from `start` over `span` radians."""
    on_arc = np.mod(np.arctan2(y, x) - start, 2 * math.pi) <= span
    ring = np.abs(np.hypot(x, y) - radius)
    ends = [(radius * math.cos(a), radius * math.sin(a)) for a in (start, start + span)]
    caps = np.minimum(*[np.hypot(x - ex, y - ey) for ex, ey in ends])
    return np.where(on_arc, ring, caps) - width / 2


def sd_triangle(x: Array, y: Array, p0: Point, p1: Point, p2: Point) -> Array:
    """Exact signed distance to a triangle (Inigo Quilez)."""
    pts = [np.array(p, float) for p in (p0, p1, p2)]
    edges = [pts[1] - pts[0], pts[2] - pts[1], pts[0] - pts[2]]
    s = math.copysign(1, edges[0][0] * edges[2][1] - edges[0][1] * edges[2][0])
    best_d2, best_side = None, None
    for p, e in zip(pts, edges):
        vx, vy = x - p[0], y - p[1]
        h = np.clip((vx * e[0] + vy * e[1]) / (e @ e), 0, 1)
        d2 = (vx - e[0] * h) ** 2 + (vy - e[1] * h) ** 2
        side = s * (vx * e[1] - vy * e[0])
        best_d2 = d2 if best_d2 is None else np.minimum(best_d2, d2)
        best_side = side if best_side is None else np.minimum(best_side, side)
    return -np.sqrt(best_d2) * np.sign(best_side)


def sd_round_triangle(x: Array, y: Array, pts: list, radius: float) -> Array:
    """Triangle with rounded corners and the same edges: shrink about the incentre, then grow."""
    a, b, c = (np.array(p, float) for p in pts)
    la, lb, lc = np.linalg.norm(b - c), np.linalg.norm(c - a), np.linalg.norm(a - b)
    incentre = (la * a + lb * b + lc * c) / (la + lb + lc)
    area = abs((b - a)[0] * (c - a)[1] - (b - a)[1] * (c - a)[0]) / 2
    k = 1 - radius / (2 * area / (la + lb + lc))
    return sd_triangle(x, y, *[incentre + (p - incentre) * k for p in (a, b, c)]) - radius


def sd_glyph(x: Array, y: Array, weight: float) -> Array:
    stroke = STROKE * weight
    start, head = math.radians(TAIL_DEG), math.radians(HEAD_DEG)
    ring = sd_arc(x, y, RING_R, stroke, start, np.mod(head - start, 2 * math.pi))

    radial = np.array([math.cos(head), math.sin(head)])
    length = HEAD_L * weight
    aim = head + math.pi / 2 + HEAD_BEND * length / RING_R  # tangent, bent a little into the curve
    tip = radial * RING_R + length * np.array([math.cos(aim), math.sin(aim)])
    half = HEAD_W * weight / 2
    arrow = sd_round_triangle(x, y, [radial * (RING_R - half), tip, radial * (RING_R + half)], HEAD_ROUND)

    r = PLAY_R
    play_pts = [(PLAY_DX - r / 2, -r * math.sqrt(3) / 2), (PLAY_DX + r, 0), (PLAY_DX - r / 2, r * math.sqrt(3) / 2)]
    play = sd_round_triangle(x, y, play_pts, PLAY_ROUND)
    return np.minimum(np.minimum(ring, arrow), play)


def blur(cov: Array, sigma: float, dy: float, scale: float) -> Array:
    """Gaussian-blurred, downward-shifted copy of a coverage map."""
    img = Image.fromarray(np.uint8(np.clip(cov, 0, 1) * 255))
    out = np.asarray(img.filter(ImageFilter.GaussianBlur(sigma * scale)), float) / 255
    shift = int(round(dy * scale))
    return np.pad(out, ((shift, 0), (0, 0)))[: out.shape[0]] if shift else out


def coverage(dist: Array, scale: float) -> Array:
    """Signed distance (canvas px) to pixel coverage, anti-aliased over one output pixel."""
    return np.clip(0.5 - dist * scale, 0, 1)


def render(size: int, frame: tuple[float, float, float] = (0, 0, CANVAS), shadow: bool = True) -> Image.Image:
    """Draw the icon at `size` px; `frame` is the (x, y, width) of the canvas to show."""
    fx, fy, fw = frame
    scale = size / fw
    idx = (np.arange(size) + 0.5) / scale
    y, x = np.meshgrid(fy + idx - CANVAS / 2, fx + idx - CANVAS / 2, indexing="ij")
    tile = coverage(sd_squircle(x, y, TILE / 2), scale)
    weight = 1.5 if size <= 16 else 1.2 if size <= 32 else 1.0  # sturdier strokes when tiny
    glyph = coverage(sd_glyph(x, y, weight), scale) * tile

    t = np.clip((x + y + TILE) / (2 * TILE), 0, 1)[..., None]
    rgb = C0 * (1 - t) + C1 * t
    top = np.clip(1 - (y + TILE / 2) / (TILE * 0.6), 0, 1)[..., None]
    rgb = rgb + (1 - rgb) * 0.12 * top                          # soft light from above
    if size > 32:
        lift = blur(glyph, 12, 9, scale)[..., None] * 0.30
        rgb = rgb * (1 - lift) + GLYPH_SHADOW * lift
    rgb = rgb * (1 - glyph[..., None]) + glyph[..., None]

    alpha = tile
    if shadow:
        drop = 0.22 * blur(tile, 6, 5, scale) + 0.16 * blur(tile, 20, 14, scale)
        under = drop * (1 - tile)
        rgb = (rgb * tile[..., None]) / np.maximum(tile + under, 1e-6)[..., None]
        alpha = tile + under
    rgba = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    return Image.fromarray(np.uint8(np.round(rgba * 255)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", nargs="?", help="asset-catalog folder for icon_16.png ... icon_1024.png")
    parser.add_argument("--docs", help="folder for icon.png (256 px) and icon-1024.png")
    parser.add_argument("--tile", help="PNG path for the bare tile, full bleed, no shadow")
    parser.add_argument("--tile-size", type=int, default=1024)
    args = parser.parse_args()
    if not (args.out or args.docs or args.tile):
        parser.error("give an output folder, --docs or --tile")

    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for size in (16, 32, 64, 128, 256, 512, 1024):
            render(size).save(os.path.join(args.out, f"icon_{size}.png"))
        print("wrote app icons to", args.out)
    if args.docs:
        os.makedirs(args.docs, exist_ok=True)
        render(256).save(os.path.join(args.docs, "icon.png"))
        render(1024).save(os.path.join(args.docs, "icon-1024.png"))
        print("wrote docs icons to", args.docs)
    if args.tile:
        margin = (CANVAS - TILE) / 2
        render(args.tile_size, frame=(margin, margin, TILE), shadow=False).save(args.tile)
        print("wrote tile to", args.tile)


if __name__ == "__main__":
    main()
