# Milestone handoff — Prompt 17: Windows build and project handoff

Date: 2026-11-14. Project: `G:\nasa app\mars_colony_godot`. Package: `G:\nasa app\_build\MarsColony_windows\` (built by `tools\build\export_windows.ps1`, not committed: it is 480 MB). Release documents: `docs\release\`.

## 1. Package

- **Export:** Godot 4.7.2 release template for Windows x86_64.
  - The official export templates are kept in `G:\nasa app\_tools\godot_4.7.2_templates`; the SHA-512 matches the official `SHA512-SUMS.txt`.
  - The templates are referenced by `export_presets.cfg` (custom template paths), not installed into %APPDATA%.
- **Contents:**
  - `MarsColony.exe`, `MarsColony.pck` (1,187 files, 368 MB: imported assets, the offline weather bundle and every data file)
  - `libtwovoip.windows.template_release.x86_64.dll`
  - `PLAYER_GUIDE.md`, `THIRD_PARTY_NOTICES.md`
  - `licenses\`: TwoVoIP licence and version, Godot's full third-party licence texts
  - `MANIFEST.txt`: SHA-256 of every file
- **Excluded, checked by listing the pack** (`tools\build\pck_list.py`): tests, tools, docs, Blender sources, raw weather downloads, Python, Markdown, test saves.
- **Kept separately:**
  - The editable project and its sources.
  - `docs\release\SOURCE_MANIFEST.md`: all 14 original `.blend` files match the Prompt 01 hashes exactly, so the Blender source is unchanged.

## 2. Clean-launch checks

| Check | Result |
|---|---|
| Headless boot of the exported exe to the main menu | Exit 0, no errors in the log |
| Windowed launch, `-- --host` (loads the world, continues the colony, hosts) | Running and responding after 50 s, LAN host on UDP 24680, no errors or warnings in the log |
| Launched outside the editor, without Blender, the MCP bridges or Python | Yes (run directly from `_build`) |
| Save location | `%APPDATA%\Godot\app_userdata\Mars Colony\saves` (the exported game wrote there; the owner's saves were backed up first and restored after) |

**Not done in the exported build:**
- start/continue through the menu by hand
- input remapping
- perspective and map keys
- the source register, graphics and sol-duration settings
- a second machine joining
- a real microphone and voice route
- a launch with the network cable unplugged (the weather refresh would only fail and keep the bundled data, as tested headless in Prompt 09)

The owner tests these by hand (D-15).

## 3. Documents

| File | What |
|---|---|
| `docs\release\PLAYER_GUIDE.md` | Launch, controls (from `player_input.gd`), tutorial (N hint, L journal), LAN host/join, voice, saves, settings, fiction vs NASA data |
| `docs\release\THIRD_PARTY_NOTICES.md` | Godot MIT and its components, TwoVoIP MIT, MEDA and LMD data terms, credits; open items listed |
| `docs\release\DEVELOPER_HANDOFF.md` | Architecture, scene and data manifest, build steps, version pins, data refresh, save schema, test commands, open defects, lighting flags, optional ideas (unimplemented) |
| `docs\release\SOURCE_MANIFEST.md` | Blender source hashes compared with Prompt 01 |
| `milestones\13_performance\HANDOFF.md` | Performance measurements (see limits) |
| `milestones\14_playtest_one\REPORT.md`, `15_fixes\FIX_MATRIX.md`, `16_playtest_two\REPORT.md` | Agent/technical playtests and the fix |

## 4. Checks run (2026-11-14)

- Compile: **COMPILE OK, 217 scripts**.
- **All 27 headless suites pass, 1,744 checks**: saves 56, session 91, game_services 25, collision 40, life_support 88, food 85, science 76, progression 84, weather_data 15, weather 66, ui_framework 125, sources 76, hud_panels 89, station_panels 158, p07_panels 54, player 112, net 34, net_game 20, game_scene 32, graphics_quality 23, rover 80, rover_drive 64, voice 84, tutorial 59, scout 60, crew_collision 5, pdf_fixes 43. Logs are in `milestones\16_playtest_two\evidence\tests\`.

## 5. Readiness and limits

**Decision:** a technical build ready for the owner's first human playtest. It is not a validated release.

1. **Performance** (Prompt 13) was measured while a hung editor game instance held the GPU at 98–100 %.
   - The numbers are not representative, and 60 FPS at 1080p is **not shown** (I-63).
   - No optimization was made. The ranked candidates are in the P13 handoff (fixture and area-light shadows first).
   - This was the desktop RTX 4060 Ti, not the owner's laptop.
2. **Lighting:** matched-camera re-scoring was not done, so every sub-95 view from Prompt 02 stays flagged.
3. **Playtests:** no human or child playtester (I-62). Prompts 14 and 16 are agent/technical playtests.
4. **Voice:** tested synthetically only (I-57).
5. **Rover:** no modelled seats (I-55); a salvage shortfall means a maximised rover is out of reach (I-56).
6. **Publishing:** no storefront, account or signing. Code signing is off, so Windows may show a SmartScreen prompt.
7. **No claims** of NASA endorsement, measured learning gains, Mac support or performance on other laptops.
