# Prompt 04 — movement, camera and input settings, with measurements

Project: `G:\nasa app\mars_colony_godot`. Every number in the "setting" columns is designer tuning unless marked
**sourced**. Measurements are from automated headless runs on 2026-11-11 (`tests\test_player.gd` in a synthetic test
room, `tests\test_game_scene.gd` in the real map's collision). Nothing here was felt by a human player.

## 1. Movement

Settings live in `scripts\player\player_tuning.gd` (`PlayerTuning`) and `scripts\core\game_config.gd` (`GameConfig`).

| Setting | Value | Measured | Note |
|---|---|---|---|
| Gravity | 3.73 m/s² (**sourced**, S01) | 3 m free fall: 1.30 s (theory 1.27 s) | Applied to the player and to carried props; the project-wide gravity setting is not relied on |
| Walk speed | 3.0 m/s | 3.000 m/s in the test room; 3.00 m/s on outdoor terrain | |
| Suit slowdown | × 0.8 (`GameConfig.suit_speed_factor`) | 2.400 m/s; ratio 0.800 on terrain | The pack's initial 20 % |
| Sprint | × 1.6 | ratio 1.600 | Drains a local stamina value for feel only (issue I-42) |
| Jump height | 0.5 m (take-off 1.93 m/s) | apex 0.500 m; 1.00–1.05 s in the air | Decision E-21. The same push on Earth gives 0.19 m and 0.39 s |
| Ground acceleration / braking | 18 / 22 m/s² | — | Reaches walking speed in about 0.17 s |
| Air control | 25 % of ground acceleration | — | Small corrections only |
| Floor snap | 0.15 m | — | Keeps feet on descending ramps |
| Slope limit | 40° | climbs 20°, refuses 50° | |
| Step height | 0.25 m | climbs a 0.2 m step | Lifts only; forward motion comes from normal movement |
| Body | capsule 1.8 m tall, radius 0.32 m; eyes at 1.65 m | walks through all 24 doors, both directions | Narrowest door opening is 1.0 m |
| Reach | 2.6 m | — | Same as the host's interaction distance |
| Throw speed | 4 m/s | thrown crate moves forward | Hold sprint while dropping |

Movement, the suit check and animation run in real seconds and do not change with the length of a sol.

**Found and fixed:** the first step-climbing code moved the body forward by its own radius every time it met a small
ledge. On uneven outdoor ground that showed up as a walk far faster than the tuned speed in a sped-up test run. The
step now only lifts the body. (Part of that first reading was also a test fault: issue I-45.)

## 2. Cameras

`scripts\player\player_camera_rig.gd` (`PlayerCameraRig`).

| Item | Setting | Check |
|---|---|---|
| Start view | First person | Tested in both suites |
| Field of view | 72° in both views (`GameConfig.fov_degrees`) | Tested |
| Third person | `SpringArm3D`, 2.5 m (`GameConfig.third_person_distance_m`), sphere shape radius 0.2 m, collides with world and doors, player's own body excluded | Open space: 2.500 m behind. Back 0.6 m from a wall: camera stays on the player's side. In the real map at the hub: nothing solid between camera and head |
| Local head | Head and helmet meshes go to render layer 19 only while in first person; the first-person camera does not draw that layer; arms, hands, torso, legs and boots stay visible | Tested: one body, no second set of limbs |
| Active camera | Exactly one is current | Tested for both views |
| Pitch limit | ± 85° | Tested |
| Room lighting on characters | `PlayerVisual.set_zone_layers(mask)`: the body takes the render layer of the room it is in, so that room's lights reach it | Set every frame the zone changes; not measured visually |

Changing view never changes ownership or cargo (20 toggles in `test_player`, 6 through real key presses in `test_game_scene`).
`M` (map) never toggles the view and `Tab` is never bound to the map.

## 3. Input

`scripts\player\player_input.gd` (`PlayerInput.ACTIONS`). Defaults are added at start-up without removing a remap;
remaps are saved to `user://input.json`.

| Action | Default | State |
|---|---|---|
| `move_forward`, `move_back`, `move_left`, `move_right` | W, S, A, D | Working |
| `sprint` | Shift | Working |
| `jump` | Space | Working (rover brake is Prompt 10) |
| `interact` | E | Working: suit rack starts the suit check; power panel opens the zone switches; other stations answer "not working yet" |
| `grab` | G and left mouse button | Working: pick up, drop, throw |
| `toggle_view` | Tab | Working |
| `map` | M | Bound; blueprint is a later prompt |
| `push_to_talk` | V | Bound; voice is Prompt 11 |
| `back` | Esc | Working: closes an open panel first, otherwise asks for a pause |
| `source_register` | Shift + Backspace | Bound; register is a later prompt |
| F5 | — | Unbound (tested) |

Interim, not in the pack: keys 1 to 4 ask to take that crew member; the host applies the hub rule (decision E-23).

## 4. Suit check and carrying

- **Suit check:** `E` at the suit rack sends `begin_suit_check`. The host runs it for 1.0 real second
  (`GameConfig.suit_check_seconds`), cancels it if the player leaves the rack or loses the character, and never changes
  the tank charge. Measured: not on at 0.5 s, on at 1.25 s; ten on/off cycles leave the charge identical; leaving the
  rack cancels it.
- **Carrying:** the controller only asks (`pick_up`, `drop`); the host decides. A carried prop is parented to the right
  hand anchor (within 1 cm while walking in `test_player`, within 2 cm in `test_game_scene`). A refused pick-up attaches
  nothing; a refused drop keeps the prop in the hand.

## 5. World collision used for these checks

`scripts\world\world_collision.gd` builds collision from `data\colony_manifest.json` and `data\colliders.json`:
19 static bodies (one per map area) with 1,417 boxes, 24 sliding doors with 52 leaves, 9 station volumes.
All 1,250 first-box centres match an independent calculation within 0.004 mm (404 rotated and 55 scaled objects included).
Floors are at y = 0.000 in every room. Outdoor ground is a 561 × 533 height grid at 1 m (`data\terrain_height.res`),
levelled under and around the buildings (decision E-22). What has no collision is listed in issue I-38.

Doors open for a player within 2.2 m in 0.6 real seconds and close behind them; the visible leaves of all 52 were found
in the map and move with their colliders.
