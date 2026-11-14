# Mars colony game — project documentation

Cumulative records, kept current by every milestone:

| File | What it holds |
| --- | --- |
| [requirements_matrix.md](requirements_matrix.md) | Every confirmed requirement, its input, its milestone and its state. |
| [source_register.md](source_register.md) | Science and engine references with how far each was checked. |
| [decisions.md](decisions.md) | Owner instructions, recorded owner decisions, executor choices. |
| [issues.md](issues.md) | Missing inputs, asset gaps, tooling problems, source gaps. |

Milestone records:

| Milestone | Handoff | Date |
| --- | --- | --- |
| Prompt 01 — Evidence, source and asset audit | [milestones/01_audit/HANDOFF.md](milestones/01_audit/HANDOFF.md) | 2026-11-11 |
| Prompt 02 — Map import and lighting calibration (rehearsal on the current map; improved map still missing) | [milestones/02_import/HANDOFF.md](milestones/02_import/HANDOFF.md) | 2026-11-11 |
| Prompt 03 — Simulation, configuration and save foundation | [milestones/03_simulation/HANDOFF.md](milestones/03_simulation/HANDOFF.md) | 2026-11-11 |
| Prompt 04 — Player rig, spacesuit, movement and cameras (movement, cameras, suit check and carrying done; body is a stand-in) | [milestones/04_player/HANDOFF.md](milestones/04_player/HANDOFF.md) | 2026-11-11 |

Prompt 01 deliverables, all in `milestones/01_audit/`: `inventory.md`, `authority_matrix.md`, `camera_manifest.json` and `.csv`, `coverage_sheet.md`, `asset_readiness.md`, `contradictions.md`, `evidence/`, `tools/`.

Prompt 02 deliverables, in `milestones/02_import/`: `import_report.md`, `lighting_report.md`, `score_sheet.csv`, `camera_pairs.json`, `evidence/`. The Godot project is `G:\nasa app\mars_colony_godot` (see its `README.md`).

Prompt 03 deliverables, in `milestones/03_simulation/`: `STATE_AND_SCHEMA.md` (state, clocks, units, save schema, migration policy), `workers/` (interface specification and the briefs and reports of the parallel workers), `evidence/tests/`.

Prompt 04 deliverables, in `milestones/04_player/`: `MOVEMENT_AND_CAMERA.md`, `rig/` (derivative character work and its provenance), `evidence/game/` (screenshots of the playable scene), `evidence/tests/`.

To run every automated check of the Godot project:

```powershell
& "G:\nasa app\mars_colony_godot\tools\run_tests.ps1" -Import
```

To repeat the Blender audit without touching the source files:

```powershell
& "G:\nasa app\mars_colony_godot\docs\milestones\01_audit\tools\run_blend_audit.ps1" -Blend "G:\nasa app\grand_colony\grand_colony.blend" -Label "grand_colony__current"
```
