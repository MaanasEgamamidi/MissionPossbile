# Upgrade paths, scout drone and survival realism: handoff (2026-11-14)

Owner request (2026-11-14): give everything an upgrade path with at least 4 visible stages (today's models = V1),
a scout drone that is manually flown first and programmable after upgrades (built in Blender, then Godot), visible
health upgrades, night energy (no sun, fast battery drain), a fast suitless death outside, the cause of death after
each med-bay respawn, and NASA-based resource drain. Built by the integrator plus seven parallel workers to the
spec in `UPGRADES_BRIEF.md`. Branch `revisions` of MaanasEgamamidi/MissionPossbile.

## What the player gets

| Area | V1 (today) → V4 | What the level changes |
|---|---|---|
| Greenhouse (`food`) | single bed layer → 2, 3, then 4 stacked grow trays with LED bars, drip lines, LED canopy | harvest meals × 1 / 1.9 / 2.8 / 3.6 |
| Garden dome (`garden`) | bare planters + new upgrade console → ground cover and herbs → raised bed ring with shrubs → 12 dwarf fruit trees | +0 / 0.5 / 1 / 2 meals per sol; plant O2 0 / 0.01 / 0.02 / 0.035 kg/h (BVAD lettuce rate × planted area) |
| Power (`energy`) | today's room → 2nd rack + big inverter → 3rd rack, cable trays, tracker wings → battery wall, coolant loop, wide wings | solar × 1 / 1.25 / 1.5 / 1.8; battery 700 / 875 / 1,050 / 1,400 kWh |
| Life support | → 2nd scrubber + O2 buffer tank → twin electrolysers + water loop → three tanks, filter bank, labelled pipes | scrubber, O2 production × 1 / 1.25 / 1.5 / 2; recycler × 1 / 1.1 / 1.2 / 1.35 |
| Med bay (`health`) | → vitals monitor + IV stand → 2nd bed + body-scanner arch → surgical light, wall screens, treatment cabinets | healing at the med station × 1 / 1.5 / 2 / 3; respawn health 50 / 60 / 70 / 80 |
| Command room | → wall map screen → relay rack + 2nd screen row → screen wall, holo table, roof dish | drone radio range 150 / 300 / 600 / 1,200 m |
| Scout drone | Blender models V1-V4 (`assets/drone/`): basic quad → bigger battery and rotors → survey camera + antenna → sensor pod, lights, long-range dish | speed 5-12 m/s, flight 90-360 s, survey radius 20-60 m; V1-V2 manual only, V3 autopilot to 1 site, V4 routes of up to 4 sites |
| Crew rover | add-on parts follow its five garage module levels (battery packs, motor housings, axle covers, cargo racks/pods, tread bands; V3 light bar and mast, V4 roll cage) | unchanged: the rover's own module stats |

- Upgrading: at the area's station (greenhouse console, power panel, life-support console, med station, colony
  computer or comms console, the new Garden console, the drone pad) an **Upgrades** strip shows V1-V4 pips, what
  the next level gives, its parts cost and who can do it, and an **Upgrade to Vn** button (host action
  `upgrade_area`). Costs 2 / 3 / 4 spare parts. A pop-up announces each level up.
- Drone: E at the pad (23.5, 0, 18) → E again to fly. W A S D, mouse to turn, Space up, Shift/Ctrl down, Tab camera,
  E hands it back. It warns at 90 % of the radio range and stops at the edge, flies itself home when the battery
  only covers the trip back, and surveys any scout site it passes within its survey radius (reveals ore like the
  scout rover). From V3 tick sites in the pad panel and press Send.
- Survival: walking out without a suit (airlock, tunnel, glass hall wall, the 8-11 m ring around the garden dome,
  the garden airlock with its outer door 912 open) starts the 4-second death; an empty suit tank too. After the
  med-bay respawn a card at the top says what happened ("No suit outside: ...") until E or 12 s.
- Energy: no sun = exactly 0 kW solar. A line under the vitals bar shows the battery, e.g. "☾ Battery 64 % ·
  falling 23.1 kW, ~9 h left". The arrival colony drains about 41 % of its battery per night; a wasteful one runs
  flat before sunrise; low battery sheds lights first and heating/control last.
- NASA rates (source S20, NASA BVAD rev 2, 2022): O2 0.895 kg, CO2 1.085 kg, water 4.48 kg, food 12.778 MJ per
  crew member per day, converted per game hour (÷ 24). See `docs/source_register.md` section 11.

## Code map

- Core: `data/area_levels.json`, `scripts/upgrades/area_levels.gd` (AreaLevels), `scripts/session/area_level_actions.gd`,
  `scripts/upgrades/area_stage_presenter.gd` + `area_stages.gd`, one look per track in `scripts/upgrades/stages/`,
  `state.levels` and `state.drone` in ColonyState.
- Drone: `scripts/drone/`, `data/drone.json`, `data/stations_drone.json`, `tools/blender/drone/build_drone.py`.
- Survival: `scripts/survival/death_reasons.gd`, `med_care.gd`, `CharacterState.last_death` / `hazard_cause`.
- Energy and NASA: `PowerModel.outlook()`, `GameBalance` rates, `data/model_sources.json`.
- UI: `scripts/ui/station_panel.gd` (strip), `scripts/ui/hud/death_notice.gd`, `energy_chip.gd`,
  `scripts/ui/stations/upgrade_console_station_panel.gd`, `drone_pad_station_panel.gd`.
- Evidence: `docs/revisions/evidence/drone/`, `food_stages/`, `room_stages_sheets/`, `rover_stages_overview.jpg`,
  `upgrades_regression/` (one log per suite and `summary.txt`).

## Verification

See `docs/revisions/evidence/upgrades_regression/summary.txt` for the run of every suite on the combined tree
(the table below is copied from it).

- Combined run of 44 suites on 2026-11-14 (before the tutorial-start and broken-parts changes): 39 passed outright; the rest failed only on old start assumptions and were fixed in their fixtures (logs in tutorial_start_fixed/).
- After that the owner took over test runs (owner rule 2026-11-14: the owner runs the suites). Later changes were checked with the compile check (COMPILE OK 354 scripts) and tools/godot/check_gold_and_sparkles.gd (43/43).

## Limits and open items

- No human playtest; headless only (owner rule). Stage visuals were checked in Blender clay renders, not in the live
  renderer: screen shaders, the hologram and emissive lights need a look in game.
- The drone has no collision with buildings (it keeps 0.6 m above terrain) and its pad charger is free power.
  Co-op piloting was tested only on the host side of the input path.
- Rover add-on parts copy the rover body's render layers, which never change as it drives (existing behaviour).
- Plant O2 is a sol average, not tied to daylight. MOXIE power (20 kWh/kg) is still balance.
- `scripts/weather/return_routes.gd` still counts the whole 11 m garden pad as shelter for return routes (the
  survival model now treats 8.15-11 m as Mars air).
- `test_game_scene` suit-rack step (I-59) is timing-flaky: the body is launched 2.3 m up after being placed in
  some runs and passes in others with identical placement.
