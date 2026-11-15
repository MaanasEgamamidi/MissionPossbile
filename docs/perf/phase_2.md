# Perf overhaul, Phase 2: zones (room sleep/wake)

Status: **implemented, ON by default, verified headless (tests/test_perf.gd 48/48) and measured: Med Bay -11 %,
Life Support -13 % GPU time, image identical (benchmark_2026-11-14.md).**

## Files

- `perf/zone.gd`, `perf/zone_door.gd`, `perf/zone_manager.gd` (new), `perf/perf_rig.gd` (adds them at the start of
  play), `scripts/game/game_main.gd` (one line: `PerfRig.attach(self)` at the end of `_begin_play`).
- `scripts/world/zone_lighting.gd`: `set_zone_awake()` / `is_zone_awake()`; a fixture is lit when its zone is powered
  **and** awake (the power simulation keeps full control; waking restores exactly what power says).
- `scripts/world/door_controller.gd`: signals `opening_started(door_id)` (the frame the door starts to move, before
  the leaves have moved) and `closed_fully(door_id)`. No behaviour change.

## How it works here (adapted, see scene_inventory.md)

| State | Drawn (camera cull mask bit) | Fixture lights | When |
|---|---|---|---|
| COLD | no | off | not seen and not near |
| VIEW_ONLY | yes | on | seen through up to `glass_view_hops` glass doors / windows, or from outside |
| WARM | yes | on | within `warm_hops` doors, or behind a door within `prewarm_distance` |
| ACTIVE | yes | on | the zone the player is in |

- Drawing: `ZoneManager._apply_camera_mask()` clears the bits of non-drawn zones from the **main viewport's current
  camera only** and gives back exactly the bits it cleared (the rig's own first-person layer is never touched; the
  rover mast camera and portraits are untouched). A mesh on a boundary carries both rooms' bits and stays drawn while
  either room is; meshes on layer 20 (roofs, outer walls) are always drawn. Shadow casting uses light masks, which
  are untouched: no shadow on a visible surface changes.
- **Lights, probes and decals are culled by the camera mask too** (through their own `layers`, default 1 = the Hangar
  bay's zone layer). The first benchmark showed it: Hangar asleep = sun and lamps gone. `ZoneManager._pin()` gives
  every light, probe, decal, fog volume and every non-map object still on layer 1 the always-drawn layer 20 (also for
  nodes added later, through `SceneTree.node_added`), and takes it off again on exit.
- Lights: `ZoneLighting.set_zone_awake`. A COLD room's shadowed fixtures leave the shadow atlas.
- Doors: every door leaf with glass is `transparent` (26 of 28), so with `glass_view_hops = 2` a room stays drawn
  while it can be seen through two glass panels in a row. Two hops was chosen because doors 1 and 9, or 22 and 21,
  line up across a room; one hop would let a far room vanish behind a door's vision panel.
- Bounds: room rectangles from the manifest (+0.15 m each side, so neighbours overlap 0.3 m), floor to ceiling;
  the plaza is the dome's super-ellipse minus the rooms, the garden dome a 11 m circle. Standing on a roof counts as
  the plaza.
- Teleport, respawn, rover exit, save load: a jump of more than `snap_distance` (6 m) between two frames calls `snap()`
  by itself, in that frame, so no game code had to change.
- Hysteresis 2 s before COLD; time-sliced queue, 1.5 ms per frame, wake before sleep, nearest first.

## What it culls (headless, player at each zone's centre, defaults)

| Player in | Zones drawn / not drawn | Not drawn |
|---|---|---|
| Hangar bay | 14 / 3 | Med Bay, East quarters, Garden dome |
| Crew corridor | 15 / 2 | East quarters, Life Support |
| Mess hall | 13 / 4 | Blast-door passage, East quarters, Service corridor, Life Support |
| Rec kitchen | 10 / 7 | West bunk, Service corridor, Greenhouse, Airlock, Power Room, Life Support, Garden |
| Med Bay | 10 / 7 | Hangar, Blast-door, West bunk, East quarters, Service, Life Support, Pipe gallery |
| Command Room | 14 / 3 | Crew corridor, West bunk, Service corridor |
| Blast-door passage | 17 / 0 | - |
| West bunk room | 11 / 6 | Rec kitchen, Blast-door, East quarters, Service, Life Support, Pipe gallery |
| East quarters | 7 / 10 | Hangar, Crew corridor, Mess, Med Bay, West bunk, Greenhouse, Airlock, Power, Pipe gallery, Garden |
| Service corridor | 11 / 6 | Mess, Rec kitchen, Med Bay, West bunk, Greenhouse, Garden |
| Greenhouse | 11 / 6 | Rec kitchen, Blast-door, East quarters, Service, Life Support, Pipe gallery |
| Airlock | 14 / 3 | Rec kitchen, East quarters, Life Support |
| Power Room | 11 / 6 | Crew corridor, Rec kitchen, Blast-door, West bunk, East quarters, Pipe gallery |
| Life Support | 6 / 11 | everything but East quarters, Service, Command, Hangar, Power + itself |
| Pipe gallery | 16 / 1 | Garden dome |
| Dome plaza | 15 / 2 | Life Support, Pipe gallery |
| Garden dome | 8 / 9 | Hangar, Crew corridor, Rec kitchen, Blast-door, West bunk, East quarters, Service, Life Support, Pipe gallery |
| Outside, 60 m south | plaza + garden drawn | all 15 rooms |

The Greenhouse's 76 fixtures (35 area lights) are off whenever it is COLD: from Rec kitchen, Life Support, East
quarters, Service corridor, Command Room... From outside, every room interior is off.

Measured (benchmark_2026-11-14.md): Med Bay -11 % and Life Support -13 % GPU time, Command Room -4 %, the rest
within drift; outdoors -25 to -29 % draw calls with no GPU-time change.

## Not done / notes

- No `process_mode` work: no room owns dynamic content (scene_inventory.md). `Zone.extra_dynamic` + the
  `_zone_state_changed` hook are there for future room content.
- Reflection probes and lamp emission are left alone (a COLD room is not drawn, so they show nothing).
- Defaults: warm_hops 1, glass_view_hops 2, prewarm 4 m, cold_delay 2 s, budget 1500 us, 10 Hz poll.

## Update 2026-11-15: newer game content

- **Runtime room props** (`room_props_enabled`, default ON). Props added while the game runs that are still on the
  default layer 1 (cassettes, broken parts, task effects, labels...) used to be pinned to the always-drawn layer, so
  they drew and simulated while their room slept. Layer 1 is also the Hangar's zone layer. Now, at the end of the frame
  they were added (after their presenter has set layers and position), a static prop standing in a room gets that
  room's layer. Movers are never tied to a room: `ZoneManager.MOVERS` (GameMain fields: player, crew visuals, carried
  items, rover, drone body, scout root; add a line for each new moving feature), any non-static physics body, and any
  prop found outside its room on the 0.5 s check (it goes back to the always-drawn layer).
- This also fixes broken-part models: they were pinned before `broken_part_presenter.gd` set their zone layer, which
  then OR'd onto layer 1 + the always layer, so they were always drawn.
- **Scout drone:** rooms are now chosen from `viewer_position()` (a camera that is not under the player, i.e. the
  drone's, counts instead of the player), and a camera made current with a copy of the old camera's mask gets back
  the zone bits that were cleared on the old one (the drone copies the player camera's mask).
