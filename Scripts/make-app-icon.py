#!/usr/bin/env python3
"""Draws the app icon and writes every size the asset catalog's AppIcon set names.

    python3 Scripts/make-app-icon.py

The icon is made in code so it can be regenerated anywhere, a cloud session included: a macOS
rounded-square tile in ink blue, a paper page with a folded corner, and the Markdown mark (an M and
a down arrow, the community's public-domain symbol for Markdown). It is drawn once at 4096 px and
scaled down, so every size is antialiased from the same geometry. Needs Pillow.
"""
import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Markdown Editor" / "Assets.xcassets" / "AppIcon.appiconset"
S = 4096  # working canvas; Apple's grid is 1024, so 1 grid unit = 4 px here
U = S / 1024


def superellipse(cx, cy, half, n=5.0, steps=720):
    """The macOS icon tile: a superellipse, close to Apple's continuous-corner rounded square."""
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = half * math.copysign(abs(c) ** (2 / n), c)
        y = half * math.copysign(abs(s) ** (2 / n), s)
        points.append((cx + x, cy + y))
    return points


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        f = y / max(1, size[1] - 1)
        gradient.putpixel((0, y), tuple(round(a + (b - a) * f) for a, b in zip(top, bottom)))
    return gradient.resize(size)


def draw_icon():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Tile: Apple's grid puts the body at 824 of 1024 units, centred, with a soft shadow below.
    half = 412 * U
    tile = superellipse(S / 2, S / 2, half)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + 12 * U) for x, y in tile], fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * U)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(tile, fill=255)
    body = vertical_gradient((S, S), (58, 88, 150), (24, 36, 74)).convert("RGBA")
    canvas.paste(body, (0, 0), mask)

    # Page: a sheet of paper with its top-right corner folded over.
    d = ImageDraw.Draw(canvas)
    left, top, right, bottom = 262 * U, 196 * U, 762 * U, 828 * U
    fold = 118 * U
    page_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(page_shadow).polygon(
        [(left, top + 10 * U), (right - fold, top + 10 * U), (right, top + fold + 10 * U), (right, bottom + 10 * U), (left, bottom + 10 * U)],
        fill=(0, 0, 0, 110),
    )
    canvas.alpha_composite(page_shadow.filter(ImageFilter.GaussianBlur(12 * U)))
    d = ImageDraw.Draw(canvas)
    d.polygon([(left, top), (right - fold, top), (right, top + fold), (right, bottom), (left, bottom)], fill=(250, 248, 242))
    d.polygon([(right - fold, top), (right - fold, top + fold), (right, top + fold)], fill=(214, 210, 200))

    # Text lines above and below the mark, the way a document reads.
    line = (196, 200, 212)
    for y, width in ((300, 300), (360, 360), (690, 380), (750, 260)):
        d.rounded_rectangle((left + 62 * U, y * U, left + (62 + width) * U, (y + 24) * U), radius=12 * U, fill=line)

    # The Markdown mark: an outlined frame holding an M and a down arrow.
    ink = (28, 42, 86)
    fx0, fy0, fx1, fy1 = 318 * U, 436 * U, 706 * U, 636 * U
    d.rounded_rectangle((fx0, fy0, fx1, fy1), radius=26 * U, outline=ink, width=int(22 * U))
    stroke = int(40 * U)
    mx0, mx1, my0, my1 = 378 * U, 532 * U, 482 * U, 590 * U
    d.line([(mx0, my1), (mx0, my0), ((mx0 + mx1) / 2, my0 + 62 * U), (mx1, my0), (mx1, my1)], fill=ink, width=stroke, joint="curve")
    ax = 618 * U
    d.line([(ax, my0), (ax, my1 - 40 * U)], fill=ink, width=stroke)
    d.polygon([(ax - 52 * U, my1 - 52 * U), (ax + 52 * U, my1 - 52 * U), (ax, my1 + 4 * U)], fill=ink)
    return canvas


def main():
    icon = draw_icon()
    contents = json.loads((ICONSET / "Contents.json").read_text())
    for image in contents["images"]:
        points = int(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        pixels = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        icon.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name, optimize=True)
        image["filename"] = name
    (ICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"make-app-icon: wrote {len(contents['images'])} images to {ICONSET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
