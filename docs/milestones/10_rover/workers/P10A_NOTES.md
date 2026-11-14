# P10A — rover economy, salvage supply, garage configurator (Prompt 10, part 1)

Worker copy: `G:\nasa app\_work\p10a`. Headless only. No git, no downloads, no MCP, no window. Nobody has played any of this.
`config/name` in project.godot was not changed.

## 1. Files

**New (owned):**
- `scripts\core\rover_balance.gd` — `RoverBalance` (Resource, `get_current()`). Every tunable rover number.
- `scripts\vehicle\rover_model.gd` — `RoverModel`. The stub is filled in, and the fixed signatures are kept. It has these optional extra parameters:
  - `stats(levels, cargo_kg, battery_kwh := -1.0, crew := 4)`
  - `energy_kwh_for_move(levels, cargo_kg, distance_m, climb_m, crew := 4)`

  It also has new helpers:
  - stats: `current_stats`, `range_now_km`, `crew_aboard`
  - seats: `seat_of`, `seat_free`
  - pose and geometry: `geometry()` (reads `data\rover.json`), `pose_position`/`pose_quat`, `to_world`, `seat_world_position`, `exit_world_position`, `exit_count`, `distance_to_rover`
  - assembly check: `challenge()`, `check_answers()`, `build_params()`, `encode_answers()`/`decode_answers()`, `levels_from_params()`
- `scripts\sim\rover_system.gd` — `RoverSystem`. A post-system that handles charging, frees seats, and keeps cargo and crew with the pose. It also provides:
  - `note_driven(state, events, distance_m, climb_m) -> float`
  - `note_pose(state, pose)`
  - `free_seat_of`, `in_garage`, `in_charge_reach`, `charge_block`, `charge_reserve_kwh`
- `scripts\session\rover_actions.gd` — `RoverActions`. Contains `rover_assemble`, `rover_refit`, `rover_enter`, `rover_exit`, `rover_load_cargo`, `rover_unload_cargo` and `rover_set_charging`. `rover_preview` is local: it is the panel's sliders, so no request is sent.
- `scripts\ui\stations\garage_station_panel.gd` — `GarageStationPanel`.
- `scripts\ui\stations\rover_charger_station_panel.gd` — `RoverChargerStationPanel`.
- `data\stations_rover.json` — the garage and charger stations.
- `data\model_sources_rover.json` — a category for every RoverBalance field, the supply/demand table and the rejected donor candidates.
- `tests\test_rover.gd` — 80 checks.

**Shared, small edits:**
- `scripts\session\session_service.gd`: `RoverActions.register(actions)` (after WeatherActions) and `sim.post_systems.append(RoverSystem.new())` (after ProgressionSystem).
- `scripts\state\colony_state.gd`: `_empty_ledger` gains `"rover_charge_kwh", "rover_charge_loss_kwh", "rover_drive_kwh", "rover_refit_clamped_kwh"`. Nothing else in the file changed.
- `data\salvage.json`: 9 donors appended. The five existing donors are untouched.
- `data\stations_science.json`: 9 salvage stations appended.
- `scripts\session\science_actions.gd`: **not changed** (data only).
- `tests\test_science.gd`: minimal change (see section 6).

## 2. Which rover and garage, and why

**Drivable rover: `sf_rover`. Garage: `sf_print_garage` (Exterior).**
- **Same place.** Both stand at Blender (8.0–8.3, −23.0), Godot (8.0–8.3, 0, 23.0), and both are turned +90°. The rover's collision is 3.1 × 5.1 m. It sits inside the garage's walls (`data\colliders.json`: walls at ±3.25 m, back wall, and a 3.8 m door at local +z). That door faces world +x, the same way as the rover's headlights (`FX_sf_rover` lights at x 10.73, emitting +x).
- **Outdoor rover.** `sf_rover` has rubber tyres, windows, a solar panel (`sf_pv`) and 74k tris. The track decal `SFX_tracks_garage` belongs to the garage.
- **Where the work is.** Outside are the crash-site donors (20–35 m away) and the sample sites.
- **Why not `hb_rover`.** It stands inside the pressurised Hangar on wheel chocks (`hb_chocks`), with its charge cable (`hb_charge_cable`). It could reach the exterior only through the hangar–airlock door (2.6 m opening) and the walk-through airlock room. It is a maintained, parked utility rover, not wreckage, so it was not made a donor either.

**Garage station:** `{"object": "sf_print_garage", "kind": "garage"}`. Its origin is in the middle of the parked rover. A player standing beside the rover, inside the garage, is 2.0–2.3 m from it, which is within reach (checked against collision boxes in test_rover).

**Charger station:** a new id, `garage_charger`, at Godot (6.2, 0, 20.7). It is not a new mesh. The evidence:
- `sf_cable_g` runs from the base to the garage's north-west corner.
- The garage has a green status light, `FX_sf_print_garage.002` with material `kit_led_grn`, at Blender (6.2, −20.45, 1.27), beside the rover's rear left.

**Fallback park pose:** `sf_rover`'s origin and +90° yaw. **P10B:** if `data\rover.json` names a different object, the garage station must move to that object's garage.

## 3. Interfaces for P10B and the executor

**Params are flat (spec deviation, forced).** `ActionRequest.shape_problem()` allows at most 8 params, and only bool, int, float or text up to 64 letters, with no dictionaries. The spec's `{"levels": {...}, "challenge": {...}}` is therefore always `bad_request`. Use `RoverModel.build_params(levels, RoverModel.challenge(state, levels), answers)`, which gives:
- `speed`, `torque`, `range`, `cargo`, `traction` (int 1–5)
- `seq` (= `rover.refit_seq`), `variant` (= `rover.challenge_variant`)
- `answers`: 4 letters per stat, from `encode_answers({stat: {"module": i, "port": id, "check": i}})`

That is exactly 8 params.

**Other actions:**
- `rover_enter {"seat": 0..3}` and `rover_exit {"exit_index": int}` take no target. `rover_exit` returns `changes.position`. The client's own body keeps its own pose, so **P10B must move the local body to `changes.position`** after a successful exit.
- `rover_enter` puts the character at its seat's world position.
- Entering needs the suit on when `session.outside_test(pose)` is true. In the game this is the zone test, and the garage is Exterior.

**Drive accounting:**
- The host calls `RoverSystem.note_driven(state, events, distance_m, climb_m)`. It uses the actual cargo and crew aboard, never takes more than the battery holds, and keeps `rover.trip` (distance_m, climb_m, energy_kwh, reset when charging starts) and `rover.odometer_m`.
- The host should store driver poses with `RoverSystem.note_pose(state, {"position": [...], "quat": [...]})`. This makes cargo and seated crew follow. If the pose is written straight into `state.rover.pose` instead, the tick still updates cargo and crew.

**Reading `data\rover.json`** (when it exists; else RoverBalance fallbacks):
- seats: `"seats"`
- exits: `"exits"`, `"exit_points"` or `"exit_offsets"`. Entries can be `[x, y, z]` or `{"position"|"local"|"offset"|"pos": [...]}`, in the rover frame.
- park pose: `"garage_park_pose"`, `"park_pose"` or `"park"`, as `{"position": [...], "quat": [x, y, z, w]}` or `"yaw_deg"`.
- `RoverModel.reload_geometry()` clears the cache.

**Seats are freed** at once on `crew_ownership_changed(id, 0)` (disconnect or release) and on `character_recovered`. The tick also frees any seat whose character is parked.

**`stats().mass_kg`** is the rover plus cargo, without crew. `crew_kg` and `total_mass_kg` are also returned. An empty battery gives no drive energy (`battery_kwh` = 0); P10B reads it.

**New state fields** (`state.rover`, filled by `RoverModel.ensure`): `charging`, `charge_status`, `trip`, `odometer_m`, `refit_seq`, `challenge_variant`, `last_refit`, `empty_announced`. The garage and charger are both outside, so their panels show no room-power line.

## 4. Design decisions

**Economy:**
- Step costs are 1/2/3/4 per stat: 10 parts per stat, 50 for all five. There is no cap, and test_rover takes all five stats to 5 (exactly 50 invested).
- Refit cost is `invested(new) − invested(old)`. A negative cost gives parts back. The ledger key `rover_parts_net` counts parts put into the rover minus parts given back.
- The first assembly at level 1 costs 0 parts.

**One-time transactions:**
- Every assembly or refit must name `rover.refit_seq`, and success increments it.
- A duplicate request id gets the stored answer.
- A replay under a new id, or after a load (the host forgets request ids at `begin()`), names a used seq and is refused "out of date". So no refund can happen twice.

**Battery on a refit:**
- A refit never fills the battery.
- On a smaller battery the energy is clamped to the new capacity. The clamped energy is booked in `rover_refit_clamped_kwh`; it "left with the removed modules" and is never created.
- The first build starts with 0 kWh, so the rover must be charged before driving.

**Refusals:**
- A refit is refused with a plain reason when the cargo aboard is more than the new bay holds, when the rover is not in the garage (6 m), or when anyone is seated.

**Assembly check (`RoverModel.challenge`):**
- It covers the changed stats, biggest change first, at most 3. The first build always includes the motor and battery.
- Each stat has three steps:
  - (a) choose the fitting module out of 3 by its clue: voltage, plug, damage, rating, bolt pattern, grip.
  - (b) choose its socket out of 3.
  - (c) a power or load check: current = power ÷ voltage; kWh = V × Ah ÷ 1000; push = torque ÷ radius; which load fits the rating; grip = μ × weight.
- It is seeded from the colony seed, the seq, the variant and each stat's levels, so it is deterministic and the same on every machine.
- A wrong answer returns ok with `assembled: false` and feedback for each step. It moves `challenge_variant` on, which gives new numbers and a new order, and costs nothing.
- The first success records evidence `res_rover_assembly` (sector resources). **No upgrade card requires it yet.**

**Charging:**
- The charger takes `charger_kw` (5 kW) from the colony battery; 90 % reaches the rover.
- Colony battery identity: `now = start + battery_in − battery_loss − battery_out − rover_charge_kwh`.
- Rover battery identity: `now = start + rover_charge_kwh − rover_charge_loss_kwh − rover_drive_kwh − rover_refit_clamped_kwh`.
- Charging pauses ("paused_reserve") at max(35 % of capacity, the energy_battery_reserve life-support reserve). It also pauses on `power_deficit`.
- It stops ("unplugged") when the rover leaves the 7 m cable reach.
- It respects the battery discharge limit.
- For display only, it adds itself to `load_kw` and `served_kw` and subtracts from `battery_kw` for the tick.

**Energy model:**
- Energy = (c·m·g·d + m·g·h) / η. c = 0.15, g = 3.73 m/s² (S01), η = 0.8.
- m = rover + 150 kg per occupied seat + cargo.
- Downhill gives nothing back.
- Distances and heights count **60×** (`map_distance_factor`, balance). The map is about 150 m across, so without this the battery would never matter. The factor does not depend on the sol length.

**Range** (`range_now_km`, "honest"):
- stored energy ÷ (kWh/km × 1.3 terrain factor)
- uses the cargo and crew aboard (at least a driver), with no downhill recovery
- in km of map driving

**Cargo:**
- Anyone may load or unload within 5 m of the rover, or from a seat.
- Item masses (balance): supply crate 25 kg, sample 2 kg, salvaged part 12 kg, other 10 kg.
- Loaded items have `holder = "rover"`, so nobody can `pick_up` them, and their positions follow the pose.

**Garage panel:**
- Five HSliders are the control. Each row shows level now → planned and the parts it costs or gives back. The panel also shows totals, a now/planned stats table (including the range with the cargo aboard) and a battery-not-refilled note.
- The three example builds are text only, not presets.
- The commit button and the check are shown only to the field engineer. Others see "⛏ Only the field engineering and geology specialist…".

**Charger panel:** shows the rover battery, the charging status and its reason, the distance to the rover, the colony battery and its reserve, and the cost per hour and so far. It has a start/stop button.

## 5. Supply and demand (category: balance, checked against the data files by test_rover)

| | parts |
|---|---|
| Start (`GameBalance.parts_start`) | 10 |
| Donors: 5 existing + 9 new = 14; compatible parts listed | 29 |
| Recoverable under the P08 rule (1 per donor; 2 with `res_component_refurbishment`) | 14 / 28 |
| **Supply** (base / max) | **24 / 38** |
| Demand: 16 facility cards (`cost_parts`) | 42 |
| Demand: comms cards (P11: 1+2+3+4; the test switches to the data once P11 merges) | 10 |
| Demand: rover, all five stats at 5 | 50 |
| **Demand total** | **102** |
| Required for the campaign (`comms_radio_1`; sector tiers cost no parts; a level-1 rover costs 0) | 1 |
| **Shortfall** | **64** |

**FLAG: a fully upgraded rover (50) is not reachable from approved map salvage**, even if nothing else is bought. The maximum supply is 38. The campaign itself is not blocked, because it needs only 1 part. No debris was spawned. **Owner decision needed.** Possible ways forward:
- (a) let a donor give every compatible part it lists: +1 → 39. This alone is not enough.
- (b) approve more donor objects, or big-wreck yields (for example `sf_crash_stage` giving 6–8).
- (c) lower the card costs.
- (d) accept that maximum is out of reach. This contradicts the brief's "all stats may eventually reach 5".

**New donors** (all damaged or derelict map objects; each has 2–3 compatible and 2 unusable parts with clues; tests are "illustrative"):
- `sf_crash_stage` (charred, gouged wreck). Its origin is inside its own 6.5 × 5.4 m collision box, so the station is an `id` with the same name, at a clear spot 0.6 m outside the box.
- `sf_crash_shield`
- `sf_crash_debris_a`, `sf_crash_debris_b`, `sf_crash_debris_c` (charred, torn foil)
- `pr_bat_hv_alarm` (alarm screen)
- `pr_bat_rack_alarm.001` and `.002` (the same asset as the P08 donor)
- `gr_rack_fault` (red fault LED, amber screen)

**Rejected candidates:**
- `mb_crash_cart`: a medical "crash cart", working equipment.
- `ls_manifold`: the working life-support manifold; nothing marks it damaged.
- `ex_lander`: the intact 28 m spacecraft on the pad, the arrival vehicle.
- `rf_tile_*_dead`: six ceiling tiles 3.0–4.7 m up, out of reach.
- `hb_rover`: parked on chocks, not derelict.
- `hg_kiosk_dark`: its screen is lit.

## 6. Change to an existing test (rule 6)

`tests\test_science.gd`, `_test_stations` checked that the salvage stations were **exactly** the 5 P08 donors, and its "damaged" wording check did not know "fault". My work adds donors, so the check was wrong for a reason this work makes true. The change:
- The check now requires that the 5 P08 donors are all present (`DONORS.all(... donors.has(x))`).
- The damaged-object check now runs over **every** salvage station, so it is stronger than before, and accepts `"fault"`.
- The two now-unused `want_donors` lines were removed, and the check's name was updated.

Original file: `C:\Users\josev\AppData\Local\Temp\claude\4e8993e10782510e\5c192c8a-2834-44d7-9584-e270f949c170\scratchpad\test_science.orig.gd`.

## 7. Test results (headless, 2026-11-14, this copy)

| suite | result |
|---|---|
| test_rover | 80/80 |
| test_saves | 56/56 |
| test_session | 91/91 |
| test_game_services | 25/25 |
| test_progression | 84/84 |
| test_science | 76/76 |
| test_life_support | 88/88 |
| test_net | 34/34 |
| test_net_game | 20/20 |
| test_station_panels | 130/130 |
| (extra) test_collision | 40/40 |
| (extra) test_p07_panels | 54/54 |
| (extra) test_food | 85/85 |
| (extra) test_weather | 66/66 |
| (extra) test_hud_panels | 89/89 |
| (extra) test_ui_framework | 125/125 |
| (extra) test_sources | 76/76 |

Compile check: **COMPILE OK 169 scripts**.

**Synthetic parts of test_rover** (labelled in the file):
- positions are set by hand
- a test-only fifth character
- "enough parts" is given by hand for the all-level-5 test
- `power_deficit` is set by hand for one direct system step
- one request runs with the outside test replaced, to show that inside needs no suit

## 8. Limits

1. **Nothing has been played or driven.** P10B's body has never called `note_driven` or `note_pose` in my copy, because `data\rover.json` does not exist here. Seats and exits use the RoverBalance fallback offsets.
2. **The garage station is not at the garage door.** Its origin is in the middle of the rover, so it is reached from beside the rover, inside the garage. When the rover is away, the garage is empty and the station is easy to reach.
3. **Freeing seats right after a load.** Within the first tick after a load (~0.2 s), a disconnect frees the seat in the stale state. The next tick frees it from the real state, because the character is then parked.
4. **The charger draws from the stored battery.** It is booked after the power model, from the battery store, not from that tick's solar surplus, and it does not trigger load shedding. It pauses at its reserve.
5. **The 60× map distance factor is a game rule.** The range is shown in km of map driving.
6. **Seated crew positions are moved by the host** when the pose changes. If the client also reports seated positions, both write nearly the same value.
7. **The supply shortfall** (section 5).
8. **The "?" buttons reuse existing explanation ids** (`battery`, `parts`, `cargo`, `load`, `specialists`). There is no rover-specific explanation.

## 9. Requests for the executor

1. **`tests\test_life_support.gd`, `_identities()`**, the battery line. The rover charger then counts in the identity:
   ```gdscript
   		"battery": d[&"battery_kwh"] - (l.battery_in_kwh - l.battery_loss_kwh - l.battery_out_kwh - float(l.get("rover_charge_kwh", 0.0))),
   ```
   It passes unchanged today, because no rover charges in that suite.
2. **P12:** do not put `record` stations on my 9 new donor objects, or on any salvage donor. `StationCatalog.extra_for_object` takes the first matching entry, so a second station on the same object is lost. Use a hook on `inspect_donor` through `events.action_resolved` instead.
3. **P11 merge:** once the `comms_radio_*` cards are in `data\upgrades.json`, test_rover reads their costs from the data. The table must still say 10.
4. **Optional:** add a `"rover"` entry to `data\explanations.json`, and point the garage panel's "?" buttons at it.
5. **Owner question** on the salvage shortfall (section 5).

## 10. Wiring for `scripts\game\game_main.gd`

**None needed from P10A.** There is no presenter, and the panels are found by the `<kind>_station_panel.gd` convention. The session lines are already in `session_service.gd`. P10B's presenter should call `RoverSystem.note_driven` and `RoverSystem.note_pose` on the host, as described in section 3.
