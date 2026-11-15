# Upgrade paths, scout drone and survival realism: shared brief (2026-11-14)

Every worker reads this first. It is the interface spec: file ownership, the shared core that already exists, the
rules for running Godot, and what each part must prove.

## The owner's requests

1. Everything gets an upgrade path, including the scout drone, the rover and every interactable area. Today's models
   are V1. Each area has at least 4 visible stages (V1..V4). Example: food goes from one grow layer to several.
2. Scout drone: manual control first. After enough upgrades it becomes programmable and flies to chosen areas by
   itself. It is a flying object: build its models in Blender, then bring them into Godot.
3. Health upgrades show visual changes.
4. Energy: when the sun goes down, solar output stops and stored power drains fast.
5. Going outside without a suit kills within seconds, not after about 5 minutes.
6. After each death and respawn in the med bay, tell the player why they died.
7. Resource drain is realistic, based on NASA data.

## Where to work

- Project: `G:\nasa app\mars_colony_revisions_wt` (Godot 4.7.2 project; git worktree on branch `revisions` of
  MaanasEgamamidi/MissionPossbile). **Do not commit, push, stash, reset, checkout or switch branches.** The
  integrator commits everything at the end.
- Godot console exe: `C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- Blender (headless only, never save over a source .blend you did not create):
  `%LOCALAPPDATA%\Microsoft\WindowsApps\blender-launcher.exe -b --factory-startup --disable-autoexec --python <script>`
- Python: `py` (3.13). The `python` alias does not work. Node is also available.
- Read `README.md`, `docs/source_register.md`, and the code around what you change. Follow the code style you see:
  tabs, `##` doc comments, plain words for players (the game is for ages 9 to 12), E is the one interact key.
- Owner rules: no texture baking (run-time materials and mesh detail instead); headless tests and compile checks only
  (the owner plays the game themselves); label every number as NASA-sourced (with a source id) or designer balance.

## File ownership

Only edit files your brief lists as yours. New files only inside your own folders. If you need a change in a file you
do not own, put the exact request in your final report instead of making it. Several workers run at the same time in
the same folder: never revert, reformat or "clean up" anything you did not write. Another Claude session may also be
running tests here: never kill a Godot process you did not start.

## Godot rules (shared folder, several workers)

- **No new `class_name`.** Load your own scripts by path (`const X := preload("res://...")`). The core classes below
  are already registered.
- **Imports:** only one at a time in the whole folder. Before `--import`, take the lock by creating the folder
  `G:\nasa app\mars_colony_revisions_wt\_locks\import` (`mkdir` fails if it exists, so it is atomic). If it exists,
  wait and retry every 30 s (up to 20 min). Remove the folder when the import ends, also on failure. Import only when
  you added assets (glb, png) Godot must import.
- **Tests:** never run `tools/run_tests.ps1` without `-Tests`, and never the whole list. Run your own new suite, plus
  the existing suites your brief names. For an existing suite take the lock `_locks\test_<suite>` the same way.
  Run a script with: `& '<godot console exe>' --headless --path . --script res://tests/<suite>.gd` and read the
  `RESULT n/m` line. A pass needs exit code 0, a full RESULT, and no `SCRIPT ERROR` or `Parse Error`.
- Compile check (no lock needed): `& '<godot>' --headless --path . --script res://tools/godot/check_compile.gd`.
- Test files under `_test_saves\<your_suite>\` only. Never delete `_test_saves` recursively.
- Network ports 24791-24794 belong to existing suites. If your test needs a port, use 24795 + your worker number.
- Godot 4.7.2 gotchas: with `Engine.time_scale` > 1 count `Engine.get_physics_frames()`; `Node3D` already has
  `set_identity()`; a `.blend` anywhere Godot scans stops the headless import, so put Blender sources under a folder
  that has a `.gdignore` file (for example `assets_src\drone\` with `assets_src\.gdignore` already present or added).

## Shared core (already written, tested by tests/test_area_levels.gd, 28/28)

- `data/area_levels.json`: the tracks `food`, `garden`, `energy`, `life_support`, `health`, `command`,
  `scout_drone`, `rover`. Each has `station_kinds` (or `station_ids`), `specialty`, `cost_parts[4]`, `stages[4]`
  (words) and `effects` (key -> 4 values, index = level - 1). You may tune the numbers and words of your own tracks
  and add effect keys for them. Keep 4 entries per list.
- `AreaLevels` (`scripts/upgrades/area_levels.gd`): `level(state, track)` 1..4; `effect(state, track, key, default)`;
  `effectf(...)`; `effect_at(track, key, level, default)`; `stage_text(track, level)`; `cost_to_reach(track, level)`;
  `blockers(state, track, actor)`; `tracks_at(station_id, station)`; `station_serves(...)`. The rover's level is
  derived from `state.rover.levels` (`rover_level()`), never stored.
- `state.levels` (`ColonyState`): track -> int. `state.drone`: plain JSON dictionary for the scout drone (owned by
  the drone worker). Both are saved and replicated already.
- Host action `upgrade_area` (`AreaLevelActions`, `scripts/session/area_level_actions.gd`): target = a station that
  serves the track, params `{"track": id}`. Checks specialist and parts, raises the level by one, spends parts once.
  The energy track's battery capacity is scaled here, once per level change.
- `AreaStagePresenter` (`scripts/upgrades/area_stage_presenter.gd`): base of every look. Subclass in
  `scripts/upgrades/stages/<track>_stages.gd` (stubs exist), override `track_id()` and `build_stage(level) -> Node3D`
  (world coordinates, null = map model only). The base polls the level, swaps stages with a grow-in, and puts every
  mesh on its zone's render layers (rooms only draw and light their own layer, so do not set layers yourself unless
  a mesh spans zones). Helpers: `station_position()`, `anchor(name)`, `mat()`, `box()`, `cylinder()`, `layers_at()`.
  `force_level` lets tests show any stage. `AreaStages.attach_all` (called from game_main) creates them all.
- Station panels: a kind gets its own panel by creating `res://scripts/ui/stations/<kind>_station_panel.gd`
  (extends StationPanel). The base StationPanel is owned by the UI worker, who adds the upgrade strip to every
  station that serves a track.

## Contracts between workers

- **Death record** (survival worker writes, UI worker reads): `CharacterState.last_death` =
  `{"cause": String id, "title": String, "text": String, "area": String, "at_hours": float, "count": int}`; empty
  dictionary = never died. Saved and replicated with the character. Set on the host at the moment of death, before
  the med bay respawn. Cause ids at least: `no_suit_outside`, `suit_oxygen_out`, `airlock_pressure`, `cabin_air`,
  `low_oxygen`, `co2`, `starvation`, `dehydration`, `cold`, `injury`, `unknown`. `title` is short ("No suit outside"),
  `text` is one or two plain sentences on what happened and how to avoid it next time.
- **Energy outlook** (energy worker writes, UI worker reads): `PowerModel.outlook(state, balance, phase) -> Dictionary`
  with `{"sun_up": bool, "solar_kw": float, "load_kw": float, "battery_kwh": float, "battery_capacity_kwh": float,
  "net_kw": float, "hours_left": float (INF when charging), "hours_to_sunrise": float, "text": String}`.
- **Effect keys** each simulation worker wires (only they edit those simulation files):
  - food worker: `food.yield_factor`, `food.grow_layers` (crop system); `garden.meals_per_sol`.
  - energy worker: `energy.solar_factor` (power model); `life_support.scrubber_factor`,
    `life_support.o2_production_factor`, `life_support.recycler_factor`, `garden.plant_o2_kg_per_hour` (life support).
  - survival worker: `health.heal_rate_factor`, `health.recovery_health_bonus`.
  - drone worker: every `scout_drone.*` key and `command.drone_range_m`.
