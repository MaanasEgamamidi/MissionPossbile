# Broken parts -> Godot: shared brief (2026-11-14)

Every worker reads this first. Source: the owner's handoff "Broken Parts -> Godot" (summarised here) and the
Implementation Prompt Pack, whose T01-T12 pages are extracted as text in `tmp/pdfs/extracted.txt` (lines ~740-1135;
the original is `output/pdf/Mars_Colony_Implementation_Prompt_Pack.pdf`). **Owner rule: when you have a question,
look in the Prompt Pack first.** Where the owner's handoff names a mini-game, the owner's words win over the pack;
use the pack for the details (seeded layout, tolerance, keyboard play, colour-blind symbols, host validation).

## Owner decisions (2026-11-14)

- BP09 water pipe is **T06 Water** (Greenhouse rack). T07 Pipes keeps no broken part. **T05 is skipped** for now.
- T12 uses **BP08, the exit-tunnel inner door** (door 901, used by S04 airlock pressure). Not BP08b.
- All 10 spots start broken in every new game; older saves are broken too unless that task was already completed.
  "Broken" means: the task has a puzzle installed and `state.repair.tasks[id].first_completed` is false.
- Git: MissionPossbile branch `revisions`. Workers never commit; the integrator does.

## The loop for every spot

1. New game: the spot shows the broken model exactly where the intact map object stands.
2. Looking at it shows its own prompt naming the problem (table below). Only these 10, and only while broken, may
   say fix / repair / broken / damaged. Fixed: the prompt goes back to the normal one. Everything else keeps
   plain "[E] Use ...".
3. E opens the spot's mini-game (TaskPanel subclass). Already wired: `StationPanels.for_station` opens
   `PuzzleRegistry.make_panel` while `PuzzleRegistry.is_broken(...)`.
4. Solved (host rule says complete): a ~1 s sparkle burst over the object's bounds with a short warm glow; at
   ~0.35 s the broken model fades/shrinks out and the intact one appears; effect objects (vapour, water spray,
   dust) stop at the same moment.
5. Afterwards the normal intact object. Saved, and replicated to all players (played on every client from the
   replicated completed state, never from local input; late joiners see it fixed with no sparkles).

## The 10 spots

| Task | Part (`G:\nasa app\broken_parts\`) | Room · Godot spot | Replaces (map objects) | Prompt while broken | Mini-game (owner's words) |
|---|---|---|---|---|---|
| T09 Mixture (medical) | BP01_lab_test_tubes | Med Bay · (-11.5, 0, -12.45) | mb_sink_counter | [E] Fix the test-tube rack | Refill the rack and sort coloured liquids into tubes (one colour per tube; fictional reagents) |
| T10 Equipment | BP02_plug_in_equipment | Med Bay · (-3.9, 0, -17.5) | md_heal_station, mb_pdu, mb_ct | [E] Fix the unplugged equipment | Drag each lead to its matching socket (colour + shape); screens light up |
| T02 Wires (electrical) | BP03_wires_task | Command Room · (25.1, 0, -17.4) | cr_rack | [E] Fix the wires | Connect 4 coloured wires (with symbols for colour-blind players) |
| T01 Comms | BP04_comms_task | Command Room · (30.15, 0, -11.7) | cr_console_alarm | [E] Fix the radio signal | Turn the dial until the signal wave matches, then hold it briefly |
| T08 Glass | BP05_dome_glass | Garden dome · centre (50, 0, 27), south panes | gd_shell | [E] Repair the broken glass | Fit pieces into the broken pane (pack: five-piece square pane) |
| T03 Rings | BP06_circle_electrical | Power Room · (34.7-39.1, 0, 9.4) | pr_swgr.003, pr_swgr.004, pr_inverter, pr_inverter.001 | [E] Fix the power dials | Stop each spinning ring when its marker lines up |
| T04 Circuits (electrical) | BP07_circuit_puzzle | Power Room · (30.0, 0, 9.45) | pw_panel (also the power station: keep its normal panel working after the fix) | [E] Repair the power circuit | Place and rotate pieces on a grid until the route reaches the target voltage |
| T12 Seal (field eng.) | BP08_airlock_air_leak | Airlock · exit-tunnel inner door (22.0, 0, 10.45) | tunnel door leaves inside SFX_tunnel_inside (environment.glb), door 901 | [E] Repair the air leak | Find the gap by the vapour, then fit/press the new seal along the edge |
| T06 Water | BP09_water_pipe | Greenhouse · (0.85, 0, 10.6) | gr_rack.002 + its trays | [E] Fix the broken pipe | Connect straight and elbow pipe pieces from the supply to the rack until water flows; kale healthy after |
| T11 Dust | BP10_hangar_dust | Hangar · x 14-30, z -8..2 | all Hangar objects (raise dust) + hg_dust__broken mesh | [E] Clean the dusty hangar | Brush/vacuum dust patches area by area until clean; floor markings show again |

Blender (5.3) headless only: `%LOCALAPPDATA%\Microsoft\WindowsApps\blender-launcher.exe -b --factory-startup
--disable-autoexec <file.blend> --python <script> -- <args>`. Never save a source .blend. Each part .blend has
collections `Original` and `Broken` side by side; every broken object has `map_matrix_world` (16 floats, Blender
coords) and `broken_task`. Blender (x, y, z) -> Godot (x, z, -y) (see `tools/godot/build_world.gd`). The exporter to
copy is `tools/blender/export_colony_glb.py` (palette-role materials on `materials/colony/<role>.tres`; new `bp_*`
roles go in `data/palette.json`, then `py -I tools/gen_materials.py <project>`). Previews: `renders/BPnn_*.png`.
Owner's annotated screenshots: `C:\Users\josev\Downloads\MAIN Consolidation.pdf` (10 pages). Reference look for the
inside of the map: `G:\nasa app\grand_colony\game\colony_outpost.template.html`.

## Contracts

- **`data/broken_parts.json`** (assets worker writes; integration worker reads):
  `{"parts": [{"task_id": "T02", "part": "BP03_wires_task", "glb": "res://assets/broken_parts/BP03.glb",
  "zone": "Command Room", "hide_objects": ["cr_rack"], "effect_nodes": ["<node names inside the glb that are
  effects: vapour, spray, puddles...>"], "bounds": {"center": [x, y, z], "size": [x, y, z]} (Godot),
  "prompt": "[E] Fix the wires", "special": "" | "door_901" | "dust"}]}`. The glb is already in Godot world
  coordinates (placed at its map matrix), so the presenter adds it at the origin.
- **Puzzle files** (`PuzzleRegistry` header has the exact rule/panel contract): `scripts/tasks/puzzles/tNN_rule.gd`
  (static `supports_resume()`, `validate(task, move)`) and `scripts/tasks/puzzles/tNN_panel.gd` (extends TaskPanel;
  sends `{"move": String, "value": int}` through `submit_move`/`request_host`; draws from the host's
  `task.puzzle_state`). The layout comes from `task.puzzle_seed` (deterministic). Every pointer action has a
  keyboard alternative (Tab/arrows/Enter); colour is never the only cue (symbols or labels too); kid-friendly words
  (ages 9-12); no fire, electric sparks, gore or scary failure. Moves are discrete and few (one request per real
  player action, not per frame); time-based puzzles (dial hold, spinning rings) send the decisive moment as a move
  and the host checks it against the seeded state, a timestamp the host can verify, or a tolerant window: false
  matches must not complete. Specialty is enforced by RepairRuntime already (catalog roles).
- Puzzle tests: `tests/test_puzzle_tNN.gd` each: solve path completes and sets first_completed; wrong, forged,
  out-of-range and replayed moves fail closed; deterministic per seed; the panel builds headless and its keyboard
  path can solve it through a SessionService; save projection behaves as `supports_resume` says.

## Folder rules (same as `docs/revisions/UPGRADES_BRIEF.md`, read its "Where to work" and "Godot rules")

No commits, no new class_name (preload by path), import lock `_locks\import`, test locks `_locks\test_<suite>`,
never the full test runner, test files under `_test_saves\<your_suite>\` only, never kill processes you did not
start, never revert or reformat files you don't own. Several workers and another session share this folder.

## Workers and file ownership

- **Assets worker:** `tools/blender/broken_parts/**`, `assets/broken_parts/**`, `data/broken_parts.json`,
  `data/palette.json` (additions), `materials/colony/bp_*.tres`, `data/stations_repairs.json` (move the 10
  repair_tNN stations to their spots, reachable on foot; keep T05/T07 where they are),
  `tests/test_broken_part_assets.gd`, `docs/revisions/evidence/broken_parts/**`.
- **Integration worker:** `scripts/tasks/broken_part_presenter.gd`, `scripts/tasks/sparkle_burst.gd`,
  `scripts/tasks/hangar_dust.gd` (any new `scripts/tasks/*.gd` except puzzles), the prompt in
  `scripts/game/game_hud.gd`, one hook line in `scripts/game/game_main.gd`, `scripts/world/environment_collision.gd`
  (door 901 broken leaves) if needed, `tests/test_broken_parts.gd`, `tests/test_repair_foundations.gd` and
  `tests/test_repair_anchors.gd` (only to keep their purpose while rules now exist: point "no rule" checks at T05/T07).
- **Puzzle workers** (one per group): only `scripts/tasks/puzzles/tNN_rule.gd`, `tNN_panel.gd` and
  `tests/test_puzzle_tNN.gd` for their own tasks. Shared puzzle UI helpers: `scripts/tasks/puzzles/<group>_ui.gd`.
