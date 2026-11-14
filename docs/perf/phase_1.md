# Perf overhaul, Phase 1: engine settings (no new systems)

Status: **implemented as switches, defaults unchanged, not measured** (no windowed runs: `phase_0.md`).

| Item | Finding | Done |
|---|---|---|
| Occlusion culling | Already ON (`rendering/occlusion_culling/use_occlusion_culling=true`), 21 roof box occluders under `world/Occluders`. No wall occluders. | A/B toggle Ctrl+5 (viewport `use_occlusion_culling`). Not baked further: "Bake Occluders" is an editor-only action, and every interior door has a glass panel, so wall occluders would need hand-cut holes at 26 doors and 7 windows. The zone system (Phase 2) removes the rooms behind walls instead. |
| Door occluders | `ZoneDoor.closed_occluder` exists; no door has one (doors are glazed: an occluder would hide what the glass shows). | none assigned |
| Mesh LOD | glb imports generate LODs. Project threshold 2.0 px. | `PerfSettings.apply_quality(&"low"/&"medium"/&"high")` = 4 / 3 / project value (2.0); Ctrl+6 cycles. Not hooked to the graphics menu (the High preset must stay authored). |
| Sun shadows | `GC_MarsSun`: max distance 160 m, 4-split PSSM, fade start 0.8. Already close to the brief's 150 m. | `sun_shadow_tuning_enabled` (OFF): 150 m, fade 0.8; Ctrl+Shift+3. Expected gain: negligible (10 m less). |
| Fixture fade | 417 fixtures; High has no distance fade, Medium/Low fade at 24/40 m (GraphicsQuality). | `light_distance_fade_enabled` (OFF): 30 m + 10 m, shadow 25 m on unfaded Omni/Spot fixtures; Ctrl+Shift+4. Restores exactly when off. |
| Far plane / fog | Camera far 4000 m, fog off. | Not changed. Option: far 2000 m (depth precision only, small perf effect); depth fog would change the authored look. |
| Repeated objects | 996 rocks share 14 meshes: Forward+ already instances identical mesh+material draws. | Not converted to MultiMesh: RockCollision and the rocks' authored per-instance ranges read the MeshInstance3D nodes. Option: 64 m MultiMesh cells per rock mesh. |
| Transparency | 11 colony glass surfaces on layer-20 meshes, ~100 glazed meshes in all (one glass surface each), the hall dome glass (54 x 32 x 17 m). Rocks fade with alpha (FADE_SELF) over their last 10 m. | Reported only. Option: rocks to FADE_DISABLED (hard pop at 5 px, no transparent pass). |

Why defaults stay off: both switches change pixels (the brief: "do not mark done until measured; leave it off").
