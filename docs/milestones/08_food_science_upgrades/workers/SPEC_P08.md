# Mars Colony (Godot 4.7.2) — Prompt 08 build spec: food, science, fabrication and earned upgrades

Three workers build three parts at the same time, each in its **own copy** of the project, with a **fixed list of
files it may create or replace**. The parts are merged afterwards, so the names, ids and data formats here are a
contract. The game: a cooperative Mars colony game for children aged 9 to 12. Players walk the base, use stations
with E, carry items, and keep power, water, oxygen and food going. The host owns the truth; players change things
only through validated actions.

## Ground rules (all parts)

- Typed GDScript 4.7, tabs, one `class_name` per file, `##` doc comments, plain wording for ages 9–12.
- Read first: `scripts/state/colony_state.gd`, `scripts/state/character_state.gd`, `scripts/sim/colony_sim.gd`,
  `scripts/sim/power_model.gd`, `scripts/sim/life_support_model.gd`, `scripts/session/action_service.gd`,
  `scripts/session/builtin_actions.gd`, `scripts/session/system_actions.gd`, `scripts/session/session_service.gd`,
  `scripts/sim/progress_evidence.gd`, `scripts/world/station_catalog.gd`, `scripts/ui/ui_panel.gd`,
  `scripts/ui/station_panel.gd`, `scripts/ui/station_panels.gd`, `scripts/ui/power_station_panel.gd` (a good model
  for a station panel), `scripts/ui/reading_row.gd`, `scripts/ui/explain_button.gd`, `scripts/ui/ui_layout_check.gd`,
  `tests/test_life_support.gd` and `tests/test_p07_panels.gd` (good test models), `docs/MODEL_P07.md`,
  `docs/source_register.md`, `data/colony_manifest.json` (map objects: `name`, `area`, `matrix_world`).
- **Hooks you plug into** (already in place):
  - Simulation: your system class has `func step(state, balance, phase, dt_hours, events) -> void`; the session runs
    `CropSystem` and `ProgressionSystem` every tick after water, oxygen and cabin air (`ColonySim.post_systems`).
    Rates are per **game hour** (one sol = `GameConfig.SOL_HOURS` = 24.66 h). Only **active** characters do anything.
  - Actions: your `XxxActions.register(service)` is already called by `SessionService`. Use `ActionService.Definition`
    exactly as `system_actions.gd` does (target kind, station kinds, specialty, params with ranges, check, apply).
  - State: your part owns one dictionary in `ColonyState` (`crops`, `science`, `progress`; plus `knowledge`,
    `evidence`, `upgrades`, `tasks`, `discoveries`, `items`, `parts`). Plain JSON-able data only (it is saved and
    sent to network clients as is). `state.has_upgrade(id)` is true when an upgrade is installed.
  - Evidence: **only** through `ProgressEvidence.record(state, events, evidence_id, sector, actor_id, detail)`; it stores
    each id once (repeats add nothing) and emits `events.upgrade_eligibility_changed`.
  - Stations: create `data/stations_<part>.json` (format in `station_catalog.gd`: map object by `object` or `prefix`,
    or a new `id` with a `position` in Godot coordinates; `kind`, `name`, `symbol`, `specialty`). They become stations
    in new games and get interaction volumes automatically. A panel for a kind: create
    `scripts/ui/stations/<kind>_station_panel.gd` extending `StationPanel` (found automatically by `StationPanels.for_station`).
  - Numbers: your own config Resource class with defaults (for example `FoodBalance`), every field commented with its
    category — `balance` (game tuning, not NASA), `physics`, or a source id from `docs/source_register.md` with what it
    supports — and the same in a `data/model_sources_<part>.json` file.
- No internet. No new art, no image generation; use the map's existing objects. No edits to files outside your list.
- Panels follow the Prompt 05 rules: built from containers in code, shared theme (`UiTheme` variations), number + unit
  + "?" button (`ExplainButton.make(id)`), colour never the only cue, keyboard reachable, ask with
  `services.request(...)`, never edit state; `UiLayoutCheck` clean at 1280×720, 1920×1080 and 1280×720 with
  `UiTheme.apply_text_scale(1.5)` (set `root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED` in tests).
- Tests: `extends SceneTree`, work in `_initialize()`, `PASS <name>` / `FAIL <name>: <detail>`, then
  `RESULT <passed>/<total>`, `quit(0)` iff all passed. Make a game with `GameServices.new()`, add it to `root`,
  point saves inside your copy (`services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/<you>"), "colony", 2)`),
  `start_new_game(1)`, and call `services.set_process(false)` after a frame when you drive ticks by hand
  (`services.session.advance(dt)` or `services.session.sim.step(...)`). Never print PASS for something not measured.
- Also keep `tests/test_life_support.gd`, `tests/test_session.gd`, `tests/test_saves.gd` passing.

## Shared ids (the contract between parts)

Sectors: `energy`, `life_support`, `food`, `resources`, `science`.

Evidence ids (who records them):

| id | sector | recorded by | when |
|---|---|---|---|
| `energy_predict_net_power` | energy | G | quiz at the power panel answered correctly after looking at the readings |
| `energy_diagnose_output_loss` | energy | G | a dusty panel is cleaned or the cleaner repaired while output was below 80 % of clean |
| `energy_verify_recovery` | energy | G | output back above 95 % of clean within a sol after such a fix |
| `ls_distinguish_inputs` | life_support | G | electrolyser and CO2 unit both run at least one game hour each |
| `ls_co2_removal` | life_support | G | cabin CO2 brought back below the warning level after it rose |
| `ls_storage_vs_pressure` | life_support | G | quiz: oxygen tank vs cabin pressure |
| `food_compare_symptom` | food | F | a plant symptom inspected and a measurement read (`inspect_bed`) |
| `food_adjust_one_cause` | food | F | exactly one input changed on a bed showing a symptom |
| `food_observe_response` | food | F | that bed's growth rate rose after the change |
| `res_identify_compatible` | resources | S | a salvage donor inspected and the compatible part chosen |
| `res_assembly_test` | resources | S | a refurbished component passes its bench test |
| `sci_record_context` | science | S | a field sample taken with its site, time and conditions recorded |
| `sci_compare_controls` | science | S | the sample compared against the reference and a control in the lab |
| `sci_apply_result` | science | S | a lab result applied to a real colony setting (for example a nutrient setting) |

Upgrade ids (catalogue and install by G; effects applied by the part that owns the behaviour):

| id | sector | effect (owner) |
|---|---|---|
| `energy_battery_reserve` | energy | battery capacity +25 % and a protected reserve for life support (G edits power_model.gd) |
| `energy_solar_tracking` | energy | trackers track with less power and +10 % output (G) |
| `energy_cleaner_automation` | energy | the cleaner never stays broken: it repairs itself after a sol (G) |
| `ls_water_reliability` | life_support | recycler +1 L/h and condition floor 0.8 (G) |
| `ls_electrolysis` | life_support | electrolyser +50 % output at the same kWh/kg (G) |
| `ls_co2_processing` | life_support | CO2-oxygen unit +50 % output (G) |
| `ls_oxygen_monitoring` | life_support | earlier, clearer oxygen and cabin-air warnings and a reserve forecast on the HUD (G) |
| `food_irrigation_reliability` | food | beds never dry out while water is allocated (F) |
| `food_nutrient_metering` | food | nutrient level held in the good band automatically (F) |
| `food_scheduled_care` | food | lights and watering run on a schedule with no player action (F) |
| `res_salvage_inspection` | resources | inspecting a donor shows every compatible part at once (S) |
| `res_component_refurbishment` | resources | refurbishing uses less time and recovers one more part from a donor (S) |
| `res_repeat_assembly` | resources | a component type assembled before needs no bench test again (S) |
| `sci_instrument_calibration` | science | lab results carry a smaller uncertainty (S) |
| `sci_sample_comparison` | science | a second reference sample becomes available (S) |
| `sci_evidence_settings` | science | lab results can be applied directly to crop and equipment settings (S, F) |

Tier rule (implementation default from the brief): per sector, tier 0 unfamiliar; tier 1 = a guided task done and its
explanation check answered; tier 2 = independent diagnosis in a changed example; tier 3 = a controlled comparison or a
transfer to new operating conditions. Tiers are shared colony progress (`state.progress.tiers[sector]`). Each card
needs the current tier, its knowledge ids answered, its evidence ids recorded, parts if it consumes parts, the right
installer specialty, and the installer standing at the install station.

---

## Part F — Food (`worker F`)

Files: `scripts/sim/crop_system.gd` (replace stub), `scripts/session/food_actions.gd` (replace stub),
`scripts/core/food_balance.gd`, `data/crops.json`, `data/stations_food.json`, `data/model_sources_food.json`,
`scripts/ui/stations/bed_station_panel.gd`, `scripts/ui/stations/food_station_panel.gd`, `tests/test_food.gd`.

- **Beds**: the six garden-dome planters (`gd_planter` … `gd_planter.005`) and the hydroponics unit (`gd_hydro`) are
  beds (station kind `bed`); the greenhouse console `gh_console` (kind `food`) is the overview and grow-light/water
  control. Small crop set: **lettuce** and **tomato** (the map has `gd_crop_lettuce` and `gd_crop_tomato` meshes;
  read `docs/source_register.md` S11/S13/S14: ISS Veggie grew lettuce; S11 says tomatoes were only *planned* — label
  tomato as "plan, not yet grown on the ISS" and lettuce as ISS analog evidence; neither proves Mars agriculture).
- **Growth**: each bed has crop, stage (seed → sprout → leafy/flowering → ready), growth progress, water level, nutrient
  level and light. Growth rate per game hour = base rate × light factor × water factor × nutrient factor; light comes
  from the Greenhouse zone being powered and not shed (and the grow-light switch); water from the greenhouse water
  allocation actually delivered (read how `LifeSupportModel` delivers it and use that, do not create water); nutrients
  fall as plants grow and are restored by `adjust_nutrients`. Missing light, water or nutrients **slow or stop**
  growth (never instant death; a bed left dry for a sol wilts and must be replanted — say so in an alert first).
  Crop cycles are **time-compressed**: say so on the panel ("about N sols here; weeks to months on Earth"), all rates
  balance. Bed water use goes to wastewater (as the model already does for greenhouse water).
- **Actions** (anyone may do them; the biology and food specialist gets the specialist symbol on the card text but the
  facility stays usable by all): `plant` (bed, `crop`), `inspect_bed` (bed: records a measurement and, if there is a
  symptom, `food_compare_symptom`), `adjust_nutrients` (bed, `level` 0–1), `set_bed_water` (bed, on/off),
  `set_grow_lights` (food console, on/off), `harvest` (bed, ready only: adds meals to `food_meals` **once**, clears the
  bed; ledger term `meals_harvested`). Symptoms (yellow leaves = low nutrients, wilting = dry, leggy pale = low light)
  shown in words with the measurement that proves them. `food_adjust_one_cause` when exactly one input changed on a bed
  with a symptom; `food_observe_response` when that bed's rate rose afterwards.
- **Upgrades** you apply: `food_irrigation_reliability`, `food_nutrient_metering`, `food_scheduled_care` (automation that
  then removes the chore reliably — never breaks on a schedule), `sci_evidence_settings` (accept a nutrient setting
  from a lab result: a `state.science` record the science part writes as `science.results[<id>] = {"kind": "nutrient_setting", "value": 0.0–1.0}`).
- **Panels**: bed panel (crop, stage, progress, time to harvest, the three inputs with words and units, symptom and
  its cause, the actions); food console (all beds, grow lights, greenhouse water allocation shortcut, food store and
  meals per sol for the crew, a "?" on why light, water and nutrients matter, and that stored meals cover the start).
- **Tests prove**: growth stops with no light, slows with low water, slows with low nutrients (each alone), harvest adds
  the right meals exactly once (repeat request is duplicate/refused), bed water draws only from the delivered greenhouse
  allocation (ledger identity still holds), wilting comes after an alert, automation upgrades remove the chore and keep
  working for 10 sols, evidence recorded once in the right order, save/load mid-growth identical, panels pass layout.

## Part S — Science and fabrication (`worker S`)

Files: `scripts/session/science_actions.gd` (replace stub), `scripts/core/science_balance.gd`, `data/samples.json`,
`data/salvage.json`, `data/stations_science.json`, `data/model_sources_science.json`,
`scripts/ui/stations/sample_site_station_panel.gd`, `scripts/ui/stations/lab_station_panel.gd`,
`scripts/ui/stations/salvage_station_panel.gd`, `scripts/ui/stations/workbench_station_panel.gd`, `tests/test_science.gd`.

- **One field-sample → lab comparison activity.** 2–3 sample sites outdoors (new station ids with positions in the
  Exterior, on walkable ground near the base: pick positions from `data/colony_manifest.json` pads or rocks and check
  them against the height grid in a test), kind `sample_site`. `take_sample` (field engineering and geology
  specialist; records `sci_record_context` with site, game time and conditions) gives a `sample` item to carry (uses
  the existing `items` + `pick_up`/`drop` and cargo slots). The lab (kind `lab`: the med-bay glovebox `mb_glovebox`)
  runs `analyze_sample`: compares the sample with a **reference** and a **control**. The reference must be a documented
  NASA/PDS sample product **or** a NASA reference comparison already in `docs/source_register.md` (S06 MSL CheMin,
  S07 SAM are PARTIAL leads: use their *mission/instrument/site* only as provenance and **label any mineral values as
  "illustrative, not from the archive"** unless the register contains them; never present a Gale crater value as a
  measurement of the fictional map). The player chooses an interpretation from 3 options; the result has a practical
  use: a `science.results[<id>] = {"kind": "nutrient_setting", "value": …}` that the food part can apply (or a rock
  type that tells where salvage is safe to dig — your choice, keep it to one). `sci_compare_controls` on a correct
  comparison; `sci_apply_result` when the result is applied (`apply_result` action, or the food part's application).
- **One compatible-salvage → usable-component workflow.** 3–5 salvage donors from **existing damaged objects in the map**
  (look in `data/colony_manifest.json` for wreck/debris/old/broken/damaged names, for example `ls_filter_old`,
  `pr_bat_rack_alarm`, crash-site objects; list them), kind `salvage`. `inspect_donor` (anyone) shows its parts and
  which are compatible; choosing the compatible one records `res_identify_compatible`. `recover_part` (field engineering
  specialist) gives a `salvaged_<part>` item; each donor part can be recovered **once** (state, saved; a reload or a
  second player cannot recover it again). At the workbench (kind `workbench`: the hangar control board
  `hg_control_board` or scissor table `hg_scissor_table`), `refurbish` turns a carried salvaged part into a working
  component and runs a bench test (`res_assembly_test`); the component adds to `state.parts` (or a component item)
  **without creating matter**: input item consumed, output counted, ledger `parts_from_salvage`. No electronics made
  from rock.
- Upgrades you apply: `res_*` and `sci_instrument_calibration`, `sci_sample_comparison`, `sci_evidence_settings`.
- **Tests prove**: wrong specialist refused for specialist steps, distance enforced, a donor part recovered once only
  (also after save/load and with a duplicate request), refurbish consumes exactly the input and adds exactly one output,
  the bench test is required unless `res_repeat_assembly`, sample provenance stored, lab comparison with right and
  wrong interpretations (wrong gives feedback and a retry variant, no penalty to health), result applies once,
  evidence recorded once, panels pass layout, sample sites are on walkable ground.

## Part G — Upgrades, knowledge and learning (`worker G`)

Files: `scripts/sim/progression_system.gd` (replace stub), `scripts/session/progression_actions.gd` (replace stub),
`scripts/core/upgrade_definition.gd` (replace; keep existing fields, add the contract's), `scripts/core/progression_balance.gd`,
`data/upgrades.json` (replace the placeholder cards), `data/questions.json`, `scripts/ui/upgrade_cards_panel.gd` (replace),
`scripts/ui/quiz_panel.gd`, `scripts/sim/power_model.gd` and `scripts/sim/life_support_model.gd` (**only** to apply the
energy and life-support upgrade effects; keep every existing test passing), `tests/test_progression.gd`.

- **Catalogue**: all 16 upgrade ids above in `data/upgrades.json`, each with: function in words, sector, required
  current tier, knowledge question ids, practical evidence ids, parts cost (balance; costs tunable in
  `progression_balance.gd`), installer specialty (energy → electrical_comms, life support → medical_life_support,
  food → biology_food, resources → field_engineering_geology, science → any, or the one that fits best — say which),
  install station id, measurable effect, and source/abstraction labels. Branching: in each sector at least two cards
  are eligible from the same tier, so players choose. Load into `UpgradeDefinition`.
- **Questions** (`data/questions.json`): short contextual questions per sector (2–4 per card), each with 3 answers,
  the right one, a plain explanation tied to the actual equipment, and **retry variants** (a different version with
  changed numbers or situation). Answering right records `state.knowledge[question_id]` once (shared colony progress).
  Wrong: explanation + a variant next time; no health loss; answering the same question again never adds more.
  Tier rules as above; tier 2 needs a diagnosis in a *changed* example (a variant different from the guided one).
- **Actions**: `answer_question` (station of the card or the colony computer; `question_id`, `choice`),
  `install_upgrade` (install station; installer specialty; checks tier, knowledge, evidence, parts; consumes parts
  exactly once; idempotent), plus anything the energy/life-support evidence needs (observe via state in
  `ProgressionSystem.step` and via `events` — for example cleaner repaired while output was low).
- **Exercise and stamina**: a `exercise` action at a gym spot (pick an object in the crew quarters or mess hall;
  add it via a `data/stations_progression.json`) uses stamina now and raises a small `conditioning` value on the
  character (stamina recovers a bit faster, capped); it is **not** an energy refill and never touches the battery.
- **Automation**: once an automation upgrade is installed the chore is removed reliably (no scheduled breakdowns).
- **Panels**: `UpgradeCardsPanel` (replace): cards grouped by sector with the sector tier; for each card the locked
  requirements (tier, each question, each evidence item, parts, installer, station) with ✓/✖ and words, eligible cards
  together so players can choose, the expected resource effect, and a separate Install button (enabled only at the
  station with the right installer); `QuizPanel` (questions, feedback, retry variant). Opened from the colony computer
  (it already opens `UpgradeCardsPanel`) and from the install stations.
- **Tests prove**: eligibility follows tier + knowledge + evidence + parts (each missing one alone keeps it locked with
  the right reason); install consumes parts once and is idempotent; wrong installer or wrong place refused; repeating a
  right answer adds nothing; a wrong answer gives an explanation and a variant, no health change; tier 2 needs a changed
  example; each energy and life-support effect measurably changes the model (and nothing else); automation keeps
  working for 10 sols; exercise uses stamina, raises conditioning, never changes the battery; the whole required
  progression is possible **solo with hub-only swapping** (a scripted solo run that switches crew at the hub to reach
  each specialist and installs one card per sector); save/load keeps knowledge, evidence, tiers and upgrades; panels
  pass layout.
