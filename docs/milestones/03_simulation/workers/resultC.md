Created:

- `scripts/world/world_collision.gd`
- `scripts/world/door_controller.gd`
- `scripts/world/terrain_height.gd`
- `tools/godot/build_heightmap.gd`
- `tests/test_collision.gd`

Exact test command:

```powershell
..\godot.cmd --headless --path . --script res://tests/test_collision.gd
```

Full last output:

```text
ERROR: Failed to open 'user://logs/godot2026-11-11T07.29.51.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
STATS {"bodies":19,"boxes":1417,"doors":24,"leaves":52,"stations":9}
PASS 24 doors, 52 leaves, 9 stations
PASS exact collider count for every eligible manifest object
PASS one static body per manifest area
PASS all 1250 first-box centres (rotated=404 scaled=55 max_error=0.000004m)
TRANSFORM hb_fl (15.0, -0.08, 1.0)
TRANSFORM hgw_door_small_leaf.002 (30.0, 1.0995, -7.2492)
TRANSFORM xc_floor.016 (11.0, -0.08, -3.0)
TRANSFORM co_floor.031 (13.0, -0.08, -9.0)
TRANSFORM co_chair.026 (7.224554, 0.4248, -15.04923)
TRANSFORM ms_beanbag_orange (22.75, 0.31, -18.35)
TRANSFORM mb_headwall (-9.0, 1.36, -17.766)
TRANSFORM cmw_door_leaf.001 (24.0, 1.0745, -12.7508)
TRANSFORM wb_floor.004 (-7.0, -0.08, -1.0)
TRANSFORM eq_wall (37.0, 1.51, -20.0)
TRANSFORM sc_e_panel (33.9602, 1.75, 1.0)
TRANSFORM gr_floor.041 (9.0, -0.08, 11.0)
TRANSFORM msw_pillar.002 (-10.0, 1.5093, 0.0)
TRANSFORM ak_wn_1 (17.0, 2.18, 2.1482)
TRANSFORM pr_floor.027 (39.0, -0.08, 3.0)
TRANSFORM pr_panelboard.001 (27.42, 1.45, 9.748)
TRANSFORM pg_floor.001 (15.0, -0.08, -11.0)
TRANSFORM sf_blast_wall.004 (-32.13102, 1.2, 19.97415)
TRANSFORM gd_hydro (54.55, 1.025, 23.4)
TRANSFORM rf_fascia.014 (37.0, 3.27, 10.0)
PASS static and station layers, metadata and radius
PASS floor Hangar bay y=-0.0000
PASS floor Crew corridor y=-0.0000
PASS floor Mess hall y=-0.0000
PASS ray across hangar wall blocked
PASS attach all synthetic door visuals
PASS closed door blocks ray
PASS player opens door within 1.0 physics second
PASS open door ray passes
PASS visual leaves move by signed door_slide
PASS door closes after player leaves
PASS locked door stays shut beside player
PASS sloped bumpy world-space mesh samples max_error=0.000000
PASS height sampling clamps edges
PASS bilinear interpolation
PASS empty sample cells filled from neighbours
PASS heightfield ray 0 error=0.00097
PASS heightfield ray 1 error=0.00151
PASS heightfield ray 2 error=0.00035
PASS heightfield ray 3 error=0.00051
PASS heightfield ray 4 error=0.00321
PASS heightfield ray 5 error=0.00274
PASS heightfield ray 6 error=0.00092
PASS heightfield ray 7 error=0.00020
PASS heightfield ray 8 error=0.00037
PASS heightfield ray 9 error=0.00050
PASS save tool input scene
ERROR: Failed to open 'user://logs/godot2026-11-11T07.29.54.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
HEIGHTMAP 9x9 -> res://tests/tmp/terrain_height.res
PASS tool writes loadable matching resource
RESULT 32/32
```

Nothing unfinished; no known specification deviations. Exit code 0, all 32 checks passed, zero script errors or warnings-as-errors. Environment errors remain for inaccessible Godot logs and the Windows certificate store.