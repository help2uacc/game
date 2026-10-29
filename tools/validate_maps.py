#!/usr/bin/env python3
"""Validate every map JSON in data/maps (PRD §10.1). Exit 1 on any error.

Checks: consistent row length, size limits, legend characters only, spawn
counts, every S has floor within 6 cells below, movers reference M cells.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP_DIR = ROOT / "data" / "maps"
THEME_DIR = ROOT / "data" / "themes"

LEGEND = set(".#%=L^CJMSWI")
FLOOR = set("#%=CM")
MIN_W, MAX_W = 70, 100
MIN_H, MAX_H = 30, 45
MIN_S, MIN_W_POINTS, MIN_I = 8, 10, 3
SPAWN_DROP = 6
EXPECTED_MAPS = 12


def validate(path: Path) -> list:
    errors = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        return [f"JSON parse error: {exc}"]
    if not isinstance(data, dict):
        return ["root must be an object"]
    for key in ("id", "name", "theme", "layout"):
        if key not in data:
            errors.append(f"missing {key}")
    if errors:
        return errors
    if data["id"] != path.stem:
        errors.append(f"id '{data['id']}' does not match file name")
    if not (THEME_DIR / f"{data['theme']}.tres").exists():
        errors.append(f"theme '{data['theme']}' has no data/themes/{data['theme']}.tres")
    rows = data["layout"]
    if not rows:
        return errors + ["empty layout"]
    h = len(rows)
    w = len(rows[0])
    for r, row in enumerate(rows):
        if len(row) != w:
            errors.append(f"row {r} has length {len(row)}, expected {w}")
    if not MIN_W <= w <= MAX_W:
        errors.append(f"width {w} outside {MIN_W}-{MAX_W}")
    if not MIN_H <= h <= MAX_H:
        errors.append(f"height {h} outside {MIN_H}-{MAX_H}")

    def cell(x, y):
        if 0 <= y < h and 0 <= x < len(rows[y]):
            return rows[y][x]
        return "."

    counts = {}
    for r, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch not in LEGEND:
                errors.append(f"invalid char '{ch}' at ({x},{r})")
            counts[ch] = counts.get(ch, 0) + 1
    if counts.get("S", 0) < MIN_S:
        errors.append(f"needs >= {MIN_S} S, has {counts.get('S', 0)}")
    if counts.get("W", 0) < MIN_W_POINTS:
        errors.append(f"needs >= {MIN_W_POINTS} W, has {counts.get('W', 0)}")
    if counts.get("I", 0) < MIN_I:
        errors.append(f"needs >= {MIN_I} I, has {counts.get('I', 0)}")
    for r, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "S" and not any(cell(x, r + dy) in FLOOR for dy in range(1, SPAWN_DROP + 1)):
                errors.append(f"spawn at ({x},{r}) has no floor within {SPAWN_DROP} cells")
    referenced = set()
    for m in data.get("movers", []):
        mid = m.get("id", "?")
        cells = m.get("cells", [])
        if not cells:
            errors.append(f"mover {mid} has no cells")
        for c in cells:
            if cell(c[0], c[1]) != "M":
                errors.append(f"mover {mid} cell ({c[0]},{c[1]}) is not an M cell")
            referenced.add((c[0], c[1]))
        if len(m.get("path", [])) < 2:
            errors.append(f"mover {mid} needs a path with >= 2 points")
        if float(m.get("speed", 0)) <= 0:
            errors.append(f"mover {mid} needs speed > 0")
    for r, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "M" and (x, r) not in referenced:
                errors.append(f"M cell ({x},{r}) not referenced by any mover")
    return errors


def main() -> int:
    paths = sorted(MAP_DIR.glob("*.json"))
    failed = False
    for p in paths:
        errs = validate(p)
        if errs:
            failed = True
            print(f"FAIL {p.name}")
            for e in errs:
                print(f"   - {e}")
        else:
            print(f"OK   {p.name}")
    expected = int(sys.argv[1]) if len(sys.argv) > 1 else EXPECTED_MAPS
    if len(paths) < expected:
        print(f"FAIL expected at least {expected} maps, found {len(paths)}")
        failed = True
    print("maps:", len(paths), "->", "FAILED" if failed else "all valid")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
