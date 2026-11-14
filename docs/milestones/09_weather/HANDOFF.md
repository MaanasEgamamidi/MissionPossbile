# Milestone handoff — Prompt 09: NASA weather archive, refresh and varied weather

Date: 2026-11-14. Project: `G:\nasa app\mars_colony_godot`. Built by two parallel Claude subagents, one for the data
and one for the service, from `workers\SPEC_P09.md`; the executor merged and wired them. Prompt 06 (LAN) had been
completed by another session, so the host distributes the weather to clients through the existing state replication.
**Headless tests and compile checks only**, by the owner's instruction; nothing was played.

## 1. Outcome

- **Verified data bundle** (`data\weather\bundle\`, built by `tools\weather\build_bundle.py` from `data\weather\raw\`). Details are in `WEATHER_DATA.md`.
  - **MEDA** (Mars 2020 Perseverance, Jezero crater), PDS bundle `urn:nasa:pds:mars2020_meda` v6.0, DOI 10.17189/1522849.
    - Derived pressure for sols 289, 313, 317 and 579; derived wind for sols 289 and 313; calibrated air temperature for sols 289 and 317. MEDA has no derived air-temperature product.
    - The sols cover a quiet sol, the January 2022 storm's arrival and peak, and the October 2022 event.
    - Every CSV was checked against its label: md5, size, record count and columns.
  - **Dust opacity:** MEDA publishes no derived dust-opacity product, so dust comes from the LMD research archive's kriged dust maps (Montabone et al., v2.5, Mars years 35 and 36, CC BY-SA 3.0), interpolated to Jezero.
    - Only the needed byte ranges were fetched.
    - Values are converted to visible optical depth with the factor the LMD page states.
  - **9 dust episodes** derived by documented steps: above a seasonal background, merged when close, curves every 0.25 sol.
  - **Wind** is measured only for the January 2022 storm. MEDA wind after sol 315 is withheld by the archive (sensor damaged), so 8 episodes say "wind not measured", and wind never drives the simulation.
  - Raw downloads total 29 MB. `validate_bundle.py` and the game's own validator both pass it.
- **Background refresh** (`WeatherRefresh`):
  - Runs at start and hourly in the windowed game, never in headless runs.
  - Uses conditional GETs, timeouts, a size cap and exponential backoff, and swaps the cache atomically.
  - A 304 means up to date. A 200 for an original archive file only means an update was published: the conversion runs in Python, so the validated bundle stays in use and the player is told.
  - Failures keep the last valid cache.
  - The running game keeps its pinned snapshot (`state.data_snapshot_id`); newer data is used from the next new game or load.
- **Seeded weather** (`WeatherSystem`):
  - Has its own saved RNG and queue, and runs on the host only.
  - Events take observed episodes scaled and stretched per seed, keeping the opacity, wind and solar relationships. Gaps vary; there is never a fixed interval.
  - Teaching first: no event until a panel has been cleaned (or 2 sols, whichever is later), and the first event is the smallest episode.
  - Readiness holds: an event waits while the battery is low or an urgent alert is active, and later while panels are dusty and the cleaner is broken.
  - Recovery intervals separate events.
  - It sets `state.dust_tau`, which the power model already uses for sky dimming and dust settling.
- **Return margin** (`ReturnRoutes`): A* over a 2 m walkability grid baked from the height grid and the exact rock shapes (`data\weather\route_grid.res`, tool `tools\godot\bake_route_grid.gd`). Warnings come at least 2× the longest outdoor walk back to the tunnel airlock (door 902), with a 4-game-hour minimum.
- **Presentation and screens:**
  - `WeatherPresenter` dims the sun and sky and thickens the fog smoothly with opacity, with bounded dust particles near an outdoor player. It is added to the game scene after the room lighting.
  - The weather screen on the command room's wall display (`cr_wall_display`, `data\stations_weather.json`) shows the active data, archive dates, last check, current conditions and the next warning. It is labelled "archive observations from Jezero, played faster" and "not a forecast for this colony".
  - Source register entries W01–W12 and 12 weather claims.

## 2. Acceptance (from `test_weather` and `test_weather_data`)

| Check | Result |
|---|---|
| Offline boot | The shipped bundle is used |
| Stale data | A cache older than the shipped bundle is ignored |
| HTTP failure | Cache kept; retries back off 1, 2, 4 … 60 min |
| Invalid units or flags | Rejected |
| Interrupted download | Cache untouched |
| Source update | Swapped atomically, used only from the next session |
| Deterministic replay | Same seed gives the same queue and opacity curve |
| Save/reload mid-storm | Continues identically (continuous values within 1e-9; storm, queue and RNG exact) |
| Late join | A replica has the same weather |
| Varied seeds (20 seeds × 20 sols) | 2–3 events per run, gaps 1.0–3.7 sols, durations 1.1–4.0 sols, severities 0.24–0.78 (maintained colony: up to 1.04, opacity up to 1.38) |
| First-event safety | The smallest episode, after the teaching condition |
| Escalation stays recoverable | Nobody reached zero health; 0 h below the battery reserve outside an event |
| Return margin | At three outdoor points, warnings were 2.3–10.3× the return walk time |
| Refresh mid-storm | Does not change the running storm |

## 3. Checks run (headless only, 2026-11-14)

Compile: **COMPILE OK, 157 scripts**. Suites: All 19 headless suites pass on the merged project, **1,275 checks**: test_saves 56, test_session 91, test_game_services 25, test_collision 40, test_life_support 88, test_food 85, test_science 76, test_progression 84, test_weather_data 14, test_weather 66, test_ui_framework 125, test_sources 76, test_hud_panels 89, test_station_panels 108, test_p07_panels 54, test_player 112, test_net 34, test_net_game 20, test_game_scene 32 (all run headless; logs in `evidence\tests\`). Found and fixed in the combined run: the weather screen was 38 px too wide at 1280×720 (long values now wrap); a station-panel title check assumed every station of a kind shares one name (numbered beds do not).

## 4. Limits

1. **Jezero is a real site, not the fictional colony.** The data are archive observations, and game time runs faster; the screens say so.
2. **Wind data are missing after sol 315.** Mars year 34 (with the 2018 global storm) was left out because its file has no observation dates.
3. **The Montabone papers were not opened.** The dust conversion factor is taken from the LMD web page.
4. **A real network refresh was not run** (headless tests use a fake transport).
5. **Readiness holds can pause storms.** With no player action, storms stop after 2–3 events. This was the trade-off chosen to keep escalation recoverable.
6. **Nothing has been played by a person.**
