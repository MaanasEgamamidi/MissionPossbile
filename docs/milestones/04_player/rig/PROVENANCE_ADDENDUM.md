# Final verification addendum

This adds findings after the create-only canonical publication. It does not replace or modify `PROVENANCE.md`, `report.json`, the GLB or any `.blend`.

- The one-command rebuild was exercised successfully as `build_character.ps1 -RunName rebuild_check01`. It created a separate revision and preserved all canonical outputs. Both source hashes remained unchanged.
- The canonical GLB SHA-256 is `3720085afb2ecd90546a8984b79e70b1324b5242038d2bdbf920744b60e4c11a`.
- Source-stage geometry: 14,089 body triangles and 42,314 suit triangles. GLB reimport: 14,089 body triangles and 42,313 suit triangles. The exporter/reimport tessellation differs by one suit triangle.
- `final01_glb_validation_v2/validation.json` checks the actual exported GLB. All vertices have weights; body vertices have at most four influences, normalized within 1.10e-7; every suit vertex has exactly one influence of 1.0. All nine clips were sampled at 30 fps. Minimum foot height was approximately 0.0000997 m; maximum horizontal Hips offset was below 1.4e-8 m. Seated feet remain approximately 10 mm above the floor.
- The 32 canonical pose stills were visually reviewed, as were six additional GLB reimport stills covering carry, sprint and seated, side views, crew and suit. No obvious detached pieces, exploded weights or limb-through-torso penetration was observed in those stills. Full-motion collision freedom is not certified.

## Additional known defect: palm anchor placement

`hand_anchor_measurements.json` measures the actual exported anchors in the rest pose. Both are correctly parented to their corresponding hands, but their heads are approximately **23.9 mm from the nearest hand surface**, rather than directly on the palm. This is a placement defect against the requested palm location. The measured nearest-surface deltas in Blender coordinates are:

- Left: (-0.01449, -0.01889, -0.00228) m.
- Right: (+0.01445, -0.01898, -0.00223) m.

Those are proximity measurements, not certified anatomical palm landmarks or final grip offsets. This defect was found after canonical publication. The user explicitly prohibited modifying any existing file, so the published files were preserved and the finding is recorded here rather than silently replacing them.

Other documented limitations remain: rigid joint/liner seams, simplified mitten gloves and boots, hard coverall/hair shading seams, approximately 0.45 m seated placement without a numerically certified seat contact, no Godot runtime/visor check, and the source-licence ambiguity quoted in full in `PROVENANCE.md`. Rest containment of the complete exported suit is 0% outside for torso, arms and legs; the pressure liners are real exported geometry and are necessary for that result.
