#!/usr/bin/env python3
"""Generate the Field Kit app icon for every platform from one drawing.

A cyan shield (the SecOps side) holding a green terminal prompt (the NetOps
side) on the shared dark chrome. Renders at 1024 then downscales, so the
small sizes stay crisp.

Run from the repo root:  python3 tool/gen_icons.py
"""
from PIL import Image, ImageDraw
import os

BG = (11, 19, 32, 255)        # 0B1320
EDGE = (35, 54, 76, 255)      # 23364C
CYAN = (34, 211, 238, 255)    # 22D3EE
GREEN = (16, 185, 129, 255)   # 10B981

S = 1024


def shield_points(cx, cy, w, h, steps=48):
    """Badge-style shield: flat top, sides tapering to a bottom point."""
    top = cy - h / 2
    pts = [(cx - w / 2, top), (cx + w / 2, top)]
    # right edge curving to the bottom tip
    for i in range(1, steps + 1):
        t = i / steps
        x = cx + (w / 2) * (1 - t * t)
        y = top + h * (0.35 + 0.65 * t)
        pts.append((x, y))
    # back up the left edge
    for i in range(steps, 0, -1):
        t = i / steps
        x = cx - (w / 2) * (1 - t * t)
        y = top + h * (0.35 + 0.65 * t)
        pts.append((x, y))
    return pts


def _shrunk(pts, cx, cy, f):
    return [(cx + (x - cx) * f, cy + (y - cy) * f) for x, y in pts]


def draw_icon(size=S):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = size / S

    # rounded dark plate
    r = 180 * k
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=BG,
                        outline=EDGE, width=max(1, int(10 * k)))

    # cyan shield ring: filled outer shield minus a shrunken inner one —
    # no polyline joints, so no corner artifacts at small sizes
    cx, cy = size / 2, size / 2 + 8 * k
    outer = shield_points(cx, cy, 600 * k, 660 * k)
    d.polygon(outer, fill=CYAN)
    d.polygon(_shrunk(outer, cx, cy + 40 * k, 0.86), fill=BG)

    # green terminal prompt ">" + underscore inside the shield
    lw = max(2, int(54 * k))
    x0, y0 = size * 0.37, size * 0.355
    d.line([(x0, y0), (x0 + 128 * k, y0 + 102 * k), (x0, y0 + 204 * k)],
           fill=GREEN, width=lw, joint='curve')
    d.line([(size * 0.535, size * 0.555), (size * 0.665, size * 0.555)],
           fill=GREEN, width=lw)
    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    master = draw_icon()

    # macOS asset catalog
    macdir = os.path.join(root, 'macos/Runner/Assets.xcassets/AppIcon.appiconset')
    for px in (16, 32, 64, 128, 256, 512, 1024):
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(macdir, f'app_icon_{px}.png'))

    # Windows .ico
    ico = os.path.join(root, 'windows/runner/resources/app_icon.ico')
    master.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                            (64, 64), (128, 128), (256, 256)])

    # Linux hicolor set for the .deb / tarball packaging
    lindir = os.path.join(root, 'linux/packaging/icons')
    os.makedirs(lindir, exist_ok=True)
    for px in (16, 24, 32, 48, 64, 128, 256, 512):
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(lindir, f'{px}.png'))

    # one big PNG for the sites / release page
    master.save(os.path.join(root, 'tool/icon-1024.png'))
    print('icons written')


if __name__ == '__main__':
    main()
