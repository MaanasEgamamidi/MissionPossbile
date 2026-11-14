# Prompt 01 — Workspace inventory

Audit date: 2026-11-11. Workspace root: `G:\nasa app`. Everything in this file was observed during this milestone unless it is marked *historical*.

## 1. Tools verified

| Tool | Observed | How it was checked |
| --- | --- | --- |
| Godot | `4.7.2.stable.official.ed1daf0bf` (full hash `ed1daf0bf001b61586d9930840f2f1394092c079`) | `Godot_v4.7.2-stable_win64_console.exe --version`; Godot MCP `get_project_info`. Hash matches the official 4.7.2 release article (source T01). |
| Godot export templates | Only `4.6.stable` and `4.6.2.stable` are installed. **No 4.7.2 templates.** | Listing of `%APPDATA%\Godot\export_templates`. |
| Godot MCP (Funplay) | Connected; editor project is `G:/aiclub projects/godot-mcp-project/` and contains only the MCP add-on (41 entries, no scenes, no main scene). | `get_project_info`, `get_capability_status`, `list_files`. |
| Blender | `5.3.0`, build `02f0899d78e3` dated 2026-11-10 (Microsoft Store install) | Blender MCP `execute_blender_code`; headless audit reports. |
| Blender MCP | Connected to the live instance (untitled default scene: Camera, Cube, Light). Its `*_for_cli` background tools fail: `BLENDER_PATH` is not set. | Tool calls. |
| Headless Blender | Works through `%LOCALAPPDATA%\Microsoft\WindowsApps\blender-launcher.exe -b`. Direct `blender.exe` is access-denied. | Used for every file inspection (`--factory-startup --disable-autoexec`, nothing saved). |
| Test machine | Desktop: ASRock B660M-HDV, Intel i7-12700KF, NVIDIA GeForce RTX 4060 Ti, 31.8 GB RAM, Windows 11 Pro 10.0.26300 | `Win32_ComputerSystem`, `Win32_VideoController`. |

## 2. Top-level contents

| Path | Files | Size | What it is |
| --- | ---: | ---: | --- |
| `grand_colony\` | 3,401 | 2,903 MB | The colony: Blender build scripts, merged `.blend`, browser game, references, renders, per-area work folders. Own git repository. |
| `grand_colony_drive\` | 5 | 261 MB | A hand-off copy dated 2026-11-08: `.blend`, browser game HTML, 15 Cycles beauty shots (zip), contact sheet, source zip. |
| `mars_kit\` | 71 | 101 MB | Earlier asset-kit study (three scenes, 9 scripts, 53 renders). Not referenced by the game build. |
| `cinematic\` | 17 | 154 MB | Intro video, keyframes, slates, shot list. Out of scope (the brief excludes video and cutscenes). |
| `lan-walk\` | 101 | 1.6 MB | Godot 4.7 LAN prototype, older variant (8 clients, random spawn). |
| `lan_walk\` | 14 | <0.1 MB | Godot 4.7 LAN prototype, newer variant (3-player cap, slot reuse). `lan_walk.zip` is its 6-file package. |
| `3d models\` | 0 | 0 | Empty. |
| `backup_before_claude_colony.blend` | 1 | 0.5 MB | Early backup scene (752 objects). |
| `.claude\launch.json` | 1 | — | Preview server configs (see section 8). |
| `docs\` | — | — | Created by this milestone. |

## 3. Blender source files (unique by SHA-256)

Opened with Blender 5.3.0 in every case. "Saved with" is the version stored in the file header.

| # | Path | Bytes | Modified | Saved with | SHA-256 |
| --- | --- | ---: | --- | --- | --- |
| B1 | `grand_colony\grand_colony.blend` | 219,541,930 | 2026-11-11 01:23:10 | 5.3 (sub 31) | `6AAD006F0CA604DDF263E644D046F19E53F9B093082EBC3EBFB90D0CD15C916B` |
| B2 | `grand_colony\grand_colony.blend1` | 219,964,569 | 2026-11-08 20:43:59 | 5.2 (sub 45) | `FEF31F232ECD93C53ED574480B9FD562BB53532F29C7642C6FEFD42CE91709B4` |
| B3 | `grand_colony_drive\grand_colony.blend` | 219,940,169 | 2026-11-08 12:39:09 | 5.2 (sub 45) | `A00D05EB063BA9BA1B03BC344D40EC8E89C8772229ECBF8D171BB4EB18A40D10` |
| B4 | `mars_kit\mars_kit.blend` | 12,634,045 | 2026-11-05 19:21:36 | 5.2 (sub 45) | `AD277F210448BD890F5E41D87445B0613BB86CCDCEF8C391CA225A07BF274B32` |
| B5 | `backup_before_claude_colony.blend` | 495,216 | 2026-11-05 18:33:04 | 5.2 (sub 45) | `8E043A750961B9E26927E0BF503CEE80BCAF95AEC4D320CD23B4800B9EB98B84` |
| B6 | `grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend` | 49,420,489 | 2026-01-20 12:59:04 | 4.2 (sub 67) | `3C121505651140CEB4D69FD1D8923F7788FFADD81672F5BE14845A5F2C75C137` |
| B7–B11 | `grand_colony\work\_v12\k1..k5\kit.blend` | ~570 KB each | 2026-11-07 | 5.2 | `F1D28096…`, `C48A60B3…`, `EEA0DF93…`, `3BE36017…`, `708A99C3…` |
| B12–B14 | `grand_colony\work\_v12\t1..t3\test.blend` | ~13 MB each | 2026-11-07 | 5.2 | `ED5055DE…`, `0D61588C…`, `81C24F65…` |

Full hashes for B7–B14 are in `evidence\hashes_before_after.csv`.

**No two `.blend` files are byte-identical.** B1, B2 and B3 are three saves of the same scene. The audit found them identical in every inspected respect (object, mesh, material, camera, light, world and collection data; all 184 camera transforms and lenses; all 471 light energies, colours, positions and sizes). They differ only in:

- render engine stored in the scene: B1 = EEVEE, B2 and B3 = Cycles;
- current frame: B1 = 115, B2 and B3 = 1;
- save version: B1 was re-saved by Blender 5.3 on 2026-11-11.

B7–B14 are intermediate kit and test builds from the v12 rework. B4 and B5 pre-date the current colony.

## 4. Other source containers

| Path | Bytes | Notes |
| --- | ---: | --- |
| `grand_colony\game\colony_outpost.template.html` | 185,930 | Browser game source, 2,409 lines. three.js r160 + cannon-es 0.20.0 from jsDelivr. |
| `grand_colony\game\colony.json` | 8,691,260 | Generated by `scripts\gc_export.py`: 593 assets, 1,857 instances, 303,340 triangles, 230 palette roles, 53 lights, 15 rooms, 21 roof rects, 3 pads, 24 doors, 9 interactables. |
| `grand_colony\game\colony_outpost.html` | 8,877,175 | Generated, self-contained game. Byte-identical to `grand_colony_drive\colony_outpost.html` (SHA-256 prefix `E9708D598509C953`). |
| `grand_colony_drive\beauty_shots_cycles_1080p.zip` | 42,117,617 | 15 PNGs `Shot_01_MedBay` … `Shot_15_GardenDome`, rendered 2026-11-08 12:14–12:39. *Historical.* |
| `grand_colony_drive\beauty_shots_contact_sheet.jpg` | ~558 KB | Contact sheet of those 15 shots. *Historical.* Copied to `evidence\contact_sheets\`. |
| `grand_colony_drive\grand_colony_v12_source.zip` | 2,104,860 | 54 files: scripts, area modules, tools, briefs. |
| `grand_colony\work\_downloads\human_base_meshes\human-base-meshes-bundle-v1.4.1.zip` | 50,643,039 | Blender Studio Human Base Meshes 1.4.1. |
| `lan_walk.zip` | 5,884 | Package of `lan_walk\` (6 files). |

No `.glb`, `.gltf`, `.fbx` or `.obj` file exists anywhere in the workspace.

## 5. Blender build and export scripts (`grand_colony\scripts`, 31,339 lines)

| Script | Lines | Role |
| --- | ---: | --- |
| `areas\a01_medbay.py` … `a15_garden_dome.py`, `x_*.py` | 20 modules | One module per area: `AREA`, `EXPORT`, optional `CAMS`/`PAD`, `build(root, cLt)`. Build order in `areas\__init__.py`. |
| `gc_place.py` | 162 | Dome, airlock, room rectangles (`ROOMS_META`), spawn, per-room dust, build orchestration. |
| `gc_shell.py`, `areas\x_shell.py` | 170 / 596 | Shared walls, floors, doors. |
| `gc_lib.py`, `gc_mat.py`, `gc_kit.py` | 755 / 623 / 833 | Asset registry with two detail levels (`render`, `game`), palette roles, physically based material classes, station kit. |
| `gc_people.py` | 709 | Survivor and EVA suits (procedural, baked caches in `work\people\cache`). |
| `gc_terrain.py`, `gc_exterior_env.py` | 1,984 / 1,503 | Terrain, glass hall, decals, dust volumes. |
| `gc_render.py`, `render_shots.py` | 655 / 87 | Light rig, sky, atmosphere, post; re-render of saved `Shot_*` cameras. |
| `gc_export.py`, `build_game.py` | 249 / 18 | Export to `colony.json` and assembly of the HTML game. **JSON only; there is no glTF/GLB export path.** |
| `area_harness.py`, `merge_colony.py` | 491 / 132 | Headless per-area harness and full merge. |
| `work\tools\*.ps1`, `*.py` | 7 files | `run_area.ps1`, `merge.ps1`, `shots.ps1`, `shot_server.py`, `contact.py`, `splice_terrain.py`. |

Several scripts hard-code `G:\nasa app\grand_colony` paths.

## 6. Version control

`grand_colony\` is a git repository with **one commit**: `30b2f40`, 2026-11-07 14:22, "Grand Colony: Blender-built Mars colony game (v11, roofed dome)". The entire v12 rework is uncommitted: 34 tracked files modified (including `grand_colony.blend`, all area modules, the game files) and 10 untracked paths (`blueprint/`, `scripts/areas/x_shell.py`, `gc_exterior_env.py`, `gc_kit.py`, `gc_mat.py`, `gc_people.py`, `gc_terrain.py`, `make_blueprint.py`, `render_shots.py`, `work/tools/shots.ps1`). Nothing was committed or staged in this milestone.

## 7. Godot projects

| Path | Engine feature tag | Contents | State |
| --- | --- | --- | --- |
| `lan_walk\` | 4.7 | `main.gd` (ENet host/join, `MultiplayerSpawner` with a spawn function, 3-player cap, slot reuse), `player.gd`, two scenes, README | Runs headless under 4.7.2 (section 9). |
| `lan-walk\` | 4.7 | Earlier variant: 8 clients, random spawn, spawnable-scene list | Not run. |
| `G:\aiclub projects\godot-mcp-project\` (outside the workspace) | — | Funplay MCP add-on only | Open in the MCP-connected editor. |

**No playable native Godot port of the colony exists in the workspace**: no world scene, no gameplay scripts, no tests, no saved test or performance reports. See contradiction C-01.

## 8. References, results and configuration

- `grand_colony\refs\` — 120 reference images in four sets (`colony-reference-library`, `game-style-life-support`, `mars-garden-references`, `mars-references`). The README states they are visual references and that generated views may differ from original screenshots.
- `grand_colony\renders\` — 68 images, versions v1 to v13, including `selftest_published_41of41.png` and `selftest_published_v8_41of41.png`. *Historical.*
- `grand_colony\work\<area>\` — 2,814 files: per-area harness outputs, `colony_check.json` exports, review renders, `plan.md` / `research.md` / `notes.md`.
- `grand_colony\work\THEME.md`, `AGENT_BRIEF.md`, `AGENT_BRIEF_V12.md`, `OWNERSHIP.md` — rules used for the v12 rebuild.
- `grand_colony\blueprint\grand_colony_blueprint.svg` and `preview.png` — plan drawing.
- `.claude\launch.json` — `colony-game` (port 8765), `terrain-test` (port 8771) and, added in this milestone, `colony-game-audit` (port 8790). Port 8765 is also the Godot MCP server's port (issue I-14).

## 9. Checks run during this milestone

| Check | Result | Evidence |
| --- | --- | --- |
| Read-only audit of all 14 `.blend` files | 14 of 14 reports written, exit 0 | `evidence\blend_reports\*.json`, `*.summary.json` |
| Asset detail pass on B1 | Written | `evidence\blend_reports\grand_colony__current_assets.assets.json` |
| Variant diff B1 vs B2, B1 vs B3 | Identical except engine and current frame | `evidence\blend_reports\grand_colony__current.details.txt` |
| Browser game self-test (`#selftest`) | **43 of 43 passed** | `evidence\checks\browser_selftest_2026-11-11.json` |
| LAN Walk loopback run, 1 host + 3 clients, headless, Godot 4.7.2 | Host and two clients each reported three moving players; the fourth process saw no players (capacity 3) | `evidence\checks\lan_walk\*.out.txt` |
| Source hashes before and after | See `evidence\hashes_before_after.csv` | — |

The browser self-test is automated: the page drives its own tutorial route and system checks. It is not a human playthrough and it validates the old browser demo only. The LAN run used four processes on one computer over loopback; it is not a test between distinct computers.

Historical results that were inspected but not rerun: the 15 Cycles beauty shots, all per-area harness reports, the `41of41` self-test screenshots.
