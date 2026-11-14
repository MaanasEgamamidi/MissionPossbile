# Milestone handoff — Prompt 03: Simulation, configuration and save foundation

Date: 2026-11-11. Project: `G:\nasa app\mars_colony_godot` (Godot 4.7.2). Access to Blender 5.3 and Godot 4.7.2 was re-checked before work began.

## 1. Outcome

The game now has a host-authoritative foundation that runs without any networking:

- a fixed 5 Hz colony tick, a sol clock whose real length can change without moving the time of day or changing any stored quantity;
- typed state for the colony and the four crew, with running ledgers that let every store be audited;
- every player action as a validated request with a clear answer, safe to repeat;
- versioned JSON saves with a checksum, safe replacement, two rolling backups, fallback, and a migration mechanism;
- a small placeholder colony model (power, oxygen, water, food, crew condition) so all of the above can be exercised.

All Prompt 03 checks pass: 172 automated checks in three suites (section 5). Nothing here was checked by a human player.

**How the work was done.** After the owner's instruction to use the Codex CLI's `gpt-6-astra` model in fast mode and to
split the work across as many workers as useful, the executor wrote the shared types, the clock, the tick model and an
interface specification (`workers\SPEC.md`), then ran five Codex workers in parallel, each in its own copy of the
project: actions and session, saving, world collision and doors, player and cameras, and the character rig. The last
three belong to Prompt 04. The executor reviewed each result, merged it, wrote the glue (`GameServices`), re-ran every
test in the real project, and fixed what the combined run exposed (section 8, "found and fixed"). The briefs and the
workers' own reports are kept in `workers\`.

## 2. Prompt 03 acceptance, item by item

| Requirement | Result | Evidence |
|---|---|---|
| Separate responsibilities; typed state and interfaces | **Met.** One file per responsibility, listed in `STATE_AND_SCHEMA.md` section 1. Player control, presentation, simulation, validation, persistence and world composition do not reach into each other; presentation listens to `GameEvents` and sends requests. | Code layout; `test_game_scene` drives everything through requests |
| Compatibility facade for legacy action and station interfaces | **Met in the form that applies.** No legacy Godot script exists (Prompt 01 finding). `LegacyStations.interact(session, peer, station_id)` maps the old browser game's "use a station" call onto requests, keeping the nine station ids from the map. Stations without a rule yet answer `not_available_yet`. | `test_session`: "legacy unknown", "legacy unavailable" |
| Fixed colony tick, 20-minute sol, adjustable duration, preserved phase | **Met.** | `test_session`: "sol settings preserve instant state", "tick cap", "backlog retained" |
| Solo pause, unanimous co-op pause | **Met** at the service level (no network yet). | `test_session`: "solo pause freezes ticks and suit", "one of two votes", "two votes pause", "leaving dissenter pauses", "unvote resumes" |
| No offline deterioration | **Met.** Nothing reads the wall clock to advance the game. | `test_game_services`: "no offline deterioration"; `test_saves`: "no offline effect" |
| Stored energy from power over game time with explicit units; changing sol duration creates or destroys nothing | **Met.** kW × game hours = kWh; ledger identity holds to 1e-6; a full sol at 5, 20 and 120 real minutes ends with the same stores (largest difference 2.5e-6 relative). | `test_session`: "battery ledger identity", "full sol 5 / 20 / 120 minutes" |
| Radio delay, input and suit check in real seconds | **Suit check met** (1.0 s at 5- and 20-minute sols alike); input is real-time by construction. Radio delay does not exist yet (Prompt 11). | `test_session`: "suit completes at 20 minutes", "suit completes at 5 minutes" |
| Host-authoritative session service before co-op | **Met.** `SessionService.submit()` is the only way state changes outside the tick. | — |
| Actions validated: ownership, distance, specialty, prerequisites, quantities, duplicate ids; stable identifiers | **Met.** Each failure reason is produced by a request built to trigger exactly it. Specialty, prerequisite and quantity rules are proven with a test-only action, because the real specialist rules are not decided yet. | `test_session`: 30 validation checks from "bad shape" to "station specialty", "duplicate success", "duplicate failure stays failed" |
| Versioned JSON under `user://`, atomic replacement, last-known-good backup | **Met, with one stated limit:** on Windows the final rename is not a single atomic step in Godot (section 8). | `test_saves` 56/56 |
| Save at interval, after important transactions, on orderly quit | **Met.** | `test_game_services`: "interval autosave", "important transaction saves right away", "ordinary action does not force a save", "orderly quit writes a save" |
| Save content: characters, equipment and condition, cargo, rover, facilities, progression, sol settings and phase, RNG state, data-snapshot identity, weather queue, recovery caches; no voice, no transient UI | **Met.** Fields for progression, rover, weather and data identity are saved now but are still empty. | `STATE_AND_SCHEMA.md` sections 4 and 5; `test_saves`: "colony deep round trip", "RNG next 20 numbers" |
| Migrations and fallback | **Met as a mechanism.** No real migration exists yet because schema 1 is the first. | `test_saves`: six migration checks |
| Fresh start, save/load, repeated save, interrupted write, backup recovery, unsupported schema give defined results | **Met.** Table in `STATE_AND_SCHEMA.md` section 5. | `test_saves`, `test_game_services` |
| No resource duplication, negative storage, offline penalty or clock jump | **Met.** `ColonyState.invariants_ok()` is checked after every action in the session suite. | `test_session`: "invariants after every action", "cannot hold twice"; `test_game_services`: "continue: no clock jump" |
| Same action sequence at different frame rates gives the same model outcome within a documented tolerance | **Met.** Documented tolerance: one tick (0.2 s real) per action. Measured: tick difference 0 and store difference 0.0 at 30, 60, 144 frames per second and with irregular frame times. | `test_session`: four "frame rate" checks |

## 3. Changed files

New in `mars_colony_godot\`:

- `scripts\core\`: `game_config.gd`, `game_balance.gd`, `game_events.gd`, `action_request.gd`, `action_result.gd`, `layers.gd`, `game_services.gd`, `upgrade_definition.gd`, `source_record.gd`, `data_snapshot.gd` (the last three are interfaces only)
- `scripts\state\`: `colony_state.gd`, `character_state.gd`
- `scripts\sim\`: `sol_clock.gd`, `colony_sim.gd`
- `scripts\session\`: `action_service.gd`, `builtin_actions.gd`, `session_service.gd`, `legacy_stations.gd`
- `scripts\save\`: `save_service.gd`, `save_migrations.gd`, `save_load_result.gd`
- `scripts\world\station_catalog.gd`
- `config\game_config.tres`, `config\game_balance.tres`
- `tests\test_saves.gd`, `tests\test_session.gd`, `tests\test_game_services.gd`
- `tools\run_tests.ps1`

New in `docs\milestones\03_simulation\`: this file, `STATE_AND_SCHEMA.md` (state, clocks, units, save schema, migration
policy), `workers\` (specification, briefs, worker reports), `evidence\tests\` (full test output).

No Blender source file was opened for writing. No existing Prompt 01 or 02 file was changed except the cumulative records.

## 4. Public interfaces

| Interface | Where | Use |
|---|---|---|
| `GameServices` | node, group `game_services`; `GameServices.find(tree)` | `start_new_game(seed, host_character)`, `continue_game() -> SaveLoadResult`, `save_now(reason)`, `quit_game()`, `snapshot()`, `restore(payload)`, members `config`, `balance`, `events`, `session`, `saves`, `zones` |
| `SessionService` | `services.session` | `submit(ActionRequest) -> ActionResult`, `request(action, target, params, peer)`, `advance(real_delta)`, `peer_joined/left`, `set_pause_vote`, `report_position`, `recover_character`, `suit_check_progress`, `paused`, `peers`, `state`, `clock`, `rng` |
| `ActionService` | `services.session.actions` | `register(Definition)`; a definition names its target kind, allowed station kinds, specialty, parameter types and ranges, and two callables `check` and `apply` |
| Built-in actions | `BuiltinActions` | `claim_character`, `release_character`, `vote_pause`, `set_sol_minutes` (host only), `set_zone_power`, `pick_up`, `drop`, `collect_cache`, `begin_suit_check` |
| `ActionRequest` / `ActionResult` | `scripts\core\` | Request: id, peer (set by the host from the sender), actor, action, target, bounded params. Result: `ok`, `reason`, plain-language `message`, `changes`, `duplicate`. Reasons and their texts: `ActionResult.MESSAGES` |
| `GameEvents` | `services.events` | `state_changed`, `objective_changed`, `weather_changed`, `upgrade_eligibility_changed`, `crew_ownership_changed`, `zone_power_changed`, `sol_settings_changed`, `pause_changed`, `sol_started`, `action_resolved`, `character_recovered`, `suit_check_started`, `suit_check_finished`, `game_saved`, `game_loaded` |
| `ColonyState`, `CharacterState` | `services.state()` | Read-only for everything except the host session and the tick |
| `SolClock` | `services.clock()` | `phase`, `sol_index`, `hour_of_sol()`, `game_hours()`, `sol_minutes` |
| `GameConfig`, `GameBalance` | `config\*.tres` | Engineering settings and designer tuning, kept apart from the two sourced constants |
| `SaveService`, `SaveMigrations`, `SaveLoadResult` | `services.saves` | `write`, `read`, `has_save`, `validate_text`; `migrations.register(from_version, step)` |
| `StationCatalog`, `LegacyStations` | static | Stations from the map manifest; old "use station" calls |
| `Layers` | static | Physics layers WORLD, PLAYER, ITEM, DOOR, STATION; render layer 19 for parts hidden from the first-person camera |

A network layer (Prompt 06) needs only three things from this milestone: call `submit()` on the host with the sender's
peer id, call `peer_joined` / `peer_left`, and replicate state and events to clients.

## 5. Checks run, with results

All automated, all headless, run with `tools\run_tests.ps1` on 2026-11-11 (Windows 11, Godot 4.7.2 console build). Full output is in `evidence\tests\`.

| Suite | Result | What it covers |
|---|---|---|
| `tests\test_saves.gd` | 56 / 56 | Fresh start, round trip, rotation, interrupted write, truncated file, temp-file recovery, bit rot, all files damaged, newer schema, migration, missing fields, numbers the engine's JSON parser does not carry exactly |
| `tests\test_session.gd` | 91 / 91 | Station catalog, every validation failure, duplicates, carrying, claiming and switching, pause, suit check, recovery, peer loss, sol length, frame-rate independence, RNG, request log |
| `tests\test_game_services.gd` | 25 / 25 | New game, save, continue in a second services node, no clock jump, no offline effect, when saves happen, repeated saves, damaged newest save, save from a newer game, quit save |

Not verified: anything over a real network; a save made on one machine loaded on another; behaviour under a real power cut (the interrupted write is simulated by stopping after 100 bytes); long play sessions.

## 6. Sources used

- S01 NASA Mars Fact Sheet: surface gravity 3.73 m/s² (`GameConfig.MARS_GRAVITY`).
- S02 NASA GISS Mars24 notes: sol length 24 h 39 min 35.244 s (`GameConfig.SOL_HOURS`).
- Godot 4.7.2 class reference (local dump) for `FileAccess`, `DirAccess`, `JSON`.

Every other number in `GameBalance` and `GameConfig` is designer or engineering tuning and is labelled so in the code. No science source was needed or cited for them.

## 7. Performance and save notes

- The three suites run in 3.3 s in total.
- Measured with `tools\godot\diag_save_cost.gd` on the development desktop (i7-12700KF, SSD): a save after ten game minutes is 7,343 bytes; write + read-back check + backup rotation takes 4.1 ms median, 11.1 ms slowest of 50; reading and checking takes 0.5 ms. Saving runs on the main thread, so an autosave can cost most of one 60 Hz frame. Not measured on the target laptop.
- The tick model is a few dozen arithmetic operations at 5 Hz. It was not profiled further.
- Schema version: **1** (first). Save schema and field list: `STATE_AND_SCHEMA.md`.

## 8. Remaining defects and limits

Found and fixed during integration (kept here because they show what the checks caught):

- **Saves could reject themselves.** Godot's JSON parser does not read every very small number back exactly (seen around 1e-25: each parse-and-print changes the last digits). The checksum compared a text made with one more round trip than the writer used, so an autosave during the end-to-end run was refused as corrupt. The reader now hashes exactly what the writer hashed, and `test_saves` has a regression case with such numbers. The previous save was never at risk: a refused write leaves it in place.
- **Walking over small bumps pushed the player forward** (step-climb code moved the body horizontally as well as up). Fixed; Prompt 04 records the measurement.

Open:

1. **The colony model is a placeholder.** Rates, capacities, the health rules and the recovery health value are tuning for testing the foundation, not a design. Prompts 07 and 08 replace them.
2. **The hub is a rehearsal position** in the Med Bay (`GameConfig.hub_position`), because the owner has not named the hub room (issue I-06).
3. **No specialist gating is defined.** Station `specialty` is empty for all nine stations. The mechanism exists and is tested.
4. **Windows rename is not atomic in Godot**: the destination is deleted, then the temp file is renamed. For that instant there is no main file. Loading accepts a complete temp file or a backup, so no state is lost, but it is not the single-step replacement the contract describes.
5. **Up to 0.2 s of simulated time is not saved** (the part of a tick still in the accumulator).
6. **Positions are trusted from the controlling peer.** `report_position` checks ownership only; speed and reach checks belong with networking (Prompt 06).
7. **Run-time saves live under `user://`**, which on Windows is outside `G:\nasa app`. The pack requires `user://`; the owner asked for all resources inside the folder. Project files and all test output are inside the folder; only a player's own save games are not. Recorded as decision E-18 for the owner to confirm.
8. **`UpgradeDefinition`, `SourceRecord`, `DataSnapshot` are field lists only.** Nothing uses them yet.
9. **No menu.** New game or continue is chosen automatically (continue if a usable save exists).

## 9. Contradictions and decisions

- E-16: Codex `gpt-6-astra` workers in fast mode wrote four code parts and attempted the rig, on the owner's instruction (D-08). The executor specified, reviewed, merged and tested.
- E-17: `GameServices` is a scene node, not an autoload, so command-line tools and tests are not affected by it.
- E-18: saves under `user://` at run time (see limit 7).
- E-19: the placeholder colony model and its numbers.
- D-07: owner instruction "stop worrying about graphics for now; move on to mechanics". Graphics pass 4 is parked in a loadable state and its Prompt 02 records were not updated (issue I-36).

No new contradiction between sources was found in this milestone.

## 10. Missing inputs — requests to the owner

Unchanged from Prompt 02 and still open: the three governing documents (I-01), the improved map (I-02), approved character and rover assets (I-04, I-05), the hub room (I-06), the target laptop. New: confirm E-18 (save location).

## 11. Dependencies for the next milestones

- Prompt 04 (player) uses `Layers`, `CharacterState`, `GameConfig` player tuning, `begin_suit_check`, `pick_up`, `drop`, and `report_position`. Done in the same session; see `..\04_player\HANDOFF.md`.
- Prompt 05 (stations and interface) should add real station actions with `ActionService.register` and replace the interim HUD.
- Prompt 06 (co-op) wraps `SessionService.submit` in RPCs and replicates state; `peers`, pause votes, switching rules and peer loss are already modelled and tested at the service level.
- Prompt 07 and 08 replace `ColonySim` rates and fill `upgrades`, `knowledge`, `tasks`.

## 12. Optional suggestions (not requirements, not acted on)

- Keep one saved file of every released schema under `tests\fixtures\` from the first public build onward.
- Consider writing saves on a worker thread once the state grows past a few hundred kilobytes.
