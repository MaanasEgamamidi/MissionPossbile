# Prompt 07 panels: show and operate the power and life-support model

The game's energy and life-support model is built (read `docs\milestones\07_power_life_support\MODEL.md` first, then
`scripts\sim\power_model.gd`, `scripts\sim\life_support_model.gd`, `scripts\sim\reserve_forecast.gd`,
`scripts\session\system_actions.gd`, `scripts\state\colony_state.gd`, `scripts\core\game_balance.gd`,
`data\model_sources.json`). The Prompt 05 UI is built too (read `G:\nasa app\_work\SPEC_P05.md` for its rules,
then `scripts\ui\ui_panel.gd`, `ui_theme.gd`, `ui_layout_check.gd`, `reading_row.gd`, `explain_button.gd`,
`explanations.gd`, `station_panel.gd`, `station_panels.gd`, `power_station_panel.gd`, `colony_summary_panel.gd`,
`blueprint_panel.gd`, and the tests `tests\test_station_panels.gd`, `tests\test_hud_panels.gd`). All Prompt 05 rules
apply: panels built in code from containers, shared theme only, plain words for ages 9–12, number + unit + "?",
colour never the only cue, keyboard reachable, `UiLayoutCheck` clean at 1280×720, 1920×1080 and 1280×720 with text
scale 1.5 (set `root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED` in tests, as the existing tests do),
panels only read state and ask with `services.request(action, target, params)`.

**Right now four UI files do not compile**, because the model removed the placeholder balance fields
`water_recycle_fraction`, `oxygen_kg_per_hour_generated`, `oxygen_generation_kw` and `health_loss_per_hour_no_oxygen`:
`scripts\ui\colony_summary_panel.gd`, `scripts\ui\power_station_panel.gd`, `scripts\ui\station_panel.gd`,
`scripts\ui\blueprint_panel.gd` (and the tests `tests\test_hud_panels.gd`, `tests\test_station_panels.gd`). Move them
to the real model as below.

## What to build

Actions available (host validates): `set_equipment` (target = a `lifesupport` or `power` station; `equipment`: one of
`trackers`, `cleaner`, `recycler`, `scrubber`, `electrolyser`, `co2_unit`, `cabin_fans`; `on`), `set_water_allocation`
(target = `lifesupport` station; `greenhouse_l_per_hour`, `electrolysis_feed_l_per_hour`, 0–20), `clean_panel`
(target = a `solar` station, a tracker), `repair_cleaner` (target = a `solar` station; only the electrical and
communications specialist), `refill_suit` (target = the `suits` station), `begin_suit_check` (`on`), `set_zone_power`.

1. **`PowerStationPanel`** (update; kind `power`): supply and demand right now (solar kW, battery kW in or out, total
   load kW, served vs shed), the battery as an amount (kWh of capacity, %) with the forecast from `ReserveForecast`
   ("lasts until about …", "at the next sunrise about … kWh"), switches for room lights (existing) **and** for the
   equipment (`set_equipment`), each with its kW; which loads are shed now and why, in words, with the shedding order
   explained; a one-line cause-and-effect sentence after each change. ExplainButtons (`battery`, `load`,
   `power_deficit`, `stock_vs_flow`, `zones_power`).
2. **`LifeSupportStationPanel`** (new; kind `lifesupport`, returned by `StationPanels.for_station`): three sections.
   *Water*: clean water and wastewater (L), quality (% and a word), recycler on/off and status, **water allocation**
   (two sliders, L per hour, sent with `set_water_allocation` on release; a sentence that drinking always comes first
   and the protected reserve). *Oxygen*: the reserve (kg) with forecast, and **both oxygen processes side by side** —
   Electrolyser (uses water: show L/h taken; status and the reason it is stopped) and CO2-oxygen unit (uses Mars air,
   no water; status) — each with on/off and kg per hour made and kW used; make it obvious that only the electrolyser
   uses water. *Cabin air*: O2, CO2 and total pressure in kPa with ok/warn/urgent words, scrubber and fans switches,
   and a sentence that safe air in the rooms is not the same as the oxygen in the tanks. Show `state.alerts` for these
   systems at the top in words.
3. **`SolarStationPanel`** (new; kind `solar`, one per tracker): this tracker's dust (%) and output (kW), the whole
   array's output, whether the trackers follow the sun (tracker power), the cleaner status; buttons "Clean this panel"
   (`clean_panel`) and "Repair the cleaner" (`repair_cleaner`, shown for everyone but disabled with the reason in words
   unless the local character is the electrical and communications specialist and the cleaner is broken).
4. **`SuitRackPanel`** (new; kind `suits`): your suit on/off with a button that starts the one-second suit check
   (`begin_suit_check {on}`), your tank (%) and the oxygen reserve (kg), and "Fill tank from colony oxygen"
   (`refill_suit`), saying how much oxygen it will take from the reserve and that this is the only way to fill a tank.
   `StationPanels.for_station` now returns it for `suits` (it returned null before).
5. **`ColonySummaryPanel`** (update): flows from the real model — use `state.rates` (per game hour) and
   `ReserveForecast.compute()` for time left, `state.solar_kw` / `state.load_kw` and the battery kW for power; add a
   short "oxygen made by each process" line and the cabin air line. Keep its existing explanation boxes.
6. **`StationPanel`** (update): remove use of the removed fields; the lifesupport kind is now its own panel.
   **`BlueprintPanel`** (update): remove use of `oxygen_generation_kw`; mark the 12 solar trackers on the plan with a
   sun symbol and their dust as a word when > 30 %.
7. **HUD**: `GameHud` shows the newest `system_alert` (connect `services.events.system_alert`) in its message line, and
   its urgent readings use the cabin air (O2 kPa low, CO2 kPa high) as well as the stores.

Files you own (create or replace only these): `scripts\ui\power_station_panel.gd`, `scripts\ui\life_support_station_panel.gd`,
`scripts\ui\solar_station_panel.gd`, `scripts\ui\suit_rack_panel.gd`, `scripts\ui\station_panels.gd`,
`scripts\ui\station_panel.gd`, `scripts\ui\colony_summary_panel.gd`, `scripts\ui\blueprint_panel.gd`,
`scripts\ui\blueprint_view.gd`, `scripts\game\game_hud.gd`, `data\explanations.json` (add ids: `wastewater`,
`water_quality`, `water_allocation`, `electrolysis`, `co2_oxygen_unit`, `cabin_air`, `co2_scrubber`, `pressure`,
`panel_dust`, `sun_trackers`, `load_shedding`, `battery_forecast`, `suit_refill`; each with title, short, long,
source_ids and claim_ids that exist in `data\sources.json` / `data\claims.json`; S08 and S09 are the only checked
life-support sources), `tests\test_station_panels.gd`, `tests\test_hud_panels.gd`, `tests\test_p07_panels.gd`.

## `tests\test_p07_panels.gd` must prove
Every station of a new game maps to the right panel class (21 stations: 9 + 12 trackers); each equipment switch
sends exactly one `set_equipment` with the right id and value and the panel reflects the state after the host's
answer and a tick; water sliders send one `set_water_allocation` per release with the values; the life-support panel
shows the electrolyser's water use and none for the CO2 unit, and the stopped reason when the feed is 0 or quality is
low; cabin readings show kPa with words and change level when CO2 is raised; the power panel lists shed loads in
words after forcing an overload (switch everything on at night with a nearly empty battery, tick); the forecast text
matches `ReserveForecast.compute()`; the solar panel cleans one tracker (dust → 0) and the repair button is disabled
for a non-electrical character with the reason and enabled for the electrical one when the cleaner is broken; the
suit rack fills the tank from the reserve (reserve falls by exactly what the tank gains) and starts the suit check;
`system_alert` text reaches the HUD message line; every panel passes `UiLayoutCheck` at the three sizes. Also keep
`tests\test_station_panels.gd` and `tests\test_hud_panels.gd` passing (update only expectations the model
legitimately changed, and list them).
