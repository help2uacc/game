# Progress

Resume here: read this file and `CHANGELOG.md`, then continue with the first
unchecked item. Run `tools/check.sh` after every change (import, tests,
warnings-as-errors lint, map validation).

## Milestones (PRD §16)
- [x] M0 Project setup
- [x] M1 Assets
- [x] M2 Local sandbox
- [x] M3 Combat
- [x] M4 Networking
- [x] M5 Match flow
- [x] M6 UI & polish
- [x] M7 Android & performance

## Current state
All milestones are implemented, pushed and released as v1.0.0. Remaining:
the manual phone tests below.

Verified locally (this environment):
- `tools/check.sh`: headless import clean, 71 tests pass, lint clean, 12 maps valid.
- `tools/net_smoke_test.sh`: host + 2–4 bot clients play multi-round matches on localhost, including a simulated connection loss + automatic reconnect.
- `tools/preview/perf.gd` (8 players, High quality, 1920×1080): ≤ 85 draw calls, ≤ 14 k primitives on every map (budget 150 / 100 k).
- Local Android export with the official 4.7.2 templates and a stubbed SDK: the APK packages fine (59.3 MB, both ABIs, permissions + package name present in the manifest). Real signing happens in CI with the runner's Android SDK.

## Release status
- Released: <https://github.com/help2uacc/game/releases/tag/v1.0.0> with `block_brawl.apk` (59.3 MB, debug-signed), built by `.github/workflows/android.yml` run 40895761621.
- Note: pushing tags from the cloud session is blocked by its git proxy, so the tag was created by the workflow (manual run with `release_tag=v1.0.0`). Pushing a `v*` tag from a normal machine also works.

## Acceptance criteria (PRD §15)

PRD §15 lists 14 numbered criteria.

| # | Criterion | Status |
|---|---|---|
| 1 | APK installs/launches on Android 7+, landscape, fullscreen, 60 FPS with 8 players on Medium | **Needs manual test** (device). Configured: min SDK 24, `sensor_landscape`, immersive, 60 FPS cap, Compatibility renderer; draw-call/primitive budget verified on desktop. |
| 2 | Host on one phone; others on same Wi-Fi or hotspot see it in Join list within 4 s; manual IP join works | **Needs manual test** (Wi-Fi/hotspot). Discovery = broadcast + /24 sweep every 2 s, verified on localhost; manual IP join verified by the smoke test. |
| 3 | Lobby 2–8 players, unique colours, name editing, ready toggles, rounds 4–99 (default 12), START conditions | [x] Implemented; unit tests for colours/START/rounds clamp; smoke test joins + readies. |
| 4 | Joining refused during a match except reconnecting players; reconnect within 60 s restores name/colour/kills and spectates until next round | [x] Implemented; smoke test with simulated drop + reconnect. Phone test still recommended (steps below). |
| 5 | Host leaving returns all clients to main menu with a message | [x] Implemented ("Host left the game" via RPC; on app close; after timeout). Phone test recommended. |
| 6 | Each round uses a different map; 12 distinct maps exist and validate | [x] 12 maps, `validate_maps.py` + GDScript tests; rotation tests (no immediate repeat). |
| 7 | Round ends at ≤1 alive or 300 s; round winner/DRAW; match winner by total kills with DRAW | [x] Rules unit tests + smoke test logs. |
| 8 | 6 weapons, punch, throw, pickup button, drop-on-swap, ammo removal, 30 s despawn, health/armor; auto-aim per §7.2 | [x] 19 combat integration tests. |
| 9 | Falling off, lava, spikes, crates, jump pads, moving platforms; environmental kill credit | [x] Integration tests (lava, spikes, pads, crates, fall, credit); movers in maps. |
| 10 | Double jump, one-way drop-through, knockback | [x] Physics integration tests. |
| 11 | Dead players can spectate and cycle living players | [x] Implemented (arrows + swipe); verify on phone (steps below). |
| 12 | All §9 screens exist; settings persist; every HUD element toggleable | [x] Screens: splash, main menu, host/lobby, join, HUD, round results, match results, settings, overlays/toasts. |
| 13 | Flat shader + palette; all assets generated in-repo | [x] `tools/` generators, outputs committed; no external assets. |
| 14 | Headless import and test suite pass with zero errors | [x] `tools/check.sh` (also runs in the workflow before export). |

### Manual test steps (phones)

Prepare: install `block_brawl.apk` from the GitHub Release on 2+ phones
(ideally 8 for criterion 1).

1. **Performance (criterion 1):** Settings → Graphics = Medium, Settings → HUD → FPS counter on. Host on one phone, join with the others (8 total if possible), start a match. Play 2–3 rounds; the FPS counter (top-right) should stay at ~60. Debug builds: a 4-finger tap shows the debug overlay (FPS, draw calls, ping, snapshot size).
2. **Discovery on Wi-Fi (criterion 2):** connect all phones to the same Wi-Fi. Phone A: HOST GAME. Phone B: JOIN GAME → the game "<name>'s game" must appear within 4 s. Tap it → lobby.
3. **Discovery on hotspot (criterion 2):** Phone A enables its mobile hotspot; Phone B connects to it. Repeat step 2 with A hosting, then with B hosting (A joins).
4. **Manual IP (criterion 2):** on the Join screen type the IP shown under the lobby title on the host → JOIN.
5. **Lobby (criterion 3):** change colours (taken ones show the owner's name and can't be picked), edit names (updates live on all phones), toggle READY; START stays disabled until ≥ 2 players and all clients are ready; rounds stepper 4–99 (long-press repeats).
6. **Reconnect (criterion 4):** during a round, turn Wi-Fi off on a client for ~10 s, then on. The client shows "Reconnecting… (Xs)", rejoins, spectates and plays from the next round with the same name/colour/kills. Also: kill the app on a client, relaunch within 60 s → main menu shows REJOIN.
7. **Join refused (criterion 4):** with a match running, a new phone sees the game as IN MATCH (greyed) and cannot join.
8. **Host leaves (criterion 5):** host presses Menu → Leave → all clients return to the main menu with "Host left the game". Repeat by closing the host app.
9. **Spectate (criterion 11):** die early in a round; the camera follows a living player; ◀ ▶ (or swipe) cycles players; HUD shows "SPECTATING: name".
