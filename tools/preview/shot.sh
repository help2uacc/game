#!/usr/bin/env bash
# tools/preview/shot.sh <out.png> <frames> [user args...]
out="$1"; frames="$2"; shift 2
cd "$(dirname "$0")/../.."
timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --rendering-driver opengl3 --resolution 1280x720 \
  -s tools/preview/screenshot.gd -- --out="res://build/$out" --frames="$frames" "$@" 2>&1 | grep -E "SCRIPT ERROR|saved" | head -20
