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


def draw_icon(size=S, plate='rounded', scale=1.0):
    """plate: 'rounded' (desktop + legacy Android), 'square' (full bleed: iOS
    and the Play listing, which round the corners themselves) or 'none'
    (Android adaptive foreground layer). scale shrinks the art around the
    centre; the defaults reproduce the original desktop icon exactly."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = size / S
    a = k * scale                      # art scale

    if plate == 'rounded':
        r = 180 * k
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=BG,
                            outline=EDGE, width=max(1, int(10 * k)))
    elif plate == 'square':
        d.rectangle([0, 0, size - 1, size - 1], fill=BG)

    def at(fx, fy):
        """A point of the 1024 design (as fractions), scaled about the centre."""
        return (size / 2 + (fx - 0.5) * S * a, size / 2 + (fy - 0.5) * S * a)

    # cyan shield ring: filled outer shield minus a shrunken inner one —
    # no polyline joints, so no corner artifacts at small sizes
    cx, cy = size / 2, size / 2 + 8 * a
    outer = shield_points(cx, cy, 600 * a, 660 * a)
    d.polygon(outer, fill=CYAN)
    d.polygon(_shrunk(outer, cx, cy + 40 * a, 0.86), fill=BG)

    # green terminal prompt ">" + underscore inside the shield
    lw = max(2, int(54 * a))
    x0, y0 = at(0.37, 0.355)
    d.line([(x0, y0), (x0 + 128 * a, y0 + 102 * a), (x0, y0 + 204 * a)],
           fill=GREEN, width=lw, joint='curve')
    d.line([at(0.535, 0.555), at(0.665, 0.555)], fill=GREEN, width=lw)
    return img


def phone_icons(root):
    """iOS asset catalog, Android legacy + adaptive launcher icons, and the
    512 px Play Store listing icon."""
    import json

    # iOS: every size the asset catalog lists, full bleed, no alpha (App Store
    # rejects icons with transparency; iOS applies its own corner mask).
    iosdir = os.path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')
    square = draw_icon(plate='square').convert('RGB')
    for im in json.load(open(os.path.join(iosdir, 'Contents.json')))['images']:
        if 'filename' not in im:
            continue
        px = round(float(im['size'].split('x')[0]) * int(im['scale'][0]))
        square.resize((px, px), Image.LANCZOS).save(os.path.join(iosdir, im['filename']))

    # Android: legacy icon (rounded plate) for old launchers, plus an adaptive
    # icon (Android 8+): dark background colour + the art on its own layer,
    # scaled to stay inside the 66 dp safe circle of the 108 dp canvas.
    res = os.path.join(root, 'android/app/src/main/res')
    rounded = draw_icon()
    fg = draw_icon(plate='none', scale=0.68)
    for dpi, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        d = os.path.join(res, f'mipmap-{dpi}')
        os.makedirs(d, exist_ok=True)
        rounded.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher.png'))
        fpx = px * 108 // 48
        fg.resize((fpx, fpx), Image.LANCZOS).save(os.path.join(d, 'ic_launcher_foreground.png'))
    os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
    with open(os.path.join(res, 'mipmap-anydpi-v26/ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    with open(os.path.join(res, 'values/ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <color name="ic_launcher_background">#0B1320</color>\n</resources>\n')

    # Play Store listing icon: 512x512 full square (Google masks it).
    draw_icon(plate='square').resize((512, 512), Image.LANCZOS).save(
        os.path.join(root, 'tool/play-icon-512.png'))


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

    phone_icons(root)
    print('icons written')


if __name__ == '__main__':
    main()
