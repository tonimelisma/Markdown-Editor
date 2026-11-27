#!/usr/bin/env python3
"""Draws the app icon and writes every size the asset catalog's AppIcon set names.

    python3 Scripts/make-app-icon.py

The icon is made in code so it can be regenerated anywhere, a cloud session included: a macOS
rounded-square tile in sage, and on it a cream legal pad, turned a few degrees, with a terracotta
binding strip, ruled lines and a Markdown heading mark (#) in the margin. It is drawn at 4096 px and
scaled down, so every size is antialiased from the same geometry; 16 and 32 px get simpler art,
without the margin mark and text, which would only be noise at that size. Needs Pillow.
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


def hash_mark(d, cx, cy, size, weight, fill, slant=0.15):
    """A '#' in grid units: two slanted uprights and two crossbars, with round ends."""
    h = size / 2
    gap = size * 0.18
    w = weight * U
    for dx in (-gap, gap):
        top = ((cx + dx + slant * h) * U, (cy - h) * U)
        foot = ((cx + dx - slant * h) * U, (cy + h) * U)
        d.line([top, foot], fill=fill, width=int(w))
        for x, y in (top, foot):
            d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=fill)
    for dy in (-gap, gap):
        d.rounded_rectangle(
            ((cx - h * 0.78) * U, (cy + dy) * U - w / 2, (cx + h * 0.78) * U, (cy + dy) * U + w / 2),
            radius=w / 2,
            fill=fill,
        )


def draw_icon(detail=True):
    """A legal pad on a sage tile: cream paper, a terracotta binding strip, ruled lines, and a
    Markdown heading mark in the margin. `detail=False` is the art for 16 and 32 px, where a margin
    mark and text would be noise: the pad, the strip and four heavier rules."""
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Tile: Apple's grid puts the body at 824 of 1024 units, centred, with a soft shadow below.
    half = 412 * U
    tile = superellipse(S / 2, S / 2, half)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + 12 * U) for x, y in tile], fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * U)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(tile, fill=255)
    body = vertical_gradient((S, S), (156, 180, 152), (100, 128, 102)).convert("RGBA")
    canvas.paste(body, (0, 0), mask)

    # The pad, drawn upright on its own layer and then turned a few degrees, as if set down.
    pad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(pad)
    left, top, right, bottom = 262 * U, 222 * U, 762 * U, 816 * U
    strip = (top + 104 * U) if detail else (top + 124 * U)
    paper, binding, binding_edge = (253, 249, 238), (200, 104, 74), (168, 82, 58)
    d.rounded_rectangle((left, top, right, bottom), radius=36 * U, fill=paper)
    d.rounded_rectangle((left, top, right, strip), radius=36 * U, fill=binding)
    d.rectangle((left, strip - 40 * U, right, strip), fill=binding)
    d.rectangle((left, strip - 10 * U, right, strip), fill=binding_edge)

    rule = (172, 196, 222)
    if detail:
        for i in range(7):
            y = strip + (70 + i * 58) * U
            d.line([(left + 38 * U, y), (right - 36 * U, y)], fill=rule, width=int(6 * U))
        margin = left + 112 * U
        d.line([(margin, strip + 14 * U), (margin, bottom - 14 * U)], fill=(230, 150, 138), width=int(6 * U))
        hash_mark(d, (left / U) + 56, (strip / U) + 50, 52, 13, binding)
        heading, text = (66, 74, 88), (150, 158, 172)
        for i, width in enumerate((300, 340, 250)):
            y = strip + (34 + i * 58) * U
            d.rounded_rectangle(
                (margin + 22 * U, y, margin + (22 + width) * U, y + 20 * U),
                radius=10 * U,
                fill=heading if i == 0 else text,
            )
    else:
        for i in range(4):
            y = strip + (96 + i * 104) * U
            d.line([(left + 52 * U, y), (right - 52 * U, y)], fill=(120, 150, 186), width=int(22 * U))

    pad = pad.rotate(-4, resample=Image.BICUBIC, center=(S / 2, S / 2))
    pad_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pad_shadow.putalpha(pad.split()[3].point(lambda v: int(v * 0.35)))
    lifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    lifted.alpha_composite(pad_shadow.filter(ImageFilter.GaussianBlur(18 * U)), (0, int(12 * U)))
    canvas.alpha_composite(lifted)
    canvas.alpha_composite(pad)
    return canvas


def main():
    icon, small = draw_icon(), draw_icon(detail=False)
    contents = json.loads((ICONSET / "Contents.json").read_text())
    for image in contents["images"]:
        points = int(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        pixels = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        art = small if pixels <= 32 else icon
        art.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name, optimize=True)
        image["filename"] = name
    (ICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"make-app-icon: wrote {len(contents['images'])} images to {ICONSET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
