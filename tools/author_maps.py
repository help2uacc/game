#!/usr/bin/env python3
"""Authoring helper for the 12 map JSON files (PRD §10).

Maps are described with a few drawing primitives on a grid whose y axis
points UP from the bottom row (y=0), most of them on the left half and
mirrored to the right half for fairness. The resulting JSON files in
data/maps/ are the source of truth used by the game; this script only makes
writing them less error-prone. Run: python3 tools/author_maps.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "maps"


class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.cells = [["."] * w for _ in range(h)]
        self.movers = []

    # y measured from the bottom (0 = bottom row)
    def put(self, x, y, ch):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.cells[self.h - 1 - y][x] = ch

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.cells[self.h - 1 - y][x]
        return "."

    def rect(self, x0, y0, x1, y1, ch):
        """Inclusive rectangle."""
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
                self.put(x, y, ch)

    def mx(self, x):
        return self.w - 1 - x

    def mrect(self, x0, y0, x1, y1, ch):
        """Rectangle plus its left/right mirror."""
        self.rect(x0, y0, x1, y1, ch)
        self.rect(self.mx(x1), y0, self.mx(x0), y1, ch)

    def mput(self, x, y, ch):
        self.put(x, y, ch)
        self.put(self.mx(x), y, ch)

    def surface(self, x, y, ch):
        """Put a marker standing on the surface whose top block is at y-1."""
        self.put(x, y, ch)

    def mover(self, mid, x0, y, length, path, speed, pause=1.0, height=1):
        """Horizontal moving platform; path offsets are in cells, +y = up."""
        cells = []
        for yy in range(y, y + height):
            for x in range(x0, x0 + length):
                self.put(x, yy, "M")
                cells.append([x, self.h - 1 - yy])
        # JSON path uses layout convention (+y = down the layout).
        self.movers.append({"id": mid, "cells": cells, "path": [[dx, -dy] for dx, dy in path],
                            "speed": speed, "pause": pause})

    def to_json(self, mid, name, theme):
        return {
            "id": mid,
            "name": name,
            "theme": theme,
            "layout": ["".join(r) for r in self.cells],
            "movers": self.movers,
        }


def candy_plains():
    g = Grid(90, 34)
    # Ground islands (pits between them and at both map edges).
    g.mrect(3, 0, 17, 4, "#")
    g.mrect(3, 4, 17, 4, "%")
    g.mrect(24, 0, 44, 3, "#")
    g.mrect(24, 3, 44, 3, "%")
    # Second level.
    g.mrect(7, 9, 13, 9, "#")
    g.mrect(26, 8, 33, 8, "=")
    g.rect(40, 11, 49, 11, "#")
    g.mrect(19, 12, 23, 12, "=")
    g.mrect(30, 15, 36, 15, "=")
    g.rect(41, 18, 48, 18, "=")
    g.mrect(10, 15, 15, 15, "=")
    # Spawns (8), weapons (10), items (3).
    for x, y in [(6, 5), (15, 5), (28, 4), (38, 4)]:
        g.mput(x, y, "S")
    for x, y in [(10, 5), (9, 10), (29, 9), (21, 13), (33, 16)]:
        g.mput(x, y, "W")
    for x, y in [(44, 12), (45, 19)]:
        g.put(x, y, "I")
    g.put(12, 16, "I")
    g.put(g.mx(12), 16, "W") if False else None
    g.mput(13, 16, ".")
    g.put(g.mx(12), 16, "I")
    return g.to_json("candy_plains", "Candy Plains", "candy")


MAPS = [candy_plains]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in MAPS:
        data = fn()
        path = OUT / f"{data['id']}.json"
        text = json.dumps(data, indent=2)
        # keep one layout row per line for readability
        path.write_text(text + "\n", encoding="utf-8")
        print("wrote", path.name)


if __name__ == "__main__":
    main()
