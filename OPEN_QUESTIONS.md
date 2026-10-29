# Open questions (PRD gaps)

Each item is also marked in code with `TODO(PRD):`. The simplest option
consistent with the PRD was implemented.

1. **Mover path axis convention** (§10.1): the example `"path": [[0,0],[0,6]]` does not say whether +y is up or down. Implemented: path offsets use the layout convention (+x right, +y down the layout, i.e. like rows). Every path point gets the `pause`. (`moving_platform.gd`)
2. **Camera width vs FOV** (§10.4): FOV 40° at Z = +30 m shows 21.8 m, not exactly "about 24 m". Implemented: FOV 40° applied horizontally (`KEEP_WIDTH`), giving ~21.8 m on every aspect ratio. (`camera_rig.gd`)
3. **Variable jump height**: `jump_held` is part of the input packet (§5.6) but no behaviour is specified for it. Implemented: fixed jump height; `jump_held` is transmitted but unused.
