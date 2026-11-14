# Game Functionality errors: scoped repairs

Base: `5d44da8` (the previously published crew-collision fix). Original Blender/GLB assets and the export/material-generation/build workflow are retained. Runtime presentation corrections follow the existing `SuitDisplays` approach and are applied by `GameMain` before prop collision is assembled.

| PDF item | Result and implementation |
| --- | --- |
| Camera inside characters | Existing solid crew bodies retained. Third-person spring arm also senses crew; an arm retracted inside the local body renders that body as shadows only. Other crew and third-person identities remain visible. |
| Corridor cement floor/wall panels | `HabitatFinish` gives `sc_floor` a smooth, neutral cement face over its old rubber tread; only the `kit_panel`/`kit_lower` surfaces of `sc_e_panel` change finish. Windows, pillars, bolts, trim and dimensions are retained. |
| Interior dirt/cloudy ceilings/walls | Indoor surface copies disable dust, wear, grime, roughness noise and bump noise. Ceiling underside tiles are included; outdoor materials and roof slabs retain their authored finishes. |
| Moving/disappearing silver kitchen rectangle | The kitchen hood retains its geometry but uses a stable matte finish and is excluded from occlusion/range culling. Rendered views at three nearby angles were inspected. |
| Silver wall smudges | Interior wear/grime layers are removed; structural hardware remains. |
| Hangar ladder | E holds/releases; W/S climb; Space or A/D releases. The real mezzanine is reachable in both directions. Side rails remain solid; a convex hull can no longer seal the rungs/exit. Prop-collision cache version increments to 4. |
| Utility-room floor vent | `ls_drain` instances hidden. |
| Chair/bed/furniture reflections | Indoor surfaces use high roughness and reduced specular; chair surfaces have zero specular. Light and power settings are retained. |
| Chess count | Original board/mug retained. Incomplete piece surfaces replaced with a complete starting position: 8 pawns, 2 rooks, 2 knights, 2 bishops, 1 queen and 1 king per side. |
| Plants growing in steel | Both `co_planter` instances have visible soil above the old steel top, within the trough rim. |
| Four suits, take/return visibility | Four rack displays; host reserves distinct slots even for simultaneous checks. Worn suits save/replicate their rack and slot. Display visibility derives from authoritative state, including after loading. Returning a suit restores its original slot. Older saves are assigned unique slots without refilling tank charge. |
| Suit reflections | Per-character copies reduce metallic/specular/clearcoat and raise suit/visor roughness. Shared imported materials are not changed. |
| Wire on floor | `qt_cable` hidden. |
| Greenhouse drains, mop and towel | `gr_floor_drain` instances hidden; a wall-mounted mop and towel are added beside the west-wall utility equipment, clear of the door and walkway. |
| Airlock footprints/dust | `ak_dust_trail` and `ak_dust_drift` hidden; interior dust finish removed. |
| Yellow arc in suited first-person jumps | The separate `Ident_*` helmet/collar bands now share the first-person shadow-only treatment of the helmet. The band was separate from `Suit_Helmet`, which was already hidden. |

## Validation

Latest completed checks: **1,292/1,292 across 20 suites**, including 43 targeted PDF checks. Suites: collision, crew collision, food, game scene, game services, graphics quality, HUD panels, life support, P07 panels, PDF fixes, player, progression, saves, science, session, sources, station panels, UI framework, weather and weather data.

The rendered scenario walkthrough exercised the actual map, prop collision, suit check/return, first-person suited jumping, both camera perspectives, kitchen views, planters, cleaning equipment and ladder ascent/descent. It captured 20 views; its final result was `PDF WALKTHROUGH failures=0`. Ascent ended on the real deck at approximately `(28.96, 2.70, -0.33)`. The yellow arc is absent in the inspected jump view.

An initial concurrent game-scene test reported zero startup movement; the serial rerun passed 32/32 with 0.84 m of movement. The targeted ladder test and rendered ladder test both passed after removing the enclosing hull. No assertion was weakened to accept a blocked exit.

Weather checks initially failed because Windows CRLF checkout altered the byte sizes/hashes of archived CSV/JSON data. Targeted `.gitattributes` LF rules and restoration of authored LF bytes resolved this; weather logic and dataset values were not changed. Weather suites then passed 66/66 and 14/14.

### Repeat checks

```powershell
& .\tools\run_tests.ps1 -Tests test_pdf_fixes,test_player,test_collision,test_game_scene,test_session,test_saves,test_weather,test_weather_data
```

Rendered replay, using the installed Godot console executable:

```powershell
& "<Godot console executable>" --path . --windowed --script res://tools/godot/verify_pdf_walkthrough.gd
```

Screenshots default to `_test_saves/pdf_views`. Test saves use `_test_saves/pdf_walkthrough`; player saves are not used. `tools/godot/diag_pdf_assets.gd` prints source surface/geometry evidence without changing assets.

## Verification limits

Live LAN transport was not certified: the earlier local ENet test did not receive client state in this restricted session. Suit reservation and save/replication records were checked in-process. A two-machine playtest remains useful before claiming multiplayer coverage.

Godot 4.7.2 emits renderer `softshadow_count` / geometry-light unpair diagnostics during rendered scene replacement/shutdown, plus restricted `user://` cache/log warnings here. These are recorded rather than presented as a clean engine log. The final replay had no GDScript errors or failed scenario assertions.

Publishing from the agent terminal is restricted by `.git` write permissions and networking. `tools/publish_pdf_fixes.ps1` stages this reviewed change set explicitly, commits, integrates the latest Maanas `main`, and pushes without force. It does not stage unrelated files.
