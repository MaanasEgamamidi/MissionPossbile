# Prompt 03 — state, clocks and save schema

Project: `G:\nasa app\mars_colony_godot` (Godot 4.7.2, typed GDScript). This file describes what the code does today.
Numbers marked **tuning** are designer balance values in `GameBalance` / `GameConfig`; they are not measurements and
not NASA specifications.

## 1. Who owns what

| Responsibility | Code | Notes |
|---|---|---|
| Settings | `scripts/core/game_config.gd` (`GameConfig`), `config/game_config.tres` | Engineering and session settings. Two sourced constants: `SOL_HOURS` 24.6598 (S02), `MARS_GRAVITY` 3.73 m/s² (S01). |
| Designer balance | `scripts/core/game_balance.gd` (`GameBalance`), `config/game_balance.tres` | Stores, rates, cargo slots, recovery. All **tuning**. |
| Typed state | `scripts/state/colony_state.gd`, `character_state.gd` | Plain data, `to_dict()` / `from_dict()`. No nodes. |
| Clock | `scripts/sim/sol_clock.gd` (`SolClock`) | Sol number, phase, tick count. |
| Colony simulation | `scripts/sim/colony_sim.gd` (`ColonySim`) | One pure tick: power, oxygen, water, food, condition. |
| Interaction validation | `scripts/session/action_service.gd`, `builtin_actions.gd` | Every player action is a validated request. |
| Host session | `scripts/session/session_service.gd` (`SessionService`) | Fixed tick, crew ownership, pause votes, suit check, recovery. |
| Legacy facade | `scripts/session/legacy_stations.gd` | "Use this station" calls from the old browser game mapped to requests. |
| Persistence | `scripts/save/save_service.gd`, `save_migrations.gd`, `save_load_result.gd` | Versioned JSON, safe replacement, backups. |
| Glue | `scripts/core/game_services.gd` (`GameServices`) | New game / continue, what a save contains, when to save. |
| Events | `scripts/core/game_events.gd` (`GameEvents`) | Signals; presentation listens instead of polling. |
| World composition | `scripts/world/*`, `scenes/world/colony_world.tscn` | Map, zones, lighting, stations, collision. |
| Player control, presentation | `scripts/player/*`, `scripts/game/*` | Prompt 04. They send requests; they do not change state. |
| Networking | — | Not built yet. `SessionService.submit()` is the single entry a network layer will call on the host. |
| Progression, data refresh | — | Not built yet. Their fields exist in the state so the save schema does not have to change shape. |

## 2. Clocks

- **Simulation tick:** 5 per real second (`GameConfig.sim_tick_hz`), driven by an accumulator in
  `SessionService.advance(real_delta)`. Left-over time carries to the next frame; at most 25 ticks run per frame
  (`max_ticks_per_frame`), the rest waits — time is delayed, never dropped.
- **Sol:** always `SOL_HOURS` = 24.6598 game hours. `sol_minutes` (default 20, host range 5–120) only sets how many
  real minutes that takes. Game hours per real second = `SOL_HOURS / (sol_minutes × 60)`.
- **Phase** is stored (0 = midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset), not derived from elapsed time, so changing
  `sol_minutes` keeps the time of day and the sol number exactly.
- **Real-second things** do not read the sol clock: input, movement, animation, the suit check
  (`suit_check_seconds` = 1.0), autosave interval (60 s).
- **Pause:** `paused` is true only while every connected peer has voted to pause. A solo player therefore pauses at
  once; co-op needs everyone. While paused no tick runs, the suit check does not progress and autosave does not fire.
- **No offline deterioration:** nothing reads the wall clock to advance the game. `saved_at_unix` in a save file is for
  display only.

## 3. Units and the tick model

All flows are `rate × game hours`, so the real length of a sol cannot create or destroy anything.

| Store | Unit | Start / capacity (**tuning**) | In | Out |
|---|---|---|---|---|
| `battery_kwh` | kWh | 180 / 400 | solar not used directly by the load | load the sun does not cover |
| `oxygen_kg` | kg | 60 / 150 | 0.2 kg/h while Life Support is powered, scaled by the share of load served | 0.035 kg/h per active astronaut |
| `water_l` | L | 900 / 2000 | 85 % of the water used, while Life Support is powered | 0.16 L/h per active astronaut |
| `food_meals` | meals | 96 / 400 | — | 3 meals per sol per active astronaut |

Power each tick: solar (peak 60 kW × a half sine between sunrise and sunset) feeds the load first; the rest charges
the battery; what does not fit is curtailed. Load the sun cannot cover comes from the battery; what the battery cannot
cover is unserved (`power_deficit`). Load = 6 kW base + each powered zone (default 1.5 kW; Greenhouse 9, Hangar bay 5,
Life Support 4, Command Room 3, Med Bay 3, Power Room 2) + 3 kW oxygen generation while Life Support is powered.

`ColonyState.ledger` keeps running totals so each store can be audited:
`battery now = battery at start + solar_used_kwh − load_served_kwh` (checked by tests to 1e-6).

Only **active** crew (controlled by a player) consume. Parked crew use nothing and their condition is frozen.
Unmet oxygen, water or food lowers the health of active crew (placeholder rates: 60 / 6 / 3 health per game hour when a
need is completely unmet). Health 0 → recovery at the hub (shared brief rule): cargo goes into one cache where it
happened, the colony is charged 0.1 sol of one astronaut's food and water (0.3 meals, 0.39 L; never blocks), health
becomes 50 (**tuning**), suit, tank charge and equipment are untouched.

This is a deliberately small placeholder model so the foundations (ticks, bookkeeping, validation, saving) can be
tested. The power, life-support and food milestones replace the rates and add detail; the bookkeeping stays.

## 4. State fields

`ColonyState`: `stores`, `capacities`, `parts`, `zones` (zone → `powered`, `condition`, `tier`), `stations`
(stable id → `kind`, `zone`, `position`, `specialty`), `characters`, `items` (id → `kind`, `position`, `holder`),
`caches`, `knowledge`, `evidence`, `upgrades`, `tasks`, `discoveries`, `rover`, `data_snapshot_id`, `weather_queue`,
`event_queue`, `rng_seed`, `rng_state`, `ledger`, `counters`. Display-only values recomputed each tick and not saved:
`solar_kw`, `load_kw`, `power_deficit`, `unmet`.

`CharacterState`: `id` (`crew_1`…`crew_4`), `specialty` (`electrical_comms`, `medical_life_support`, `biology_food`,
`field_engineering_geology`), `display_name`, `owner_peer` (0 = parked), `position`, `yaw`, `hub_spot`, `health`,
`stamina`, `suit_on`, `suit_charge`, `equipment`, `cargo`.

Stable identifiers: stations use the map object name (`pw_panel`, `al_suit_rack`, …); crew `crew_N`; items their key;
caches `cache_N` from a saved counter; zones their room name.

`ColonyState.invariants_ok()` lists violations of: no negative or over-capacity store, no NaN, parts ≥ 0, no item
carried twice, no peer controlling two characters.

## 5. Save file

Location: `user://saves/colony.json` (plus `colony.bak1.json`, `colony.bak2.json`, and `colony.json.tmp` only while
writing). On Windows `user://` is `%APPDATA%\Godot\app_userdata\Mars Colony\`. Tests write inside the project folder instead.

```json
{
  "format": "mars_colony_save",
  "schema": 1,
  "game_version": "0.3.0",
  "saved_at_unix": 1794300000,
  "reason": "autosave",
  "checksum": "<SHA-256 of the canonical payload text>",
  "payload": {
    "clock":   { "sol_minutes": 20.0, "sol_index": 0, "phase": 0.3, "ticks": 0, "real_seconds": 0.0 },
    "colony":  { "...": "ColonyState.to_dict()" },
    "session": { "host_character": "crew_1" }
  }
}
```

- 64-bit random-generator seed and state are stored as strings (JSON numbers are doubles and would lose bits).
- Network peer ids are not saved. `owner_peer` is written as 0 for everyone; `session.host_character` remembers who
  the host was playing. On load, every other character is placed at its hub spot (no penalty).
- Not saved, by design: microphone or voice data, anything on screen (camera view, open menus, messages), pause votes,
  the request log, a running suit check, and the part of a tick left in the accumulator (less than 0.2 s).

**When the game saves:** right after a new game is created; every 60 real seconds while not paused; right after an
important transaction (`claim_character`, `release_character`, `set_sol_minutes`, `collect_cache`, a recovery); on
orderly quit (menu quit or closing the window).

**Writing:** the whole file is written to `colony.json.tmp`, read back and validated; only then are the backups
rotated (`bak1` → `bak2`, a copy of the current main file → `bak1`) and the temp file renamed over the main file.
A failed or interrupted write leaves the previous save in place. Godot's rename on Windows deletes the destination
first, so for an instant there is no main file; loading therefore also accepts a complete temp file and the backups.

**Loading** tries main, temp, `bak1`, `bak2` in that order and takes the first file that parses, has the right
format, passes the checksum and has a usable schema. Loading never changes or deletes a file.

| Situation | Result (`SaveLoadResult.status`) | What the game does |
|---|---|---|
| No file at all | `no_save` | Starts a new game |
| Main file good | `ok` | Loads it |
| Main file damaged or missing, an older file good | `recovered_from_backup` | Loads the older file and tells the player |
| Every file damaged | `corrupt` | Starts a new game under another save name; the damaged files are left alone |
| File written by a newer game | `unsupported_schema` | Same as above; the newer save is never overwritten |
| Older schema with a migration path | `ok`, `migrated_from` set | Loads the migrated copy; the file is rewritten only at the next normal save |

## 6. Migration policy

- `SaveMigrations.current_version` is the schema this build writes (now 1).
- Any change to the meaning or shape of saved data raises the schema by one and adds exactly one step function that
  lifts a payload from the previous version. Steps are chained; none is ever removed or edited after release.
- Adding a field that has a safe default in `from_dict()` does not need a new schema.
- A save from a newer schema is refused, never guessed at, never overwritten.
- Migration happens in memory. The old file is kept as it is until the next normal save, when it becomes a backup.
- Each step gets a test with a real file of the old version kept under `tests/fixtures/`.
