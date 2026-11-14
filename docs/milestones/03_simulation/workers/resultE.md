Created [astronaut.glb](</G:/nasa app/mars_colony_godot/assets/characters/astronaut.glb>), [astronaut.blend](</G:/nasa app/mars_colony_godot/assets_src/characters/astronaut.blend>), rebuild scripts, 32 pose stills, [report.json](</G:/nasa app/docs/milestones/04_player/rig/report.json>) and [provenance](</G:/nasa app/docs/milestones/04_player/rig/PROVENANCE.md>).

Rebuild command, tested successfully:

```powershell
& .\mars_colony_godot\tools\blender\character\build_character.ps1
```

Rebuilds create fresh revision folders and preserve existing files.

Verified: **23 bones, 8 meshes, 9 clips**, 14,089 body triangles and 42,313 reimported suit triangles. Complete-suit containment: **0% outside** for torso, arms and legs, including added pressure liners. Exported animation samples passed foot-clearance checks. Source hashes remained unchanged; Godot was not run.

Known defects and limitations:

- Hand anchors sit approximately **24 mm off the hand surface**; seated feet are approximately **10 mm above ground**.
- Visible rigid-joint/liner seams, simplified mittens and boots, and some hard shading seams remain.
- Full-motion collisions and Godot visor rendering are unverified.
- Source licence ambiguity is recorded verbatim.

The anchor defect was discovered after publication. Your no-overwrite rule prevented replacing those files; details are in the [final addendum](</G:/nasa app/docs/milestones/04_player/rig/PROVENANCE_ADDENDUM.md>).