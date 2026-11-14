# Prompt 07 — energy and life-support model

Code: `scripts/sim/colony_sim.gd` (tick order), `power_model.gd`, `life_support_model.gd`, `reserve_forecast.gd`,
`scripts/session/system_actions.gd`. Numbers: `scripts/core/game_balance.gd`; categories per field: `data/model_sources.json`.
Test: `tests/test_life_support.gd` (88 checks). Rates are per **game hour**; one sol = 24.6598 game hours (S02).
Categories: **physics** (standard science), **S08** (ISS ECLSS page), **S09-fiction** (MOXIE mechanism; the colony-size
unit is fiction scaled from S09), **balance** (game tuning, no source; never a NASA figure).

## Tick order
Drinking → plan allocations and oxygen output → power allocation and shedding → panel dust / cleaner → greenhouse water,
electrolyser, CO2-oxygen unit, recycler → cabin air (airlock, breathing, scrubber, regulator) → suits → food → health →
alerts. Only active (player-controlled) crew use anything; parked crew are frozen.

## Energy (`PowerModel`)
| Mechanism | Inputs → outputs | Numbers (category) |
|---|---|---|
| Solar, 12 trackers | each = peak/12 × sun term × atmosphere × (1 − panel dust) × tracker condition | peak 100 kW (balance, fiction array) |
| Sun term | tracking (trackers powered): √sin(π(phase−0.25)/0.5); fixed (unpowered/off): sin(…); 0 at night | ≈ 20 % more energy per sol when tracking (physics of the curve) |
| Atmosphere | exp(−0.6 × (dust_tau − 0.5)), = 1 at the default sky | factor 0.6, default τ 0.5 (balance, mechanism only) |
| Panel dust | +0.02 per sol × τ/0.5 on each panel; cleaner (condition ≥ 0.5, on, powered) wipes all at sunrise; `clean_panel` wipes one | start 0.45, cleaner failed (balance) |
| Battery | stored = in × 0.9, loss ledgered | 560 / 800 kWh, charge ≤ 80 kW, discharge ≤ 45 kW, warn < 30 % (balance) |
| Loads | base 4 + critical lights (Life Support, Power Room, Airlock, Med Bay); room lights (Greenhouse 9, Hangar 1, plaza/garden 0.8, Exterior 0.6, others 0.2–0.4); trackers 0.6, cleaner 0.2, recycler 1.0, scrubber 1.5, fans 0.6; electrolyser 6 kWh/kg × output; CO2 unit 20 kWh/kg × output | all kW, balance |
| Shedding | while demand > solar + battery limit, whole groups go, lowest first: lights → greenhouse → CO2 unit → electrolyser → recycler → trackers → cleaner → scrubber → fans → base | shed load = "on but unpowered"; alert names it |

Ledger (kWh): `battery_now = start + battery_in − battery_loss − battery_out`; `solar_offered = solar_used + solar_curtailed`;
`load_served = solar to loads + battery_out`; `load_unserved` = shed kW × hours.

## Water and oxygen (`LifeSupportModel`)
- **Use**: 0.25 L/h per active astronaut (balance); 85 % returns as wastewater, the rest is lost (balance). Drinking is
  always first. Allocations (`set_water_allocation`, 0–20 L/h each) take only water above the 100 L drinking reserve
  (balance); if short, greenhouse and electrolyser get the same share. Greenhouse water goes to wastewater for now.
- **Recycler**: up to 3 L/h (balance), 1 kW; returns **90 %** as clean water (**S08**, "about 90 percent"), the rest is
  brine. Off, broken (< 0.5) or unpowered → wastewater builds up (alert). Below condition 0.8 its water has quality
  condition / 0.8; quality mixes by volume. **Drinking ignores quality** (kept simple on purpose).
- **Electrolyser** (S08 mechanism): needs power, condition ≥ 0.5, feed allocated, quality ≥ 0.9 (balance). Up to
  0.2 kg O2/h (balance) at 6 kWh/kg (balance; physics minimum ≈ 4.1). Uses exactly **1.126 L water per kg O2** and vents
  hydrogen = water × 2/18 (**physics**). Short feed → proportionally less.
- **CO2-oxygen unit** (S09-fiction): Mars CO2 and power only, up to 0.15 kg O2/h (≈ 12.5 × MOXIE's 12 g/h) at 20 kWh/kg
  (balance). CO is vented (56/32 per kg O2, physics). Its code path has no water term; tested in 64 switch combinations.
- Both, either or neither may run; `state.oxygen_process` reports each one's status.
- **Oxygen reserve** (`oxygen_kg`, tanks, 60 / 150 kg, balance) is not the cabin air.

## Cabin air, pressure, suits
- One volume 400 m³ at 295 K (balance). Masses of O2, N2, CO2; partial pressures by p = m/M·R·T/V (**physics**). Start
  21 / 79 / 0.1 kPa (balance, Earth-like).
- Inside crew breathe 0.035 kg O2/h and add 0.042 kg CO2/h (balance). Outside crew breathe from the suit only.
- **Scrubber** (S08 mechanism: molecular sieves): up to 0.4 kg CO2/h, not below 0.1 kPa; 25 % without fans (balance).
  Alerts at 0.5 kPa, harm above 1.0 kPa (balance).
- **Regulator** (no power needed): back to 21 kPa O2 from the reserve and 79 kPa N2 from the N2 reserve (60 / 120 kg),
  at most 3 kg/h per gas (balance). Empty reserve → cabin O2 falls slowly (≈ 75 h to the 19 kPa warning with 4 crew).
- **Airlock**: `note_airlock_cycle()` queues a cycle; the next tick removes 2 kg of cabin air in proportion (balance).
  Pressure < 90 kPa → alert.
- **Suits**: `outside` comes from `SessionService.outside_test` in `report_position`. Tank 0.4 kg (≈ 11 h, balance).
  No suit or empty tank outside → 25 health/h with an urgent alert. `refill_suit` moves O2 from the reserve; the suit
  check never changes the tank.
- **Health** (per active character, each scaled by severity): low O2 < 16 kPa up to 40/h, CO2 > 1 kPa up to 20/h, no air
  outside 25/h, no water 6/h, no food 3/h (balance). Zero health → existing hub recovery.

## Alerts and forecast
`state.alerts` is recomputed every tick (`id`, `level`, `text`, `since_hours`); a new id is announced once through
`events.system_alert`. `ReserveForecast.compute()` gives hours until empty (−1 = not falling) for the oxygen reserve,
water, food and each outside suit (straight line at the last tick's net rate), and steps the battery forward with the
current loads and the real sun curve for up to 3 sols (hours until empty, charge at the next sunrise), plus text lines.
Measured against forward simulations: within 2 % (most within 0.2 %).

## Starting conditions and why they are safe (measured in the test)
Arrival: cleaner failed, panels 45 % dusty, electrolyser and CO2 unit off, everything else on, all rooms lit.
With 4 active crew and **no action**: the battery falls about 90–110 kWh per sol (482 → 385 → 271 kWh at sunrise), its
lowest point in 3 sols is 265 kWh; the oxygen reserve falls 3.45 kg/sol (60 → 49.6 kg); water barely moves (recycler);
nobody is harmed. Warnings at once: "Panel cleaner is broken", "panels dusty". Left alone longer, "Battery low" comes at
93 h, 29 h before the first load is shed (122 h); nights then run dark but the sun restarts everything each day; the
first harm is hunger at 197 h (food runs out — the food milestone adds growth), 25 h after "Food low".
**Restoration** (clean the 12 panels, the electrical specialist repairs the cleaner, feed 0.5 L/h and switch on the
electrolyser and/or the CO2 unit): over a sol the panels collect 936 kWh against 604–678 kWh used plus 34–38 kWh battery
loss; from 300 kWh at sunrise the battery ends the sol at 458–496 kWh; oxygen reserve +1.48 (electrolyser), +0.25 (CO2
unit) or +5.18 kg/sol (both).

## Simplified on purpose
No equipment wear (condition changes only by repair or events); one cabin volume; constant temperature; regulator and
greenhouse water need no power; failed equipment draws nothing; shedding is whole groups; drinking ignores water quality;
hydrogen and CO are vented, not used; the battery forecast keeps today's loads fixed.

## What later milestones plug in
Weather: set `state.dust_tau` (sky dimming and dust settling follow). Food: use the greenhouse water allocation and the
Greenhouse light load. Events/wear: change `equipment[x].condition`. Panels (UI): read `equipment`, `alerts`,
`oxygen_process`, the `flows_dict()` values and `ReserveForecast.compute()`.
