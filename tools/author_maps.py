#!/usr/bin/env python3
"""Authoring helper for the 12 map JSON files (PRD §10).

Maps are described with a few drawing primitives on a grid whose y axis
points UP from the bottom row (y = 0), drawn on the left half and mirrored
to the right half for fairness. The resulting JSON files in data/maps/ are
the source of truth used by the game; this script only makes writing them
less error-prone. It also runs a rough reachability check (jump heights from
PRD §6.4) so every spawn, weapon and item point can be reached.

Usage: python3 tools/author_maps.py [--print]
"""
import json
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "maps"

# Movement envelope (PRD §6.4): jump 11 m/s, double jump 10 m/s, gravity 30.
MAX_RISE = 3          # cells a player can climb with a double jump (3.69 m)
PAD_RISE = 8          # jump pad 20 m/s -> 6.7 m, plus a double jump
MAX_GAP_LEVEL = 8     # horizontal gap (cells) across at the same height
MAX_GAP_RISE = 5      # horizontal gap when climbing


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

    def ground(self, x0, x1, top, cap="%"):
        """Solid ground from y=0 to top-1 with a decorative cap row."""
        self.rect(x0, 0, x1, top - 1, "#")
        if cap:
            self.rect(x0, top - 1, x1, top - 1, cap)

    def mground(self, x0, x1, top, cap="%"):
        self.ground(x0, x1, top, cap)
        self.ground(self.mx(x1), self.mx(x0), top, cap)

    def mover(self, mid, x0, y, length, path, speed, pause=1.0, height=1):
        """Moving platform; `path` offsets are cells with +y = up."""
        cells = []
        for yy in range(y, y + height):
            for x in range(x0, x0 + length):
                self.put(x, yy, "M")
                cells.append([x, self.h - 1 - yy])
        # JSON path uses the layout convention (+y = down the layout).
        self.movers.append({"id": mid, "cells": cells, "path": [[dx, -dy] for dx, dy in path],
                            "speed": speed, "pause": pause})

    def mmover(self, mid, x0, y, length, path, speed, pause=1.0):
        self.mover(mid + "a", x0, y, length, path, speed, pause)
        self.mover(mid + "b", self.mx(x0 + length - 1), y, length, [[-dx, dy] for dx, dy in path], speed, pause)

    def to_json(self, mid, name, theme):
        return {
            "id": mid,
            "name": name,
            "theme": theme,
            "layout": ["".join(r) for r in self.cells],
            "movers": self.movers,
        }


# ------------------------------------------------------------------ maps
def candy_plains():
    """Pits only (introductory)."""
    g = Grid(90, 32)
    g.mground(3, 17, 5)
    g.mground(24, 44, 4)
    g.mrect(6, 7, 13, 7, "#")
    g.mrect(27, 6, 33, 6, "=")
    g.mrect(18, 9, 23, 9, "=")
    g.rect(40, 9, 49, 9, "#")
    g.mrect(30, 12, 36, 12, "=")
    g.mrect(8, 12, 14, 12, "=")
    g.rect(40, 15, 49, 15, "=")
    g.mrect(18, 15, 24, 15, "=")
    g.mrect(28, 18, 34, 18, "=")
    g.rect(41, 21, 48, 21, "=")
    for x, y in [(6, 5), (14, 5), (27, 4), (38, 4)]:
        g.mput(x, y, "S")
    for x, y in [(9, 8), (20, 10), (31, 4), (33, 13), (11, 13)]:
        g.mput(x, y, "W")
    g.put(44, 16, "I")
    g.mput(21, 16, "I")
    return g.to_json("candy_plains", "Candy Plains", "candy")


def mint_towers():
    """Tall towers, many one-way platforms."""
    g = Grid(84, 42)
    g.mground(2, 14, 4)
    g.mground(30, 41, 4)
    # Towers rising out of the pits.
    g.mrect(20, 0, 22, 27, "#")
    g.rect(40, 4, 43, 19, "#")
    # One-way ledges around the towers.
    for y, left in [(6, True), (9, False), (12, True), (15, False), (18, True), (21, False), (24, True)]:
        if left:
            g.mrect(16, y, 19, y, "=")
        else:
            g.mrect(23, y, 26, y, "=")
    for y, left in [(6, True), (9, False), (12, True), (15, False)]:
        if left:
            g.mrect(34, y, 39, y, "=")
        else:
            g.mrect(34, y + 1, 37, y + 1, "=")
    g.mrect(4, 6, 10, 6, "=")
    g.mrect(4, 9, 10, 9, "=")
    g.mrect(6, 12, 12, 12, "=")
    g.rect(36, 22, 47, 22, "=")
    g.mrect(28, 25, 34, 25, "=")
    g.rect(38, 28, 45, 28, "=")
    for x, y in [(5, 4), (11, 4), (32, 4), (37, 4)]:
        g.mput(x, y, "S")
    for x, y in [(17, 7), (25, 13), (7, 10), (35, 11), (21, 28)]:
        g.mput(x, y, "W")
    g.put(41, 20, "I")
    g.mput(9, 13, "I")
    return g.to_json("mint_towers", "Mint Towers", "mint")


def lava_lagoon():
    """Lava pools between islands."""
    g = Grid(92, 34)
    g.rect(2, 0, 89, 1, "L")
    g.mground(3, 14, 6)
    g.mground(22, 32, 5)
    g.ground(40, 51, 7)
    g.mrect(15, 8, 20, 8, "=")
    g.mrect(33, 7, 38, 7, "=")
    g.mrect(7, 9, 12, 9, "=")
    g.mrect(24, 8, 30, 8, "=")
    g.rect(42, 9, 49, 9, "=")
    g.rect(43, 13, 48, 13, "=")
    g.mrect(28, 11, 34, 11, "=")
    g.mrect(16, 12, 21, 12, "=")
    for x, y in [(6, 6), (12, 6), (25, 5), (30, 5)]:
        g.mput(x, y, "S")
    for x, y in [(9, 10), (17, 9), (27, 9), (35, 8), (42, 7)]:
        g.mput(x, y, "W")
    g.put(45, 14, "I")
    g.mput(4, 6, "I")
    return g.to_json("lava_lagoon", "Lava Lagoon", "lava")


def cloud_hop():
    """Moving platforms over a big void."""
    g = Grid(96, 40)
    # Clouds (two rows thick).
    g.mrect(3, 10, 13, 11, "#")
    g.mrect(3, 11, 13, 11, "%")
    g.rect(42, 12, 53, 13, "#")
    g.rect(42, 13, 53, 13, "%")
    g.mrect(22, 15, 28, 16, "#")
    g.mrect(22, 16, 28, 16, "%")
    g.mrect(30, 6, 35, 7, "#")
    g.mrect(33, 18, 37, 19, "#")
    g.rect(40, 21, 55, 22, "#")
    g.rect(40, 22, 55, 22, "%")
    # Shuttles between the side clouds and the centre cloud.
    g.mmover("low", 15, 11, 3, [[0, 0], [20, 0]], 2.5, 1.0)
    for x, y in [(5, 12), (11, 12), (23, 17), (27, 17)]:
        g.mput(x, y, "S")
    for x, y in [(8, 12), (25, 17), (44, 14), (32, 8), (46, 23)]:
        g.mput(x, y, "W")
    g.put(47, 14, "I")
    g.mput(6, 12, "I")
    return g.to_json("cloud_hop", "Cloud Hop", "cloud")


def crate_yard():
    """Many destructible crates as cover."""
    g = Grid(90, 32)
    g.mground(4, 42, 4)
    g.mrect(10, 7, 20, 7, "=")
    g.mrect(30, 7, 40, 7, "=")
    g.mrect(20, 10, 33, 10, "=")
    g.rect(38, 13, 51, 13, "=")
    g.mrect(4, 10, 9, 10, "=")
    for x, y in [(9, 4), (9, 5), (10, 4), (18, 4), (28, 4), (29, 4), (28, 5), (39, 4), (40, 4),
                 (14, 8), (36, 8), (24, 11)]:
        g.mput(x, y, "C")
    g.put(44, 4, "C")
    g.put(45, 4, "C")
    for x, y in [(6, 4), (15, 4), (24, 4), (34, 4)]:
        g.mput(x, y, "S")
    for x, y in [(12, 8), (33, 8), (27, 11), (21, 4), (41, 14)]:
        g.mput(x, y, "W")
    g.put(44, 14, "I")
    g.mput(31, 4, "I")
    return g.to_json("crate_yard", "Crate Yard", "crate")


def spike_factory():
    """Spikes + horizontal moving platforms."""
    g = Grid(92, 36)
    g.mground(2, 20, 4)
    g.ground(36, 55, 4)
    # Spike pits between the floors.
    g.mground(21, 35, 2, cap="")
    g.mrect(21, 2, 35, 2, "^")
    g.mmover("pit", 22, 5, 3, [[0, 0], [10, 0]], 2.0, 0.8)
    g.mrect(3, 6, 7, 6, "=")
    g.mrect(8, 8, 16, 9, "#")
    g.mput(15, 10, "^")
    g.mput(16, 10, "^")
    g.mrect(38, 7, 44, 7, "=")
    g.mrect(26, 10, 32, 10, "=")
    g.mrect(36, 10, 40, 10, "=")
    g.rect(42, 13, 49, 13, "#")
    g.mrect(34, 16, 40, 16, "=")
    g.mrect(4, 12, 9, 12, "=")
    for x, y in [(5, 4), (14, 4), (39, 4), (43, 4)]:
        g.mput(x, y, "S")
    for x, y in [(10, 10), (28, 11), (41, 8), (37, 17), (18, 4)]:
        g.mput(x, y, "W")
    g.put(45, 14, "I")
    g.mput(6, 13, "I")
    return g.to_json("spike_factory", "Spike Factory", "spike")


def bubblegum_bridges():
    """Long thin bridges, wide pits."""
    g = Grid(100, 34)
    g.mground(2, 8, 6)
    g.mground(26, 31, 5)
    g.ground(46, 53, 6)
    g.mrect(9, 7, 25, 7, "=")
    g.mrect(32, 7, 45, 7, "#")
    g.mrect(14, 10, 40, 10, "=")
    g.rect(30, 13, 69, 13, "=")
    g.mrect(4, 13, 10, 13, "=")
    for x, y in [(4, 6), (7, 6), (27, 5), (30, 5)]:
        g.mput(x, y, "S")
    for x, y in [(17, 8), (39, 8), (20, 11), (35, 11), (40, 14)]:
        g.mput(x, y, "W")
    g.put(49, 6, "I")
    g.mput(25, 11, "I")
    return g.to_json("bubblegum_bridges", "Bubblegum Bridges", "bubblegum")


def lilac_caves():
    """Enclosed cave, low ceilings, lava at the bottom."""
    g = Grid(90, 38)
    g.rect(0, 0, 89, 2, "L")
    g.mrect(0, 0, 1, 37, "#")
    g.rect(0, 31, 89, 37, "#")
    g.rect(0, 31, 89, 31, "%")
    for x in (10, 11, 24, 25, 26, 37):
        g.mrect(x, 28, x, 30, "#")
    g.mrect(2, 3, 14, 6, "#")
    g.mrect(2, 6, 14, 6, "%")
    g.mrect(20, 4, 30, 5, "#")
    g.mrect(20, 5, 30, 5, "%")
    g.rect(38, 5, 51, 7, "#")
    g.rect(38, 7, 51, 7, "%")
    # Low ceilings over the side ledges.
    g.mrect(2, 13, 4, 13, "#")
    g.mrect(14, 9, 19, 9, "=")
    g.mrect(6, 12, 12, 12, "#")
    g.mrect(14, 15, 22, 15, "=")
    g.mrect(26, 18, 34, 18, "#")
    g.mrect(26, 12, 32, 12, "=")
    g.rect(38, 10, 51, 10, "=")
    g.rect(38, 21, 51, 21, "=")
    g.rect(41, 24, 48, 24, "=")
    for x, y in [(4, 7), (10, 7), (22, 6), (28, 6)]:
        g.mput(x, y, "S")
    for x, y in [(16, 10), (9, 13), (18, 16), (30, 19), (41, 8)]:
        g.mput(x, y, "W")
    g.put(44, 22, "I")
    g.mput(12, 7, "I")
    return g.to_json("lilac_caves", "Lilac Caves", "lilac")


def peach_pyramid():
    """Central stepped pyramid, spikes at its base."""
    g = Grid(90, 36)
    g.mground(2, 16, 3)
    g.mground(22, 30, 3)
    g.ground(31, 58, 3)
    for i, top in enumerate([5, 7, 9, 11, 13, 15]):
        x0 = 33 + 2 * i
        g.rect(x0, top - 2, g.mx(x0), top - 1, "#")
        g.rect(x0, top - 1, g.mx(x0), top - 1, "%")
    g.mrect(31, 3, 32, 3, "^")
    g.mrect(8, 5, 16, 5, "=")
    g.mrect(18, 8, 26, 8, "#")
    g.mrect(10, 11, 18, 11, "=")
    g.mrect(24, 14, 32, 14, "=")
    g.mrect(34, 17, 40, 17, "=")
    for x, y in [(5, 3), (13, 3), (25, 3), (29, 3)]:
        g.mput(x, y, "S")
    for x, y in [(12, 6), (22, 9), (14, 12), (28, 15), (38, 9)]:
        g.mput(x, y, "W")
    g.put(44, 15, "I")
    g.mput(9, 3, "I")
    return g.to_json("peach_pyramid", "Peach Pyramid", "peach")


def sky_lifts():
    """Vertical moving lifts, high verticality."""
    g = Grid(84, 44)
    g.mground(2, 16, 4)
    g.ground(32, 51, 4)
    g.mmover("lift", 20, 3, 3, [[0, 0], [0, 13]], 2.5, 1.0)
    g.mrect(4, 7, 10, 7, "#")
    g.mrect(8, 10, 15, 10, "=")
    g.mrect(24, 15, 30, 15, "#")
    g.mrect(26, 18, 34, 18, "=")
    g.rect(36, 21, 47, 21, "#")
    g.mmover("lift2", 12, 13, 3, [[0, 0], [0, 12]], 2.0, 1.2)
    g.mrect(15, 24, 22, 24, "=")
    g.mrect(24, 27, 31, 27, "=")
    g.mrect(32, 30, 38, 30, "=")
    g.rect(39, 33, 44, 33, "=")
    for x, y in [(4, 4), (13, 4), (34, 4), (38, 4)]:
        g.mput(x, y, "S")
    for x, y in [(7, 8), (11, 11), (27, 16), (30, 19), (18, 25)]:
        g.mput(x, y, "W")
    g.put(41, 22, "I")
    g.put(42, 34, "I")
    g.put(41, 4, "I")
    return g.to_json("sky_lifts", "Sky Lifts", "sky")


def bounce_garden():
    """Jump pads, hedges, pits."""
    g = Grid(92, 36)
    g.mground(2, 20, 4)
    g.ground(28, 63, 4)
    g.mrect(9, 4, 10, 5, "%")
    g.mrect(40, 4, 41, 5, "%")
    g.mput(19, 4, "J")
    g.mput(34, 4, "J")
    g.mrect(30, 9, 38, 9, "=")
    g.mput(36, 10, "J")
    g.mrect(5, 6, 11, 6, "=")
    g.mrect(14, 14, 24, 14, "#")
    g.mrect(14, 14, 24, 14, "%")
    g.rect(42, 17, 49, 17, "=")
    g.mrect(2, 9, 6, 9, "=")
    for x, y in [(4, 4), (13, 4), (31, 4), (38, 4)]:
        g.mput(x, y, "S")
    for x, y in [(8, 7), (22, 15), (32, 10), (44, 18), (15, 4)]:
        g.mput(x, y, "W")
    g.put(45, 4, "I")
    g.mput(19, 15, "I")
    return g.to_json("bounce_garden", "Bounce Garden", "garden")


def sorbet_arena():
    """Symmetric arena using all hazards lightly."""
    g = Grid(90, 38)
    g.mground(3, 41, 4)
    g.ground(42, 47, 2, cap="")
    g.rect(42, 2, 47, 2, "L")
    g.mput(20, 4, "^")
    g.mput(21, 4, "^")
    for x, y in [(12, 4), (12, 5), (30, 4)]:
        g.mput(x, y, "C")
    g.mput(8, 4, "J")
    g.mrect(4, 10, 12, 10, "=")
    g.mrect(24, 7, 32, 7, "=")
    g.mrect(16, 10, 22, 10, "#")
    g.mrect(20, 13, 26, 13, "=")
    g.mover("mid", 38, 13, 4, [[0, 0], [10, 0]], 2.0, 1.0)
    g.mrect(28, 16, 34, 16, "#")
    g.rect(40, 19, 49, 19, "=")
    for x, y in [(5, 4), (15, 4), (26, 4), (35, 4)]:
        g.mput(x, y, "S")
    for x, y in [(8, 11), (28, 8), (18, 11), (23, 14), (30, 17)]:
        g.mput(x, y, "W")
    g.put(44, 20, "I")
    g.mput(38, 4, "I")
    return g.to_json("sorbet_arena", "Sorbet Arena", "sorbet")


MAPS = [candy_plains, mint_towers, lava_lagoon, cloud_hop, crate_yard, spike_factory,
        bubblegum_bridges, lilac_caves, peach_pyramid, sky_lifts, bounce_garden, sorbet_arena]


# ------------------------------------------------------------------ reachability
FLOOR = set("#%=CM")
SOLID = set("#%CM")


def surfaces(data):
    """Standable segments: (y, x0, x1, is_pad) where cell (x, y) is open and
    (x, y-1) is floor (y measured from the bottom). Movers count along their
    whole path."""
    rows = data["layout"]
    h, w = len(rows), len(rows[0])

    def cell(x, y):
        if 0 <= x < w and 0 <= y < h:
            return rows[h - 1 - y][x]
        return "."

    floor = {}
    for y in range(h):
        for x in range(w):
            if cell(x, y) in FLOOR:
                floor[(x, y)] = cell(x, y)
    for m in data.get("movers", []):
        pts = m["path"]
        for c in m["cells"]:
            cx, cy = c[0], h - 1 - c[1]
            for dx, dy in pts:
                floor[(cx + dx, cy - dy)] = "M"
            # interpolate straight segments
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                steps = max(abs(bx - ax), abs(by - ay))
                for s in range(steps + 1):
                    fx = ax + (bx - ax) * s // max(steps, 1)
                    fy = ay + (by - ay) * s // max(steps, 1)
                    floor[(cx + fx, cy - fy)] = "M"
    stand = set()
    for (x, y), _ in floor.items():
        above = cell(x, y + 1)
        if above in ".SWIJ^" and above != "^":
            stand.add((x, y + 1))
    return stand, cell


def reachable_check(data):
    stand, cell = surfaces(data)
    # Group standable cells into horizontal segments.
    segs = []
    seen = set()
    for (x, y) in sorted(stand, key=lambda p: (p[1], p[0])):
        if (x, y) in seen:
            continue
        x1 = x
        while (x1 + 1, y) in stand:
            x1 += 1
        for xx in range(x, x1 + 1):
            seen.add((xx, y))
        pad = any(cell(xx, y) == "J" for xx in range(x, x1 + 1))
        segs.append((y, x, x1, pad))

    def can(a, b):
        ya, ax0, ax1, apad = a
        yb, bx0, bx1, _ = b
        gap = max(0, bx0 - ax1 - 1, ax0 - bx1 - 1)
        rise = yb - ya
        limit_rise = PAD_RISE if apad else MAX_RISE
        if rise > limit_rise:
            return False
        if rise > 0:
            return gap <= (MAX_GAP_LEVEL if apad else MAX_GAP_RISE)
        return gap <= MAX_GAP_LEVEL + (-rise)

    start = None
    targets = []
    rows = data["layout"]
    h = len(rows)
    for r, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in "SWI":
                targets.append((x, h - 1 - r, ch))
    s0 = next(t for t in targets if t[2] == "S")
    for i, sg in enumerate(segs):
        if sg[0] == s0[1] and sg[1] <= s0[0] <= sg[2]:
            start = i
    if start is None:
        return [f"start spawn {s0} not on a surface"]
    reach = {start}
    q = deque([start])
    while q:
        a = q.popleft()
        for j, b in enumerate(segs):
            if j not in reach and can(segs[a], b):
                reach.add(j)
                q.append(j)
    problems = []
    for (x, y, ch) in targets:
        ok = any(sg[0] == y and sg[1] <= x <= sg[2] for j, sg in enumerate(segs) if j in reach)
        if not ok:
            # Points in the air are fine if a reachable surface is directly below.
            below = any(sg[1] <= x <= sg[2] and 0 < y - sg[0] <= 6 for j, sg in enumerate(segs) if j in reach)
            if not below:
                problems.append(f"{ch} at ({x},{y}) unreachable")
    return problems


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    show = "--print" in sys.argv
    bad = False
    for fn in MAPS:
        data = fn()
        path = OUT / f"{data['id']}.json"
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        problems = reachable_check(data)
        status = "ok" if not problems else "REACH: " + "; ".join(problems)
        bad = bad or bool(problems)
        print(f"wrote {path.name:24s} {len(data['layout'][0])}x{len(data['layout'])} {status}")
        if show:
            print("\n".join(data["layout"]))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
