# Open questions (PRD gaps)

Each item is also marked in code with `TODO(PRD):`. The simplest option
consistent with the PRD was implemented.

1. **Mover path axis convention** (§10.1): the example `"path": [[0,0],[0,6]]` does not say whether +y is up or down. Implemented: path offsets use the layout convention (+x right, +y down the layout, i.e. like rows). Every path point gets the `pause`. (`moving_platform.gd`)
2. **Camera width vs FOV** (§10.4): resolved in v1.1 — camera at Z = +40 m, FOV 40° applied horizontally (~29 m visible).
3. **Variable jump height**: `jump_held` is part of the input packet (§5.6) but no behaviour is specified for it. Implemented: fixed jump height; `jump_held` is transmitted but unused.
4. **Spread meaning** (§7.3): "Spread 2°" / "15° cone" read as the full cone angle; each shot/pellet deviates uniformly within ±spread/2. (`world.gd::_fire_hitscan`)
5. **Spike bounce strength** (§10.1): "bounce up" has no value. Implemented: vertical velocity set to the jump velocity (11 m/s). (`world.gd`, `SPIKE_BOUNCE_VELOCITY`)
6. **Grenade throw** (v1.1 manual aim): no speed is specified. Implemented: thrown along the aim at 15 m/s plus 3 m/s lift; grenades bounce on world geometry with restitution 0.5 and pass through players. (`world.gd::fire_weapon`, `GRENADE_RESTITUTION`)
7. **Thrown weapon arc** (§7.1): "slight upward arc" implemented as 4 m/s initial upward velocity with normal gravity (30 m/s²).
8. **Items at full HP/armor** (§7.4): picked up automatically on touch even when already full (simplest reading of "picked up automatically on touch").
9. **Weapon held at death**: not specified; the weapon disappears with the player (no drop).
10. **Explosion knockback** (§7.3): full weapon knockback is applied to every damaged player (not scaled by distance), direction from the explosion centre.
11. **Punch reach** (§7.3): 1.2 m measured from the attacker's centre to the target's capsule edge, hitting the nearest enemy in front (|Δy| < 1 m); if no player, a crate in front is hit.
12. **Crate "destroyed by any damage source"** (§10.1): crates have 30 HP and every damage source (bullets, punch, thrown weapons) reduces it; explosions from rockets/grenades destroy crates in their radius outright ("Destroys crates").
13. **Replication mechanism** (§5.6): instead of `MultiplayerSynchronizer`/`MultiplayerSpawner`, the "equivalent packed RPC" option is used for state *and* entity spawning: every 30 Hz snapshot carries the full lists of players, projectiles, pickups, movers and crates; clients create/remove their visual nodes from those lists (entities are always created by the server only). This avoids node-path races on map changes and reconnects.
14. **Message for new joins during a match** (§5.3): not specified; clients get "Match in progress".
15. **Reconnect window expiry on the client** (§5.5): when 60 s of retries fail, the client returns to the main menu with "Host left the game".
16. **Subnet mask for the sweep** (§5.2): Godot cannot read interface netmasks without native code, so every private IPv4 interface is assumed to be a /24 (the usual home Wi-Fi / Android hotspot setup).
17. **Discovery of incompatible hosts** (§5.2): hosts running another protocol version are not listed (the version check also happens on connect).
18. **Number of acceptance criteria**: the task description mentions 15 acceptance criteria, PRD §15 lists 14; all 14 are tracked in `PROGRESS.md`.
19. **v1.1 melee combo window**: "2 times hit by melee" has no time limit; implemented as 2 punches within 3 s (counter resets after the stun or when the window passes).
20. **v1.1 spawn telegraph length**: 1.5 s glow before each weapon *and* item spawn (items too, for consistency).
21. **v1.1 touch aiming scheme**: aim by dragging from the Attack button (press = fire, drag = aim); desktop aims with the mouse.
22. **v1.2 Android 8 "cannot see controllers"**: could not be reproduced without the device. Fixed the two plausible causes: (a) invalid safe-area values on older Android now ignored/clamped, (b) the 35 % white buttons and touch-only joystick were near-invisible on pastel maps — buttons are now opaque and coloured and the joystick is always shown. Please re-test on the phone.
23. **v1.2 drop-through without a Jump button**: hold the joystick down for 0.15 s on a one-way platform (keyboard: S, or S + Space).
