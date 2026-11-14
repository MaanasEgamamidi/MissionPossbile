# Milestone handoff — Prompt 01: Evidence, source and asset audit

Date: 2026-11-11. Workspace: `G:\nasa app`. Executor: Claude (Claude Code session). Scope instruction from the owner: read and execute the prompt pack only to page 12, which was located as Prompt 01 (decision E-01).

## 1. Outcome

Prompt 01 is complete as an audit, with three of its inputs missing. No gameplay behaviour, project setting or source asset was changed.

The audit's main result is that the starting state the pack describes is not the state of this workspace:

- **There is no native Godot port of the colony here.** The only Godot projects are two small LAN-walking prototypes.
- **The three governing documents are not here**, so requirements could be traced only to the pack.
- **The improved map has not been supplied.** It is requested again in section 9.

What does exist is a complete Blender colony (one scene, three saves), a working browser game built from it, and build scripts for both.

## 2. Requirements covered

Prompt 01's own acceptance, item by item:

| Acceptance item | Result |
| --- | --- |
| Every confirmed requirement maps to an input and a future milestone. | Done for the 62 requirements recorded in the pack: `docs\requirements_matrix.md`. Not checked against the governing documents, which are missing. |
| Each claimed inspection has evidence. | Done. Every figure in the reports comes from a file under `evidence\`; section 4 lists the checks. |
| Original source hashes remain unchanged. | Done. 14 of 14 `.blend` files and 6 other source files have the same SHA-256 before and after: `evidence\hashes_before_after.csv`. |
| The improved-map dependency and asset gaps are explicit. | Done: `docs\issues.md` I-02, I-04, I-05, I-08 to I-13, I-18 to I-20. |
| No gameplay behaviour is changed. | Done. See section 3. |

Not achieved, and why:

| Prompt 01 task | State |
| --- | --- |
| Read the product documents and identify confirmed, proposed, open and deferred material. | Not possible: the documents are missing (I-01). Classification was done from the pack only. |
| Inventory the existing Godot project, its test code and saved results. | Nothing to inventory beyond the LAN prototypes (C-01). |
| Record the explicit conversation overrides. | Only as far as the pack records them; the earlier conversation is not available (`docs\decisions.md` section 2). |
| Four-seat rover clearance. | Not measurable until a chassis is approved (I-05). |
| Raw data products. | Archives were located and their pages checked; no product was downloaded (I-25). |

## 3. Changed files

Created (all under `G:\nasa app\docs\`):

| File | Purpose |
| --- | --- |
| `requirements_matrix.md` | Cumulative requirements matrix. |
| `source_register.md` | Cumulative source register. |
| `decisions.md` | Cumulative change decisions and overrides. |
| `issues.md` | Cumulative issue list. |
| `milestones\01_audit\HANDOFF.md` | This record. |
| `milestones\01_audit\inventory.md` | Workspace inventory, versions, hashes, checks. |
| `milestones\01_audit\authority_matrix.md` | Source and authority matrix. |
| `milestones\01_audit\camera_manifest.json`, `.csv` | 184 cameras of the current map with transforms and lenses. |
| `milestones\01_audit\coverage_sheet.md` | Coverage by area and asset class. |
| `milestones\01_audit\asset_readiness.md` | Asset-readiness report. |
| `milestones\01_audit\contradictions.md` | Contradiction register (C-01 to C-20). |
| `milestones\01_audit\evidence\…` | Blend reports, check logs, contact sheets, hash table. |
| `milestones\01_audit\tools\…` | The nine scripts that produced the evidence. |

Modified outside `docs\`:

| File | Change |
| --- | --- |
| `.claude\launch.json` | One entry added: `colony-game-audit` (static file server for `grand_colony\game` on port 8790). Existing entries untouched. |

Not modified: every `.blend`, every script, the browser game, both Godot projects, the git repository state. Godot may have refreshed its own cache while the LAN prototype ran; no file in `lan_walk\` or `lan-walk\` has a modification time from this session.

## 4. Checks run in this milestone, with results

| # | Check | Method | Result |
| --- | --- | --- | --- |
| 1 | Godot version | Console binary `--version`; MCP `get_project_info` | `4.7.2.stable.official.ed1daf0bf` |
| 2 | Blender version | Live MCP call; headless reports | `5.3.0`, build `02f0899d78e3` |
| 3 | Read-only audit of 14 `.blend` files | Background Blender, `tools\blend_audit.py` | 14 reports, all exit 0 |
| 4 | Detail pass on gameplay-critical assets | `tools\asset_detail.py` on B1 | Written |
| 5 | Diff of the three colony saves | `tools\report_details.py` | Identical apart from stored engine and current frame |
| 6 | Browser game self-test | Built-in browser, `colony_outpost.html#selftest`, 1024 × 768 | 43 of 43 passed |
| 7 | LAN Walk under Godot 4.7.2 | 1 headless host + 3 headless clients on loopback, about 12 s | Host and two clients each listed three moving players; the fourth process listed none |
| 8 | Source hashes | SHA-256 before and after | All unchanged |
| 9 | Primary sources | 23 source checks by page fetch on 2026-11-11 | 13 verified, 8 partial, 2 failed; 8 register entries are search leads only |

All of these are automated or scripted. Nothing was walked or driven by a person, nothing was observed by human players, and no child playtest took place. No frame rate, lighting score or image metric was measured. The only timing figure recorded is the browser self-test's own physics-step report (0.40 ms median over 1,278 bodies), which describes the old browser demo.

Historical material inspected but not rerun: the 15 Cycles beauty shots of 2026-11-08, the per-area harness reports and renders, and the `41of41` self-test screenshots in `grand_colony\renders\`.

## 5. Evidence images

| Image | Source | Camera and state | Resolution | Kind |
| --- | --- | --- | --- | --- |
| `evidence\contact_sheets\cycles_beauty_shots_2026-11-08_existing.jpg` | Copy of `grand_colony_drive\beauty_shots_contact_sheet.jpg` | `Shot_01` to `Shot_15`; day, powered, compositor state not recorded with the renders | Sheet 1932 × 1910; originals 1920 × 1080 (checked in the zip) | Historical Cycles renders |
| `evidence\contact_sheets\asset_classes_existing_renders.jpg` | Assembled in this milestone from 12 existing PNGs under `grand_colony\work\` | Review cameras named in `coverage_sheet.md` section 4; day, powered | Sheet 2560 × 1146; originals 1280 × 720 where checked | Historical harness renders |

No new render and no Godot capture was made.

## 6. Interfaces, saves and schema

No interface, scene, script, save format or schema was created or changed. The identifiers that later milestones should keep stable are recorded in `asset_readiness.md`: `gc_asset` names, 24 `door_id` values, and nine station ids (`suits`, `computer`, `comms`, `food`, `board`, `lifesupport`, `heal`, `survivor`, `power`).

## 7. Sources

Register: `docs\source_register.md`. Verified by fetching the page: S01, S02, S08, S09, S11, T01 to T07, T10. Partial: S03 to S07, T08, T09, T11. Failed: S10, and one lookup for S15. Search leads only: S12 to S19.

Checked facts used in this milestone: Mars mean surface gravity 3.73 m/s² (S01); Godot 4.7.2 commit `ed1daf0bf` (T01), which matches the local binary.

## 8. Remaining defects, contradictions and gaps

- Contradictions: C-01 to C-20 in `contradictions.md`. Those that change later work: C-01, C-02, C-03, C-05, C-06, C-09.
- Issues: I-01 to I-28 in `docs\issues.md`.
- Limits of this audit:
  - The pack's reference pages were not read, so source ids are inferred (C-14).
  - The seat count of the surface rover was not established (I-20).
  - The exporter behaviour for area lights and colour attributes was read from the Blender 4.5 manual through a summary, not from the 5.3 manual (T11).
  - Area-specific detail in the 20 area modules was not read line by line; object data came from the scene itself.

## 9. Missing inputs — requests to the owner

1. **The improved map**, with its source Blender scene. Prompt 02 cannot import or calibrate lighting without it.
2. **The three governing documents**, placed in `G:\nasa app`.
3. **The existing Godot port**, if it exists elsewhere; or confirmation that the Godot game starts from the browser game, the Blender source and the LAN Walk prototype.
4. **A Godot project location inside `G:\nasa app`**, opened in the MCP-connected editor.
5. **Which human assets and which rover chassis are approved**, and which room is the hub.
6. **The target laptop**, or acceptance of this desktop as the test machine.

## 10. Dependencies for the next milestone (Prompt 02, map import and lighting calibration)

| Dependency | State |
| --- | --- |
| Improved map and source scene | Missing. Without it Prompt 02 allows only "independent preparation". |
| A Godot project to import into | Missing inside the workspace. |
| Reproducible GLB export workflow | Must be built (I-08). |
| Material strategy for 256 procedural materials with no UVs | Undecided (I-09). |
| Light transfer for 431 area lights | Data preserved; method undecided (I-10). |
| Reference camera list | 184 cameras documented; 4 rooms and 1 interior need hero cameras (I-18). |
| Reference states (night, unpowered, suit, rover) | Do not exist (I-11). |
| Godot 4.7.2 export templates | Not installed; not needed until packaging (I-15). |

Independent preparation that could proceed without the map: creating the Godot project inside the workspace; building and testing the derivative GLB export on one room of the current map; deciding the material approach on that room; adding the missing hero cameras to a copy. None of this was started, because it belongs to Prompt 02.

## 11. Optional suggestions (not requirements, not acted on)

- Commit the v12 state of `grand_colony` before any derivative work, so the original scripts and scene have a recoverable baseline (I-21).
- Decide early whether the Godot materials come from baked textures or from the existing 230-role flat palette. The palette already exists as data and avoids UV work, at the cost of the procedural surface detail.
- Keep one of the two LAN prototypes and delete or archive the other.
- Set `BLENDER_PATH` for the Blender MCP so its background tools work without the wrapper script.
