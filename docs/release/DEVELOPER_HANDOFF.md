# Mars Colony — Developer handoff (Prompt 17)

Project: `G:\nasa app\mars_colony_godot` (Godot 4.7.2, typed GDScript, native Windows). Records: `docs\`. Written 2026-11-14
from the code and the milestone records. Where a fact comes from a record rather than from code read for this file, the
record is named. Nothing here claims NASA endorsement, measured learning gains, awards, Mac support or performance on
every laptop.

## 1. Architecture

### 1.1 Services (`scripts\core\game_services.gd`)

`GameServices` is a plain node added by the game scene (not an autoload, E-17), so tools and tests can build their own.

| Part | Script | Role |
| --- | --- | --- |
| `SessionService` | `scripts\session\session_service.gd` | The host's authority: sol clock, simulation ticks, validated actions, crew ownership, pause votes. The only way state changes outside the tick is `SessionService.submit()`. |
| `SaveService` | `scripts\save\save_service.gd` | Files on disk: versioned, checksummed JSON, safe replacement, backups, migrations. |
| `GameServices` | `scripts\core\game_services.gd` | Glue: new game / continue, what goes into a save, autosave (every 60 s, `game_config.tres`), `mode` = `offline`, `host` or `client`. |
| `NetSession` | `scripts\net\net_session.gd` | LAN session (child node `Net`). |
| `GameEvents` | `scripts\core\game_events.gd` | Signals that presentation listens to. |

Every request from the local player goes through `GameServices.request`; on a client it is sent to the host and a
pending answer returns at once, the real answer arriving as `events.action_resolved` (E-30). Presentation reads
replicated state, never answers.

### 1.2 Session and host authority

- The host is network peer 1. It owns the colony, ticks the simulation, validates every request and writes the save.
- Solo play is the same path with `mode = offline`.
- Crew: four characters always exist; a player may take an unoccupied one only at the hub; the host rejects duplicate
  claims; parked crew are frozen and use nothing.
- Pause: solo pauses in menus; co-op pauses only on a unanimous vote (pause menu opens a vote, closing withdraws it).
- Client loss: character and inventory return to the hub without a cargo drop or recovery charge. Host loss: clients
  return to the menu. No host migration.

### 1.3 Simulation (`scripts\sim\colony_sim.gd`)

Fixed **5 Hz** tick. Pure: reads `GameBalance`, changes `ColonyState`, knows nothing about nodes, input or network.
Every flow is rate × game hours, so sol length cannot create or destroy anything. Order inside a tick:

1. `pre_systems`: `WeatherSystem` (sets dust optical depth before solar power).
2. Drinking and washing; plan water allocations and both oxygen processes.
3. Power: solar, battery, shedding by priority (`PowerModel`).
4. Panel dust and the cleaner at sunrise.
5. Greenhouse water, electrolyser, CO2-to-oxygen unit, water recycler (`LifeSupportModel`).
6. Cabin air: airlock losses, breathing, CO2 scrubber, regulator.
7. `post_systems`: `CropSystem`, `ProgressionSystem`, `ScoutSystem`, `RoverSystem`, `TutorialSystem` (registered in `session_service.gd`).
8. Suits of crew outside, food, health of active crew; alerts.

`SolClock` (`sol_clock.gd`): default 20 real minutes per sol, host setting 5–120 min, phase preserved on change and
replicated. Movement, animation, the 1 s suit check, network latency and radio delay do not scale with sol length.
Mars gravity 3.73 m/s² everywhere.

### 1.4 Actions and state

- Actions: `scripts\session\` — `action_service.gd` plus one file per part: `builtin_actions`, `system_actions`,
  `food_actions`, `science_actions`, `progression_actions`, `weather_actions`, `rover_actions`, `scout_actions`,
  `tutorial_actions` (registered last; it wraps watched actions without changing them), `legacy_stations`.
- State: `scripts\state\colony_state.gd` (one dictionary per part: `crops`, `science`, `progress`, `weather`,
  `campaign`, recoverable cargo caches, `discoveries`, …) and `character_state.gd` (equipment, cargo, health, stamina,
  suit charge per character). Details: `docs\milestones\03_simulation\STATE_AND_SCHEMA.md`.

### 1.5 Network channels (`NetSession`, ENet, UDP port **24680**, max 4 players = host + 3)

| Channel | Mode | Carries |
| --- | --- | --- |
| 0 `CHANNEL_STATE` | reliable, ordered | requests, answers, colony snapshots (5 per second and at once after any action) and forwarded GameEvents; one channel so state always arrives before the event that refers to it |
| 1 `CHANNEL_MOTION` | unreliable, ordered | body poses about 20/s each way, unchanged poses repeated every 0.5 s (E-45); "motion extras" such as the driver's rover pose |
| 2 `CHANNEL_VOICE` | reliable, ordered (E-42) | Opus voice packets (max 4000 bytes); the host relays a client's packets to the others |

A protocol version is checked on join; a client of another version is turned away with a plain reason. Development
shortcuts after `--`: `--host` / `--host=PORT` (see `docs\milestones\06_lan\HANDOFF.md`).

### 1.6 Presenters and UI

Presentation only listens to events and sends requests: `scripts\player\` (controller, camera rig, input, visual),
`scripts\vehicle\` (rover body/model/presenter/HUD, scout), `scripts\voice\` (`VoiceService`, `VoiceRouter` decided on
each listener's machine, `VoiceScheduler`, `CommsStage`, `VoiceHud`), `scripts\weather\weather_presenter.gd`,
`scripts\game\` (`game_main`, HUDs, tutorial presenter), `scripts\world\` (collision, doors, zone lighting, stations),
`scripts\ui\` (code-built Control UI with one code-built theme, E-29: menus, settings, panels, source register, credits).

## 2. Scene, asset and data manifest (summary)

| Item | Path |
| --- | --- |
| Main scene | `res://scenes/game.tscn` (`run/main_scene`) |
| World scene | `res://scenes/world/colony_world.tscn` (loaded by `game_main.gd`), lighting under `scenes\world\lighting\` |
| Colony models (derivative glTF exports of `grand_colony.blend`) | `assets\colony\colony.glb`, `environment.glb`, `terrain.glb` |
| Crew | `assets\characters\astronaut.glb` (sources in `assets_src\characters\`, excluded from export) |
| Menu backdrop | `assets\menu\beauty_shots\` |
| Config | `config\game_config.tres`, `config\game_balance.tres` |
| Data (JSON) | `data\`: stations (`stations_*.json`), `upgrades.json`, `questions.json`, `explanations.json`, `crops.json`, `samples.json`, `salvage.json`, `rover.json`, `tutorial.json`, `lore.json`, `scout_sites.json`, `sources*.json`, `claims*.json`, `model_sources*.json`, `credits.json`, `colony_manifest.json`, `colliders.json`, `palette.json`, `lighting_preset.json`, import/build reports |
| Binary data | `data\prop_collision_cache.bin`, `data\terrain_height.res`, `data\weather\route_grid.res` |
| Weather bundle | `data\weather\bundle\` (`manifest.json`, `episodes.json`, MEDA and LMD CSVs); `data\weather\raw\` is excluded |
| Voice addon | `addons\twovoip\` (gdextension + Windows x86_64 libraries) |

The export filter (`export_presets.cfg`) includes `data/*.json, *.bin, *.csv, data/weather/bundle/*` and excludes
`tests/`, `tools/`, `docs/`, `assets_src/`, `data/weather/raw/`, `data/_exp/`, test save/weather folders,
`scenes/world/_exp_world*`, `*.md`, `*.py`, `addons/twovoip/voiphelper/`.

## 3. Build (Windows)

```powershell
& "G:\nasa app\mars_colony_godot\tools\build\export_windows.ps1"            # release
& "G:\nasa app\mars_colony_godot\tools\build\export_windows.ps1" -Debug     # debug export
```

Defaults: output `G:\nasa app\_build\MarsColony_windows`, staging `G:\nasa app\_work\export_stage`. The script:

1. checks the Godot 4.7.2 console editor in `%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\` and the templates in
   `G:\nasa app\_tools\godot_4.7.2_templates\extracted\templates` (`version.txt` must read `4.7.2.stable`);
2. mirrors the project to staging without `.git`, test saves, `assets_src`, evidence and logs (the real project's import
   cache is never touched);
3. imports and exports headless with the `Windows Desktop` preset (x86_64, PCK not embedded, S3TC/BPTC, no code signing,
   version 0.17.0.0);
4. copies `docs\release\PLAYER_GUIDE.md` and `THIRD_PARTY_NOTICES.md` and the TwoVoIP licence and version into the package;
5. lists the PCK (`tools\build\pck_list.py`, run with `py -I`) and fails if a development file got in;
6. writes `MANIFEST.txt` with every packaged file's SHA-256.

Templates: `Godot_v4.7.2-stable_export_templates.tpz` SHA-512 matches the official `SHA512-SUMS.txt` (re-checked
2026-11-14, see `SOURCE_MANIFEST.md`). Proposed addition: also copy `docs\release\GODOT_COPYRIGHT.txt` (Godot's
third-party texts) into `licenses\`.

## 4. Version pins

| Item | Pin |
| --- | --- |
| Godot | 4.7.2-stable (official), commit `ed1daf0bf001b61586d9930840f2f1394092c079` |
| Export templates | 4.7.2.stable, tpz SHA-512 `CA4D71C4…CCB84079` (official sums) |
| TwoVoIP | 6.1, release asset SHA-256 `01825E1FB99B483FE6EF3B43A4578F6E5CF029AE6F39C292D99EB8AF3DD0D098`; release DLL SHA-256 `C9F47DF2…E9B86FDFCBF` |
| Blender (tool) | 5.3 (P02 handoff; `grand_colony.blend` saved with 5.3 sub 31 per P01 inventory) |
| Save schema | 1 (`SaveMigrations.current_version`) |
| Net protocol | version constant in `net_session.gd` |
| Weather data | bundle `data\weather\bundle\manifest.json` (per-product sha256, ETag, Last-Modified); the running game pins `state.data_snapshot_id` |

## 5. Weather data and refresh (`scripts\weather\`)

- The validated bundle ships in the package; the game needs no network.
- `WeatherRefresh` checks for updates only in windowed runs (never headless, E-39): at start and every
  `WeatherConfig.refresh_hours` (1 h) while online, with conditional GET (If-None-Match / If-Modified-Since), a timeout
  and a size cap.
  - 304: up to date.
  - 200 for an entry that points at an archive original: marked as "update published"; the bundle stays (the transform
    to bundle CSV is done by the Python build tool).
  - 200 with a bundle CSV: a complete new bundle is built in a temporary folder, validated as a whole, then swapped in
    atomically (incoming → current, old current kept as previous).
  - Anything else: cache untouched; retries back off 1, 2, 4 … minutes, at most 60.
- A running game keeps its pinned data; a newer bundle is used from the next new game or load. Cache:
  `user://weather_cache`.
- Data and licences: `docs\milestones\09_weather\WEATHER_DATA.md`. A real network refresh has never been run (I-53).

## 6. Saves (`scripts\save\`)

- Location: `user://saves` → `%APPDATA%\Godot\app_userdata\Mars Colony\saves\` (project `config/name="Mars Colony"`,
  no custom user dir). Files: `colony.json`, `colony.json.tmp` during a write, backups `colony.bak1.json`,
  `colony.bak2.json`. Settings `user://settings.json`, remaps `user://input.json`, HUD `user://mission_hud.json`.
- Envelope fields: `format` (`mars_colony_save`), `schema`, `game_version`, `saved_at_unix`, `reason`, `checksum`,
  `payload` (`colony`, `clock`, `session`). Checksum = SHA-256 of the text a reader reconstructs (E-20, I-44).
- Write: temporary file written and verified, backups rotated, then main replaced. Read: main, then the temporary file,
  then backups; a backup load is reported to the player. A save of an unsupported schema is never overwritten: the
  game starts a new colony beside it under `colony_new`.
- Migrations: `SaveMigrations` holds sequential one-step upgrades registered per source version and applied to a deep
  copy; schema is 1 and no migration step exists yet. Policy: `docs\milestones\03_simulation\STATE_AND_SCHEMA.md`.
- No offline deterioration: loading adds no real time.

## 7. Sources

`docs\source_register.md` (S, T, L, W ids with how far each was checked), shown in game through Shift + Backspace and
Sources and credits (`data\sources*.json`, `data\claims*.json`). Licence status: `THIRD_PARTY_NOTICES.md`.

## 8. Tests

```powershell
& "G:\nasa app\mars_colony_godot\tools\run_tests.ps1" -Import              # all 27 suites, headless
& "G:\nasa app\mars_colony_godot\tools\run_tests.ps1" -Tests test_net,test_voice -LogDir "G:\nasa app\_work\logs"
```

The 27 suites: `test_saves`, `test_session`, `test_game_services`, `test_collision`, `test_life_support`, `test_food`,
`test_science`, `test_progression`, `test_weather_data`, `test_weather`, `test_ui_framework`, `test_sources`,
`test_hud_panels`, `test_station_panels`, `test_p07_panels`, `test_player`, `test_net`, `test_net_game`,
`test_game_scene`, `test_graphics_quality`, `test_rover`, `test_rover_drive`, `test_voice`, `test_tutorial`,
`test_scout`, `test_crew_collision`, `test_pdf_fixes`. Each prints a `RESULT` line; the runner fails on a non-zero exit,
a missing RESULT line, `FAIL`, `SCRIPT ERROR` or `Parse Error`. Known flake: `test_game_scene` suit-rack step (I-59).
Blender audit (read-only): `docs\milestones\01_audit\tools\run_blend_audit.ps1`.

## 9. Playtest reports

- Playtest one: `docs\milestones\14_*\` — **TO BE FILLED** (Prompt 14 not yet recorded at the time of writing).
- Improvement stage: `docs\milestones\15_*\` — **TO BE FILLED**.
- Playtest two and comparison: `docs\milestones\16_*\` — **TO BE FILLED**.

No child or independent human playtest is recorded so far; any agent/technical playtest cannot establish the audience
targets (80 % / 80 % / 70 % pilot measures), which stay **unverified hypotheses**.

## 10. Performance

> **TODO (P13, being measured now):** hardware, resolution, graphics preset, workload (player count, scene), CPU/GPU frame
> times and percentiles, memory. Replace this line with the measured statement; do not generalise to other laptops.

Recorded so far (not a release statement): Prompt 02 static 1080p views took 9–28 ms GPU each on a desktop RTX 4060 Ti,
5 of 15 above 16.7 ms (I-32); pass-4 probe 19–41 ms (I-36); playable-scene frame rate not measured properly (I-37);
target laptop not identified (I-07).

## 11. Outstanding lighting flags

No view reaches the 95-point rubric target (I-29). Scores are the executor's rubric review of the **Prompt 02
rehearsal on the current map, pass 3** (`docs\milestones\02_import\score_sheet.csv`); owner review pending; the improved
map was never supplied (I-02); pass 4 was parked (D-07, I-36) and its records were not rescored. P13 results, if any,
replace this table.

| View (matched camera) | Rubric /100 | SSIM | EV diff | ΔE76 | GPU ms 1080p | Main mismatch |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Shot_01_MedBay | 73 | 0.808 | +0.14 | 6.54 | 9.9 | contact shadows; emissive panels |
| Shot_02_MessHall | 74 | 0.858 | −0.09 | 7.57 | 13.2 | wall hot spots; floor dust colour |
| Shot_03_RecKitchen | 74 | 0.813 | −0.04 | 8.05 | 10.1 | emissive board; contact shadows |
| Shot_04_CrewCorridor | 77 | 0.860 | −0.13 | 7.70 | 17.2 | floor colour |
| Shot_05_Hangar | 67 | 0.719 | +0.10 | 10.65 | 17.1 | ceiling brightness; contact shadows |
| Shot_06_Airlock | 68 | 0.708 | −0.01 | 9.24 | 16.9 | floor dust pattern; glazing |
| Shot_07_PowerRoom | 62 | 0.710 | +0.30 | 10.06 | 11.8 | exposure +0.30 EV; ceiling; screens |
| Shot_08_LifeSupport | 71 | 0.732 | +0.10 | 8.66 | 11.1 | ceiling brightness; contact shadows |
| Shot_09_Command | 64 | 0.763 | +0.18 | 7.93 | 10.6 | screens; floor colour |
| Shot_10_EastQuarters | 73 | 0.835 | +0.02 | 10.60 | 9.0 | floor saturation; partition colour |
| Shot_11_Greenhouse | 69 | 0.799 | +0.16 | 11.07 | 23.9 | ceiling shadows; plant detail |
| Shot_12_WestBunk | 73 | 0.843 | +0.11 | 7.39 | 11.9 | floor dust |
| Shot_13_Exterior_Airlock | 60 | 0.579 | +0.13 | 14.01 | 28.0 | ground detail; hall glass; haze |
| Shot_14_Exterior_Wide | 68 | 0.759 | +0.08 | 7.93 | 15.2 | haze; glass reflections |
| Shot_15_GardenDome | 64 | 0.673 | −0.07 | 9.39 | 9.3 | dome glass and frame; lamp bloom |

Mean rubric 69.1. Not scored at all: Pipe gallery, Service corridor, Blast-door passage, Dome plaza, garden-dome interior
(no hero camera, I-18); night and unpowered states have no reference renders (I-11). Causes: flat palette materials
(I-30), no real indoor GI (I-31), no atmosphere (I-33), partial compositor (I-34), open-door leaks unverified (I-35).

## 12. Remaining defects (open items in `docs\issues.md`, grouped)

**Missing owner inputs:** I-01 governing documents absent; I-02 improved map never supplied (Blocker for final import
and lighting); I-03 no prior Godot port; I-04 / I-05 human assets and rover chassis approval (rover chassis `sf_rover`
in use, approval pending); I-06 no designated hub (Med Bay rehearsal point); I-07 target laptop unknown.

**Visual and performance:** I-29 no view at 95; I-30 materials; I-31 indoor GI; I-32 GPU time and draw calls; I-33
atmosphere; I-34 compositor; I-35 door light leaks; I-36 pass 4 parked and P02 records stale; I-37 frame rate not
measured; I-11 / I-18 missing reference views.

**World and assets:** I-12 Human Base Meshes licence; I-13 / I-54 crops have no growth stages, shared map symbol;
I-19 terrain partly imported; I-20 rover close view; I-38 partial outdoor collision (rocks got hulls in E-28; glass-hall
frames, dome shell, ladder, deco still open); I-55 rover has no seats, rigid wheels, opaque windows; I-56 salvage
supply 40 parts vs 102 demand (all rover stats at 5 unreachable).

**Gameplay and rules:** I-39 doors have no airlock interlock or pressure rule; I-40 / I-52 balance and content not
owner-approved; I-42 stamina still local; I-58 play starts at the hub not the landed spacecraft, pacing unplayed,
96 meals = 8 sols for four.

**Network and voice:** I-48 LAN verified only on one computer over 127.0.0.1; firewall prompt on first host;
I-57 voice synthetic only (no real microphone or second computer), full Opus/SpeexDSP/RNNoise texts not in package.

**Testing and tooling:** I-43 engine "unpair geometries" message and exit 255 at windowed teardown; I-50 concurrent
sessions; I-51 Prompts 08/09 not played by a person; I-53 weather data gaps and no real refresh; I-59 flaky
`test_game_scene` step; I-15 export templates — now installed and SHA-512-checked (row in `issues.md` still says Open;
update it); I-21 / I-22 / I-23 `grand_colony` uncommitted v12 work, hard-coded paths, duplicate LAN prototypes;
I-24 / I-26 / I-27 source gaps.

## 13. Scope and ownership

The owner receives the package and the project. Publishing, store submission and account creation need a separate
instruction. Original Blender sources are preserved and unchanged (`SOURCE_MANIFEST.md`: 14 of 14 hashes match).
Whether any unapproved game system entered the build is for the executor's P17 review; this document adds none.

## 14. Optional ideas (UNIMPLEMENTED — not requirements)

- Merge repeated static meshes (ceiling and floor tiles) into MultiMesh per room to cut draw calls; reduce the rock meshes (3.39 M triangles).
- Try VoxelGI per room once the final geometry is fixed.
- Keep one saved file of every released schema under `tests\fixtures\` from the first public build; write saves on a worker thread if state grows past a few hundred KB.
- Different head or hair shapes per specialist; box colliders for the largest rocks and hall frames.
- Commit `grand_colony` v12; keep one LAN prototype; set `BLENDER_PATH` for the Blender MCP.
- Starting at the landed spacecraft instead of the hub (needs an owner decision; see `docs\milestones\12_tutorial\workers\P12_NOTES.md`).
