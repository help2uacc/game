# Block Brawl

A small, cute, blocky 2.5D side-view party shooter for Android. 2–8 friends
on the same local network (Wi-Fi or a phone hotspot) fight over 4–99 rounds
on 12 hand-authored maps. Everything (models, icons, branding, SFX, music)
is generated in this repository. The full specification is in `PRD.md`.

## Engine

| | |
|---|---|
| Engine | **Godot 4.7.2 stable**, `4.7.2.stable.official.ed1daf0bf` |
| Download | <https://github.com/godotengine/godot/releases/tag/4.7.2-stable> (`Godot_v4.7.2-stable_linux.x86_64.zip`, or the Windows/macOS editor of the same version) |
| Export templates | `Godot_v4.7.2-stable_export_templates.tpz` from the same release |
| Language / renderer | GDScript (static typing everywhere), Compatibility renderer, no addons |

`project.godot` declares `config/features = ["4.7", "GL Compatibility"]`.

## Open and run in the editor

1. Install the Godot 4.7.2 editor (above).
2. *Import* → select this folder's `project.godot` → *Import & Edit*.
3. Press **F5** (Run Project). The main menu opens.
   - First launch asks for a player name.
   - **SANDBOX (debug)** (debug builds only) opens a single-player
     playground with two training dummies on Candy Plains
     (`scenes/main/sandbox.tscn` can also be run directly with **F6**).

Touch: left joystick moves — **push up to jump** (again in the air for a
double jump), hold down to drop through a one-way platform; Attack (drag to
aim), Pick Up and Throw on the right. Dying in the sandbox restarts it.

Desktop debug controls: **A/D** move, **S** down (hold to drop through a
one-way platform), **Space** jump, **J** attack, **K** pick up,
**L** throw, **mouse** aims, **Esc** menu/back, **F3** debug overlay (FPS, draw calls, ping,
snapshot size). Mouse clicks emulate touches, so the on-screen joystick and
buttons can be tried with the mouse (on phones: drag from the Attack button
to aim).

## Test multiplayer with several editor instances

1. *Debug → Customize Run Instances…* → enable *Enable Multiple Instances*,
   set the count to 2–4 → OK.
2. Press **F5**: several game windows open.
3. In one window press **HOST GAME**.
4. In the others press **JOIN GAME**. In debug builds the host on the same
   machine (127.0.0.1) appears in the list within ~2 s; you can also type
   `127.0.0.1` in the manual IP field and press JOIN.
5. Clients press **READY UP**; the host presses **START**.

Automated variant (headless, no window): `tools/net_smoke_test.sh 2 90 4`
starts one host and two bot clients on localhost that play a short match;
`DROP=25 tools/net_smoke_test.sh` also simulates a connection loss and
reconnect. (Bot input exists only in debug builds behind command-line flags;
it is a test harness, not a gameplay feature.)

## Install the APK on Android

1. Open the latest GitHub Release of this repository (tag `v1.x.x`) on the
   phone and download `block_brawl.apk`.
2. Allow your browser / file manager to *install unknown apps* when Android
   asks.
3. Open the APK and install it. The build is debug-signed; if an older build
   signed with a different key is installed, uninstall it first.
4. Requirements: Android 7.0 (API 24) or newer, arm64-v8a or armeabi-v7a.

Playing: one phone presses **HOST GAME** (the lobby shows its IP address).
Other phones on the same Wi-Fi — or connected to a phone hotspot — press
**JOIN GAME** and pick the game from the list, or type the host IP.

## Build a new APK (GitHub Actions)

The workflow `.github/workflows/android.yml` builds a debug-signed APK on
`ubuntu-latest` (Android SDK preinstalled, JDK 17): it downloads Godot 4.7.2
and its export templates, configures the editor settings with
`$ANDROID_SDK_ROOT`, generates a throw-away debug keystore with `keytool`,
runs the headless import + tests, exports `build/block_brawl.apk` and
uploads it as a workflow artifact.

- **New release:** push a tag starting with `v`, e.g.

  ```bash
  git tag v1.0.1
  ```

  ```bash
  git push origin v1.0.1
  ```

  The run then creates a GitHub Release for that tag with
  `block_brawl.apk` attached.
- **Manual build:** *Actions → Android APK → Run workflow* (the APK is
  available as the `block_brawl-apk` artifact of the run). Fill in
  *release_tag* (e.g. `v1.0.1`) to also create that tag and a GitHub
  Release with the APK.

### Release keystore (optional)

The preset contains no secrets. To sign a release build yourself:

```bash
keytool -genkeypair -v -keystore release.keystore -alias blockbrawl -keyalg RSA -keysize 2048 -validity 10000
```

then export with the environment variables `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
`GODOT_ANDROID_KEYSTORE_RELEASE_USER` and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`
set, using `godot --headless --export-release "Android" build/block_brawl.apk`.
Keep the keystore out of the repository (`*.keystore` is git-ignored).

## Checks

```bash
tools/check.sh
```

runs everything the PRD asks for (§14.1) and fails on any error or warning:

- `godot --headless --import`
- `godot --headless -s tests/run_tests.gd` (unit + physics/combat
  integration tests; exit code 0 = pass)
- a GDScript lint pass that turns Godot's default warnings into errors
- `python3 tools/validate_maps.py` (all 12 maps)

## Generated assets

All assets are created by scripts in `tools/` (Python 3 standard library +
NumPy + Pillow, and Godot itself) and committed together with their outputs:

| Script | Output |
|---|---|
| `tools/gen_branding.py` | `assets/branding/*.png` (icon, adaptive icon, splash, logo) |
| `tools/gen_icons.py` | `assets/ui/icons/*.svg` |
| `tools/gen_sfx.py` (+ `tools/synth.py`) | `assets/audio/sfx/*.wav` (40 sounds, 44.1 kHz) |
| `tools/gen_music.py` | `assets/audio/music/*.wav` (menu, 3 battle loops, results jingle, 22.05 kHz) |
| `tools/build_assets.gd` | materials, weapon/item/theme data, box-built scenes, `assets/blocks/mesh_library.tres`, `ui/theme/block_brawl_theme.tres` |
| `tools/author_maps.py` | `data/maps/*.json` (with a reachability check) |

`tools/build_all.sh` regenerates everything. Visual previews:
`tools/preview/shot.sh` (screenshots via Xvfb) and
`tools/preview/perf.gd` (draw calls per map with 8 players).

## Project layout

See PRD §13. Highlights: `scripts/autoload/` (Settings, AudioManager,
GameState, NetManager, LanDiscovery, MatchManager, SceneRouter),
`scripts/gameplay/` (World simulation, Player, GameMap, hazards),
`scripts/net/` (discovery protocol, snapshots), `scripts/ui/` (screens,
HUD, controls), `tests/`.

Status, acceptance checklist and resume notes: `PROGRESS.md`. Decisions on
PRD gaps: `OPEN_QUESTIONS.md`. History: `CHANGELOG.md`.
