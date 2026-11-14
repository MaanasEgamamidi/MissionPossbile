# Milestone handoff — Prompt 08: Food, science, fabrication and earned upgrades

Date: 2026-11-14. Project: `G:\nasa app\mars_colony_godot`. Blender 5.3 and Godot 4.7.2 (MCP now connected to this
project) were checked before work began. Built by three parallel Claude subagents (Codex is signed out, I-47), each in
its own project copy from one specification (`workers\SPEC_P08.md`). The executor wrote the shared hooks first and
merged the parts:
- simulation hooks, per-part state, action files and station data files
- station panels found by naming convention, and `ProgressEvidence`
- the merge itself, then the cross-part wiring

**Owner's instruction for this milestone:** headless tests and compile checks only. The owner tests run time and
gameplay. No windowed captures were made, and **no person has played any of it**.

## 1. Outcome

- **Food.** The six garden-dome planters and the hydroponics unit are beds, and the greenhouse console runs grow lights and water.
  - Lettuce: ISS analog evidence, S11.
  - Tomato: "a plan, not yet grown on the ISS", S11/S13.
  - Growth follows light (the Greenhouse room's power, shed or not), the greenhouse water actually delivered, and nutrients.
  - Missing inputs slow or stop growth. A bed left dry for a sol wilts, after an alert.
  - Harvest adds meals to the food store exactly once.
  - Symptoms (yellow leaves, wilting, leggy and pale) come with the measurement that proves them.
  - Cycles are time-compressed and the panel says so.
  - Diagnosis evidence: compare a symptom, change exactly one cause, see the growth respond.
- **Science.**
  - Three outdoor sample sites, on walkable ground checked against the height grid.
  - The field engineer takes a sample, recording site, time and sky.
  - At the med-bay glovebox it is compared with a reference and an empty-holder control, and the player chooses an interpretation. A wrong choice gets feedback and a retry with new numbers; there is no penalty.
  - The result is a nutrient setting for the greenhouse.
  - The reference names Curiosity / CheMin / Gale crater (`msl-m-chemin-4-rdr-v1`) as provenance only. Its mineral shares are labelled **"illustrative, not from the archive"** because the register has no values. Gale is never presented as a measurement of the fictional map.
- **Fabrication.**
  - Five damaged objects already in the map are salvage donors.
  - Inspect a donor and choose the compatible part (anyone); the field engineer recovers it once per donor part, which holds across reloads and other players.
  - At the hangar workbench it is refurbished, and a bench test turns it into one spare part.
  - The input item is consumed and the output counted (`parts_from_salvage`). No matter is created.
- **Upgrades and learning.**
  - 16 cards across the five sectors from the brief's table, each with function, tier, questions, practical evidence, parts cost, installer specialty, install station, measurable effect and source labels. Catalogue in `data\upgrades.json`.
  - 32 contextual questions, each with retry variants (`data\questions.json`).
  - Tiers 0–3 per sector are shared colony progress; tier 2 needs a diagnosis in a changed example.
  - Eligible cards are shown together so players choose. Locked reasons are given in words.
  - Install consumes parts exactly once and is idempotent.
  - Automation upgrades remove a chore reliably, with no scheduled breakdowns.
  - Exercise at the rec-kitchen treadmill uses stamina and builds conditioning; it never touches the battery.
- **Wired across parts** (executor):
  - A lab result reaches the beds by one path. The science `apply_result` and the food `apply_nutrient_result` both set the beds' nutrient level, mark the result used once, and record `sci_apply_result` once.
  - Nutrient metering holds the lab's setting when one was applied.
  - Greenhouse warnings join the colony's warning list.
  - Two shared-hook bugs found by the workers were fixed: custom station panels never opened, and new station kinds were missing from the blueprint legend.

## 2. Acceptance

| Check | Result |
|---|---|
| Crops stop or slow under each missing input | `test_food`: no light stops growth; low water and low nutrients each slow it |
| Harvest adds the right stock once | `test_food`: exact meals; a repeat request is a duplicate |
| Bed water only from the delivered allocation | `test_food`: the ledger identity holds |
| Fabrication validates compatible inventory, no matter created | `test_science`: one input consumed, one output; the bench test is required unless the upgrade is installed |
| A donor part is recovered once | `test_science`: also after save/load and on a duplicate request |
| Eligible and locked upgrades follow knowledge and task evidence | `test_progression`: each missing tier, question, evidence item or parts amount alone keeps the card locked with the right reason |
| No bypass by a wrong role or a distant action | `test_progression`, `test_science`: wrong specialist and too far are refused |
| Required progression possible solo with hub-only swapping | `test_progression`: a scripted solo run switches crew at the hub and installs one card per sector |
| Repeating a quiz cannot farm mastery or duplicate an unlock | `test_progression` |
| Exercise is not an energy refill | `test_progression`: the battery is unchanged |
| Upgrade effects change the model measurably, and nothing else | `test_progression`, with `test_life_support` still passing |

Suite results on the merged project: see section 5.

## 3. Files

- **Food:** `scripts\sim\crop_system.gd`, `scripts\session\food_actions.gd`, `scripts\core\food_balance.gd`, `data\crops.json`, `data\stations_food.json`, `data\model_sources_food.json`, `scripts\ui\stations\bed_station_panel.gd`, `food_station_panel.gd`, `tests\test_food.gd`.
- **Science:** `scripts\session\science_actions.gd`, `scripts\core\science_balance.gd`, `data\samples.json`, `salvage.json`, `stations_science.json`, `model_sources_science.json`, `scripts\ui\stations\sample_site_station_panel.gd`, `lab_station_panel.gd`, `salvage_station_panel.gd`, `workbench_station_panel.gd`, `tests\test_science.gd`.
- **Progression:** `scripts\sim\progression_system.gd`, `scripts\session\progression_actions.gd`, `scripts\core\upgrade_definition.gd`, `progression_balance.gd`, `data\upgrades.json`, `questions.json`, `stations_progression.json`, `model_sources_progression.json`, `scripts\ui\upgrade_cards_panel.gd`, `quiz_panel.gd`, `scripts\ui\stations\gym_station_panel.gd`, `tests\test_progression.gd`. Effects are applied in `scripts\sim\power_model.gd` and `life_support_model.gd`.
- **Shared:** `scripts\sim\colony_sim.gd` (pre/post systems, greenhouse alerts), `scripts\sim\progress_evidence.gd`, `scripts\state\colony_state.gd` (`crops`, `science`, `progress`, `weather`, `has_upgrade`), `scripts\world\station_catalog.gd` and `world_collision.gd` (stations from `data\stations_*.json`), `scripts\ui\station_panels.gd` (panel convention, names and symbols from data), `scripts\ui\blueprint_view.gd` (legend), `tools\godot\check_compile.gd`.
- **Tests changed:** station-count checks now count the 21 base stations exactly; stations added by data files need only a known kind (`test_session`, `test_game_services`, `test_collision`, `test_p07_panels`, `test_station_panels`). The upgrade-card checks in `test_station_panels` now check the real 16 cards.

## 4. Numbers and sources

Every number is game balance with its category in `data\model_sources_food.json`, `model_sources_science.json` and `model_sources_progression.json`.
- **Lettuce:** 3 sols per cycle, 5 meals.
- **Tomato:** 6 sols, 12 meals.
- **Beds:** each holds 6 L. Growth is at full speed from 50 % soil water; drip lines clog 25 % per sol; the good nutrient band is 40–80 %.
- **Card costs:** 2–4 parts. The 10 starting parts buy one card per sector.
- **Science values:** mineral shares are illustrative; nutrient settings are balance.

Sources: S11 and S13 (crops, analog only), S06 (CheMin provenance only). No new source was checked in this milestone.

## 5. Checks run (headless only, 2026-11-14)

- Compile: `tools\godot\check_compile.gd` loads every script: **COMPILE OK, 157 scripts**.
- Suites: All 19 headless suites pass on the merged project, **1,275 checks**: test_saves 56, test_session 91, test_game_services 25, test_collision 40, test_life_support 88, test_food 85, test_science 76, test_progression 84, test_weather_data 14, test_weather 66, test_ui_framework 125, test_sources 76, test_hud_panels 89, test_station_panels 108, test_p07_panels 54, test_player 112, test_net 34, test_net_game 20, test_game_scene 32 (all run headless; logs in `evidence\tests\`). Found and fixed in the combined run: the weather screen was 38 px too wide at 1280×720 (long values now wrap); a station-panel title check assumed every station of a kind shares one name (numbered beds do not).

## 6. Limits and defects

1. **Nothing has been played by a person.** Run time and game bugs are the owner's test.
2. **The map's crop meshes don't change** with crop stage.
3. **Some "?" buttons reuse general explanation ids**; science and fabrication wording is written into the panels instead.
4. **The exercise station's symbol (♥) is the same as the patient's.**
5. **Conditioning is stored in `state.progress`**, not on the character; stamina is still the local feel in the player controller.
6. **Install stations other than the colony computer don't open the upgrade cards.** Each card's Questions button opens the quiz.
7. **The upgrade catalogue implements the brief's table.** The owner has not approved the specific questions, costs or effects.
