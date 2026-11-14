# Mars Colony (Godot 4.7.2) — Prompt 07 build spec: power, water and two oxygen processes (model and actions)

You build the colony's **energy and life-support model**, the host actions that operate it, and its tests. The
panels that show it are built separately afterwards; you only expose clean data for them.
Game: cooperative Mars colony game for ages 9 to 12, Godot 4.7.2, typed GDScript. The host owns the truth; players
change things only through validated actions. Read these first in your copy: `scripts/sim/colony_sim.gd`,
`scripts/sim/sol_clock.gd`, `scripts/state/colony_state.gd`, `scripts/state/character_state.gd`,
`scripts/core/game_balance.gd`, `scripts/core/game_config.gd`, `scripts/session/session_service.gd`,
`scripts/session/action_service.gd`, `scripts/session/builtin_actions.gd`, `scripts/core/game_events.gd`,
`scripts/world/station_catalog.gd`, `tests/test_session.gd`, `docs/source_register.md` (sections 1–4 and "How to
read it"), and `docs/STATE_AND_SCHEMA.md` (the Prompt 03 model description).

## Ground rules

- Typed GDScript 4.7, tabs, `##` doc comments, plain wording. No nodes in the model: pure RefCounted classes.
- **Every rate, capacity, timer and scaled hardware figure is game configuration** in `GameBalance` with a comment
  saying its evidence category and source id: `physics` (stoichiometry, ideal gas — standard science, no register id
  needed), `S08` (ISS ECLSS: electrolysis of water, CO2 removal with molecular sieves, water recovery about 90 %),
  `S09` (MOXIE made O2 from Mars CO2, best 12 g/h, 98 % purity; a colony-size unit is **fiction scaled from S09**),
  `S01`/`S02` (gravity, sol), or `balance` (game tuning, no source). Never present a balance number as a NASA figure.
  Do not use the old browser demo's 90 / 128 / 140 kW figures. Also write `data/model_sources.json`:
  `{"field_name": {"category": "...", "source_ids": [...], "note": "..."}}` for every new or changed GameBalance field.
- Units are in field names (`_kw`, `_kwh`, `_kg`, `_l`, `_kpa`, `_per_hour`, `_per_sol`). Rates are per **game
  hour**; one sol = `GameConfig.SOL_HOURS` game hours. kW (rate) and kWh (amount) are never mixed.
- Conservation: every store keeps a ledger (`ColonyState.ledger`) so `now == start + Σin − Σout` holds to 1e-6.
  Capacities clamp; nothing goes negative; nothing is created by toggling, by reordering actions, or by save/load.
- Only **active** characters (controlled by a player) breathe, drink, eat and use suit air. Parked characters use
  nothing and keep a frozen condition (existing rule).
- No sudden unavoidable failure: problems raise an alert first and give time; health falls gradually, and recovery
  at the hub (existing `SessionService.recover_character`) stays the end point.
- Run Godot through the wrapper (see your task message). Tests: `extends SceneTree`, work in `_initialize()`,
  print `PASS <name>` / `FAIL <name>: <detail>` then `RESULT <passed>/<total>`, `quit(0)` iff all passed. Never print
  PASS for something not measured.
- GDScript traps: no variable named like a global class; `var x := <Variant>` fails — type it; JSON numbers return as
  float; global transforms need the tree.

## Files you own (create or replace only these)

`scripts/sim/colony_sim.gd` (replace, keep `step` signature), `scripts/sim/power_model.gd`,
`scripts/sim/life_support_model.gd`, `scripts/sim/reserve_forecast.gd`, `scripts/core/game_balance.gd` (extend; keep
existing fields that other code reads: `battery_kwh_capacity`, `cargo_slots`, `load_of_zone()`, `meals_per_sol`,
`water_l_per_hour`, `oxygen_kg_per_hour`, `recovery_health` — you may change their values),
`scripts/state/colony_state.gd` (extend), `scripts/state/character_state.gd` (add fields), `scripts/session/system_actions.gd`,
`scripts/session/session_service.gd` (only the small additions listed below), `scripts/world/station_catalog.gd`
(add solar stations), `data/model_sources.json`, `tests/test_life_support.gd`, `docs/MODEL_P07.md`.

## The model

### Energy (`PowerModel`)
- **Solar**: 12 sun trackers (`sf_solar_tracker`, `.001` … `.011` in the map). Output kW =
  `solar_kw_peak` (fiction/balance) × sun term × atmosphere term × (1 − panel dust) × tracker condition, summed per
  tracker (each tracker has 1/12 of the peak). Sun term: with the trackers powered they follow the sun
  (`sin(π·(phase−0.25)/0.5)^0.5` between sunrise 0.25 and sunset 0.75, 0 at night); with tracker power off they stay
  fixed (plain half-sine): **orientation matters and losing power has an effect**. Atmosphere term
  `exp(−dust_tau_factor × state.dust_tau)` normalised so the default `dust_tau` gives 1.0 (mechanism: dust in the air
  blocks sunlight; the weather milestone will drive `dust_tau`; default constant). Category: balance with mechanism note.
- **Panel dust**: per tracker 0..1. Settles by `dust_deposit_per_sol` × (`dust_tau` / default). **Cleaners**: one
  automatic cleaner system with `condition` 0..1 and power draw; when working (condition ≥ 0.5 and powered) it removes
  dust on every tracker once per sol at sunrise. **Manual cleaning**: action `clean_panel` at a tracker (anyone)
  sets that tracker's dust to 0. At the start of a new game the cleaner system has **failed** (condition 0) and
  panels are dusty (0.45): part of the arrival restoration.
- **Battery**: `battery_kwh` (amount), `battery_kwh_capacity`, `battery_charge_kw_max`, `battery_discharge_kw_max`,
  `battery_charge_efficiency` (energy stored = energy in × efficiency; the loss goes to `ledger.battery_loss_kwh`).
- **Loads and allocation**: demand = base load + each powered lighting zone (`load_of_zone`) + each piece of equipment
  that is switched on: trackers, cleaner, water recycler, CO2 scrubber, electrolyser, CO2-oxygen unit, cabin air fans
  ("base load" stays for control and heating). Supply = solar + battery discharge (bounded by max and by charge).
  When supply < demand, loads are **shed automatically by priority** (lowest first): non-critical room lights →
  greenhouse → CO2-oxygen unit → electrolyser → water recycler → trackers → cleaner → CO2 scrubber → cabin fans →
  base. A shed load is "switched on but unpowered" this tick (`state.equipment[x].powered == false`), and an alert
  says what stopped and why. Surplus solar charges the battery up to its limits; the rest is curtailed.
- Ledger terms: `solar_used_kwh`, `solar_curtailed_kwh`, `battery_in_kwh`, `battery_out_kwh`, `battery_loss_kwh`,
  `load_served_kwh`, `load_unserved_kwh`. Identity: `battery_now = battery_start + battery_in − battery_loss − battery_out`.

### Water (`LifeSupportModel`)
- Stores: `water_l` (clean water), `wastewater_l` (used water waiting to be cleaned), capacity for each.
- Use: each active astronaut drinks and washes `water_l_per_hour`; a fraction `water_to_wastewater` returns to
  wastewater, the rest is lost (breath, sweat — balance).
- **Allocation** (player setting, host action `set_water_allocation`): litres per hour requested for the greenhouse
  (`greenhouse_l_per_hour`, used by the food milestone later; for now it only goes to wastewater) and for the
  electrolyser feed (`electrolysis_feed_l_per_hour`). Drinking always comes first; allocations take only what is
  left above a protected drinking reserve (`water_reserve_l`, balance) and never take the store below it.
- **Recycler** (equipment, power): cleans up to `recycler_l_per_hour` of wastewater; returns `recycler_recovery`
  (0.90, S08 "about 90 percent") of it as clean water; the rest is brine (lost, ledgered). Without power or with
  condition < 0.5 it stops and wastewater builds up (alert).
- **Water quality** 0..1: clean water made by a recycler in poor condition (< 0.8) has lower quality; quality mixes by
  volume. Effect that matters for decisions: the **electrolyser needs quality ≥ 0.9** feed water (it stops, with an
  alert, below that). Drinking is unaffected (keep it simple; say so in MODEL_P07.md).

### Oxygen: two separate processes (`LifeSupportModel`)
- `oxygen_kg` is the **oxygen reserve** (stored tanks). It is not the cabin air.
- **Electrolyser** (path 1, S08 mechanism): needs power, condition ≥ 0.5, feed water allocated and quality ≥ 0.9.
  Makes O2 at up to `electrolysis_o2_kg_per_hour`, uses exactly `1.126` kg (= L) of water per kg O2 (stoichiometry,
  physics: 2 H2O → 2 H2 + O2; 36 g water gives 32 g oxygen) and `electrolysis_kwh_per_kg_o2` of electricity;
  hydrogen is vented (ledger `hydrogen_vented_kg` = water × 2/18). If the feed is short, it makes proportionally less.
- **CO2-oxygen unit** (path 2, MOXIE mechanism, colony scale is fiction scaled from S09): takes CO2 from the Mars
  atmosphere outside (no water at all), needs power and condition ≥ 0.5, makes up to `co2_unit_o2_kg_per_hour`
  using `co2_unit_kwh_per_kg_o2`; carbon monoxide is vented. It must be impossible for this path to use water.
- Either, both or neither may run; the player switches each one (`set_equipment`). `state.oxygen_process` is not a
  single choice: report both statuses.

### Cabin air, CO2 removal and pressure (`LifeSupportModel`)
- The habitat is one pressurised volume `cabin_volume_m3` (fiction/balance) at `cabin_temperature_k`. Track masses
  `cabin_o2_kg`, `cabin_n2_kg`, `cabin_co2_kg`; partial pressures from the ideal gas law (physics):
  `p = m / M × R × T / V` (M: O2 0.032, N2 0.028, CO2 0.044 kg/mol; R 8.314). Report `cabin_o2_kpa`,
  `cabin_co2_kpa`, `cabin_pressure_kpa`. Start near 21 kPa O2, 79 kPa N2 (balance: Earth-like cabin), ~0.1 kPa CO2.
- Each active astronaut **inside** breathes `oxygen_kg_per_hour` of O2 from the cabin and adds `co2_kg_per_hour` of CO2.
- **O2 regulator**: keeps cabin O2 at its set point by releasing oxygen from the reserve (`oxygen_kg`). An empty
  reserve means cabin O2 falls — slowly, with alerts — instead of anything sudden.
- **CO2 scrubber** (equipment, power; S08: CO2 removed with molecular sieves): removes up to
  `scrubber_co2_kg_per_hour`. Off or unpowered → CO2 builds up; alerts at `co2_warn_kpa` and `co2_danger_kpa` (balance).
- **Pressure boundary**: the airlock loses `airlock_cycle_loss_kg` of cabin air per cycle (mixed in proportion);
  `SessionService.note_airlock_cycle()` (host) queues one cycle, the next tick applies it, the regulator replaces O2
  from the reserve and N2 from `n2_reserve_kg` (a finite store, balance). Outside the habitat there is no cabin air.
  Pressure below `pressure_warn_kpa` raises an alert. Keep pressure and safe air separate from oxygen produced.

### Suits (`LifeSupportModel` + actions)
- A character is **outside** when the host's `SessionService.outside_test.call(position)` is true (a Callable the
  game sets; default returns false). `report_position` updates `CharacterState.outside`.
- Outside with the suit on: the suit tank (`suit_charge` 0–100 % of `suit_o2_capacity_kg`) supplies
  `oxygen_kg_per_hour`; CO2 is scrubbed by the suit. Inside: suits use nothing.
- Outside without a suit, or with an empty tank: health falls at `health_loss_per_hour_no_air` with an urgent alert
  for that character (no instant death; recovery at zero health as before).
- Action `refill_suit` at the suit rack (target kind `suits`): moves oxygen from the reserve into the tank, up to full;
  if the reserve is short it fills what it can and says so. **No free refill**: the existing suit check never changes
  the tank, and the existing rule stands.

### Food
Unchanged from Prompt 03 (stored meals, use per active astronaut); the food milestone adds growth.

### Health and alerts
- Causes of health loss for active crew, each scaled by how bad it is: cabin O2 below `o2_low_kpa` (inside), CO2 above
  `co2_danger_kpa` (inside), no air outside (above), no water, no food. Alerts come before harm.
- `ColonyState.alerts`: Array of `{"id", "level" ("info"/"warn"/"urgent"), "text", "since_hours"}` with the active
  problems, recomputed every tick; when an alert first appears (or a piece of equipment stops for a reason) emit
  `events.system_alert(id, level, text)` once (SessionService passes `events` — add an `events` argument via a
  setter on the sim, keep `step`'s signature). Text names cause and effect in plain words:
  "Water pump stopped: no power. Wastewater is building up." "Electrolyser stopped: the water is not clean enough."

### Reserve forecast (`ReserveForecast`)
`static func compute(state, balance, clock) -> Dictionary`: at current flows, game hours until empty for battery,
oxygen reserve, water, food, each suit of an active character outside; battery charge expected at the next sunrise;
plus `text` lines like "Battery: 140 kWh, lasts until about 06:30 tomorrow at this rate". Use −1 for "not falling".

### State fields to add (ColonyState; all saved; to_dict/from_dict/assign_from; defaults in from_dict)
`equipment` = `{id: {"on": bool, "powered": bool, "condition": float, "kw": float}}` for `trackers`, `cleaner`,
`recycler`, `scrubber`, `electrolyser`, `co2_unit`, `cabin_fans`; `panel_dust` (Array of 12 floats); `dust_tau`;
`wastewater_l`, `water_quality`, `water_allocation` (`{"greenhouse_l_per_hour", "electrolysis_feed_l_per_hour"}`);
`cabin_o2_kg`, `cabin_n2_kg`, `cabin_co2_kg`, `n2_reserve_kg`, `pending_airlock_cycles`; `alerts`. Add capacities
for the new stores and extend `invariants_ok()`. `CharacterState`: `outside: bool`.

### Starting conditions (tutorial-safe; test them)
Four active astronauts, nobody does anything for **3 sols**: no one reaches zero health, every store stays above
zero, and alerts appear in good time (first battery or air warning at least 12 game hours before any harm).
With the arrival restoration done (clean all 12 panels, repair the cleaner, switch on the electrolyser with a feed
and/or the CO2-oxygen unit), the colony is **energy-positive over a sol** and oxygen-positive. Pick the numbers to make
this true and record them in MODEL_P07.md with their categories.

## Actions (`SystemActions.register(service)`, called from `SessionService._init` after BuiltinActions)

| id | target | params | rules | effect |
|---|---|---|---|---|
| `set_equipment` | station `lifesupport` or `power` | `equipment: String`, `on: bool` | unknown equipment → `unknown_target` | `equipment[x].on = on`; alert text of the effect |
| `set_water_allocation` | station `lifesupport` | `greenhouse_l_per_hour` 0–20, `electrolysis_feed_l_per_hour` 0–20 | — | sets the allocation |
| `clean_panel` | station `solar` (a tracker) | — | anyone | that tracker's dust → 0 |
| `repair_cleaner` | station `solar` | — | **specialty `electrical_comms`** (else `wrong_specialty`); `missing_prerequisite` if not failed | cleaner condition → 1 |
| `refill_suit` | station `suits` | — | `missing_prerequisite` if full; `insufficient` if reserve empty | moves O2 reserve → tank |

`StationCatalog.from_manifest` also returns the 12 trackers as stations `{"kind": "solar", "zone": "Exterior", ...}`
(object names starting `sf_solar_tracker`). SessionService additions: `var outside_test: Callable`,
`func note_airlock_cycle() -> void`, set `CharacterState.outside` in `report_position`, and register SystemActions.

## `tests/test_life_support.gd` must prove (measure, do not assume)
Conservation identities for battery, water (clean + waste + losses), oxygen reserve, cabin gases, N2 over a 5-sol run
with switching; capacity bounds; zero input (no sun at night: battery only; no water: electrolyser makes nothing);
overload (demand above supply: shedding order exactly as listed, alerts name the shed loads, unserved energy ledgered);
solar cleaning (output rises by the expected fraction after cleaning one tracker; cleaner repair needs the electrical
specialist, then keeps panels clean daily); tracker power off lowers output by the expected ratio; recycler powered vs
unpowered (wastewater builds up only when it is off; alert raised once); each oxygen path alone, both together,
neither; the CO2 unit uses no water under any switch combination; water at the electrolyser exactly 1.126 L/kg O2;
electrolyser stops below quality 0.9; scrubber off raises cabin CO2 to the warning level and alerts before harm;
airlock cycles lower pressure and the regulator restores it from the reserves; suit use only outside, refill takes
from the reserve (no free refill; suit check still leaves the tank unchanged); active-count changes (1–4 active, parked
crew consume nothing); recovery with empty shared stores still succeeds and stores stay ≥ 0; toggling equipment on/off
1,000 times creates nothing; save → load → continue gives identical results to an uninterrupted run (to 1e-9);
arrival survivability for 3 sols with no action and energy/oxygen positive after the restoration; the reserve forecast
matches a forward simulation within 2 %; a full sol at 5, 20 and 120 real minutes per sol ends with the same stores
within 1 %. Also run the existing `tests/test_session.gd` and `tests/test_saves.gd` and keep them passing (update only
expectations that your new rates legitimately change, and say which).

## `docs/MODEL_P07.md`
One page: each mechanism, its inputs and outputs, every number with unit, category and source id, the starting
conditions and why they are safe, what is simplified, and what later milestones (food, weather) plug in.
