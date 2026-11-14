# Milestone handoff — Prompt 05: Native game UI, controls and sources

Date: 2026-11-12. Project: `G:\nasa app\mars_colony_godot` (Godot 4.7.2). Blender 5.3 and Godot 4.7.2 access was
checked before work began (Godot needed two rechecks; see D-09 context in `decisions.md`).

## 1. Outcome

The game now has its own native interface, built from Godot Control nodes with one shared Theme:
- **Menus:** a main menu (continue, new colony, host and join, settings, sources and credits, quit), a pause menu, and settings with key remapping.
- **In-game screens:** a small HUD, a colony summary, crew selection, cargo, upgrade cards, a blueprint map, and a surface for every station.
- **Source register:** opens with Shift + Backspace from anywhere and works offline.

Everything is checked by automated tests, layout checks and screenshots of the running game. **No person has used
the screens yet**; whether children aged 9 to 12 find them readable is untested.

Prompt 06 (LAN co-op) was skipped at the owner's request (D-10). Host and Join exist in the menu and explain that
playing together is not built yet. The request path every screen uses is already network-ready (section 4).

How it was built: the executor wrote the shared contracts first: `UiPanel`, `UiTheme` names, `UiLayoutCheck`, request
routing in `GameServices`, and stubs. Four parallel workers then built the four parts from one specification
(`workers\SPEC_P05.md`): framework and menus, sources, HUD and crew, stations and map. Codex was signed out, so they
ran as Claude subagents instead of Codex `gpt-6-astra` (I-49). The executor merged the parts, fixed what the combined
run exposed, and wired them into the game scene. A separate owner session, "Game UI improvements with Godot",
restyled parts of the UI at the same time; its changes were kept by three-way merging (I-50).

## 2. Acceptance, item by item

| Requirement | Result | Evidence |
|---|---|---|
| Native menus and HUD with one shared Theme | **Met.** `UiTheme` builds one Theme in code; every panel uses its type variations. | `test_ui_framework` (contrast and focus styles for every variation) |
| Start, continue, host, join | **Start and continue met. Host and join present but not working** (Prompt 06 skipped); the menu says so in plain words. | `screens\01_main_menu.png` |
| Small readable HUD, interaction cues, colony summary | **Met.** HUD shows sol and time, at most three urgent readings (otherwise "Colony OK ✓"), crew member, health, body energy, suit tank, the E cue, and messages. Colony summary separates stocks from flows, gives time left and causes. | `test_hud_panels` 89/89; `screens\02_hud_first_person.png`, `03_colony_summary.png` |
| Specialist selection | **Met as crew selection** (C key, pause menu): four cards with portrait, specialty, status, refusal reason in words. Hub rule enforced by the host. | `test_hud_panels`; `screens\08_crew.png` |
| Upgrade cards | **Met as display.** 8 placeholder cards across the five sectors, with cost against parts, installer, effect and locked reason. Install is disabled until Prompt 08. | `test_station_panels`; `screens\11_upgrades.png` |
| Station surfaces | **Met.** 21 stations (9 tagged in the map + 12 sun trackers): power, life support, solar, suit rack, colony computer, comms, greenhouse, med station, board, patient. | `test_station_panels` 70/70, `test_p07_panels` 54/54 |
| Inventory and cargo | **Met** (I key): slots, put down, known caches. | `screens\09_cargo.png` |
| Blueprint | **Met** (M key): plan drawn from the map data with rooms, dome, pads, stations, crew, items, caches, unpowered rooms, sun trackers and a legend. Zoom, pan and "centre on me". | `screens\10_blueprint.png` |
| Settings | **Met:** UI scale, text size (1.0 / 1.25 / 1.5), high contrast, subtitles, reduce motion, FOV, mouse sensitivity, invert Y, toggle sprint, full key remapping. | `test_ui_framework`; `screens\13_settings.png` |
| Pause voting | **Met for solo** (pauses at once). Co-op vote counts are shown when they exist; untested without Prompt 06. | `test_ui_framework`; `screens\14_pause_menu.png` |
| Portraits, symbols, short text; colour supports, never alone | **Met by design** (✓ / ! / ✖ with words). Portraits are small 3D renders of the crew model, with a drawn badge as fallback. | screens |
| Explain stamina vs electricity, stock vs flow | **Met.** HUD labels stamina "Body energy" and the battery "colony electricity"; explanation boxes and "?" buttons. | `test_hud_panels` |
| Few urgent readings, details on demand | **Met.** At most 3 on the HUD; full units and causes in the panels and behind "?". | `test_hud_panels` |
| UI scaling, subtitles, remapping, sensitivity and FOV, visible focus, contrast, alternatives to timed or precise inputs | **Met.** WCAG 4.5:1 contrast checked for every label variation over light, dark and orange backgrounds. Toggle sprint is the hold alternative. The only timed action, the 1 s suit check, is automatic. | `test_ui_framework` 118/118 |
| Shift + Backspace source register, offline | **Met.** 38 sources and 16 claims built from `source_register.md` by `tools\build_source_data.py`. No network calls; links open the browser only when pressed. | `test_sources` 76/76; `screens\12_sources.png` |
| Claims mapped with mission, site, dates, units, status, primary link | **Met where the register has the data.** Claims citing only unchecked pages show "Source not yet checked", never a citation. | `test_sources` |
| Archive vs game-time vs fiction vs balance distinguished | **Met.** Each claim has a category, shown in words. | `data\claims.json` |
| Credits | **Met.** Licences not yet established are stated as unknown. | `data\credits.json`, `CreditsPanel` |
| Tab and M only with gameplay focus; text entry never moves the camera | **Met.** Typing "tab m" in the join field fires neither. | `test_ui_framework` |
| E never opens and closes in the same event; mouse mode restored | **Met.** | `test_ui_framework` |
| Host sol-duration setting and pause rules shown clearly | **Met.** Host-only slider in the pause menu, 5–120 real minutes per sol, with an explanation. | `test_ui_framework` |
| Scroll and focus kept after rapid panel switches | **Met.** UiRoot restores scroll, tab and focus per panel. | `test_ui_framework` |
| Usable at 1280×720, 1920×1080 and enlarged text, no clipping, visible focus | **Met by automated layout checks** on every panel at all three sizes (found and fixed: the HUD was 14 px too tall at 720 p with large text). | all UI suites |

## 3. Changed files

New: `scripts\ui\` (29 files: framework, theme, settings, menus, HUD helpers, sources, crew, cargo, stations, solar,
suit rack, life support, power, blueprint, upgrades); `data\sources.json`, `claims.json`, `explanations.json`,
`credits.json`, `upgrades.json`; `tools\build_source_data.py`; `tools\godot\capture_ui.gd`; tests `test_ui_framework`,
`test_sources`, `test_hud_panels`, `test_station_panels`, `test_p07_panels`.
Changed: `scripts\game\game_hud.gd` (rewritten), `scripts\game\game_main.gd` (menu, UiRoot, settings, station
surfaces), `scripts\core\game_services.gd` (request routing), `scripts\core\action_result.gd` (pending answers),
`scripts\state\*` (in-place replica updates), `scripts\player\player_input.gd` (I and C keys, action names),
`scripts\player\player_controller.gd` (E for every interaction, invert Y, toggle sprint),
`scripts\player\player_camera_rig.gd` (FOV setting), `scripts\net\net_session.gd` (interface stub for Prompt 06).

## 4. Interfaces

- `UiRoot`: `open(panel)`, `close_top()`, `close_all()`, `is_open()`, `top()`, `gameplay_has_focus()`, `open_pause_menu()`, `show_subtitle(text, seconds, speaker, essential)`; signals `menu_mode_changed`, `quit_to_menu_requested`.
- `UiPanel` base: `setup(services)`, `refresh()`, `first_focus()`, `can_close()`; signals `close_requested`, `open_requested(panel)`.
- `StationPanels.for_station(id, services)`: returns the panel for any station.
- `GameSettings` (`user://settings.json`).
- `SourceLibrary`, `Explanations`, `ExplainButton.make(id)`.
- `GameServices.request(action, target, params)`, `local_peer()`, `local_character()`, `is_authority()`, `report_position()`. On a future network client, `request` returns `ActionResult.pending` and the answer arrives as `events.action_resolved`.
- `NetSession`: interface stub only (Prompt 06).

## 5. Checks run (automated, headless, 2026-11-12)

All twelve suites pass on the merged project, 829 checks:

| Suite | Checks |
|---|---|
| `test_saves` | 56 |
| `test_session` | 91 |
| `test_game_services` | 25 |
| `test_collision` | 40 |
| `test_life_support` | 88 |
| `test_ui_framework` | 118 |
| `test_sources` | 76 |
| `test_hud_panels` | 89 |
| `test_station_panels` | 70 |
| `test_p07_panels` | 54 |
| `test_player` | 90 |
| `test_game_scene` | 32 |

Screens were captured from the windowed game with the map loaded (`tools\godot\capture_ui.gd`); 14 images are in
`evidence\screens\`. Layout tests run with the project's 1920×1080 stretch switched off, so 1280×720 is measured in
real pixels.

Not verified: any person using the screens; gamepad; screen readers; co-op pause; the 3D portraits' pixels when
headless (built, not looked at in every state); the symbol glyphs on other machines' fonts.

## 6. Sources

The in-game register is generated from `docs\source_register.md`; no new science source was added in this
milestone. `S18` (dust) and `S15` (radio delay) remain leads, shown as "not yet checked".

## 7. Remaining defects and limits

1. **Host and Join do nothing yet** (Prompt 06 skipped).
2. **Upgrade cards are placeholders**; the install button is disabled until Prompt 08.
3. **Specialist colours are constants** in `CrewPortrait` and `BlueprintView`, not in `UiTheme` (spec deviation from two workers).
4. **The source register's list is an ItemList**: its own scroll position is not restored by UiRoot.
5. **Comms, board and patient surfaces** are descriptive only.
6. **New colony** asks for a second press when a save exists; there is no separate confirmation dialog.
7. **Wording is untested with children.**
8. **Two other sessions edited the same project during this milestone** (I-50); their changes were merged, not reviewed in depth here.

## 8. Decisions

D-09 (push to GitHub, records moved into the repo), D-10 (skip Prompt 06), D-11 (E for all interactions), E-25 to
E-31 in `decisions.md`.

## 9. Next

Prompt 07 was done in the same session (`..\07_power_life_support\HANDOFF.md`). Prompt 06 stays open; Prompts 10 and 11
depend on it (I-48).
