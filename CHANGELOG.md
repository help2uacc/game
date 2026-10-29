# Changelog

## M0 — Project setup
- Godot 4.7.2 project (Compatibility renderer, 1920×1080 canvas_items/expand, landscape, 60 FPS, 60 Hz physics).
- Android export preset (`com.blockbrawl.game`, arm64-v8a + armeabi-v7a, permissions, immersive, icons; no secrets).
- Global palette, flat unlit block shader (+ alpha variant, sky gradient, blob shadow).
- Autoload skeletons, pure rule classes (damage, kill credit, winners, colours, map rotation, discovery protocol, map data).
- Headless test runner (`tests/run_tests.gd`) with unit tests; `tools/check.sh`; `tools/validate_maps.py`.
- Branding generator (`tools/gen_branding.py`), GitHub Actions APK workflow.
