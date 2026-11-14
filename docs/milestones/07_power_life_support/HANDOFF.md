# Milestone handoff — Prompt 07: Power, water and two oxygen processes

Date: 2026-11-12. Project: `G:\nasa app\mars_colony_godot`. Done after Prompt 05; Prompt 06 was skipped at the owner's
request. Prompt 07's prerequisites (simulation, crew, station and UI contracts; checked NASA references) do not
include Prompt 06.

## 1. Outcome

The colony now runs on a connected energy and life-support model:
- **Solar:** 12 sun trackers whose output depends on the sun's angle, tracking or fixed mounting, dust in the air, dust on each panel and condition.
- **Battery:** charge and discharge limits and charging losses.
- **Power allocation:** loads are shed automatically by priority when supply runs short.
- **Water:** clean water and wastewater, a recycler (returns 90 %, S08), water quality, and a player-set allocation.
- **Oxygen:** two separate processes, electrolysis of water (S08) and a CO2-from-Mars-air unit (MOXIE mechanism, S09, colony scale is fiction).
- **Cabin air:** O2, N2 and CO2 tracked separately, with a CO2 scrubber, a pressure regulator and airlock losses.
- **Suits:** the tank is used only outside and refilled only from the colony reserve.
- **Alerts and forecasts:** warnings with causes in words come before any harm, and a reserve forecast shows when each store runs out.

Panels show and operate all of it: power, life support, sun trackers, suit rack, colony summary, and HUD alerts.

Every number is game configuration with a category and source label (`data\model_sources.json`). No old browser-demo
power figures are used. Full model description: `MODEL.md` in this folder.

## 2. Acceptance, item by item

| Check | Result |
|---|---|
| Conservation and capacity over 5 sols with switching | Every ledger identity holds within 3e-11. |
| Zero input: night, no water | Battery only at night; the electrolyser makes nothing without feed water. |
| Overload | Shedding follows the order exactly: lights → greenhouse → CO2 unit → electrolyser → recycler → trackers → cleaner → scrubber → fans → base. The alerts name the loads and unserved energy is recorded. |
| Solar cleaning, cleaner repair (electrical specialist only), tracker power | All proven, including the expected output ratios. |
| Powered and unpowered pumps | Wastewater builds up only when the recycler is off; the alert is raised once. |
| Each oxygen path alone, both, neither | Proven. The CO2 unit uses no water in any of 64 switch combinations. Electrolysis uses exactly 1.126 L of water per kg O2 (physics). |
| CO2 removal | Scrubber off: CO2 rises to the warning level and an alert comes before any harm. |
| Pressurised boundary | Airlock cycles lower the pressure; the regulator restores it from the reserves. In the game, opening the outer tunnel door counts as one cycle. |
| Suit use and refill | The tank is used only outside. Refill takes exactly from the reserve. The suit check and recovery never refill it. |
| Active-count changes | 1–4 active crew; parked crew use nothing. |
| Recovery with empty shared stores | Succeeds; stores stay ≥ 0. |
| No creation by toggling or save/load | 1,000 toggles create nothing. Save → load → continue matches an uninterrupted run within 3e-14. |
| Tutorial-safe start | Four active crew, no action for 3 sols: nobody harmed. The lowest battery reached is 265 kWh. The first warning comes 104 h before the first harm. After the arrival restoration (clean the panels, repair the cleaner, run an oxygen process) the colony is energy- and oxygen-positive. |
| Forecast | Within 2 % of a forward simulation. |
| Sol length | A full sol at 5, 20 and 120 real minutes ends with the same stores (largest difference 0.0039 %). |
| Readings and causal feedback in native panels | Supply and demand, battery reserve, water allocation and both oxygen processes are shown side by side ("only the electrolyser uses water"). Cabin air is shown separately from the oxygen in the tanks. `system_alert` reaches the HUD. |

Suites: `test_life_support` 88/88, `test_p07_panels` 54/54, and all twelve suites 829/829 (see the Prompt 05 handoff).
Screens: `..\05_ui\evidence\screens\04_power_panel.png`, `05_life_support.png`, `06_solar_tracker.png`, `07_suit_rack.png`.

## 3. Changed files

New: `scripts\sim\power_model.gd`, `life_support_model.gd`, `reserve_forecast.gd`, `scripts\session\system_actions.gd`,
`data\model_sources.json`, `tests\test_life_support.gd`, `tests\test_p07_panels.gd`; UI panels listed in the
Prompt 05 handoff.
Rewritten: `scripts\sim\colony_sim.gd`, `scripts\core\game_balance.gd`, `scripts\state\colony_state.gd`.
Edited: `scripts\state\character_state.gd` (`outside`), `scripts\session\session_service.gd` (`outside_test`,
`note_airlock_cycle`), `scripts\world\station_catalog.gd` and `world_collision.gd` (sun trackers are stations),
`scripts\core\game_services.gd` (outside = Exterior zone), `scripts\game\game_main.gd` (airlock cycles).

## 4. Interfaces

New actions:
- `set_equipment`
- `set_water_allocation`
- `clean_panel`
- `repair_cleaner` (electrical and communications specialist)
- `refill_suit`

New state:
- `equipment`, `panel_dust`, `dust_tau`
- `wastewater_l`, `water_quality`, `water_allocation`
- cabin gas masses, `n2_reserve_kg`
- `alerts`, `rates`, `oxygen_process`

Also: `ReserveForecast.compute(state, balance, clock)` and `events.system_alert`.

Later milestones plug in as follows:
- **Weather (Prompt 09)** sets `state.dust_tau`.
- **Food (Prompt 08)** uses the greenhouse water allocation and light load.
- **Wear and events** change `equipment[x].condition`.

## 5. Defects and limits

1. The model is deliberately simple: one cabin volume, constant temperature, no equipment wear, and drinking ignores water quality. See `MODEL.md`.
2. **Every rate is balance**, except the 90 % recovery (S08), the stoichiometry (physics) and the mechanisms (S08, S09).
3. **Dust (S18) is still an unchecked lead**, so the dust mechanism is labelled as game balance.
4. **The owner's existing save** loads with the new systems at their defaults: cleaner broken, panels dusty. Nothing is lost.
5. **"Outside" is the Exterior zone only**; the dome plaza and garden dome count as pressurised.
6. **No human play of the restoration sequence**; it is checked by model tests only.
7. **Some model texts still write "CO2"** where the panels show "CO₂".
