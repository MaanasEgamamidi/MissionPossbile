# Milestone handoff — Prompt 04: Player rig, spacesuit, movement and cameras

Date: 2026-11-11. Project: `G:\nasa app\mars_colony_godot` (Godot 4.7.2). Blender 5.3 and Godot 4.7.2 access was re-checked before work began.

## 1. Outcome

The game can be played: start it, walk the base in first or third person under Mars gravity, go through every door,
do the one-second suit check at the suit rack, carry a crate, switch rooms off at the power panel, pause, and be
recovered to the hub if condition reaches zero. Everything the player does goes to the host as a request.

A derivative crew member and spacesuit were built from the workspace's own assets: a rigged, clothed body from the
Human Base Meshes bundle and a wearable suit cut from the wall-stowed `qt_spacesuit`, with nine animation clips. It is
in the game for the local player and the three parked crew.

All checks are automated (129 in three suites, section 5) plus screenshots of the running game. **No human has played
it.** How the controls feel, whether the camera is comfortable, and whether children aged 9 to 12 can use it are unknown.

The owner's instruction during this session was to stop work on looks and concentrate on mechanics (D-07), so the
character art received no polish beyond what the build script produced.

**How the work was done.** Three Codex `gpt-6-astra` workers (fast tier) built parts of this milestone in parallel from
the shared specification (`..\03_simulation\workers\SPEC.md`): world collision and doors; player, cameras and input; the
character rig in Blender. The executor reviewed and merged each, wrote the game scene, HUD and end-to-end test, fixed
what the combined run exposed, and wired the rig into the game.

## 2. Prompt 04 acceptance, item by item

| Requirement | Result | Evidence |
|---|---|---|
| Derivative rig from approved human and suit assets | **Built, approval pending.** Body: `GEO-body_male_realistic` (Human Base Meshes 1.4.1), reduced from 21,160 to 14,089 triangles in four meshes, 23-bone armature, automatic weights. Suit: `qt_spacesuit` from `grand_colony.blend`, wall mount removed, 86,524 → 42,314 triangles in four meshes, each loose part bound rigidly to one bone. No source file was changed (hashes equal before and after). The owner has not yet said which human assets are approved (I-04). | `rig\PROVENANCE.md`, `rig\report.json` |
| The person fits inside the suit | **Met in the rest pose by measurement; sampled by eye in motion.** With the complete suit, 0 % of torso, arm and leg vertices are outside. The original outer shell alone left 0.74 % (torso), 0.05 % (arms) and 13.5 % (legs) outside, so the build adds inner liners at the joints. Posed frames were looked at as stills, not tested exhaustively. | `rig\report.json` (`rest_containment`, `outer_shell_containment`), `rig\poses\` |
| Four specialist identities with restrained identifiers | **Partly met.** A shoulder patch and chest stripe take one of four colours. All four crew share one body and face; there are no names, portraits or tools. | `evidence\game\03_third_person_hub.png` |
| Idle, walk, sprint, jump/land, carry/use, suit, seated | **Nine clips exist** (idle 4 s, walk 1 s, sprint 0.7 s, jump 0.4 s, land 0.4 s, carry 2 s, use 1 s, suit 1 s, seated single pose). In the game: idle, walk, sprint, jump and carry follow movement; land plays on touchdown, use on a station, suit during the suit check. Seated has no use yet (no seats or rover). Feet stay on or above the ground in every sampled frame. | `rig\poses\contact_*.jpg`, `rig\report.json` (`clips`) |
| First person after the start screen, with arms, hands, torso, legs, boots | **Met without a start screen** (none exists yet). One body is used in both views. | `test_player`: "starts first person", "first person head hidden limbs visible" |
| Local head and helmet hidden by render layers | **Met.** Head and helmet meshes are on render layer 19 only while in first person; the first-person camera skips that layer. | `test_player`: "zone layers preserve hidden head", "replacement model anchors and head layers" |
| Tab toggles a close rear third person; M stays the map | **Met.** | `test_player`: "map never toggles perspective"; `test_game_scene`: "six Tab presses" |
| SpringArm3D with a shape and player-collider exclusion | **Met.** Sphere radius 0.2 m; collides with world and doors. | `test_player`: "spring arm sphere and mask", "camera stays before wall" |
| CharacterBody3D with Mars gravity; jump, acceleration, floor snap, slopes, thresholds, 20 % suit slowdown retuned | **Met**, values and measurements in `MOVEMENT_AND_CAMERA.md`. | `test_player` 20 movement checks; `test_game_scene`: jump, outdoor speed |
| Prop pickup and drop; held items follow hand anchors | **Met** for the three rehearsal crates. With the rig, the anchor is a bone attachment on `HandAnchorR`. | `test_player`: 8 carrying checks; `test_game_scene`: 4 |
| Suit check about one real second, preserves tank charge, cancelled if conditions cease; no refill by repeated equip | **Met.** | `test_session`: 8 suit checks; `test_game_scene`: 4 |
| Capture poses and clipping evidence | **Done**: 32 pose stills (8 clips × front/side × with/without suit), four contact sheets, 9 game screenshots. | `rig\poses\`, `evidence\game\` |
| Both perspectives playable with input | **Automated only.** Key presses were injected; no person played. | `test_game_scene` |
| Correct FOV | **Met**: 72° in both views. | both suites |
| No wall penetration | **Met in the tests run**: 2 s walking into a wall; camera against a wall; 24 doors. Not an exhaustive sweep of the map. | `test_player`, `test_game_scene` |
| No duplicate limbs | **Met**: one body, no separate first-person arms. | `test_game_scene`: "three parked crew are shown, none of them is a second local body" |
| No body through suit | Rest pose measured at 0 %; motion sampled by eye only (see above). | `rig\` |
| Traverse approved routes under Mars gravity | **No approved route list exists.** Checked instead: every one of the 24 doors walked through in both directions, a walk at the hub, a 6 m run on outdoor terrain. | `test_game_scene`: "doors open for the player…  24 of 24" |
| Suit speed, charge and viewpoint changes do not alter authority or inventory | **Met.** | `test_player`: "20 view toggles and suit preserve authority", "controller never changes cargo or owner" |

## 3. Changed files

New in `mars_colony_godot\`:

- `scripts\player\`: `player_controller.gd`, `player_camera_rig.gd`, `player_input.gd`, `player_tuning.gd`, `player_visual.gd`, `carry_item.gd`
- `scripts\world\`: `world_collision.gd`, `door_controller.gd`, `terrain_height.gd`
- `scripts\game\`: `game_main.gd`, `game_hud.gd`; `scenes\game.tscn` (now the main scene in `project.godot`)
- `data\terrain_height.res` (561 × 533 samples at 1 m)
- `assets\characters\astronaut.glb` (2.05 MB, no image textures) and `assets_src\characters\` (the built `.blend`; ignored by Godot)
- `tools\blender\character\` (build scripts; `build_character.ps1` rebuilds the model from the two source files)
- `tools\godot\`: `build_heightmap.gd`, `heightmap_level_rooms.gd`, `capture_game.gd`, `diag_ground.gd`, `diag_save_cost.gd`
- `tests\`: `test_collision.gd`, `test_player.gd`, `test_game_scene.gd`

New in `docs\milestones\04_player\`: this file, `MOVEMENT_AND_CAMERA.md`, `rig\` (provenance, report, poses, logs), `evidence\game\`, `evidence\tests\`.

Changed: `project.godot` (main scene), `README.md`, `.gitignore`.

## 4. Interfaces later milestones use

| Interface | Use |
|---|---|
| `GameMain` (root of `scenes\game.tscn`) | `services`, `world`, `collision`, `lighting`, `player`, `hud`; exports `load_world` and `save_directory` for tests |
| `PlayerController` | `setup(config, tuning, character, submit, report_position)`, `set_first_person`, `camera_rig()`, `visual()`, `teleport`, `held_item()`, `aimed_target()`, `input_enabled`; signals `perspective_changed`, `action_answered` |
| `PlayerVisual` | `use_rig_if_available()`, `set_model(scene)`, `set_first_person`, `set_zone_layers(mask)`, `set_suit`, `set_crew_identity(0..3)`, `hand_anchor(right)`, `play(state)`, `play_once(state, seconds)` |
| `PlayerInput` | `ACTIONS`, `ensure_actions()`, `rebind`, `reset`, `save`, `load`, `describe(action)` |
| `PlayerTuning` | All movement numbers |
| `WorldCollision.build(manifest, colliders)` | Node `Collision` with `Static\<area>`, `Doors\<DoorController>`, `Stations\<Area3D with station_id, kind>` |
| `DoorController` | `door_id`, `locked`, `set_locked`, `is_open()`, `open_seconds`, `sense_radius`, `attach_visuals(scene)`, signal `opened_changed` |
| `TerrainHeight` | `height_at(x, z)`, `make_body()`, `from_meshes(root, cell, bounds)` |
| `CarryItem` | `item_id`, `attach_to(anchor)`, `release(position, velocity)`, `make_crate(id)` |
| Character model contract | Meshes `Body_Head`, `Body_Torso`, `Body_Arms`, `Body_Legs`, `Suit_Helmet`, `Suit_Torso`, `Suit_Arms`, `Suit_Legs`; bones `HandAnchorL`, `HandAnchorR`; material `Mat_Ident`; clips `idle walk sprint jump land carry use suit seated`; built facing Blender −Y |

## 5. Checks run, with results

Automated, headless, `tools\run_tests.ps1`, 2026-11-11. Full output in `evidence\tests\`.

| Suite | Result | What it covers |
|---|---|---|
| `tests\test_collision.gd` | 32 / 32 | Collider counts against the JSON, 1,250 transforms, floors, walls, doors, station volumes, height grid |
| `tests\test_player.gd` | 66 / 66 | Input map, gravity, jump, speeds, slopes, step, walls, both cameras, layers, carrying through a fake host, body states |
| `tests\test_game_scene.gd` | 31 / 31 | The assembled game on the real map's collision: start, walking, jump, view toggle, carrying, suit check, outdoor speeds, power panel, pause, recovery, all doors |

Also run: the game with the full map in a window (`tools\godot\capture_game.gd`): loads in about 5 s on the development desktop, all 52 door leaves found, nine screenshots written. The executor looked at five of them and at two of the rig contact sheets.

Not verified: any human play; frame rate (issue I-37); the rig's clips in motion inside Godot (only stills from the game and from Blender were looked at); transparency of the visor in Godot; a second player's view of another player's body; the remapping functions through an actual settings screen; the target laptop.

## 6. Sources and provenance

- S01 NASA Mars Fact Sheet: gravity 3.73 m/s².
- Human Base Meshes 1.4.1 (Blender Studio), file `grand_colony\work\_downloads\human_base_meshes\…\human_base_meshes_bundle.blend`: the bundle's README says CC0; a separate licence text inside names the "Rain Rig" under CC BY 4.0 (issue I-12, still open). The rig built here uses a body mesh only and its own new armature.
- `qt_spacesuit` in `grand_colony\grand_colony.blend`: the project's own procedurally built suit.
- Full step-by-step record with numbers: `rig\PROVENANCE.md`.

## 7. Performance notes

- Headless suites: 3.5 s, 15.2 s and 37 s.
- Character: 14,089 + 42,314 triangles, 23 bones, 21 materials, no textures. Four are on screen at the hub.
- Frame rate was **not measured properly**. Single readings during the capture run ranged from 7 to 63 frames per second at 1080p on the development desktop; they were taken moments after scene changes and include the unfinished graphics pass (issues I-36, I-37).

## 8. Remaining defects and limits

Found and fixed during integration:

- **The four outside doors could not be entered from outside.** The sampled terrain dipped next to the building and left a step taller than the player can climb. The grid is now levelled around the rooms (E-22); the door test then passed 24 of 24.
- **Step climbing pushed the player forward** on small bumps. Fixed (lift only).
- **A method named `set_identity` hid Godot's own `Node3D.set_identity`.** Renamed `set_crew_identity`.
- **The worker's jump was 0.22 m**, which hides the low gravity. Now 0.5 m (E-21).
- **Esc was handled twice** (body and game). The game now owns it: close a panel, otherwise pause.
- **Godot tried to import the rig's source `.blend`** and stopped importing. `assets_src\` now has a `.gdignore`.

Open:

1. **Character art is a first build**: rigid suit joints, mitten-like gloves, liners visible through gaps at hips, knees and ankles, hard shading seams on the coverall, simple block boots, one face for all four crew. Not approved by the owner (I-04).
2. **No human playtest** of movement, camera or controls.
   - Rig details the build itself reports: the hand anchors sit about 24 mm off the hand surface (found after the model was written; see `rig\PROVENANCE_ADDENDUM.md`); seated feet are about 10 mm above the ground.
   - Rebuilding: `tools\blender\character\build_character.ps1` writes a new revision folder next to the model instead of replacing it. Copy the new `astronaut.glb` over `assets\characters\astronaut.glb` and delete the revision folder, or Godot will import both. The folder also still holds the superseded pipeline scripts (`character_pipeline*.py`, `pipeline_resolved_v*.py`); `build_character.py` is the current one.
3. **Outdoor collision is incomplete** (I-38): rocks, glass-hall frames and the garden dome shell can be walked through.
4. **Doors are automatic for everyone**; no airlock logic (I-39).
5. **Only three rehearsal crates can be carried.** Map props are fixed.
6. **`seated` has no use; `land`, `use` and `suit` are simple timed one-shots**, not blended with walking.
7. **The first-person camera sits 0.1 m in front of the head pivot** so that looking down shows the chest rather than the inside of the collar. With the rig, looking straight down still shows mostly the chest; arms only enter view when a clip raises them.
8. **Interim presentation**: plain-text HUD, keys 1 to 4 for crew switching, a plain list for the power panel (I-41).
9. **Engine errors at quit** in a windowed run of the full scene (I-43).
10. **The hub is a rehearsal position** in the Med Bay (I-06), not at the landed spacecraft as the brief wants (PW-05).

## 9. Contradictions and decisions

Decisions E-21 (movement tuning), E-22 (terrain levelling), E-23 (interim crew keys and power list), E-24 (fixed map props) in `..\..\decisions.md`. No new contradiction between sources.

## 10. Missing inputs — requests to the owner

- Approval or replacement of the character and suit assets (I-04), and whether four distinct bodies or faces are wanted.
- The hub room and the start position (I-06, PW-05), with the improved map (I-02).
- A list of routes that must be walkable ("approved routes"), if a specific list is intended.
- A human playtest of movement and camera, ideally with a child in the target age range.

## 11. Dependencies for the next milestone (Prompt 05)

- Station actions: register them with `ActionService.register`; `PlayerController` already sends `use_station` for every station other than the suit rack, and `GameMain._submit` is where a station's panel is opened.
- The HUD is `scripts\game\game_hud.gd`; it reads state for display and listens to events.
- A crew screen should send `claim_character`; the hub rule is already enforced by the host.
- A settings screen can call `PlayerInput.rebind`, `reset`, `save`.

## 12. Optional suggestions (not requirements, not acted on)

- Give each specialist a different head or hair shape from the same bundle before investing in faces.
- Add simple box colliders for the largest rocks and the hall frames before the rover milestone.

## Change after handoff (2026-11-11): Mixamo walk on the player

- The owner supplied `Walking.fbx` (Mixamo, skeleton only, 32 frames at 30 fps). Copied to `mars_colony_godot\assets_src\characters\anims\Walking.fbx`.
- `tools\blender\character\retarget_mixamo_walk.py` retargets it onto the 23-bone astronaut rig. Each bone follows the source bone's world rotation after a rest-pose correction from T-pose. Root motion is removed (1.648 m per cycle, 1.545 m/s). The hips height is set per frame so the legs' lowest point stays at rest height (0 mm residual). The script replaces only the `walk` clip, saves `astronaut.blend` and re-exports `assets\characters\astronaut.glb`. Backups: `assets_src\characters\astronaut_pre_mixamo_walk.blend/.glb`. Report: `anims\walk_retarget_report.json`.
- `PlayerVisual.WALK_CLIP_SPEED` = 1.545 m/s. The controller plays `walk` at ground speed / 1.545, clamped 0.5–2.5×: 1.94× at the 3 m/s walk, lower in the suit. `speed_scale` is now set on every `play()` call. Sprint, carry and the other clips are unchanged.
- Checked: all 7 test suites pass (301 checks). `tools\godot\capture_walk.gd` (windowed) shows `walk` looping in third person, at 1.94× and 3.00 m/s on open ground.

## Change after handoff (2026-11-11): crew character v2 from the owner's base mesh

- **Owner's instruction:** use `simple-low-poly-character.zip` (`PlayerCharacter.fbx`: one unrigged low-poly man, 2,828 tris) for all character models, styled after the owner's orange-astronaut screenshots. Copied to `assets_src\characters\crew_v2\`. The owner's approval of this base settles I-04 for the body.
- **References:** 11 views of an unsuited crew member made with Codex image generation in `assets_src\characters\refs\crew_unsuited\generated\`: T-pose from the front, back, both sides, top and bottom, plus arms-down views and a face close-up. Web search was unavailable at the time. The generated patch shows a NASA-like logo, which was not copied; the model uses a plain crew-colour patch.
- **Build:** `tools\blender\character\build_crew_v2.py`, run in the live Blender through the MCP. It scales the base to 1.80 m and re-centres the 23-bone rig's arm and leg joints in the new limbs. The skin is auto-weighted and the clothing shells get their weights by data transfer. The crew member is dressed in a teal flight suit with long sleeves, a belt seam, a shoulder patch (`Mat_Ident`) and simple eyes and brows. The spacesuit is the skin body pushed out 3–3.5 cm (same weights), with orange panels, white stripes, gloves and boots, dark knee and elbow pads, a helmet with see-through visor, a neck ring and lamps, a backpack with two tanks and light strips, and a chest panel with a screen. It is split into the existing contract names (`Body_Head/Torso/Arms/Legs`, `Suit_Torso/Arms/Legs/Helmet`). Total 4,550 tris; `astronaut.glb` went from 2.05 MB to 0.65 MB. All nine clips are kept, and the Mixamo walk was re-retargeted onto the new rest pose. Source: `assets_src\characters\crew_v2\crew_v2.blend`. The previous model is kept as `assets_src\characters\astronaut_v1_mixamo_walk.glb`.
- **Fix found on the way:** parked crew were created in first-person mode, so their heads were hidden from the first-person camera. `game_main.gd` now sets `set_first_person(false)` on them.
- **Evidence:** `docs\milestones\04_player\crew_v2\turnaround\` (sheet_rest.png, sheet_poses.png) and `crew_v2\game\`. All 6 suites pass (301 checks).
- **Open:** suit stripes follow the low-poly faces, so their edges are stepped; the body under the suit is hidden rather than proven to fit in every pose; the four crew share one face and hair.

## Change after handoff (2026-11-11): own walk and sprint, suit prompt, tunnel doors, glass hall walls, first-person view, display suits

Owner report: the walk could be better and the legs were too far apart; no "press E" prompt at the suit rack; the airlock's outer door would not open and the walls near it could be walked through; looking down in first person showed the inside of the body; display suits should be the new suit.

- **Walk and sprint:** `tools\blender\character\make_gait.py` keys both cycles from a few gait settings (step length, stance time, foot spacing, hip bob and sway, pelvis and chest turn, arm swing, heel and toe roll). The feet are placed first and the legs reach them with two-bone IK. Cause of the wide legs: the rig's hip joints sit 0.24 m from the centre line, so the retargeted Mixamo walk hung the feet about 0.48 m apart; the new cycles keep the ankles 0.24 m apart. Walk: 16 frames, 0.667 s, 1.607 m/s at speed 1. Sprint: 14 frames, 0.583 s, 3.248 m/s. The controller now speed-scales sprint as well as walk (`PlayerVisual.SPRINT_CLIP_SPEED`). The Mixamo walk is kept in `crew_v2.blend` as `walk_old` but not exported. Renders: `crew_v2\walk_v2\blender_walk_sheet.png`, `blender_sprint_sheet.png`; in game: `walk_v2\walk_sheet.png` (3.00 m/s, ×1.87).
- **Suit prompt (and every console):** the look ray stopped on a station's own collision box before reaching its sensing sphere, which also sat at floor level. `PlayerController.aimed_target()` now treats a hit on a station object's box as the station, and the spheres are raised 1 m. The prompt now shows at the suit rack, colony computer, comms, power panel, med station and greenhouse console.
- **Tunnel doors and glass hall:** the colony's glass hall, its exit tunnel and the tunnel's two sliding doors are scenery in the environment file, not manifest objects, so they had no collision and the doors were part of one static mesh. New `scripts\world\environment_collision.gd` (called from `GameMain`) makes the hall glass, portal and tunnel solid (two-sided trimesh) and cuts the four door leaves out of `SFX_tunnel_inside` into two `DoorController`s (ids 901 inner, 902 outer). Checked by walking: both doors open and pass both ways (52/52 doors), the glass stops the player from inside (z 11.98) and outside (x −12.62).
- **First-person look-down:** the eye's forward offset turned with the pitch, so looking down moved the eye into the chest. `PlayerCameraRig` now keeps the offset level and adds up to 0.2 m more forward when looking down (0.3 m at most, inside the 0.32 m capsule).
- **Display suits:** new `scripts\world\suit_displays.gd` cuts the old white suits out of the suit rack and the two suit stands when the game loads and hangs an empty crew suit (no head, no idle motion, crew-colour patch) in each place, facing the room.
- **Evidence:** `crew_v2\fixes\` (rack, stands, first-person, doors). All 6 suites pass (301 checks). New diagnostic tools: `tools\godot\diag_game.gd` (stations aimable, every door walkable), `diag_walk_lines.gd`, `capture_at.gd`, `diag_collision.gd`, `diag_find_at.gd`, `diag_list_under.gd`, `diag_mesh_parts.gd`.
- **Open:** the hall frames, curb and outdoor scenery still have no collision; the new suits are not playtested by a person; the airlock has no pressure cycle, so both tunnel doors can be open at once.

## Change after handoff (2026-11-11): airlock pressure cycle, owner's Mixamo walk restored with narrow feet

- **Airlock:** the exit tunnel's inner (901) and outer (902) doors are paired (`DoorController.partner`). A shut door opens only after the other has been fully shut for `cycle_seconds` (2.5 s); while it waits the HUD says "Airlock cycling: the other door must stay shut. Wait N s." Someone standing where both doors sense them gets the inner door. `tools\godot\diag_airlock.gd` walks through both ways: 0 frames with both doors open, 2.5 s wait each way, player reaches the far side. Evidence: `crew_v2\airlock\`.
- **Walk:** the owner asked to use their `Walking.fbx` again (same file as before). `retarget_mixamo_walk.py` now places each ankle where the Mixamo ankle is relative to the Mixamo hips (scaled to the rig) and reaches it with two-bone IK, knee bending like the source knee; feet keep the retargeted rotations (`--wide` gives the old behaviour). Ankle gap 0.15–0.23 m instead of about 0.48 m. 32 frames, 1.0667 s, 1.545 m/s; plays at 1.94× at 3 m/s. The hand-keyed walk is kept in `crew_v2.blend` as `walk_handmade`. Evidence: `crew_v2\walk_v3\`.
- **Frame rate:** importing the FBX sets the scene to 30 fps, so the hand-keyed sprint (14 frames) lasts 0.467 s and covers 4.06 m/s; `SPRINT_CLIP_SPEED` = 4.06 and `make_gait.py` now times clips at the scene rate.
- All 6 suites pass (301 checks).

## Change after handoff (2026-11-12): every rigid object is solid (collision v2)

Owner report: the player could stand half inside a dark ribbed wall with a rover beside it (the 3D-printed garage `sf_print_garage` with `sf_rover` inside, north of the airlock tunnel), and "all the walls near it are walkable".

- **Audit** (`tools\godot\diag_uncovered.gd`): 2,941 visible meshes in the loaded game. For each, up to 48 points on its near-vertical faces between 0.1 and 1.9 m above the ground were tested for collision within 0.25 m. Before the change 267 meshes had less than 60 % of that surface covered: the 24 glass-hall frames and the hall curb, the garden-dome shell, the printed garage, both rovers, the lander and launch tower, the tank farm, blast walls, light masts, the comms dish, the antenna, solar trackers, crash-site wreckage, beacons and junction boxes outside; and indoors the pipe-gallery rack, crane, workbench, colony computer, crops and trees, planters, lockers, tanks, consoles, desks and other furniture. The final audit uses a fairer test: collision counts if it lies up to 0.6 m in front of the surface or 0.25 m behind it, from either side. By that test 110 meshes remain. 92 are roof and ceiling pieces above head height and 3 are pendant lamps. The rest have authored boxes or ring walls standing further out than 0.6 m (tank farm, comms dish, launch tower, crash site, crops, colony computer), so the player stops before the surface. The garden-dome glass sits behind its ring wall. Walk tests confirm the dome walls stop the player from inside (x 54.5) and from outside (x 58.6, z 35.7).
- **New `scripts\world\prop_collision.gd` (`PropCollision`)**, called from `GameMain` after the ground is added. It goes through every visible mesh of the world and gives it collision unless it is excluded. The rules are generic; there is no list of object names.
  - **Excluded:** manifest floors and doors; door leaves moved by a `DoorController` (including the tunnel airlock 901/902); terrain tiles (the height field covers them); rocks (`RockCollision`); the hall glass, portal and tunnel (`EnvironmentCollision`); manifest objects whose authored `colliders.json` boxes already fill at least 80 % of the object between 0.05 and 1.9 m (kept as authored, including stairs, walls and most furniture); manifest objects whose authored boxes reach into a doorway (door frames and walls with openings); ground decals, gouges and sand drifts (detected by material); skinned meshes (the display suits, whose racks are solid already); cloth curtains; anything with "stair" in its name; anything under 0.1 m or flatter than 3 cm; anything whose bottom is more than 2.2 m above the ground under it (ceilings, pendant lamps, roofs). Also not touched: the player and crew bodies and carry crates (they are not part of the world).
  - **Compact meshes** (up to 4.5 m across and 3.5 m tall, and not reaching into a doorway passage) get one convex hull, computed once per shared mesh. That gives 148 hulls, including the hangar rover, crops, trees, furniture and machines.
  - **Everything else** gets a two-sided trimesh (`ConcavePolygonShape3D`, `backface_collision`) of its own triangles, cut to those reaching below 3 m above the ground. That gives 90 trimeshes with 1.04 M triangles: the hall curb and frames, the garage, the garden-dome shell, the lander and tower, the solar trackers, blast walls, the pipe rack, the outdoor rover `sf_ltv`, and frames around doors. Openings and interiors stay as modelled.
  - All shapes are on the `WORLD` layer, so they stop the player, carried crates and the camera spring arm. They carry `object_name` metadata, so looking at a station's hull still counts as looking at the station.
- **Startup cost:** working out and baking the shapes takes about 1.7 s, and creating the physics shapes about 1.0 s. The baked shapes are cached in `data\prop_collision_cache.bin` (38 MB, git-ignored). The cache is rebuilt automatically when any input changes: the GLBs, manifest, colliders, height grid, the world scene, or one of the collision scripts. With a valid cache, the step adds about **1.1 s** to loading; on the first run after a map change it adds about 2.7–3.3 s. All times are headless timings on the development desktop.
- **Checks:**
  - `tools\godot\diag_walk_into.gd` walks the real player into every prop shape from 4 sides. Of 440 walks, the player never overlapped a shape (tested with a capsule 8 cm thinner than the body): 353 were stopped and 87 slid round small objects. 386 starts were skipped because they were inside other geometry.
  - Named walks: the printed garage from north, south, west and east stops at the wall (e.g. at z 26.84 against the north wall at 26.5); the hangar rover stops the player at x 21.64; the outdoor rover `sf_ltv` stops the player at x 27.16.
  - `diag_game`: all 52 doors walkable both ways, and station aiming is unchanged (no prop hull is in front of a station).
  - `diag_airlock`: 0 frames with both doors open, 2.5 s cycle each way, player gets through.
  - `test_collision` has 8 new checks in a synthetic scene: a hull stops a walker at a crate face, a two-sided trimesh corridor stops it from inside and outside yet stays open end to end, and a decal, an overhead lamp, a floor and an object already filled by its box get nothing. It now has 40 checks.
- **Evidence:** `collision_v2\` has windowed third-person captures at the stop points. `garage_north_wall_tp.png` and `garage_west_wall_tp.png` show the player against the printed garage's ribbed wall. `hangar_rover_tp.png` shows the player stopped at the hangar rover's rear. `ltv_rover_tp.png` shows the player stopped at `sf_ltv`.
- **Tests:** all six suites pass: `test_saves` 56, `test_session` 91, `test_game_services` 25, `test_collision` 40, `test_player` 90, `test_game_scene` 32, which is 334 checks. The counts include tests other workers added in parallel.
- **New tools:** `diag_uncovered.gd` (audit), `diag_props.gd` (lists the built shapes), `diag_walk_into.gd` (walk test, accepts `--line`; use `--fixed-fps 60` for a 2-minute run), `diag_ray_probe.gd` (what a ray at body height hits; `props:` names see only the prop shapes). `diag_game`, `diag_walk_lines` and the other game diagnostics now keep their saves under `_test_saves\diag\` and set `show_menu = false`.
- **Not done / open:**
  - The printed garage is closed all round in the mesh, so its rover can no longer be reached from inside. Before, the player could only get inside by walking through the wall.
  - Hulls are fuller than concave props: there is no walking under desks or between plant rows of one bed.
  - Things above 2.2 m (roof units, ceiling tiles) have no collision, in case a roof is ever made walkable.
  - Display suits rely on their rack's boxes.
  - The cache is written into `res://data`; an exported build cannot write there and simply rebuilds the shapes on every start (about 3 s).
