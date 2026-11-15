# Broken parts redo: how to rebuild, export and render ONE part (2026-11-14)

Owner request: every part must look MUCH more broken (3-5x, readable at 6-10 m). Kid rule: no flames, no electric
sparks/arcs, no gore, no scary failure (ask the lead before any scorch/soot). Keep the map's low-poly-with-bevels style
and palette. Split: lead = BP05, BP08, BP10 + final assembly; helper 1 = BP01-BP03; helper 2 = BP04, BP06;
helper 3 = BP07, BP09.

All commands are PowerShell. Blender is headless only; never save the map. `$p` = the Godot project.

```powershell
$b = "$env:LOCALAPPDATA\Microsoft\WindowsApps\blender-launcher.exe"
$p = "G:\nasa app\mars_colony_revisions_wt"
$NN = "BP03"; $part = "BP03_wires_task"        # your part
```

Run Blender with PowerShell `& $b ...` (it waits for Blender to finish; from Git Bash the launcher returns at once and
prints nothing). Every tool writes its own log/report file, so read that file afterwards.

## 1. Rebuild the part's .blend (your own script, `G:\nasa app\broken_parts\scripts\BPnn_*.py`)

```powershell
& $b -b --factory-startup --disable-autoexec "G:\nasa app\grand_colony\grand_colony.blend" `
     --python "G:\nasa app\broken_parts\scripts\$part.py" | Out-Null
```
(arguments after `--` as each script's docstring says, e.g. `-- --log <txt>`). Output: `G:\nasa app\broken_parts\$part.blend`
and `renders\$part*.png`. Re-open the written .blend once to check it loads.

What the exporter needs from the .blend (do not break these):
- collection `Broken`; every exported object is a MESH with custom property `map_matrix_world` (16 floats, row-major,
  Blender map coordinates). Objects without it, names containing `__context`, and objects whose `note` starts with
  `unchanged` are skipped. The glb is placed by `map_matrix_world` only (not by the side-by-side layout).
- materials named `GC_<role>`. Roles of the colony library and the existing bp_ roles (bp_spill, bp_pink, bp_copper,
  bp_static, bp_static_dk, bp_red, bp_crack, bp_haze, bp_shard, bp_led_red, bp_vapour, bp_water, bp_puddle, bp_print)
  work as they are. A NEW role must carry a material custom property `bp_role` (JSON string), e.g.
  `m["bp_role"] = json.dumps({"pal": ["#36c58f", 0, 0.04, 0.0], "class": "plastic", "params": {"rough": 0.04}, "alpha": None})`
  (pal = hex, emission, roughness, metallic; class = a gc_mat class: paint, plastic, metal, glass, glow, rubber, ...;
  alpha only for see-through roles). Name new roles `bp_<something>`. Tell the lead the new role names.
- effect geometry (spray, puddle, vapour, debris that should vanish at the fix): either a separate object with custom
  property `bp_kind = "effect"`, or keep the existing effect objects/materials. Existing node names the game uses
  (keep them, or tell the lead the new ones): BP01 spill = faces of `GC_bp_spill` in `mb_sink_counter__broken`;
  BP05 `gd_glass_shards__broken`; BP08 `air_leak_vfx__broken`, leaves `tunnel_door_inner_leaf_L/R__broken`, seals =
  `GC_kit_rubber` islands at the meeting edge, alarm = faces differing from `tunnel_door_inner_portal__original`;
  BP09 `gr_rack_water_leak__broken` (split by `GC_bp_water` / `GC_bp_puddle`); BP10 `hg_dust__broken`.
- object names `<map object>__broken` (dots allowed; the export turns them into `_`).
- visual only: collision is unchanged in the game. Keep the floor in front of the repair station clear (stations:
  `$p\data\stations_repairs.json`, Godot coords; Blender = (x, -z)); nothing new where a player stands or walks.

## 2. Export the part to Godot (glb + report)

```powershell
& $b -b --factory-startup --disable-autoexec "G:\nasa app\broken_parts\$part.blend" `
     --python "$p\tools\blender\broken_parts\export_broken_parts.py" -- --out $p | Out-Null
Get-Content "$p\tools\blender\broken_parts\reports\${NN}_export.json" -TotalCount 40
```
Check in the report: `"ok": true`, no `error`, `unmapped_materials` empty, the nodes and their Godot AABBs
(`aabb_min/max`), `bounds`. Writes `$p\assets\broken_parts\$NN.glb`. Do NOT run the Godot import,
`build_broken_parts_data.py` or `annotate_in_map.py` (lead only, once at the end).

## 3. Render the in-map broken/fixed pair (checks the glb in the map)

```powershell
& $b -b --factory-startup --disable-autoexec "G:\nasa app\grand_colony_intact\grand_colony_intact.blend" `
     --python "$p\tools\blender\broken_parts\render_in_map.py" -- --proj $p --parts $NN --samples 32 --overview 0 | Out-Null
Get-Content "$p\docs\revisions\evidence\broken_parts\in_map\render_log_$NN.txt"
```
Writes `docs\revisions\evidence\broken_parts\in_map\${NN}_broken_in_map.png` and `${NN}_fixed_in_map.png` (same
camera; the lead adds titles and the locator inset later) and `in_map\cams\$NN.json`. Takes about 1-2 min (map load +
2 renders). The camera is the one the lead set for the part; for a one-off view add
`--eye x,y,z --look x,y,z` (Godot coordinates) and say so in your report. Read both PNGs yourself: is the damage obvious
from there, and is the part exactly where the intact object stands?

## 4. Report to the lead

Per part: what got more broken, new roles (name + bp_role JSON), new / renamed effect nodes, the image paths, and
anything near a station spot or walkway.
