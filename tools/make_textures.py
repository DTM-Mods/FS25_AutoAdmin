"""Draws the mod's textures with Pillow:

  gui/autoAdmin_ui.dds   the GUI sheet: white shapes and icons (512x512, 8x8 cells of 64 px, DXT5), tinted in the game
  icon_autoAdmin.dds     the mod icon (512x512 DXT1, no mipmaps, as GIANTS' TestRunner wants it)
  icon_autoAdmin.png     the same icon as PNG (not shipped: the .dds of the same name is)
  modhub/icon_512.png    the icon for the ModHub page
  previews/ui_sheet.png  the GUI sheet on a dark background, to look at

Usage: python -I tools/make_textures.py

The cell order must match AutoAdminGui.CELLS in scripts/gui/AutoAdminGui.lua.
The mod icon is GIANTS' ModHub background (_tools/modhub/modIcon_background.png) with a simple picture and the
English title, as GIANTS asks for script mods (no modder logos on it).
"""
import io
import math
import os
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DTM = ROOT.parent
BG = DTM / "_tools" / "modhub" / "modIcon_background.png"
FONT = DTM / "_brand" / "font" / "Outfit.ttf"

CELLS = ["solid", "circle", "tile", "shield", "user", "key", "clock", "pause",
         "play", "trash", "plus", "refresh", "check", "power", "ring", "chevron",
         "crown", "lock", "up", "down"]

S = 4            # supersampling
CELL = 64
SIZE = 512


def cell_canvas():
    return Image.new("L", (CELL * S, CELL * S), 0)


def shield_path(cx, cy, w, h):
    """Points of a shield outline centred on (cx, cy)."""
    pts = []
    top = cy - h / 2
    left, right = cx - w / 2, cx + w / 2
    # flat-ish top with a little notch upward in the middle
    pts += [(left, top + h * 0.12), (cx - w * 0.18, top + h * 0.05), (cx, top), (cx + w * 0.18, top + h * 0.05),
            (right, top + h * 0.12)]
    # right side down then curve to the bottom point
    steps = 24
    for i in range(steps + 1):
        t = i / steps
        x = right - (right - cx) * (t ** 1.6)
        y = top + h * 0.12 + (h * 0.88) * (math.sin(t * math.pi / 2))
        pts.append((x, y))
    for i in range(steps, -1, -1):
        t = i / steps
        x = left + (cx - left) * (t ** 1.6)
        y = top + h * 0.12 + (h * 0.88) * (math.sin(t * math.pi / 2))
        pts.append((x, y))
    return pts


def draw_cell(name):
    im = cell_canvas()
    d = ImageDraw.Draw(im)
    c = CELL * S
    m = 8 * S          # icon margin
    W = 255
    if name == "solid":
        d.rectangle([0, 0, c, c], fill=W)
    elif name == "circle":
        d.ellipse([2 * S, 2 * S, c - 2 * S, c - 2 * S], fill=W)
    elif name == "ring":
        d.ellipse([4 * S, 4 * S, c - 4 * S, c - 4 * S], outline=W, width=6 * S)
    elif name == "tile":
        d.rounded_rectangle([0, 0, c - 1, c - 1], radius=14 * S, fill=W)
    elif name == "shield":
        d.polygon(shield_path(c / 2, c / 2 + 1 * S, 44 * S, 50 * S), fill=W)
        # check mark cut out
        d.line([(20 * S, 33 * S), (28 * S, 41 * S), (44 * S, 24 * S)], fill=0, width=6 * S, joint="curve")
    elif name == "user":
        d.ellipse([22 * S, 8 * S, 42 * S, 28 * S], fill=W)
        d.rounded_rectangle([12 * S, 32 * S, 52 * S, 58 * S], radius=16 * S, fill=W)
        d.rectangle([12 * S, 50 * S, 52 * S, 58 * S], fill=W)
    elif name == "key":
        d.ellipse([8 * S, 18 * S, 34 * S, 44 * S], fill=W)
        d.ellipse([15 * S, 25 * S, 27 * S, 37 * S], fill=0)
        d.rectangle([30 * S, 28 * S, 58 * S, 35 * S], fill=W)
        d.rectangle([46 * S, 35 * S, 52 * S, 44 * S], fill=W)
        d.rectangle([38 * S, 35 * S, 43 * S, 42 * S], fill=W)
    elif name == "clock":
        d.ellipse([m, m, c - m, c - m], outline=W, width=6 * S)
        d.line([(32 * S, 18 * S), (32 * S, 33 * S), (42 * S, 39 * S)], fill=W, width=5 * S, joint="curve")
    elif name == "pause":
        d.rounded_rectangle([18 * S, 14 * S, 28 * S, 50 * S], radius=2 * S, fill=W)
        d.rounded_rectangle([36 * S, 14 * S, 46 * S, 50 * S], radius=2 * S, fill=W)
    elif name == "play":
        d.polygon([(20 * S, 12 * S), (50 * S, 32 * S), (20 * S, 52 * S)], fill=W)
    elif name == "trash":
        d.rounded_rectangle([16 * S, 20 * S, 48 * S, 56 * S], radius=4 * S, fill=W)
        d.rectangle([12 * S, 13 * S, 52 * S, 18 * S], fill=W)
        d.rectangle([26 * S, 8 * S, 38 * S, 13 * S], fill=W)
        for x in (24, 32, 40):
            d.line([(x * S, 26 * S), (x * S, 50 * S)], fill=0, width=3 * S)
    elif name == "plus":
        d.rounded_rectangle([28 * S, 10 * S, 36 * S, 54 * S], radius=2 * S, fill=W)
        d.rounded_rectangle([10 * S, 28 * S, 54 * S, 36 * S], radius=2 * S, fill=W)
    elif name == "refresh":
        d.arc([12 * S, 12 * S, 52 * S, 52 * S], start=40, end=330, fill=W, width=6 * S)
        d.polygon([(44 * S, 6 * S), (56 * S, 22 * S), (38 * S, 24 * S)], fill=W)
    elif name == "check":
        d.line([(12 * S, 33 * S), (26 * S, 47 * S), (52 * S, 18 * S)], fill=W, width=8 * S, joint="curve")
    elif name == "power":
        d.arc([12 * S, 14 * S, 52 * S, 54 * S], start=-60, end=240, fill=W, width=6 * S)
        d.rounded_rectangle([29 * S, 8 * S, 35 * S, 34 * S], radius=3 * S, fill=W)
    elif name == "chevron":
        d.line([(24 * S, 14 * S), (42 * S, 32 * S), (24 * S, 50 * S)], fill=W, width=7 * S, joint="curve")
    elif name == "crown":
        d.polygon([(8 * S, 20 * S), (21 * S, 33 * S), (32 * S, 12 * S), (43 * S, 33 * S), (56 * S, 20 * S),
                   (51 * S, 48 * S), (13 * S, 48 * S)], fill=W)
        d.rounded_rectangle([13 * S, 51 * S, 51 * S, 56 * S], radius=2 * S, fill=W)
        for x, y in ((8, 18), (32, 10), (56, 18)):
            d.ellipse([(x - 4) * S, (y - 4) * S, (x + 4) * S, (y + 4) * S], fill=W)
    elif name == "lock":
        d.arc([18 * S, 8 * S, 46 * S, 40 * S], start=180, end=360, fill=W, width=6 * S)
        d.rectangle([18 * S, 23 * S, 24 * S, 30 * S], fill=W)
        d.rectangle([40 * S, 23 * S, 46 * S, 30 * S], fill=W)
        d.rounded_rectangle([12 * S, 28 * S, 52 * S, 56 * S], radius=5 * S, fill=W)
        d.ellipse([28 * S, 36 * S, 36 * S, 44 * S], fill=0)
        d.rectangle([30 * S, 42 * S, 34 * S, 50 * S], fill=0)
    elif name == "up":
        d.polygon([(32 * S, 8 * S), (54 * S, 32 * S), (40 * S, 32 * S), (40 * S, 56 * S), (24 * S, 56 * S),
                   (24 * S, 32 * S), (10 * S, 32 * S)], fill=W)
    elif name == "down":
        d.polygon([(32 * S, 56 * S), (54 * S, 32 * S), (40 * S, 32 * S), (40 * S, 8 * S), (24 * S, 8 * S),
                   (24 * S, 32 * S), (10 * S, 32 * S)], fill=W)
    return im.resize((CELL, CELL), Image.LANCZOS)


def save_dds(image, out, fmt):
    buf = io.BytesIO()
    image.save(buf, "DDS", pixel_format=fmt)
    data = buf.getvalue()
    # Pillow writes one level; make sure the header says so (no mipmaps)
    header = bytearray(data[:128])
    struct.pack_into("<I", header, 28, 0)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(bytes(header) + data[128:])


def make_sheet():
    sheet = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    for i, name in enumerate(CELLS):
        col, row = i % 8, i // 8
        alpha = draw_cell(name)
        white = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 255))
        white.putalpha(alpha)
        sheet.paste(white, (col * CELL, row * CELL))
    save_dds(sheet, ROOT / "gui" / "autoAdmin_ui.dds", "DXT5")
    preview = Image.new("RGBA", (SIZE, SIZE), (28, 29, 27, 255))
    preview.alpha_composite(sheet)
    (ROOT / "previews").mkdir(exist_ok=True)
    preview.save(ROOT / "previews" / "ui_sheet.png")


def make_icon():
    gold = (217, 164, 65, 255)
    cream = (244, 241, 232, 255)
    night = (20, 51, 38, 255)
    sage = (127, 164, 138, 255)
    big = 512 * S
    fg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    cx, cy = big / 2, 196 * S
    # shield: gold rim, night-green body, cream check
    d.polygon(shield_path(cx, cy, 300 * S, 330 * S), fill=gold)
    d.polygon(shield_path(cx, cy + 4 * S, 256 * S, 286 * S), fill=night)
    d.line([(cx - 74 * S, cy + 6 * S), (cx - 20 * S, cy + 60 * S), (cx + 82 * S, cy - 52 * S)],
           fill=cream, width=34 * S, joint="curve")
    # a small "remembered" marker: a sage ring with a clock hand, bottom right of the shield
    rx, ry, rr = cx + 118 * S, cy + 104 * S, 58 * S
    d.ellipse([rx - rr, ry - rr, rx + rr, ry + rr], fill=cream)
    d.ellipse([rx - rr + 12 * S, ry - rr + 12 * S, rx + rr - 12 * S, ry + rr - 12 * S], fill=sage)
    d.line([(rx, ry - 30 * S), (rx, ry), (rx + 22 * S, ry + 14 * S)], fill=cream, width=12 * S, joint="curve")
    fg = fg.resize((512, 512), Image.LANCZOS)
    font = ImageFont.truetype(str(FONT), 58)
    try:
        font.set_variation_by_name("Bold")
    except (OSError, ValueError):
        pass
    td = ImageDraw.Draw(fg)
    title = "Auto Admin"
    w = td.textlength(title, font=font)
    td.text(((512 - w) / 2, 400), title, font=font, fill=(255, 255, 255, 255))
    bg = Image.open(BG).convert("RGBA").resize((512, 512), Image.LANCZOS)
    bg.alpha_composite(fg)
    icon = bg.convert("RGB")
    icon.save(ROOT / "icon_autoAdmin.png")
    (ROOT / "modhub").mkdir(exist_ok=True)
    icon.save(ROOT / "modhub" / "icon_512.png")
    save_dds(icon.convert("RGBA"), ROOT / "icon_autoAdmin.dds", "DXT1")


if __name__ == "__main__":
    for p in (BG, FONT):
        if not p.exists():
            sys.exit(f"missing {p}")
    make_sheet()
    make_icon()
    print("done")
