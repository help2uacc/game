# PRD — Block Brawl

> **Status:** v1.0 — ready for implementation
> **Owner:** Joe
> **Implementer:** Claude Code (cloud), working against the project GitHub repository
> **Platform:** Android only · Landscape · Local network multiplayer (Wi-Fi / Hotspot)
> **Engine:** Godot 4.7.x stable (latest patch at project start) · GDScript · Compatibility renderer

---

## 0. How to use this document

- This PRD is the **single source of truth**. If something is not specified here, the implementer must **not invent gameplay behaviour**; stop and ask the owner (open a GitHub issue / leave a `TODO(PRD):` note and continue with the rest).
- Section 17 lists every value that was **delegated to Claude** by the owner ("you decide"). Those values are final defaults but are intentionally collected in one place for easy tuning.
- All numbers are in **metres (m)**, **seconds (s)** and **HP** unless stated otherwise. 1 world unit = 1 m.
- Everything in this document is **in scope for v1**. There is no "later" phase except the items listed in Section 18 (Out of scope).

---

## 1. Product summary

**Block Brawl** is a small, cute, blocky **2.5D side-view party shooter** for Android, played by 2–8 friends on the same local network. One phone **hosts** a match; others **find** it automatically (or by typing the host IP) and join a lobby. Each player is a **blocky stickman** in a unique pastel colour.

A match is a series of **rounds** (default **12**, host can set **4–99**). Every round takes place on a **different map**. Weapons and items **spawn randomly** on the ground during the round; players **pick them up with a button** and fight. Each player has **one life per round**. The player with the **most total kills** across all rounds wins the match.

**Reference feel:** *Stick Fight: The Game* (side view, platforms, falling off the map kills you, chaotic weapon pickups), but with a clean, flat, pastel, blocky art style and touch controls.

### 1.1 Goals
1. Friends in the same room can start a match in under 30 seconds.
2. Stable **60 FPS** on a mid-range Android phone with 8 players.
3. Clean, minimal, cute look; every asset is made by Claude (no third-party art, no external asset downloads).
4. Simple touch controls: one joystick + a few buttons, auto-aim.

### 1.2 Non-goals
- No internet play, no accounts, no servers, no ads, no in-app purchases, no analytics, no stored statistics.
- No bots / AI players.
- No chat, no emotes.

---

## 2. Technical foundation

| Topic | Decision |
|---|---|
| Engine | Godot **4.7.x stable**, latest patch release at project start. Record the exact version in `README.md` and keep `config/features` in `project.godot` consistent. Do not use dev/beta builds. |
| Language | **GDScript** only (best Android support, smallest APK, no .NET runtime). Use static typing everywhere (`var x: int`, typed arrays, `-> void`). |
| Renderer | **Compatibility** (OpenGL ES 3 / WebGL 2 class). Chosen for widest Android support and best performance with flat, unlit visuals. |
| Target | **Android only.** arm64-v8a + armeabi-v7a. Min SDK = the minimum supported by the Godot 4.7 Android template (API 24 / Android 7.0). |
| Orientation | **Landscape only** (`sensor_landscape`). |
| Frame rate | Target **60 FPS**. `application/run/max_fps = 60`, V-Sync enabled. Physics tick **60 Hz**. |
| Base resolution | Design viewport **1920×1080**, stretch mode `canvas_items`, aspect `expand` (supports 16:9 to 21:9 phones; UI anchored, safe-area aware for notches). |
| Fullscreen | Immersive mode on, keep screen on while in a match. |
| Desktop | The project must **run in the Godot editor on desktop** for development (keyboard debug controls, multiple instances). No desktop export is shipped. |

### 2.1 Android export preset
- Package name: `com.blockbrawl.game`
- App name: `Block Brawl`
- Version: `1.0.0` (versionCode 1)
- Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `VIBRATE`
- Signing: debug keystore is acceptable (personal build). Document in README how to generate a release keystore if wanted.
- Icons: launcher icon 192×192 PNG + adaptive icon foreground/background 432×432 PNG (generated, see §11.6).
- Boot splash: generated PNG (see §11.6), background colour = palette `bg_sky`.

---

## 3. Core game loop

```
Main Menu ──► Host Game ──► Lobby ──(host presses START)──► Round 1 … Round N ──► Match Results ──► Lobby / Main Menu
          └─► Join Game ──► (server list / manual IP) ──► Lobby
```

Per round:
```
Load map (all clients) ─► 3 s countdown (players frozen) ─► FIGHT (max 300 s) ─► round end ─► Round Results (6 s) ─► next round
```

---

## 4. Match & round rules

### 4.1 Match
- **Rounds per match:** default **12**. Host can change it in the lobby to any integer from **4 to 99**.
- **Players:** minimum **2**, maximum **8** (host included).
- **Winner of the match:** the player(s) with the **highest total kills** summed over all rounds.
- **Match tie:** if two or more players share the highest total, the Match Results screen shows **"DRAW"** and lists all tied players. No tiebreaker.
- After the final round's results, show **Match Results** (§9.8). From there the host can **return everyone to the Lobby** (same players, same colours, kills reset) or anyone can **Leave** to the main menu.

### 4.2 Round
- Each player has exactly **one life per round**. No respawn.
- **Round timer:** **300 s**.
- **A round ends immediately when either:**
  1. **≤ 1 player is alive**, or
  2. the timer reaches **0**.
- **Round winner:** the player with the **most kills in that round**.
- **Round tie:** if several players share the most kills in the round (including everyone on 0), the Round Results screen shows **"DRAW"** and lists the tied players.
- Round wins are displayed but **do not** decide the match; only total kills do.

### 4.3 Kill credit
- A kill is credited to the player who dealt the **lethal damage**.
- **Environmental deaths** (falling off the map, lava, spikes, explosions from hazards): the kill is credited to the **last enemy player who damaged the victim within the previous 5.0 s**. If nobody damaged the victim in that window, **no one** gets the kill.
- Damaging yourself (e.g. own rocket splash) never credits a kill to yourself. If you die from your own damage, the 5 s last-enemy-attacker rule still applies; otherwise no one gets the kill.
- There are **no negative points**.

### 4.4 Dead players
- A dead player enters **Spectate mode** until the round ends: the camera follows a living player; **tap the left/right arrows** (or swipe) to cycle between living players. The HUD shows "SPECTATING: <name>".

### 4.5 Map rotation
- The game ships **12 maps** (§10).
- At match start the server shuffles the 12 maps into a queue. Each round takes the next map. When the queue is exhausted (rounds > 12) it is reshuffled, ensuring the first map of the new queue ≠ the last map played.

---

## 5. Networking

### 5.1 Topology
- **Local network only**: same Wi-Fi network, or one phone acts as a **mobile Hotspot** and others connect to it (the host may or may not be the hotspot phone).
- **Host-authoritative**: the host phone runs the authoritative simulation **and** plays as a normal player. Clients send **inputs only**; the host simulates movement, combat, spawning, scoring and sends state back.
- Transport: Godot high-level multiplayer with **`ENetMultiplayerPeer`**.
- **Game port:** UDP `47820`. **Discovery port:** UDP `47821`.
- **Protocol version:** integer constant `NET_PROTOCOL_VERSION = 1`. Clients with a different version are rejected with message "Version mismatch — update the app".

### 5.2 Finding a game (discovery)
Join screen shows a live-updating list of hosts **and** a manual IP field.

Discovery must work on Android without native plugins, therefore it uses **two methods in parallel**, refreshed every **2 s** while the Join screen is open:
1. **Broadcast probe:** client sends a `DISCOVER` packet to `255.255.255.255:47821` and to the subnet broadcast address of every local IPv4 interface.
2. **Unicast subnet sweep:** for each local private IPv4 interface (`10.x`, `172.16–31.x`, `192.168.x`) with a /24 network, the client sends a `DISCOVER` packet to every host `.1`–`.254` on port `47821` (this works on devices that filter broadcast packets without a multicast lock).

The host listens on `47821` (`PacketPeerUDP`, bound on all interfaces) and replies **unicast** to the sender.

Packets are UTF-8 JSON:
```json
// client -> host
{ "t": "BB_DISCOVER", "v": 1 }
// host -> client
{ "t": "BB_HOST", "v": 1, "name": "Joe's game", "players": 3, "max": 8,
  "state": "lobby", "port": 47820 }
```
- `name` = `"<host player name>'s game"`.
- `state` = `"lobby"` or `"in_match"`.
- Hosts not seen for **6 s** are removed from the list.
- List rows show: game name, `players/8`, state, host IP. Rows in `in_match` state are shown greyed with the label "IN MATCH" and can only be joined by a player who is reconnecting (§5.5).
- **Manual join:** text field accepting an IPv4 address (port fixed to 47820) + JOIN button. Validate format before connecting. Connection timeout **5 s** → error toast "Could not connect".

### 5.3 Who can join when
- **Lobby:** anyone can join while players < 8 and the host is in the lobby.
- **During a match:** new players **cannot** join. Only **reconnecting** players (§5.5) are accepted.
- Full lobby → reject with "Game is full".

### 5.4 Host leaves
- If the host disconnects, closes the app, or presses Leave, **the match/lobby ends for everyone**. Clients return to the Main Menu with the message "Host left the game".
- No host migration.

### 5.5 Reconnect (clients)
- On first connect each client generates a random **session token** (UUID v4 string) kept in memory and written to `user://session.cfg` together with the host IP and the time. The server maps token → player slot (name, colour, kills, round history).
- If a client loses connection during a match, the server keeps its slot for **60 s** (the **reconnect window**).
- The client automatically retries the last host every **2 s** for up to **60 s**, showing an overlay "Reconnecting… (Xs)" with a "Leave" button. The Join screen also lets the player re-select the host (shown as "IN MATCH") within the window; the token is sent on connect.
- If the app was killed and relaunched within the window, the Main Menu shows a **"REJOIN"** button (from `user://session.cfg`) that tries to reconnect.
- On successful reconnect the player keeps name, colour and all kills.
- **If the player disconnected while alive**, they are treated as **dead for that round** (normal kill-credit rule §4.3 applies, i.e. the last enemy attacker within 5 s gets the kill). On rejoin mid-round they enter **Spectate mode**; they play again from the next round.
- If the reconnect window expires, the slot is released: the player disappears from the active player list but their kills remain on the scoreboard (greyed name).
- Disconnecting during the **lobby** simply removes the player (no reconnect window needed).
- **Not enough players:** if, during a match, fewer than 2 players are connected (ignoring players inside their reconnect window), the server waits until all reconnect windows expire; if still < 2 connected, the match ends early and goes to Match Results.

### 5.6 Replication model
- **Inputs (client → host):** sent every physics frame (60 Hz), `unreliable_ordered` RPC, packed: `seq:int, move_x:float(-1..1), down:bool, jump_pressed:bool, jump_held:bool, attack_held:bool, pickup_pressed:bool, throw_pressed:bool`. Edge-triggered flags ("pressed") are latched until acknowledged in the next snapshot to avoid loss.
- **State (host → clients):** snapshots at **30 Hz** via `MultiplayerSynchronizer` (replication interval 1/30 s) or an equivalent packed RPC. Contains per player: position, velocity, facing, HP, armor, weapon id, ammo, animation state, alive flag; plus projectiles, pickups, moving platforms and crates.
- **Events (host → clients):** `reliable` RPCs for discrete events: shot fired (origin, end point, weapon id → tracer/VFX/SFX), hit, kill (killer, victim, cause → kill feed), pickup spawned/removed, crate destroyed, explosion, round state changes, scoreboard updates.
- **Spawning:** `MultiplayerSpawner` (server authority) for players, pickups, projectiles.
- **Client smoothing:** remote entities are rendered with a **100 ms interpolation buffer**. No client-side prediction in v1 (LAN latency is low); the local player is rendered from the latest snapshot with interpolation as well. The host player plays directly from the simulation.
- **Map load sync:** server sends `load_map(map_id)`; each client replies `map_ready`. Countdown starts when all connected clients are ready or after **10 s** timeout (late clients spectate that round).
- All randomness (spawns, map order) is generated **on the server only**.
- **Ping** is measured every 1 s (RPC round trip) and shown in HUD (optional element).

---

## 6. Player character

### 6.1 Look
A **blocky stickman**, cute and chunky, built only from boxes:
- **Head:** cube 0.5 m, with two small dark square **eyes** (0.08 m) on the front face — the eyes give the cute look and show facing direction.
- **Torso:** box 0.18 × 0.6 × 0.18 m.
- **Arms:** two boxes 0.12 × 0.45 × 0.12 m (pivot at shoulder).
- **Legs:** two boxes 0.14 × 0.55 × 0.14 m (pivot at hip).
- Total height ≈ **1.8 m**. Collision: `CapsuleShape3D` radius 0.3 m, height 1.8 m.
- The whole body is the **player's colour**; eyes are `ink` colour (§11.1). The held weapon is attached to the front hand.
- A **blob shadow** (soft dark transparent quad) is projected straight down onto the ground below the character (raycast), to help readability without real-time lights.
- **Name tag** above the head: player name in white with a dark outline, small, always facing camera. Local player's tag has a small ▼ marker.

### 6.2 Colours (player picks, unique per match)
8 pastel colours, slightly saturated so characters stand out from the lighter maps:

| ID | Name | Hex |
|---|---|---|
| 0 | Pink | `#FF8FB1` |
| 1 | Orange | `#FFB26B` |
| 2 | Yellow | `#FFE066` |
| 3 | Green | `#8FD694` |
| 4 | Teal | `#6FD3C8` |
| 5 | Blue | `#7FB7FF` |
| 6 | Purple | `#B49CFF` |
| 7 | Cocoa | `#C49A7A` |

- A joining player is auto-assigned the **first free** colour; they can change to any **free** colour in the lobby. Taken colours are shown locked with the owner's name. Two players can never share a colour (server validates).
- Only colour customisation; no hats/skins.

### 6.3 Animations (procedural / `AnimationPlayer` on box transforms, no skeleton)
`idle` (gentle bob), `run` (leg/arm swing), `jump`, `double_jump` (quick front flip of the whole body), `fall`, `land` (squash), `punch`, `shoot` (arm recoil, per weapon strength), `hold_weapon` (arm pose overlay), `throw`, `hit` (short flinch + white flash 0.08 s), `death` (character topples backwards, bounces once, fades out over 0.6 s and pops into small cube particles in the player colour).

### 6.4 Stats & movement
| Parameter | Value |
|---|---|
| Max HP | 100 |
| Max armor | 50 |
| Run speed | 7.0 m/s |
| Ground acceleration | 60 m/s² |
| Air acceleration | 35 m/s² |
| Gravity | 30 m/s² |
| Max fall speed | 25 m/s |
| Jump velocity | 11 m/s |
| Double-jump velocity | 10 m/s (one per airtime, resets on landing) |
| Coyote time | 0.10 s |
| Jump buffer | 0.10 s |
| Drop through one-way platform | hold joystick down + press Jump |
| Movement plane | X (horizontal) and Y (vertical) only; Z locked at 0 |

- Implementation: `CharacterBody3D` with Z axis locked.
- **Falling below the map's kill line** (map bottom − 10 m) = instant death.
- **Knockback:** each hit adds an impulse `knockback × direction` with an extra upward component of `0.3 × knockback`. Knockback decays with normal acceleration; while knockback speed > run speed, player input control is reduced to 30 %.

### 6.5 Damage
- Damage applies to **armor first**, the remainder to HP.
- Hit feedback: hit flash, small cube-particle burst, damage SFX, optional vibration (setting) for the local player when hit.
- **Invulnerability:** none, except 0.5 s after touching spikes (spikes only).

---

## 7. Combat

### 7.1 General rules
- A player holds **at most one weapon**.
- **Pickup** is done **with the Pick Up button** while overlapping a pickup (radius 1.0 m). If already holding a weapon, picking up a new one **drops** the current weapon at the player's position (with its remaining ammo).
- **Throw:** the Throw button throws the held weapon in the facing direction (speed 14 m/s, slight upward arc). A thrown weapon hitting an enemy deals **15 damage** and **knockback 6**, then falls to the ground as a normal pickup **keeping its remaining ammo**.
- **Out of ammo:** when a weapon's ammo reaches 0 it is **removed** (it disappears with a small poof; the player is unarmed again). Dropped/thrown weapons with ammo > 0 stay as pickups.
- **Unarmed:** the Attack button performs a **punch**.
- **Auto-fire:** holding Attack fires repeatedly at the weapon's fire rate.
- Weapons lying on the ground **despawn after 30 s** if not picked up (blink during the last 3 s).
- **Friendly fire:** not applicable (free-for-all).

### 7.2 Auto-aim
When Attack is pressed with a ranged weapon or grenade:
1. Candidate targets = living enemies within the weapon's **range** with a clear **line of sight** (raycast from the weapon muzzle to the target's chest against world geometry).
2. Choose the **nearest** candidate; on equal distance prefer one in the facing direction.
3. If a target exists: the character turns to face it and fires toward its chest (spread still applies).
4. If none: fire **horizontally in the facing direction**.
- The aim is computed **on the server** at fire time.
- For the **local player only**, a small target marker (pulsing corner brackets in the player's colour) is drawn around the currently auto-aimed enemy (client computes the same rule locally for display only).
- Punch is not auto-aimed; it hits in the facing direction.

### 7.3 Weapons
Six weapons. Hitscan weapons use a server raycast; clients draw a short-lived tracer line (0.06 s) and muzzle flash.

| Weapon | Type | Damage | Fire rate | Ammo | Range | Spread | Knockback | Notes |
|---|---|---|---|---|---|---|---|---|
| Pistol | Hitscan | 18 | 3 /s | 12 | 25 m | 2° | 2 | — |
| SMG | Hitscan | 9 | 10 /s | 40 | 18 m | 6° | 1 | — |
| Shotgun | Hitscan ×6 pellets | 9 per pellet | 1.2 /s | 6 | 10 m | 15° cone | 8 (total, if ≥1 pellet hits) | — |
| Sniper | Hitscan | 70 | 0.8 /s | 4 | 60 m | 0° | 10 | Piercing: no (stops at first hit) |
| Rocket Launcher | Projectile | 60 direct; splash 3.0 m radius, 60→20 linear falloff | 0.7 /s | 3 | 40 m (auto-aim) | 0° | 14 | Rocket speed 18 m/s, no gravity, explodes on contact or after 3 s. Self-damage 50 %. Destroys crates. |
| Grenades | Thrown projectile | 70 at centre, 3.5 m radius, linear falloff to 15 | 1 /s | 3 | 16 m (auto-aim) | — | 12 | Arc throw computed to land near target; bounces; 2.0 s fuse. Self-damage 50 %. Destroys crates. |
| *(Punch)* | Melee | 12 | cooldown 0.45 s | ∞ | 1.2 m | — | 5 | Unarmed only |

Weapon spawn weights: Pistol 25, SMG 20, Shotgun 20, Grenades 15, Sniper 12, Rocket Launcher 8.

Weapon data lives in `WeaponData` resources (`res://data/weapons/*.tres`) so values can be tuned without code changes.

### 7.4 Items (power-ups)
| Item | Effect | Look |
|---|---|---|
| Health Pack | +40 HP (capped at 100) | White cube with a pastel-red plus |
| Armor | +50 armor (capped at 50) | Pastel-blue cube with a shield-shaped notch |

- Items are picked up **automatically** on touch (they are not weapons, so no button needed). *(Pick Up button applies to weapons only.)*
- Item spawn weights: Health 60, Armor 40.

### 7.5 Spawning during a round
- Each map defines **player spawn points** (≥ 8), **weapon spawn points** (≥ 10) and **item spawn points** (≥ 3).
- Player spawn points are assigned randomly, one player per point.
- **At round start (end of countdown):** 3 weapons spawn at random free weapon points.
- **Then:** every **8 s** one weapon spawns at a random free weapon point, if fewer than **6** weapons are on the ground.
- **Items:** first item at **30 s**, then every **20 s**, if fewer than **2** items are on the ground.
- A pickup spawns with a short "pop" animation (scale 0 → 1.15 → 1.0, 0.25 s) and spawn SFX. Pickups bob and slowly rotate. A pickup point is "free" if no pickup is within 1.5 m.

---

## 8. Controls (touch)

Minimal, fixed layout, clean and semi-transparent (not customisable in v1, but joystick sensitivity is a setting).

| Control | Position | Behaviour |
|---|---|---|
| **Joystick** | Left half of the screen, **floating**: appears where the thumb touches. Radius 110 px (design res). | Horizontal axis → move. Pushing down (y > 0.6) + Jump → drop through one-way platform. |
| **Attack** | Right side, largest button (160 px) | Shoot (held = auto-fire) / punch when unarmed. Icon changes to the current weapon. |
| **Jump** | Right side, below-right of Attack (130 px) | Jump / double jump. |
| **Pick Up** | Right side, above Attack (100 px) | **Visible only** when overlapping a weapon pickup. |
| **Throw** | Right side, left of Attack (100 px) | **Visible only** when holding a weapon. |
| **Menu** (☰) | Top-left small button | Opens in-match overlay: Resume, Settings, Leave (confirm). The game is **not paused** (multiplayer). |
| **Spectate ◀ ▶** | Bottom centre, visible only when spectating | Cycle followed player. |

- Multi-touch: joystick and buttons must work simultaneously.
- Buttons: white rounded squares at 35 % opacity with a simple icon; pressed state 70 % opacity + scale 0.92.
- Android **Back** button = opens the in-match overlay (in match) or goes back one screen (menus).

**Debug keyboard controls (editor/desktop only):** A/D move, S down, Space jump, J attack, K pick up, L throw, Esc menu.

---

## 9. Screens & UI

Language: **English only**. UI style: flat pastel panels, large rounded corners (16 px), soft drop shadow, chunky bold text. Godot's default font is used, styled through a single `Theme` resource (`res://ui/theme/block_brawl_theme.tres`). Button press: scale 0.95 + click SFX. Screen transitions: 0.2 s fade.

### 9.1 Splash
Godot boot splash (generated image), then Main Menu.

### 9.2 Main Menu
- Animated background: a slowly scrolling pastel block landscape with a few idle stickmen in different colours.
- Game logo (blocky lettering built from boxes / generated texture).
- Buttons: **HOST GAME**, **JOIN GAME**, **SETTINGS**, **QUIT**.
- **REJOIN** button appears only when a valid session from `user://session.cfg` exists and is < 60 s old (§5.5).
- First launch: if no player name is set, show a name prompt (1–12 chars, letters/digits/space/`_`/`-`), default `Player` + 4 random digits.

### 9.3 Host Game
Pressing HOST creates the server immediately and opens the Lobby. If ports cannot be bound → error toast "Could not start host. Check your network."
Host screen shows the host's **local IP address(es)** so friends can type it manually.

### 9.4 Join Game
- Live host list (§5.2) with a "Searching…" animation when empty.
- Manual IP input + JOIN button.
- Back button.

### 9.5 Lobby
- Title: game name; subtitle: host IP.
- **Player slots (8):** colour swatch, name, READY badge, "HOST" badge, ping. Empty slots show "Waiting…".
- **Colour picker:** 8 swatches; taken ones locked with the owner's name.
- **Name:** editable here as well (updates live).
- **Ready toggle** (clients). The host does not need to ready up.
- **Host only:** "Rounds" stepper (− / value / +), range **4–99**, default **12**, long-press for fast change. Clients see the value read-only.
- **START** (host only): enabled when **≥ 2 players** and **all clients are ready**.
- **Leave** button (host leaving closes the lobby for everyone, with confirmation dialog).

### 9.6 HUD (in round)
All elements are on by default; each can be toggled in Settings → HUD.

| Element | Position |
|---|---|
| HP bar + Armor bar (armor drawn as a light-blue segment over HP) | Top-left (right of Menu button) |
| Current weapon icon + ammo count | Below HP bar |
| Round counter "ROUND 3 / 12" | Top-centre |
| Round timer (mm:ss; turns red in the last 30 s) | Top-centre, under the round counter |
| Alive counter (person icon × N) | Top-centre, right of timer |
| Mini scoreboard (top 3 by total kills, plus the local player if not in top 3) | Top-right |
| Kill feed (last 4 entries, 5 s each): "`Pink` [weapon icon] `Blue`", environmental deaths show a hazard icon | Right side, under the mini scoreboard |
| Off-screen enemy indicators (small coloured arrows at the screen edge pointing at enemies) | Screen edges |
| Ping (ms) | Top-right corner, small |
| FPS counter | Top-right corner, small (**off by default**) |
| Damage numbers (floating numbers on hit) | World space |
| Countdown "3, 2, 1, FIGHT!" | Centre |

### 9.7 Round Results (6 s, automatic)
- "ROUND X WINNER: <name>" in the winner's colour, or "DRAW" with the tied names.
- Table: all players sorted by total kills: colour, name, kills this round, total kills.
- Progress bar for the 6 s, then the next map loads.

### 9.8 Match Results
- Podium (1st / 2nd / 3rd) with stickmen in player colours on blocky podium blocks; winner does a jump animation; confetti cubes.
- "WINNER: <name>" or "DRAW" with tied names.
- Full table: rank, colour, name, total kills, round wins.
- Buttons: **BACK TO LOBBY** (host only; brings all connected players back to the lobby with kills reset), **LEAVE**.

### 9.9 Settings
Persisted to `user://settings.cfg` (this is the only data the game stores besides the reconnect session).

- **Player:** name.
- **Audio:** Master, Music, SFX volume sliders (0–100 %).
- **Controls:** joystick sensitivity (0.5×–1.5×, default 1.0×), vibration on/off (default on).
- **Graphics:** quality preset **Low / Medium / High** (default Medium):
  - Low: render scale 0.75, particles ×0.3, no background decorations, no blob shadows for remote players.
  - Medium: render scale 1.0, particles ×0.6, background decorations on.
  - High: render scale 1.0, particles ×1.0, background decorations + parallax layer on.
- **HUD:** toggle each element listed in §9.6; HUD scale 80 %–120 %.
- **Reset to defaults** button.

### 9.10 Overlays & toasts
- In-match menu overlay (Resume / Settings / Leave).
- Reconnecting overlay (§5.5).
- Toasts for errors and info ("Host left the game", "Game is full", "Version mismatch — update the app", "Could not connect", "<name> joined", "<name> left").

---

## 10. Maps

### 10.1 Format (data-driven, AI-friendly)
Maps are **JSON files** in `res://data/maps/` built at runtime into a `GridMap` (using a `MeshLibrary` of pastel blocks) plus hazard/mover/crate nodes. This keeps maps readable and easy for Claude to author and validate.

```json
{
  "id": "candy_plains",
  "name": "Candy Plains",
  "theme": "candy",
  "layout": [
    "................................................",
    "......W...........S..........W..........S.......",
    "....=====.......######.....=====......######....",
    "S.......................I.......................",
    "###########......##########.......##########...."
  ],
  "movers": [
    { "id": "m1", "cells": [[10,5],[11,5],[12,5]], "path": [[0,0],[0,6]], "speed": 2.0, "pause": 1.0 }
  ]
}
```
- `layout[0]` is the **top** row. Each character is one 1 m × 1 m cell (blocks are 1 m deep in Z, with a decorative back layer — see 10.3).
- Legend:

| Char | Meaning |
|---|---|
| `.` | empty |
| `#` | solid block (theme primary colour) |
| `%` | solid block (theme secondary colour, decorative variation) |
| `=` | one-way platform (thin, 0.25 m) |
| `L` | lava (instant death, fills the cell) |
| `^` | spikes (34 dmg, bounce up, 0.5 s invulnerability) |
| `C` | destructible crate (30 HP; destroyed by any damage source; no drops) |
| `J` | jump pad (launches player up at 20 m/s) |
| `M` | moving-platform cell (defined in `movers`; path offsets in cells, ping-pong) |
| `S` | player spawn point (empty cell) |
| `W` | weapon spawn point (empty cell) |
| `I` | item spawn point (empty cell) |

- **Map size:** larger than one screen — **70–100 cells wide**, **30–45 cells tall**. Camera shows about 24 m horizontally.
- Every map: ≥ 8 `S`, ≥ 10 `W`, ≥ 3 `I`, roughly **mirror-symmetric** left/right for fairness, at least two vertical levels, and open pits/edges to fall off.
- `tools/validate_maps.py` (and a GDScript test) must verify: consistent row length, size limits, legend characters only, spawn counts, every `S` has floor within 6 cells below, movers reference `M` cells.

### 10.2 Map list (12)
Each map has its own pastel theme (primary/secondary block colours + background gradient) and hazard mix:

| # | ID | Name | Theme colours | Hazards / features |
|---|---|---|---|---|
| 1 | `candy_plains` | Candy Plains | pink / cream | Pits only (introductory) |
| 2 | `mint_towers` | Mint Towers | mint / white | Tall towers, many one-way platforms |
| 3 | `lava_lagoon` | Lava Lagoon | peach / coral, lava orange | Lava pools between islands |
| 4 | `cloud_hop` | Cloud Hop | sky blue / white | Moving platforms over a big void |
| 5 | `crate_yard` | Crate Yard | butter yellow / cocoa | Many destructible crates as cover |
| 6 | `spike_factory` | Spike Factory | lavender / grey | Spikes + horizontal moving platforms |
| 7 | `bubblegum_bridges` | Bubblegum Bridges | bubblegum / lilac | Long thin bridges, wide pits |
| 8 | `lilac_caves` | Lilac Caves | lilac / plum | Enclosed cave, low ceilings, lava at bottom |
| 9 | `peach_pyramid` | Peach Pyramid | peach / sand | Central stepped pyramid, spikes at base |
| 10 | `sky_lifts` | Sky Lifts | baby blue / mint | Vertical moving lifts, high verticality |
| 11 | `bounce_garden` | Bounce Garden | green / pink | Jump pads, hedges, pits |
| 12 | `sorbet_arena` | Sorbet Arena | mixed rainbow pastels | Symmetric arena using all hazards lightly |

### 10.3 Visual depth (the "2.5D")
- Gameplay is strictly on the Z = 0 plane.
- Blocks are 3D cubes; the playfield row is 1 m deep. A **background layer** (Z = −3 to −8) contains decorative blocks (hills, clouds, towers) in lighter, desaturated theme colours, and on High quality a slow **parallax** far layer.
- Background: vertical gradient (shader on a large quad) per theme.
- No real-time lights or shadow maps (see §11.2).

### 10.4 Camera
- `Camera3D`, **perspective**, FOV 40°, positioned at Z = +30 m looking at the player with a slight downward tilt (−6°), so cube sides and depth are visible.
- Follows **only the local player** (or the spectated player). Smooth follow (lerp factor 8/s), horizontal look-ahead 2 m in the movement direction, small vertical dead-zone (1 m).
- Clamped to map bounds (with 2 m margin) so the camera never shows far outside the map.
- Small screen shake on explosions (amplitude 0.3 m, 0.25 s) and sniper/rocket fire (0.1 m) — on the local camera, scaled by distance.

---

## 11. Art direction & assets

**All assets are created by Claude** inside the repo — no external downloads, no third-party art or audio.

### 11.1 Style
- **Blocky, cute, clean, low-poly, flat pastel.** No pixel art, no textures with detail, no outlines, no gradients on objects (gradients only for sky backgrounds).
- Everything is built from **boxes** (`BoxMesh`) with flat colours.
- **Global palette** (`res://assets/palette.gd`, single source of truth for colours):
  - `ink` `#3A3550` (eyes, text outlines, UI text)
  - `white` `#FFFDF8`
  - `bg_sky` `#DCEBFF`, `bg_sky_low` `#FFF0F5`
  - `ui_panel` `#FFFFFF` @ 85 %, `ui_shadow` `#3A3550` @ 15 %
  - `danger` `#FF6B6B`, `heal` `#FF8FA3`, `armor` `#8EC9FF`, `gold` `#FFD36E`
  - Player colours: §6.2. Theme colours: defined per map in `res://data/themes/*.tres`.
- Weapons are distinct silhouettes made of 2–6 boxes in `ink` + one accent colour, readable at small size.

### 11.2 Shading (flat, no lights)
- One shared **unlit spatial shader** `res://assets/shaders/flat_block.gdshader` with a `albedo` uniform. It fakes simple lighting by tinting each face by its world normal: **top ×1.00, front ×0.94, sides ×0.84, bottom ×0.70**. This keeps the flat look while making cubes read as 3D, at near-zero cost.
- No `DirectionalLight3D`, no shadow maps, no SSAO/glow. Blob shadows only (§6.1).
- Materials are shared `ShaderMaterial` resources per colour (reuse; avoid creating materials at runtime per instance).

### 11.3 Scene assets (`.tscn`, built from primitives)
- `scenes/characters/stickman.tscn` (+ animations, colour set via code)
- `scenes/weapons/`: `pistol.tscn`, `smg.tscn`, `shotgun.tscn`, `sniper.tscn`, `rocket_launcher.tscn`, `grenade.tscn`, plus `rocket_projectile.tscn`, `grenade_projectile.tscn`
- `scenes/pickups/`: `weapon_pickup.tscn` (wraps a weapon model, bob + rotate), `health_pack.tscn`, `armor.tscn`
- `scenes/hazards/`: `lava.tscn` (animated bubbling cubes), `spikes.tscn`, `crate.tscn`, `jump_pad.tscn`, `moving_platform.tscn`
- `assets/blocks/mesh_library.tres` — block meshes for `GridMap` (generated by an editor/tool script from `BoxMesh`)
- UI icons (weapons, HP, armor, alive, ping, menu, arrows, hazard): drawn as **SVG files** made of simple rectangles (Godot imports SVG), in `assets/ui/icons/`.

### 11.4 VFX (`CPUParticles3D` only, for Compatibility renderer)
Muzzle flash (2–3 bright cubes, 0.05 s), bullet tracer (thin stretched box, 0.06 s), hit burst (cubes in victim colour), explosion (expanding pastel cube burst + shockwave ring of cubes), death poof (cubes in player colour), crate break (crate-coloured cubes), pickup sparkle, spawn pop, landing dust (small white cubes), jump-pad puff, lava bubbles. Particle counts scaled by quality preset.

### 11.5 Audio (generated)
- Generated by Python scripts in `tools/` using only the standard library + NumPy (**sfxr-style synthesis**: square/saw/noise oscillators, envelopes, pitch slides). Deterministic seeds so regeneration gives identical files. Output **WAV, 44.1 kHz (SFX) / 22.05 kHz (music), mono, 16-bit**, committed to the repo.
- Style: soft, round, cute "bloopy" sounds, not harsh.
- **SFX list:** `ui_click`, `ui_back`, `ui_toggle`, `ready`, `player_join`, `player_leave`, `countdown_tick`, `round_start`, `round_end`, `match_win`, `jump`, `double_jump`, `land`, `footstep`, `punch_swing`, `punch_hit`, `pickup_weapon`, `pickup_health`, `pickup_armor`, `throw`, `thrown_hit`, `weapon_empty`, `pistol`, `smg`, `shotgun`, `sniper`, `rocket_launch`, `explosion`, `grenade_throw`, `grenade_bounce`, `hit`, `armor_hit`, `death`, `fall_whoosh`, `lava_sizzle`, `spike_hit`, `crate_break`, `jump_pad`, `spawn_pop`, `low_time_tick`.
- **Music:** `menu_loop` (calm, ~32 s), `battle_loop_a`, `battle_loop_b`, `battle_loop_c` (upbeat, ~32 s each, one picked randomly per round), `results_jingle` (~4 s). Simple chiptune-style melody + bass + light percussion, seamless loops.
- In-world SFX use `AudioStreamPlayer3D` (distance attenuation); UI uses `AudioStreamPlayer`. Buses: `Master` → `Music`, `SFX`. Limit simultaneous voices of the same SFX to 4.

### 11.6 Branding images (generated with Python/Pillow from simple shapes)
- `assets/branding/icon.png` 192×192: pastel rounded-square background, a blocky stickman head with eyes.
- `assets/branding/icon_fg.png` / `icon_bg.png` 432×432 (adaptive icon).
- `assets/branding/splash.png` 1920×1080: "BLOCK BRAWL" in blocky letters made of squares on `bg_sky`.
- In-game logo: same blocky lettering (texture or box-built scene).

---

## 12. Performance budget (60 FPS, 8 players)

- Draw calls ≤ **150** per frame in a match; use `GridMap` (batched by mesh) for map blocks; share materials.
- Visible triangles ≤ 100 k.
- Particles: ≤ 300 live particles on High, scaled down per preset.
- No real-time lights, no shadows, no post-processing.
- Script: avoid per-frame allocations in hot paths; pool tracers, damage numbers and particles.
- Network: snapshot payload for 8 players ≤ 2 KB per snapshot at 30 Hz.
- APK size target ≤ **60 MB**.
- Include a debug overlay (F3 on desktop / 4-finger tap on device in debug builds) showing FPS, draw calls, ping, snapshot size.

---

## 13. Project structure & conventions

Standard Godot conventions (official GDScript style guide):
- Files/folders: `snake_case`. Classes: `PascalCase` via `class_name`. Constants: `UPPER_SNAKE_CASE`. Signals: past tense (`player_died`).
- Static typing required. One script per scene root. Communicate down with calls, up with signals.
- No addons/plugins (keep the repo dependency-free).

```
/PRD.md
/README.md                      # setup, Godot version, how to build APK, how to test multiplayer
/project.godot
/export_presets.cfg             # Android preset (no secrets committed)
/assets/
  palette.gd
  shaders/flat_block.gdshader, sky_gradient.gdshader
  materials/                    # shared ShaderMaterials
  blocks/mesh_library.tres
  audio/sfx/*.wav  audio/music/*.wav
  ui/icons/*.svg
  branding/*.png
/data/
  weapons/*.tres                # WeaponData resources
  items/*.tres
  themes/*.tres                 # MapTheme resources
  maps/*.json                   # 12 maps
/scenes/
  main/main.tscn                # root, screen router
  characters/  weapons/  pickups/  hazards/  maps/map_root.tscn
  ui/ main_menu, join, lobby, hud, round_results, match_results, settings, overlays, controls
/scripts/
  autoload/
    settings.gd                 # load/save user://settings.cfg
    audio_manager.gd
    net_manager.gd              # ENet host/join, reconnect, ping
    lan_discovery.gd            # broadcast + subnet sweep, host responder
    game_state.gd               # players, colours, scores (replicated)
    match_manager.gd            # server-side round/match flow, spawning, scoring
    scene_router.gd             # screen transitions
  resources/ weapon_data.gd, item_data.gd, map_theme.gd
  gameplay/ ...                 # player controller, combat, auto-aim, hazards, map_builder
  ui/ ...
/tools/
  gen_sfx.py  gen_music.py  gen_branding.py  validate_maps.py
/tests/
  run_tests.gd                  # headless test runner (no addon), exit code != 0 on failure
  test_*.gd
```

---

## 14. Testing & verification

### 14.1 Automated (headless, run by Claude in the cloud environment)
Claude downloads the matching **Godot 4.7.x headless/Linux editor binary from the official GitHub releases** and runs:
- `godot --headless --import` must finish without errors.
- `godot --headless -s tests/run_tests.gd` covering at minimum:
  - map JSON parsing + validation for all 12 maps
  - kill credit rules (direct, environmental within/after 5 s, self-damage)
  - round end conditions (≤1 alive, timer)
  - round/match winner and DRAW logic
  - damage → armor → HP
  - colour uniqueness / auto-assignment
  - rounds setting clamp 4–99
  - map rotation (no immediate repeat on reshuffle)
  - discovery packet encode/decode and version check
- `python tools/validate_maps.py`
- (Optional) a GitHub Actions workflow running the same headless checks on push.

### 14.2 Manual (owner)
- Desktop: run 2–4 editor instances (Debug → Customize Run Instances) on localhost to test host/join/lobby/match.
- Android: install the APK on 2+ phones; test on the same Wi-Fi and with one phone as Hotspot; verify discovery, manual IP, reconnect (toggle Wi-Fi on a client mid-round), host leaving.

---

## 15. Acceptance criteria (v1 is done when all pass)

1. APK installs and launches on Android 7+ in landscape, fullscreen, at 60 FPS on a mid-range phone during an 8-player match on Medium quality.
2. A phone can host; other phones on the same Wi-Fi **or** connected to a phone hotspot see the game in the Join list within 4 s; manual IP join works.
3. Lobby supports 2–8 players, unique colour selection, name editing, ready toggles, host round setting 4–99 (default 12); START only enabled under the stated conditions.
4. Joining is refused during a match except for reconnecting players; reconnect within 60 s restores name, colour and kills, and the player spectates until the next round.
5. Host leaving returns all clients to the main menu with a message.
6. Each round uses a different map; 12 distinct maps exist and validate.
7. Round ends at ≤1 alive or 300 s; round winner and DRAW are shown correctly; match winner by total kills with DRAW support.
8. All 6 weapons, punch, throw, pickup button, drop-on-swap, ammo removal, 30 s despawn, health and armor items behave as specified; auto-aim follows §7.2.
9. Falling off the map, lava, spikes, crates, jump pads and moving platforms work; environmental kill credit follows §4.3.
10. Double jump, one-way platform drop-through, knockback work as specified.
11. Dead players can spectate and cycle living players.
12. All screens from §9 exist; settings persist across app restarts; every HUD element can be toggled.
13. All visuals use the flat shader + palette; all assets (models, icons, branding, SFX, music) are generated in-repo by Claude; no external assets.
14. Headless import and test suite pass with zero errors.

---

## 16. Implementation milestones (for Claude Code)

Each milestone ends with a commit/PR, passing headless checks, and a short note in `CHANGELOG.md`.

| # | Milestone | Content |
|---|---|---|
| M0 | Project setup | Godot 4.7.x project, Compatibility renderer, display/stretch settings, Android export preset, autoload skeletons, palette, flat shader, test runner, README. |
| M1 | Assets | Stickman scene + animations, weapons, pickups, hazards, mesh library, UI icon SVGs, branding images (script), SFX + music (scripts), theme resource. |
| M2 | Local sandbox | Map JSON loader → GridMap, 1 test map, player controller (move, jump, double jump, drop-through, knockback), camera, touch controls + debug keyboard, single-player sandbox scene for testing. |
| M3 | Combat | Weapons data, pickup/drop/throw, auto-aim, hitscan + projectiles, punch, HP/armor, damage, hazards, crates, jump pads, movers, items, spawning rules, VFX/SFX hooks. |
| M4 | Networking | NetManager (host/join, protocol version), LAN discovery (broadcast + subnet sweep), lobby (names, colours, ready, rounds), input/state replication, interpolation, reconnect, host-left handling. |
| M5 | Match flow | MatchManager: map rotation, countdown, round end rules, kill credit, spectate, round results, match results, back to lobby; all 12 maps authored + validated. |
| M6 | UI & polish | Main menu background, settings (persisted), full HUD with toggles, kill feed, off-screen indicators, damage numbers, toasts/overlays, audio wiring + buses, screen shake, quality presets. |
| M7 | Android & performance | APK build instructions, performance pass to budget (§12), debug overlay, acceptance checklist (§15) run-through, final README. |

---

## 17. Values delegated to Claude (final defaults, tunable)

The owner explicitly delegated these decisions; they are the defaults above, collected here:
- GDScript + Compatibility renderer (owner: "whichever performs better on mobile").
- Game name **Block Brawl**, package `com.blockbrawl.game`.
- Round Results screen duration **6 s**; countdown 3 s.
- Weapon list and all weapon stats (§7.3), spawn weights, punch/throw stats.
- Spawn timings: 3 weapons at start, +1 every 8 s up to 6; items first at 30 s then every 20 s up to 2; ground weapon despawn 30 s.
- Item values (Health +40, Armor +50).
- Movement values (§6.4), knockback model, HP 100.
- Kill-credit window **5 s**; reconnect window **60 s**; early match end when < 2 players connected after reconnect windows expire.
- Ports 47820/47821, discovery method.
- Map format, sizes, legend, 12 map names/themes/hazards.
- Palette and player colours.
- HUD elements and layout (all toggleable), settings contents, quality presets.
- Music included (menu, 3 battle loops, results jingle) alongside SFX.

## 18. Out of scope (v1)

Internet play, host migration, bots, chat/emotes, accounts, stored stats/leaderboards, ads, IAP, analytics, iOS/desktop builds, cosmetics beyond colour, control layout customisation, client-side prediction, localisation other than English.
