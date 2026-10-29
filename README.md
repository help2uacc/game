# Block Brawl

Small, cute, blocky 2.5D side-view party shooter for Android, for 2–8 friends
on the same local network (Wi-Fi or phone hotspot). See `PRD.md` for the full
specification.

## Engine

- **Godot 4.7.2 stable** (`4.7.2.stable.official.ed1daf0bf`), official build
  from <https://github.com/godotengine/godot/releases/tag/4.7.2-stable>.
- GDScript only, Compatibility renderer, no addons.

## Headless checks

```bash
tools/check.sh
```

runs `godot --headless --import`, `godot --headless -s tests/run_tests.gd`
and `python3 tools/validate_maps.py`.
