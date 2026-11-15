# Intact map (2026-11-14)

Owner request: the old tutorial's broken parts are not the ones the new tutorial needs. Put the original map back in
Godot "without any of the impurities", with intact floors in every room, and make every in-world prompt that said
"fix" or "use broken/damaged …" just say "Use". The new tutorial's broken parts are built as separate Blender files
in `G:\nasa app\broken_parts\` and are NOT in this project.

## Where the broken parts came from

No version of today's map without them was ever saved. They were authored into the v12 rebuild of
`G:\nasa app\grand_colony\grand_colony.blend` (2026-11-08, `work\THEME.md` §2 "the story the rooms must tell": a
lander crash, a Power Room fire, brownouts, a comms console "broken at first"). The Godot map was a byte-identical
export of that file (sha256 6AAD006F…). The only older map, v11 (2026-11-07), is low-poly and already had the broken
comms console, so it was not used.

## What was done

`tools\blender\make_intact_map.py` opens the source map headless and writes a copy,
`G:\nasa app\grand_colony_intact\grand_colony_intact.blend` (the source is never saved). In the copy:

| Room | Object(s) | Change |
|---|---|---|
| Power Room | `pr_swgr_burnt` | -> intact `pr_swgr` mesh |
| Power Room | `pr_bat_rack_alarm` ×3, `pr_bat_rack_open` | -> `pr_bat_rack` |
| Power Room | `pr_bat_hv_alarm` | -> `pr_bat_hv` |
| Power Room | `pr_scorch`, `pr_barrier`, `pr_ext_used` | removed (scorch and debris on the floor, barrier tape, dropped extinguisher) |
| Command Room | `cr_console_alarm` | -> `cr_console` |
| Command Room | `cm_comms_console` | rebuilt intact (builder `cm_comms_console_ok` in the script: bays closed, every card in, cover on, no test leads, green displays) |
| Greenhouse | `gr_rack_fault` (+ its 3 grow lights added) | -> `gr_rack` |
| Greenhouse | `gr_tray_wilt_a` ×2, `gr_tray_wilt_b` | -> `gr_tray_romaine`, `gr_tray_butter_m` |
| Life Support | `ls_air_unit_open` | -> `ls_air_unit` |
| Mess Hall | `co_meal_spill`, `co_chair_down` | -> `co_meal`, `co_chair` |
| Ceilings | `rf_tile_lt/dk/eng_dead` ×6 (+ their 6 fixture lights added) | -> `rf_tile_*_lamp` |

Object NAMES are unchanged (stations, salvage donors and lore records bind to names such as `pr_swgr_burnt`); only
the mesh and `gc_asset` changed. The exterior lander crash site stays (owner's choice). `ls_filter_old` (a used
filter cartridge on the floor, a salvage donor) is not damaged and stays.

Then `tools\export_from_blender.ps1 -Blend <intact copy> -Report docs\milestones\intact_map\export` and
`tools\build.ps1`. Manifest diff against the previous export: exactly the 24 objects above changed or removed and 9
lights added (1857 -> 1854 objects, 471 -> 480 lights); `environment.glb`, `terrain.glb` and `colliders.json` came
out byte-identical. `palette.json` dropped the roles nothing uses any more (soot, smoke, dead LED, brown leaf), so
`gen_materials.py` deleted their four `.tres`. The far LOD proxies (`res://lod/`) were not rebuilt: their source
(the exterior shell) is unchanged (782 meshes, 4,433,475 triangles, checked with `--dry-run`).

Prompt: `GameHud.STATION_NAMES["salvage"]` is now empty, so salvage donors show "[E] Use" instead of
"[E] Use damaged machine". No other in-world prompt said fix/broken/damaged.

## Floors (owner screenshots, same day: "it still is broken, have floor be normal")

- Greenhouse: two 2 m holes down to the sand at (-7, -9) and (-5, -7). Cause: `HabitatFinish` (2026-11-13 fix for an
  earlier PDF) hid every `gr_floor_drain` tile to get rid of the drain grates, which removed the whole floor tile. Now
  `HabitatFinish.PLAIN_FLOOR` draws those three tiles with the plain `gr_floor` mesh (grate gone, floor whole).
- Dome plaza (the strip between the rooms and the glass hall): bare crater sand, because the source map has no plaza
  floor; the browser game (Grand Colony artifact) draws a "dome deck" in code. New `scripts\world\dome_deck.gd`
  rebuilds it the same way (1 m cells over the hall footprint, 2 m checker #3e332e / #473a33, 3 cm under the room
  floors; the terrain there is flat at -0.05 m, so it needs no collision). Called from `GameMain` after HabitatFinish.
- Owner rule: when unsure how the inside should look, follow the artifact
  (https://claude.ai/artifact/Wso1226sanTfxkWpLciT2g, source `G:\nasa app\grand_colony\game\colony_outpost.template.html`).
- Checks: compile OK (239 scripts); test_pdf_fixes 42/42 (drain tiles drawn whole, deck present), test_collision 40/40,
  test_hud_panels 89/89. test_game_scene's suit-rack step (I-59) fails on some runs with the old and the new code alike.

## Not changed (for the next instruction)

- Game data still describes the old story: salvage donor names ("Burnt switchgear cabinet", "Battery rack with a
  fault alarm"), lore records, the tutorial text (`data\tutorial.json`: "Install the first radio repair card", the
  broken panel cleaner) and the broken-down rover outside (a game-side prop, not part of the map).
- Rebuild: run `make_intact_map.py` on the source map again, then the two tools above.
