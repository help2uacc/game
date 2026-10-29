#!/usr/bin/env python3
"""Generate UI icons (PRD §11.3) as SVG files made of simple rectangles.

Each icon is drawn on a 64x64 grid. Shapes are drawn twice: a white
'outline' pass (each rect grown by 3 px) and an ink pass, so icons read on
both light panels and the game view. Output: assets/ui/icons/*.svg
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "icons"
INK = "#3A3550"
WHITE = "#FFFDF8"
OUTLINE = 3

# Each icon: list of (x, y, w, h[, color]) rectangles on a 64x64 grid.
ICONS = {
    "pistol": [(10, 20, 40, 12), (14, 30, 10, 18), (48, 22, 6, 6), (24, 32, 8, 4)],
    "smg": [(6, 20, 46, 12), (52, 23, 8, 5), (22, 32, 9, 20), (8, 32, 9, 13), (14, 16, 20, 4)],
    "shotgun": [(4, 24, 56, 8), (24, 32, 16, 8), (4, 32, 14, 12), (40, 20, 4, 4)],
    "sniper": [(2, 28, 60, 6), (8, 34, 22, 8), (14, 18, 22, 8), (12, 42, 8, 10), (40, 26, 4, 4)],
    "rocket_launcher": [(6, 22, 48, 16), (54, 20, 6, 20), (2, 20, 6, 20), (22, 38, 8, 12), (30, 16, 10, 6)],
    "grenades": [(20, 24, 26, 26), (26, 16, 14, 8), (40, 12, 10, 4), (46, 12, 4, 10)],
    "punch": [(16, 20, 32, 26), (12, 24, 6, 18), (48, 26, 6, 14), (22, 46, 22, 8), (16, 20, 8, 6, WHITE), (26, 20, 8, 6, WHITE), (36, 20, 8, 6, WHITE)],
    "thrown": [(10, 40, 10, 10), (22, 30, 10, 10), (34, 22, 10, 10), (46, 18, 10, 10)],
    "hp": [(24, 10, 16, 44), (10, 24, 44, 16)],
    "armor": [(10, 10, 44, 10), (14, 20, 36, 14), (20, 34, 24, 10), (26, 44, 12, 8)],
    "alive": [(24, 6, 16, 16), (26, 24, 12, 20), (16, 24, 8, 16), (40, 24, 8, 16), (24, 44, 7, 14), (33, 44, 7, 14)],
    "ping": [(8, 42, 10, 14), (22, 32, 10, 24), (36, 20, 10, 36), (50, 8, 8, 48)],
    "menu": [(10, 14, 44, 8), (10, 28, 44, 8), (10, 42, 44, 8)],
    "arrow_left": [(14, 28, 8, 8), (22, 20, 8, 24), (30, 12, 8, 40), (38, 26, 16, 12)],
    "arrow_right": [(42, 28, 8, 8), (34, 20, 8, 24), (26, 12, 8, 40), (10, 26, 16, 12)],
    "hazard": [(28, 6, 8, 8), (22, 14, 20, 10), (16, 24, 32, 10), (10, 34, 44, 10), (4, 44, 56, 12), (29, 18, 6, 18, WHITE), (29, 40, 6, 6, WHITE)],
    "jump": [(28, 8, 8, 8), (20, 16, 24, 8), (12, 24, 40, 8), (26, 32, 12, 24)],
    "pickup": [(26, 6, 12, 22), (16, 24, 32, 8), (22, 32, 20, 6), (10, 44, 44, 12)],
    "throw": [(8, 40, 12, 12), (20, 30, 12, 12), (32, 22, 12, 12), (44, 10, 12, 20), (36, 10, 20, 8)],
    "attack": [(28, 4, 8, 18), (28, 42, 8, 18), (4, 28, 18, 8), (42, 28, 18, 8), (28, 28, 8, 8)],
    "crown": [(8, 20, 8, 28), (28, 12, 8, 36), (48, 20, 8, 28), (8, 36, 48, 16)],
    "fall": [(28, 6, 8, 30), (18, 30, 28, 8), (24, 38, 16, 8), (8, 52, 48, 6)],
    "lava": [(6, 36, 52, 20), (14, 24, 10, 10), (34, 16, 10, 10), (46, 28, 6, 6)],
    "spikes": [(8, 44, 48, 12), (10, 32, 8, 12), (28, 28, 8, 16), (46, 32, 8, 12), (12, 24, 4, 8), (30, 18, 4, 10), (48, 24, 4, 8)],
    "skull": [(14, 10, 36, 30), (20, 40, 24, 12), (20, 20, 8, 8, WHITE), (36, 20, 8, 8, WHITE), (24, 44, 4, 6, WHITE), (36, 44, 4, 6, WHITE)],
    "settings": [(26, 4, 12, 56), (4, 26, 56, 12), (12, 12, 40, 40), (24, 24, 16, 16, WHITE)],
    "back": [(10, 28, 8, 8), (18, 20, 8, 24), (26, 26, 28, 12)],
}


def svg(rects) -> str:
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 64 64">']
    for r in rects:
        x, y, w, h = r[:4]
        parts.append(
            f'<rect x="{x - OUTLINE}" y="{y - OUTLINE}" width="{w + 2 * OUTLINE}" '
            f'height="{h + 2 * OUTLINE}" rx="3" fill="{WHITE}"/>'
        )
    for r in rects:
        x, y, w, h = r[:4]
        color = r[4] if len(r) > 4 else INK
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="2" fill="{color}"/>')
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def toggle(on: bool) -> str:
    """Pill-shaped switch for settings toggles (CheckButton icons)."""
    track = "#FFD36E" if on else "#D6D3E0"
    knob_x = 50 if on else 6
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="64" viewBox="0 0 96 52">\n'
        f'<rect x="2" y="4" width="92" height="44" rx="22" fill="{track}"/>\n'
        f'<rect x="{knob_x}" y="8" width="40" height="36" rx="18" fill="{WHITE}"/>\n'
        f'<rect x="{knob_x + 14}" y="20" width="12" height="12" rx="3" fill="{INK}"/>\n'
        "</svg>\n"
    )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, rects in ICONS.items():
        (OUT / f"{name}.svg").write_text(svg(rects), encoding="utf-8")
    (OUT / "toggle_on.svg").write_text(toggle(True), encoding="utf-8")
    (OUT / "toggle_off.svg").write_text(toggle(False), encoding="utf-8")
    print(f"{len(ICONS) + 2} icons written to {OUT}")


if __name__ == "__main__":
    main()
