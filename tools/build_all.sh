#!/usr/bin/env bash
# Regenerates every generated asset (deterministic), then re-imports.
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
python3 tools/gen_branding.py
python3 tools/gen_icons.py
python3 tools/gen_sfx.py
python3 tools/gen_music.py
"$GODOT" --headless --import > /dev/null 2>&1 || true
"$GODOT" --headless -s tools/build_assets.gd
"$GODOT" --headless --import > /dev/null 2>&1
