#!/usr/bin/env python3
"""Generate Block Brawl branding PNGs (PRD §11.6) from simple shapes.

Outputs (deterministic):
  assets/branding/icon.png       192x192 launcher icon
  assets/branding/icon_fg.png    432x432 adaptive icon foreground
  assets/branding/icon_bg.png    432x432 adaptive icon background
  assets/branding/splash.png     1920x1080 boot splash
  assets/branding/logo.png       in-game logo (transparent)

Only the standard library + Pillow are used.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding"

INK = (0x3A, 0x35, 0x50)
WHITE = (0xFF, 0xFD, 0xF8)
BG_SKY = (0xDC, 0xEB, 0xFF)
PLAYER = [
    (0xFF, 0x8F, 0xB1), (0xFF, 0xB2, 0x6B), (0xFF, 0xE0, 0x66), (0x8F, 0xD6, 0x94),
    (0x6F, 0xD3, 0xC8), (0x7F, 0xB7, 0xFF), (0xB4, 0x9C, 0xFF), (0xC4, 0x9A, 0x7A),
]

# 5x7 blocky font for the letters we need.
FONT = {
    "B": ["1111.", "1...1", "1...1", "1111.", "1...1", "1...1", "1111."],
    "L": ["1....", "1....", "1....", "1....", "1....", "1....", "11111"],
    "O": [".111.", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."],
    "C": [".1111", "1....", "1....", "1....", "1....", "1....", ".1111"],
    "K": ["1...1", "1..1.", "1.1..", "11...", "1.1..", "1..1.", "1...1"],
    "R": ["1111.", "1...1", "1...1", "1111.", "1.1..", "1..1.", "1...1"],
    "A": [".111.", "1...1", "1...1", "11111", "1...1", "1...1", "1...1"],
    "W": ["1...1", "1...1", "1...1", "1.1.1", "1.1.1", "11.11", "1...1"],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


def shade(c, f):
    return tuple(max(0, min(255, int(round(v * f)))) for v in c)


def draw_block(d: ImageDraw.ImageDraw, x, y, s, color, depth):
    """A cube seen slightly from above-right: front face + top + side faces."""
    dep = max(1, int(s * depth))
    # side (right) face
    d.polygon([(x + s, y), (x + s + dep, y - dep), (x + s + dep, y + s - dep), (x + s, y + s)], fill=shade(color, 0.84))
    # top face
    d.polygon([(x, y), (x + dep, y - dep), (x + s + dep, y - dep), (x + s, y)], fill=color)
    # front face
    d.rectangle([x, y, x + s - 1, y + s - 1], fill=shade(color, 0.94))


def draw_text(d, text, x0, y0, cell, gap, colors, shadow=True):
    x = x0
    for i, ch in enumerate(text):
        glyph = FONT[ch]
        color = colors[i % len(colors)]
        if ch != " ":
            if shadow:
                for r, row in enumerate(glyph):
                    for c, v in enumerate(row):
                        if v == "1":
                            sx = x + c * cell + cell // 5
                            sy = y0 + r * cell + cell // 4
                            d.rectangle([sx, sy, sx + cell - 1, sy + cell - 1], fill=INK + (40,))
            for r, row in enumerate(glyph):
                for c, v in enumerate(row):
                    if v == "1":
                        draw_block(d, x + c * cell, y0 + r * cell, cell - 2, color, 0.18)
        x += 5 * cell + gap


def text_width(text, cell, gap):
    return len(text) * 5 * cell + (len(text) - 1) * gap


def draw_head(d, cx, cy, size, color):
    """Blocky stickman head (cube) with two dark square eyes."""
    s = size
    x = cx - s // 2
    y = cy - s // 2
    draw_block(d, x, y, s, color, 0.16)
    eye = max(2, int(s * 0.16))
    ey = y + int(s * 0.38)
    d.rectangle([x + int(s * 0.24), ey, x + int(s * 0.24) + eye, ey + eye], fill=INK)
    d.rectangle([x + int(s * 0.60), ey, x + int(s * 0.60) + eye, ey + eye], fill=INK)
    # tiny torso hint below
    tw = int(s * 0.36)
    d.rectangle([cx - tw // 2, y + s + int(s * 0.06), cx + tw // 2, y + s + int(s * 0.22)], fill=shade(color, 0.94))


def rounded_bg(size, color, radius):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=color)
    return img, d


def gen_icon():
    img, d = rounded_bg(192, BG_SKY + (255,), 40)
    # little ground blocks
    for i in range(6):
        draw_block(d, 6 + i * 31, 160, 28, PLAYER[(i + 3) % 8], 0.0)
    draw_head(d, 92, 88, 92, PLAYER[0])
    img.save(OUT / "icon.png")


def gen_adaptive():
    bg = Image.new("RGBA", (432, 432), BG_SKY + (255,))
    d = ImageDraw.Draw(bg)
    for i in range(10):
        draw_block(d, i * 44, 360, 42, PLAYER[(i + 3) % 8], 0.0)
    bg.save(OUT / "icon_bg.png")
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    draw_head(d, 212, 204, 150, PLAYER[0])
    fg.save(OUT / "icon_fg.png")


def gen_splash():
    img = Image.new("RGBA", (1920, 1080), BG_SKY + (255,))
    d = ImageDraw.Draw(img, "RGBA")
    cell, gap = 26, 26
    for line, y, offset in (("BLOCK", 300, 0), ("BRAWL", 540, 5)):
        w = text_width(line, cell, gap)
        colors = PLAYER[offset:] + PLAYER[:offset]
        draw_text(d, line, (1920 - w) // 2, y, cell, gap, colors)
    for i in range(0, 1920, 48):
        draw_block(d, i, 1000, 46, PLAYER[(i // 48) % 8], 0.0)
    img.save(OUT / "splash.png")


def gen_logo():
    cell, gap = 16, 14
    w = text_width("BLOCK BRAWL", cell, gap) + 20
    h = 7 * cell + 30
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    draw_text(d, "BLOCK BRAWL", 6, 12, cell, gap, PLAYER)
    img.save(OUT / "logo.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    gen_icon()
    gen_adaptive()
    gen_splash()
    gen_logo()
    print("branding written to", OUT)


if __name__ == "__main__":
    main()
