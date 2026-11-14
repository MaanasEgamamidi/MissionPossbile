# Worker P10B: the drivable rover (Prompt 10, part 2)

Copy: `G:\nasa app\_work\p10b`. Headless only; no git, no downloads, no editor or MCP. Date 2026-11-14.

## What I built (files)

| File | Status | What |
|---|---|---|
| `scripts/vehicle/rover_body.gd` | new, `class_name RoverBody` | RigidBody3D with one ray-cast spring/damper per wheel (6), Mars gravity applied in `_integrate_forces`, drive / brake / rolling resistance / lateral grip limited by `traction_mu` x normal load (friction circle), Ackermann steering on front and counter-steered rear pair, speed-dependent steering lock, anti-roll pairs, low custom centre of mass, empty battery = no drive force; kinematic follow mode for network copies; pose helpers (live pose <-> saved JSON pose, validation). |
| `scripts/vehicle/rover_presenter.gd` | new, `class_name RoverPresenter` | Scene side: builds the body from the map's `sf_rover`, hides the map mesh and draws a copy in the body, switches off `sf_rover`'s static boxes, moves its 7 fixture lamps onto the body, clears the parking footprint in the garage trimesh (see "Garage floor object"), seats (E in / E out with exit clearance checks), seated bodies of other players, HUD widget, network roles and pose, host energy accounting. |
| `scripts/vehicle/rover_hud.gd` | new, `class_name RoverHud` | HUD widget under `GameHud`: bottom-right panel while seated (speed m/s and km/h, battery kWh and %, honest range from `RoverModel.stats().range_km`, cargo kg of capacity, seat list, keys, empty-battery warning); cue under the crosshair when looking at the rover. |
| `data/rover.json` | new | Geometry (body frame), choice evidence, wheels, collision boxes, cabin, 4 seats, 6 exits, cargo bay, `enter_distance_m`, garage park pose, garage clear box, tuning (all `game_tuning`). |
| `tools/godot/rover_drive_check.gd` | new | Headless driving harness: `run()` (full game scene WITH the map, scripted key presses only), `print_table()`, and `-- --inspect` (prints the map evidence: tyre clusters, cabin probes, garage and rover colliders). |
| `tests/test_rover_drive.gd` | new | 62 checks: pure, the drive, network. Contains the stand-in `rover_enter` / `rover_exit` (see below). Option `-- --net-only`. |
| `scripts/player/player_controller.gd` | shared, small edit | seat / stand / vehicle target (details below) |
| `scripts/player/player_camera_rig.gd` | shared, small edit | seated eye height and chase arm (details below) |
| `scripts/player/player_visual.gd` | shared, small edit | stand-in seated legs point forward (2 lines) |

Nothing else was changed. `project.godot` untouched.

### Shared-file edits (for the three-way merge)

`player_controller.gd`:
- new signal `vehicle_interact(vehicle: Node)`; new vars `_seat`, `_collider`, `_standing_layers` (`_collider` is assigned in `setup()` right after `add_child(collider)`; the collider stays child 0, as `test_player` expects).
- new funcs `sit(anchor, vehicle, eye_height, chase_length)`, `stand(world_position, yaw)`, `is_seated()`, `seat_anchor()`, `view_yaw()`, `_follow_seat()`, `_process()` (follows the seat each drawn frame), `_seated_step()`.
- `aimed_target()`: returns empty while seated; a collider with meta `vehicle_id` is `{"kind": "vehicle", "id", "node"}`.
- `_physics_process()`: `if is_seated(): _seated_step(); return` at the top. Seated: Tab still toggles the view, E emits `vehicle_interact(null)`, no movement / jump / sprint / grab, body follows the seat, plays `seated`, reports the seat position.
- `_interact()`: `if target.kind == "vehicle" and held_item() == null: vehicle_interact.emit(target.node); return` before the station logic (hands full: E still puts the item down, as before).

`player_camera_rig.gd`: vars `_standing_eye`, `_standing_arm`, `_seated`, `_vehicle_rid` (set in `setup()`); funcs `set_seated(on, eye_height, chase_length, vehicle)` (eye drops to the seat's head height; third person becomes a 7.5 m chase arm that excludes the rover body; `false` restores 1.65 m / config distance), `is_seated()`, `spring_arm()`.

`player_visual.gd`: the procedural stand-in's `seated` legs used `-PI/2` (legs pointing backwards, the stand-in faces -Z); now `PI/2`. Only used when the rigged astronaut is missing. (Observed, not changed: the stand-in's `carry` arms at `-1.1` also swing backwards for the same reason.)

## Which rover, and why (evidence)

`sf_rover` (Exterior) is the drivable rover; its garage is `sf_print_garage`. Measured headlessly (`rover_drive_check.gd -- --inspect`, `colliders.json`, manifest):
- `sf_rover` stands inside `sf_print_garage` (same rotation, origin 0.3 m from the garage origin). The garage's open side (posts at local x +-2.7, a 3.8 m opening) faces the rover's front, so it drives straight out onto the open ground (world +x). Track 3.0 m (3.1 m with the wheel-block box): 0.35 m clearance each side in the door.
- 6 tyres (material `rubber`): three per side at mesh z -1.55, 0, +1.55, x 1.1..1.5, radius 0.525 m.
- Hollow cabin: floor y 0.88, ceiling ~2.74, inner half width 1.15 m, 4.8 m long. No seat geometry. Windows (`sf_win`) are the opaque `colony_surface` shader with back-face culling: from inside the walls at window height are not drawn, so the seated driver sees out; from outside the cabin is opaque.
- `hb_rover` (Hangar) is 2.2 m wide inside the pressurised hangar whose widest door is 1.36 m (door 2): it cannot reach the exterior; it has 2 webbing seats. `sf_ltv` (Exterior) was not a candidate in the spec.

P10A must put the garage station on `sf_print_garage` (`data/rover.json` `garage_object`). Caution for P10A / executor: the garage's origin (world 8.0, 23.0) is under the parked rover, so a station sphere placed at the object origin sits inside the rover's cabin box and cannot be aimed at from outside; give the garage station an explicit `position` beside the rover (for example by the side wall, world about (8.0, 0, 25.4), 1.4 m clear of the rover side).

## Design decisions

- **Body frame**: origin on the ground under the middle axle, -Z forward. The map mesh's authored front is +Z, so the drawn copy is turned 180 degrees (`mesh_yaw_deg`). `state.rover.pose = {"position": [x, y, z], "quat": [x, y, z, w]}` is this frame; exits and seats are offsets in it: `world = position + quat * offset`.
- **Seats (flag)**: the model has NO seats. Four seat anchors stand on the cabin floor, two rows: driver front-left (-0.57, 0.88, -1.2), front right (0.57, 0.88, -1.2), rear (-+0.57, 0.88, 0.3). Bodies sit on invisible seats (the rig's real `seated` clip, authored for a 0.45 m seat: hips 0.50 m above the anchor). The seated legs splay (toe bones +-0.54 m to the side): neighbours' boots may touch at the centre line (about 2 cm between toe bones) and the outer boot may touch the side wall. Seated eye height 1.29 m above the anchor (measured from the clip's Head bone + 0.18 m, as standing).
- **Seated pose**: real rig clip `seated` (no substitute). Local player: first person at the seat's head height (head hidden as usual, torso, arms in the clip's lap pose and legs visible); Tab = chase camera 7.5 m behind with SpringArm3D collision that ignores the rover's own body. Hands are not on a steering wheel (there is none).
- **E handling**: I chose "a target entry aimed_target() can see": the RoverBody carries meta `vehicle_id`, `aimed_target()` returns kind `"vehicle"`, the controller emits `vehicle_interact`, the presenter decides. Standing: driver's seat if free, else the first free passenger seat; client-side refusals with plain words for not built / hands full / all four seats taken. Seated: refused while moving faster than 0.8 m/s ("Stop the rover before getting out: hold Space."), else the first exit whose standing capsule (r 0.22, 1.8 m) is clear of map, doors, props and people and has ground within 0.8 m of the exit point; all blocked -> "Every way out is blocked. Drive a little way into the open, then press E again." and stays seated. Requests: `services.request(&"rover_enter", &"", {"seat": i})`, `services.request(&"rover_exit", &"", {"exit_index": i})` (target empty).
- **Seat state comes only from `state.rover.seats`** (host-validated). The presenter sits / stands the local player when its id appears / disappears; out of the seat it stands at the exit it asked for, else (freed by the host for another reason: recovery, reload) where the host put the character if that is more than `enter_distance_m` away, else at the first clear exit.
- **Other players' seated crew**: drawn by the presenter in the seat (own PlayerVisual with rig, suit, identity, name tag, seated clip); GameMain's walking copy is hidden and its door-sensing Presence body switched off while seated, restored on exit.
- **Collision**: RoverBody on layer WORLD (people, props and the aim ray meet it), mask WORLD | DOOR | ITEM (not PLAYER: it never pushes a person; a person standing in its way is pushed out by their own move_and_slide). Boxes from `colliders.json` turned into the body frame; the wheel block is raised to start 0.42 m up so the ray suspension carries the rover. The map copy's 3 static boxes are disabled at load.
- **Garage floor object**: the garage mesh has a black floor object (cable or hose, mesh `black`, up to 0.91 m, garage local x 0.98..2.52, z -1.82..-0.28) under the parked rover's left rear wheels. As part of PropCollision's garage trimesh it trapped the rover (first drive: the body could not leave its spot). The presenter drops the 212 garage-trimesh triangles whose centre lies inside the parked rover's box (`garage_clear_box`, 0.12..3.0 m above the wheels' ground) at load; the garage pad floor below stays. A person can now walk through that cable inside the garage.
- **Network** (as specified): roles DRIVE (seat 0 is this machine's character: simulate, send pose ~20 Hz via `send_motion_extra("rover", pose)`; host drives: straight into the broadcast), PARK (host, nobody drives or the driver's character has no owner: simulate with the brake held), FOLLOW (kinematic copy eased toward the newest pose, extrapolated by velocity up to 0.25 s, snap beyond 5 m). Host accepts a pose only from the peer whose character sits in seat 0, valid (finite, unit quaternion, speeds < 100 m/s) and within 2 m + (2 x top speed + 2) x elapsed of the last; stores `state.rover.pose` (10 Hz) and serves `net.motion_extras_provider` = `{"rover": pose}`. Clients without extras for 1.5 s follow the replicated `state.rover.pose` (late join). The 5 Hz state never moves the body while extras arrive.
- **Energy**: the host counts distance from the authoritative pose stream (own body or accepted driver poses), steps under 2 cm ignored (settling), and once a second calls `note_driven(state, events, distance_m, net climb_m)`. Lookup at run time: if `res://scripts/vehicle/rover_system.gd` exists and has `note_driven` (static: called on the script; instance method: on the RoverSystem found in `session.sim.post_systems`), it is used; else a fallback takes `RoverModel.energy_kwh_for_move(levels, cargo, d, climb)` from `rover.battery_kwh` (never below 0). Zero battery -> no drive force; coast and brake work.
- **Mass**: `RoverModel.stats(levels, cargo).mass_kg`; if it does not grow with the cargo the presenter adds the cargo mass itself; plus 160 kg per occupied seat.
- **Menus**: when a panel takes the keyboard while driving, the rover holds the brake rather than roll on.

## Numbers and their categories

All vehicle numbers are **fictional game tuning (`game_tuning`) supported by real principles**, not NASA rover specifications. Measured map geometry is labelled "measured from the map mesh" in `data/rover.json`. Mars gravity 3.73 m/s2 is the existing `GameConfig.MARS_GRAVITY` (NASA fact sheet, source N01).

| Value | Number | Category / reason |
|---|---|---|
| suspension sag | 0.06 m | game tuning: spring rate k = m g / (6 x sag), natural frequency sqrt(g / sag) = 1.3 Hz |
| travel / bump stop | 0.25 m / 0.18 m | game tuning |
| damping ratio | 0.55 | game tuning |
| anti-roll ratio | 0.6 of k | game tuning |
| centre of mass | 0.55 m up | game tuning: batteries in the floor; static stability factor 1.3/0.55 = 2.4 |
| steering | 30 deg full lock up to 1.5 m/s, fading to 9 deg over the next 6 m/s; 110 deg/s | game tuning; Ackermann on one turn centre |
| rolling resistance / coast drag | 0.05 / 0.25 m/s2 | game tuning |
| reverse top speed | 40 % of top | game tuning |
| lateral stiffness | 0.6 | game tuning (fraction of the side slip cancelled per step) |
| crew mass | 160 kg per seat | game value for a suited adult, not a cited suit mass (P10A's energy model has its own crew assumption) |
| pose rate | 20 Hz | engineering default (NetSession.MOTION_HZ) |
| chase camera | 7.5 m | game tuning (rover is 5.7 m long) |

## Driving table (headless, real map collision, 60 Hz physics, P10A's STUB RoverModel)

`RoverModel` here is the interface stub (top 3.0 m/s, 1500 N, mu 0.6, 900 kg, battery 10 kWh, 0.0002 kWh/m). Numbers change once P10A's model is merged; the test bounds are written relative to the stats.

```
TABLE physics 60 Hz, Mars gravity 3.73 m/s2; stats (RoverModel) top 3.00 m/s, drive 1500 N, mu 0.60, mass 900 kg (+160 kg crew aboard); accounting: fallback: RoverModel.energy_kwh_for_move
TABLE settle      origin y 0.098 m, 6/6 wheels down, tilt 0.0 deg
TABLE straight    0 -> 2.70 m/s in 2.33 s over 3.2 m (left the garage at x 20.9)
TABLE cruise      full throttle on the open straight: 2.94 m/s over the last 10 m, peak 2.96 m/s (top 3.00 m/s)
TABLE braking     from 2.95 m/s: 2.05 m in 1.38 s (friction limit 1.95 m at mu 0.60)
TABLE tight turn  radius 2.69 m at 1.36 m/s, full lock (steering geometry 2.68 m), 395 deg in 14.7 s
TABLE cargo       0 -> 2 m/s: 2.32 s at 1060 kg, 5.43 s with 800 kg more (1860 kg)
TABLE no battery  full throttle 3 s: moved 0.004 m, speed 0.001 m/s
TABLE long route  garage -> sf_crash_shield (front 5.0 m from its centre, 3.3 m from its side) -> dunes -> rocks -> garage: 238.0 m in 141.7 s, energy 0.0476 kWh (charged 0.0476, counted 237.9 m), height -0.23..3.12 m, stuck 0, flips 0, back in garage: true
TABLE rough       dunes and rock field: 180.3 m, height -0.23..3.12 m, max tilt 26.9 deg, wheel contact 99.4 %, stuck 0, flips 0
TABLE exits       clear when parked [true, true, true, false, true, true]; all boxed -> first clear -1, still seated true; box 2 removed -> first clear 2, out true (0.00 m from the exit)
TABLE four seats  ["crew_1", "crew_2", "crew_3", "crew_4"], taken seat refused true (already_held), seated bodies 3 at seats (worst 0.000 m), crew mass +640 kg
```

Route (one continuous session from the garage park pose, E to board, only key presses; a harness "driver" turns waypoints into W/S/A/D/Space): out of the garage east, north along x 23 (cruise, brake, tight turn, cargo and empty-battery runs), west to the donor `sf_crash_shield` (stop beside it, back off 8 m), round the crash debris field east, north to z 66, west up the dune to about 3 m height (slope ~17-20 deg), down, east, south through the small-rock field at x 30-33 (rocks 0.2-0.37 m), west through the rocks by the garage door and forward into the garage. The stub's 1500 N on 1060 kg can climb about 22 deg under Mars gravity; a weaker or heavier P10A build may stall on that dune.

Bounds in the test and why: 90 % of top speed no sooner than the force law allows and within 2.5 x that; cruise > 90 % of top and peak < 105 %; braking distance between 0.9 and 1.6 x the friction limit v^2 / (2 mu g); turn radius 0.8..1.6 x the steering geometry (at 1.5 m/s the side force is far below mu g); 800 kg slows 0-2 m/s at least 1 + 0.7 x (mass ratio - 1); empty battery moves < 5 cm; donor reached within 4 m of its box; back inside the garage footprint; route > 150 m; 0 stuck, 0 flips, tilt < 30 deg, wheel contact >= 90 %; host-counted distance within 5 % of the path; charged energy = battery drop; saved pose within 0.2 m of the body.

## Test results (my copy, 2026-11-14)

`tools\run_tests.ps1 -Import -Tests test_rover_drive,test_saves,test_session,test_game_services,test_progression,test_science,test_life_support,test_net,test_net_game,test_station_panels,test_player,test_collision,test_game_scene`:

| Suite | Result |
|---|---|
| test_rover_drive (new) | 62/62 (about 85 s; drive ~60 s real time) |
| test_saves | 56/56 |
| test_session | 91/91 |
| test_game_services | 25/25 |
| test_progression | 84/84 |
| test_science | 76/76 |
| test_life_support | 88/88 |
| test_net | 34/34 |
| test_net_game | 20/20 |
| test_station_panels | 108/108 |
| test_player | 112/112 |
| test_collision | 40/40 |
| test_game_scene | 32/32 |

Compile check (`--script res://tools/godot/check_compile.gd`): `COMPILE OK 168 scripts`. Baseline before my changes: the same 12 existing suites all passed with the same counts. No existing check was changed. (One rename inside my own suite: the runner's case-insensitive `SCRIPT ERROR` filter matched my check title "no engine or script errors", so it is now "clean run: the engine error log stayed empty".)

The prop collision cache (`data/prop_collision_cache.bin`) is only read, never rewritten, by these runs (none of its inputs changed).

## Stand-ins (test only)

`tests/test_rover_drive.gd` `install_stand_ins(session)` registers minimal `rover_enter` / `rover_exit` with the fixed ids and params **only if the session has no definition of that id**, marked "STAND-IN UNTIL P10A MERGES". After the merge the same tests exercise P10A's real actions. My stand-ins check: built, seat free, actor not already seated, actor within `enter_distance_m` (6.0 m) of the pose; exit: actor seated, index in range, sets `actor.position = pose + quat * offset`. `rover_drive_check.gd` run standalone loads them from the test script.

## Limits (honest)

- **No seat meshes** in the model: four invisible seat anchors (flag above). Seated boots may touch each other / the wall slightly.
- **The tyres are part of the single map mesh**: they do not spin, steer or move with the suspension on screen; on uneven ground a wheel can look sunk or lifted by a few cm.
- **The cabin is opaque from outside** (the map's window material is opaque): seated crew are drawn at their seats on every screen, but nobody outside can see them through the windows. No entry hatch animation: E moves you into the seat.
- Driving was verified only headlessly (physics, positions, HUD text). Nothing was looked at on screen: camera framing, the first-person view through the cabin, the seated pose inside the cabin, the HUD layout at 1280x720 and the lamps on the moving rover are **not visually verified**. The HUD widget was not added to `UiLayoutCheck` / `test_station_panels` (it is not a station panel).
- Driving checks use P10A's **stub** `RoverModel`; real stats change the numbers (bounds are relative to them).
- The garage trimesh triangles inside the parked rover's box are dropped at load (the floor cable no longer blocks people there).
- Network was tested in one process over ENet on 127.0.0.1 (two game scenes, no map), not on two machines or a real LAN.
- **Observed in NetSession (not my file)**: after the client player was teleported and then stood still, the host kept the old position for 15 s; it arrived as soon as the view turned. `send_position` sends only when the pose changes, so one lost unreliable packet leaves a still player's position stale on the host (relevant for every host distance check, including `rover_enter`). The test turns the view slightly until the host has it. Suggested fix below.
- Rover lamps (`FX_sf_rover*`, 7 SpotLights) are moved onto the body; ZoneLighting still switches them with the exterior zone.
- `RoverModel.cargo_mass_kg` is P10A's; the cargo-mass run uses `RoverBody.set_payload(800)` directly.

## Requests for the executor

1. **Wire the presenter** in `scripts/game/game_main.gd` (see next section).
2. **P10A merge**: `rover_enter` / `rover_exit` should take an empty target and use `data/rover.json` `enter_distance_m` (6.0 m from the pose origin) for the distance check, not `interact_distance_m` (2.6 m from the pose origin would require standing inside the rover). `rover_exit` sets `actor.position = pose.position + quat * exits[i].position` (body frame, feet on the ground). Driver disconnect: free seat 0; the presenter then brakes the rover where it is. P10A's garage station on `sf_print_garage` needs an explicit position beside the rover (see above).
3. If another worker also needs `NetSession.motion_extras_provider`, merge into one Callable that returns the union, e.g. `func() -> Dictionary: var d := rover.motion_extras(); d.merge(other.call()); return d`.
4. Optional (NetSession owner): resend the body pose about once a second even when unchanged (`send_position`), so a single lost unreliable packet cannot leave a standing player's position stale on the host.
5. After merging, run `tools\run_tests.ps1 -Import -Tests test_rover_drive,...` again: the stand-ins step aside for the real actions and the numbers follow P10A's model; the drive takes ~60 s real time (4x sped-up 60 Hz physics).

## What to add to `scripts/game/game_main.gd`

In `GameMain` add a member and create the presenter at the end of `_begin_play()` (after the HUD exists and `_rebuild_crew()` has made the player; before `ui.close_all()` is fine):

```gdscript
## Prompt 10: the shared four-seat rover (body, seats, cameras, HUD widget, network pose).
var rover: RoverPresenter
```

```gdscript
	# Prompt 10: the drivable rover, built from the map's sf_rover (works without the map too: collision only).
	rover = RoverPresenter.new()
	rover.name = "Rover"
	add_child(rover)
	rover.setup(world, services, self)
```

It needs `collision`, `hud`, `player` and `_crew_visuals` of GameMain (read by name) and must be a child of GameMain. It sets `services.net.motion_extras_provider` itself. Nothing else in GameMain changes.
