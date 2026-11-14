# Scout rover and mission-control HUD: handoff

Date: 2026-11-13. Branch `feat/astra-ui-scout`. The owner asked for this directly. It overrides two pack rules: "no new buildings" (the scout bay and its props are made at run time; the map file is unchanged) and "reference UI for design study, not copied screens" (the HUD closely follows ASTRA's layout; credited in `data/credits.json`, MIT, no code or images copied).

## What changed

| Area | Files |
|---|---|
| Scout rover (host sim + actions) | `scripts/vehicle/scout_system.gd`, `scripts/session/scout_actions.gd`, `state.scout` in `ColonyState` |
| World props (run time) | `scripts/vehicle/scout_models.gd`, `scripts/vehicle/scout_presenter.gd` (also the live mast camera and snapshots) |
| Data | `data/stations_scout.json`, `data/scout_sites.json`, `data/model_sources_scout.json`, broken-rover donor in `data/salvage.json`, `also_install_kinds` on the energy cards in `data/upgrades.json` |
| HUD | `scripts/game/mission_hud.gd`, `scripts/ui/hud/*` (vitals bar, goals, minimap, pop-ups, Mission Control card, power / science / build drawers, storm outlook) |
| Panels | `scripts/ui/stations/scout_bay_station_panel.gd`, `ore_deposit_station_panel.gd`; ore section in the workbench; "Scout rover" button on the colony computer |
| Small shared edits | `game_main.gd` (two presenters), `game_hud.gd` (storm chip, alert routing, message placement, cue names), `ui_panel.gd`/`ui_root.gd` (`align_right`), `player_input.gd` (P B H J K F1), `progression_system.gd`, `upgrade_definition.gd`, `session_service.gd` |

## How it plays

1. The scout starts half built at the bay outside the airlock. The field engineer finishes it there for 2 parts.
2. Anyone sends it from the bay or the colony computer to one of five sites. It drives on its own and looks around. Then it radios a report home: a Mission Control card with the mast camera picture. Ore near the site gets marked on the map.
3. The crew walk out and collect the ore (anyone can do this; there are also deposits the scout never saw). At the workbench, hematite becomes spare parts (2 to 1). The other ores raise the science score.
4. The broken-down rover is a salvage donor: a tool kit, a hub motor and a camera.
5. By a sun tracker, B opens the build drawer for the three energy upgrades. They can now be installed there as well as at the power panel.
6. HUD keys:
   - P: power and life-support drawer
   - H: fold the vitals bar (⋯)
   - F1: the science behind the numbers (?)
   - J: fold the goals
   - K: close a Mission Control message
   - Dust storm warnings say how many more storms are lined up in the next 5 sols. They are labelled archive patterns, not a forecast.

## Checks that ran

- `tools/run_tests.ps1`, 21 suites, 1,438 checks, all passing, including the new `test_scout` (60 checks).
- `test_science`: one check changed on purpose. The donor list excludes `broken_rover`, which has no map object.
- Screenshots: 11 shots of the windowed game at 2560×1369 and 1280×720 in `evidence/`, made with `tools/godot/capture_scout.gd` (`godot --path . --script res://tools/godot/capture_scout.gd -- <out folder>`).
- No human playtest.

## Known limits and requests

- **Crew rover (P10A):** the HUD and the scout panel show a goal of "science score 3 + Resources level 1" before crew rover trips. P10A should enforce it in `rover_enter`/`rover_assemble` if the owner agrees.
- **Tutorial objectives (P12):** the goals card shows `state.campaign.objectives` (`[{text, done, fraction?, label?}]`) first, if P12 publishes that list.
- **Mineral facts:** the SC1 to SC4 entries in `model_sources_scout.json` are NASA pages marked *unchecked*. Add them to `docs/source_register.md` before calling them citations.
- **Renderer messages:** the windowed game prints `softshadow_count==0` / "did not unpair" errors. They also appear with the scout presenter removed, so they come from the existing lighting setup, not from this work.
- **Earlier fix:** `.gitattributes` now keeps the weather bundle's bytes exact. On Windows, autocrlf broke its sha256 check, and the game had silently run with no dust storms.
