# Prompt 02 — Lighting calibration report

Date: 2026-11-11. Godot `4.7.2.stable.official.ed1daf0bf`, Forward+, NVIDIA GeForce RTX 4060 Ti.

**Scope warning.** The improved map was not supplied, so no final-map Cycles reference set could be rendered. This is a rehearsal on the **current** map against the 15 Cycles beauty shots saved on 2026-11-08. Those shots are historical renders of the same scene content (Prompt 01 found the three saved copies of the scene identical apart from engine setting and frame). The result is a working pipeline, a first lighting preset and a measured list of what does not match. It is not an acceptance of the final map.

**No view reaches the target of 95.** Rubric scores run from 60 to 77, mean 69.1. The rubric is a visual review score out of 100. It is not a measured physical percentage, and the image metrics below do not show that lighting is any given percentage accurate.

## 1. Protocol actually used

| Item | Reference (Cycles) | Godot |
| --- | --- | --- |
| Cameras | 15 `Shot_*` cameras stored in the scene | The same 15, rebuilt from `data\colony_manifest.json`: world matrix, vertical FOV derived from the horizontal sensor fit at 16:9, clip planes. Largest position error against the source: 0 m. |
| Resolution | 1920 × 1080 (checked in the zip) | 1920 × 1080, off-screen viewport, MSAA 4×, no UI, no debug overlay |
| Frames before capture | — | 100 |
| Colour management | AgX, look "AgX - Punchy", exposure −0.45 EV, sRGB | AgX tonemapper, exposure 2^−0.45, contrast 1.3, saturation 1.12 |
| Post | Compositor as saved in the scene (bloom, dispersion, colour balance, vignette). Whether it was active for these renders was not recorded. | Glow only. No dispersion, no vignette. |
| Scene state | Day, all fixtures on | Day, all fixtures on |
| Geometry | Render detail level, procedural materials | Game detail level, flat palette materials with shader dust |
| Lights | 407 fixture area lights, 10 exterior area lights, 1 sun | The same 418, see section 3 |

Camera parameters per pair: `camera_pairs.json`. Pair images: `evidence\pairs\sheets_pass3\`. Godot captures per pass: `evidence\pairs\pass0_baseline`, `pass1`, `pass2`, `pass3`.

Differences that limit any comparison and that calibration cannot remove: the detail level, the materials, and the unrecorded compositor state. The same 15 camera pairs were used in every pass; no reference was changed.

## 2. Three correction passes

| Pass | Focus | What changed | Mean SSIM | Mean abs. EV difference | Mean ΔE76 |
| --- | --- | --- | ---: | ---: | ---: |
| 0 | Baseline | All 417 fixtures as AreaLight3D, SDFGI on, first-guess energies | 0.670 | 0.689 | 16.74 |
| 1 | Fixture type and energy balance | Spot lights (140° cone, inverse-square) for panels under 1 m², AreaLight3D for the 39 larger ones; per-room ambient from fixture power; SDFGI off; sun and sky lowered | 0.738 | 0.175 | 11.10 |
| 2 | Materials and colour | Shader dust from the per-object dust value; explicit render colours; room light masks tightened; smoked hall glass; saturation 1.12 and AgX contrast 1.3; fog tested and rejected | 0.734 | 0.151 | 10.44 |
| 3 | Shadows, contact, reflections, bloom | Shadow maps on the 3 largest fixtures per zone; stronger SSAO; SSIL; glow; room ambient scaled by each room's mean albedo; probe intensity halved; screen emission reduced; airlock tunnel pieces lit from the rooms; fixtures assigned to the room that built them | 0.764 | 0.111 | 9.12 |

Metric settings: both images resized to 960 × 540 (Lanczos); SSIM on sRGB luma, Gaussian window 11 × 11, σ 1.5, K1 0.01, K2 0.03; EV difference is log2 of the ratio of mean linear luminance; ΔE76 is the mean CIE76 difference at 480 × 270. Files: `evidence\pairs\metrics_<pass>.json` and `.csv`.

Pass 3 was captured twice. After the first capture three faults were corrected (ambient in dark rooms, screen emission, the unlit airlock tunnel door) and the set was captured again; the first set is kept as `pass3_preliminary`. A later fix to fixture ownership (section 5) changed the images slightly and the final set was captured once more. No fourth calibration pass was run.

Experiments behind the choices are in `evidence\pairs\experiments\` (`exp1` to `exp6`, each with its variant file and `experiment_results.json`).

## 3. Findings that shaped the preset

1. **AreaLight3D does not feed SDFGI in this build.** Raising `light_indirect_energy` fourfold on all 417 area lights changed no measured value (`exp1`, variant C equals the baseline to two decimals).
2. **SDFGI leaked sky light into the rooms.** Turning SDFGI off changed the interiors by 0.01 to 0.10 EV; lowering the sky energy darkened the ceilings. The indoor "bounce" in the baseline was sky light, which must not be there. SDFGI is off in the preset.
3. **Area lights cost about twice as much as spot lights here.** At 960 × 540 the three test views took 9 to 12 ms with 417 area lights and 5 to 6.5 ms with spot lights (`exp2`). The preset uses 39 AreaLight3D (panels of 1 m² or more) and 378 SpotLight3D.
4. **Unshadowed fixtures must not cross walls.** Each room, the plaza, the garden dome and the exterior have their own render layer. Every fixture's cull mask is its own zone; every mesh carries the layers of the zones it actually overlaps. Floor tiles and furniture belong to one room; thin door and partition panels and straddling walls belong to both.
5. **Fog made the match worse.** Fog at density 0.0012 raised the top quarter of the three exterior frames by 1.0 to 1.5 EV and reduced the red-to-green ratio (`exp6`). Fog is off.
6. **Indoor bounce is a managed stand-in.** Each room's reflection probe carries a uniform ambient equal to k × (fixture watts ÷ room surface) × ρ ÷ (1 − ρ), with ρ the room's mean surface albedo computed from the source meshes, tinted by the power-weighted fixture colour. k = 0.085 was fitted on the references. It cannot leak between rooms and it follows the room's power state.

## 4. Lighting preset (initial)

File: `mars_colony_godot\data\lighting_preset.json`. Every scale is a visual fit to the reference images. None is a physical conversion from Blender watts.

| Group | Setting |
| --- | --- |
| Tonemap | AgX, exposure −0.45 EV, contrast 1.3, white 16.29 |
| Adjustment | Saturation 1.12 |
| Sun | Blender strength 2.6 × 0.18 = energy 0.468; colour (1.00, 0.93, 0.84); angular size 0.9°; 4-split shadows to 160 m |
| Sky | Procedural, colours from `gc_render.setup_world`; energy 0.45; ambient and reflections from sky outdoors |
| Fixtures | Mixed mode. Spot: energy = watts × 0.055, cone 70° half-angle, angle attenuation 0.6, distance attenuation 2.0, range 14 m indoors and 30 m outdoors. Area (≥ 1 m²): energy = watts × 0.014, normalised. Specular 0.6. |
| Fixture shadows | 51 lights: the 3 largest panels per zone with area ≥ 0.25 m² |
| Dynamic GI | SDFGI off. SSAO radius 1.2, intensity 2.6. SSIL on. |
| Room probes | 15, one per room rectangle: interior, box projection, intensity 0.5, per-room ambient (k = 0.085), box margin 0.5 m, blend 0.05 m |
| Fog | Off |
| Glow | Intensity 0.25, bloom 0.03 |
| Materials | Emission scale 1.0; screens × 0.35; dust gain 1.0; hall glass alpha 0.5; garden-dome glass alpha 0.3 |

Room ambient values produced by the rule range from 0.036 (Pipe gallery, mean albedo 0.09) to 0.321 (Greenhouse); the list is in `mars_colony_godot\data\build_world_report.json`.

## 5. Day and night, powered and unpowered

Design, implemented in `scripts\world\zone_lighting.gd` and `colony_zones.gd`:

- **Nothing is baked.** The scene has no LightmapGI node and the meshes are imported with light baking disabled. There is no stored indirect light that could outlive a switch.
- **Zone power.** `set_zone_powered(zone, false)` hides the zone's fixture lights, sets the per-instance `power` value of its glowing meshes to 0 (no emission), sets the room ambient to 0 and re-renders the room's reflection probe once. Powering on restores the authored values. Fixtures and glowing meshes belong to the room that built them, so a wall light on a room line follows its own room.
- **Sun.** `set_sun_phase(phase)` rotates the sun, fades its energy to 0 below the horizon and scales the sky energy down to 2%. The reference state is local noon. The sol clock of Prompt 03 only has to call this with its phase; the 20-minute sol length is not hard-coded anywhere.
- **Saved preset untouched.** Run-time changes act on a per-instance copy of the environment.

Checks run:

| Check | Method | Result |
| --- | --- | --- |
| Switching logic, all 18 zones | `tools\godot\test_zone_lighting.gd`, headless | Pass. Off: 0 lights visible, 0 meshes glowing, ambient 0 in every zone; on: authored energies restored. Night: sun hidden, sky energy 0.009; day: 0.468 and 0.45 restored. 0 LightmapGI nodes. `evidence\states\test_zone_lighting.json` |
| Greenhouse unpowered, grow lights included | Capture of `Shot_11_Greenhouse` with `--off greenhouse` | Mean linear luminance 0.3156 → 0.0012 (0.4%). No pixel above luma 0.67; share of pixels above 0.5 is 0. |
| Neighbour unaffected | `Shot_02_MessHall` in the same run | 0.1633 powered, 0.1633 with the greenhouse off |
| No daylight indoors | `Shot_02_MessHall` at night | 0.1633 day, 0.1628 night (−0.3%) |
| Night exterior | `Shot_14_Exterior_Wide` with `--night` | 0.0408 → 0.0026 (6%); remaining light is the base's own fixtures |

Statistics: `evidence\states\state_stats.json`. Images: `evidence\states\`.

A fault found by these checks and fixed: one greenhouse wall light stayed on when the greenhouse was switched off, because lights were assigned to zones by position and that light sits on the room line. Fixtures are now assigned through the object they were generated from.

Not verified: light leaks at doorways with doors open (all doors are closed in the import), probe boundaries while moving, and any state combination other than the ones listed.

## 6. Score sheet (final pass)

Reviewer: the executor, from the side-by-side sheets. Owner review is pending. Columns: brightness and contrast (30), colour and white balance (25), shadows and contact (25), reflections and transmission (15), atmosphere and haze (5). The scores were given on the sheets captured before the fixture-ownership fix; the final recapture differs from those by at most 0.008 SSIM and 0.08 EV per view.

| View | B/30 | C/25 | S/25 | R/15 | A/5 | Total | SSIM pass 0 → 3 | EV diff pass 0 → 3 | ΔE76 pass 0 → 3 | GPU ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | ---: |
| 01 Med Bay | 24 | 21 | 15 | 9 | 4 | **73** | 0.706 → 0.808 | +0.47 → +0.14 | 17.1 → 6.5 | 9.9 |
| 02 Mess hall | 25 | 20 | 15 | 10 | 4 | **74** | 0.775 → 0.858 | +0.21 → −0.09 | 12.1 → 7.6 | 13.2 |
| 03 Rec kitchen | 25 | 20 | 15 | 10 | 4 | **74** | 0.737 → 0.813 | +0.24 → −0.04 | 14.7 → 8.1 | 10.1 |
| 04 Crew corridor | 26 | 20 | 17 | 10 | 4 | **77** | 0.727 → 0.860 | +1.13 → −0.13 | 17.2 → 7.7 | 17.2 |
| 05 Hangar | 22 | 20 | 13 | 9 | 3 | **67** | 0.645 → 0.719 | +0.50 → +0.10 | 14.9 → 10.7 | 17.1 |
| 06 Airlock | 23 | 19 | 14 | 9 | 3 | **68** | 0.567 → 0.708 | +0.27 → −0.01 | 18.5 → 9.2 | 16.9 |
| 07 Power Room | 20 | 18 | 13 | 8 | 3 | **62** | 0.601 → 0.710 | +0.81 → +0.30 | 16.6 → 10.1 | 11.8 |
| 08 Life Support | 24 | 20 | 14 | 9 | 4 | **71** | 0.689 → 0.732 | +0.48 → +0.10 | 13.4 → 8.7 | 11.1 |
| 09 Command Room | 22 | 17 | 14 | 8 | 3 | **64** | 0.693 → 0.763 | +0.42 → +0.18 | 12.9 → 7.9 | 10.6 |
| 10 East quarters | 25 | 19 | 15 | 10 | 4 | **73** | 0.736 → 0.835 | +0.36 → +0.02 | 17.6 → 10.6 | 9.0 |
| 11 Greenhouse | 24 | 20 | 13 | 9 | 3 | **69** | 0.711 → 0.799 | +0.17 → +0.16 | 16.8 → 11.1 | 23.9 |
| 12 West bunk room | 25 | 19 | 15 | 10 | 4 | **73** | 0.738 → 0.843 | +0.61 → +0.11 | 16.3 → 7.4 | 11.9 |
| 13 Exterior, airlock | 22 | 17 | 13 | 6 | 2 | **60** | 0.532 → 0.579 | +1.63 → +0.13 | 23.7 → 14.0 | 28.0 |
| 14 Exterior, wide | 24 | 19 | 15 | 8 | 2 | **68** | 0.603 → 0.759 | +1.47 → +0.08 | 18.9 → 7.9 | 15.2 |
| 15 Garden dome | 23 | 18 | 14 | 7 | 2 | **64** | 0.593 → 0.673 | +1.56 → −0.07 | 20.4 → 9.4 | 9.3 |

Earlier-pass rubric scores exist only for the views that were looked at in that pass: baseline — Mess hall 59, Hangar 53, Greenhouse 59, Exterior wide 42; pass 1 — Crew corridor 63, Power Room 56, Airlock 55, Exterior airlock 49. Full data: `score_sheet.csv`, `score_sheet.json`.

## 7. Views below 95 — all 15

| View | Score | Mismatch | Likely cause | Remaining work |
| --- | ---: | --- | --- | --- |
| 01 Med Bay | 73 | Contact shadows; one glowing panel | Flat room ambient instead of bounced light; 3 shadowed fixtures per zone | Per-fixture shadows or baked occlusion on static furniture; content for the panel |
| 02 Mess hall | 74 | Wall hot spots; floor dust colour | Spot cones near sconces; dust shader too rusty at low dust | Cone falloff per fixture type; dust response below 0.2 |
| 03 Rec kitchen | 74 | Glowing board; contact shadows | Boards and screens are flat emissive colours | Screen and board content |
| 04 Crew corridor | 77 | Floor colour | Dust redder and more contrasty than the reference | Dust colour and patch contrast |
| 05 Hangar | 67 | Ceiling too light; small shadows missing | Open metal deck above the fixtures receives the same ambient as everything else | Less ambient above the fixture plane; more shadowed fixtures |
| 06 Airlock | 68 | Floor dust pattern; door glazing | Procedural dust pattern not reproduced; flat window glass | Dust fit; reflective glazing |
| 07 Power Room | 62 | +0.30 EV; ceiling; screens | Light ducts and deck; flat screens | Ceiling occlusion; screen content; check the room's area lights |
| 08 Life Support | 71 | Ceiling slightly light | Same deck effect as the hangar | As hangar |
| 09 Command Room | 64 | Screens; floor colour | Flat blue and teal screens; rust dust on a floor that is cool grey in the reference | Screen content; per-finish dust response |
| 10 East quarters | 73 | Floor saturation; partition colour | Saturation fit; partition role colour | Check the partition material |
| 11 Greenhouse | 69 | Ceiling shadows; plant detail | Grow lights unshadowed; game-detail crops | Shadowed grow lights; crop detail in Prompts 08 and 13 |
| 12 West bunk room | 73 | Floor dust | Dust heavier and redder | Dust fit |
| 13 Exterior, airlock | 60 | Ground detail; hall glass; no haze | No gravel, tracks or micro-shadows; alpha glass instead of transmission; no atmosphere volume | Terrain shader using the three unused colour attributes; glass with reflection; haze that does not brighten the distance |
| 14 Exterior, wide | 68 | Haze; glass reflections; slightly blue | As above; outdoor white balance (blue-to-green ratio +16%) | As above |
| 15 Garden dome | 64 | Dome frame and glass; lamp bloom | Game-detail struts; clear glass; glow threshold | Dome glass tint; glow threshold |

The largest single cause across the set is materials (dust response, flat screens, glass), followed by missing bounced light on ceilings and missing small contact shadows; haze affects only the three exteriors.

## 8. Render time observed during capture

Engine-reported viewport render time while capturing each view at 1920 × 1080, MSAA 4×, static camera, one process: GPU mean 14.3 ms, maximum 28.0 ms (exterior airlock view); 5 of 15 views above 16.7 ms. CPU mean 5.3 ms, maximum 12.7 ms. Draw calls 1,175 to 11,938.

This is not a performance test: no player, no movement, no dust, no second client, and the machine is a desktop, not the target laptop. It does show that the current import does not hold 60 FPS in every static view. The main loads are the 6.95 M-triangle environment, one draw call per object, and 417 fixture lights.

## 9. What changes when the improved map arrives

1. Run `export_from_blender.ps1 -Blend <improved map>` and `build.ps1`; run `verify_import.gd`.
2. Render the Cycles reference set from that map's own scene with the compositor state recorded, including the four rooms that have no hero camera, night, unpowered, suit and rover views.
3. Run the three passes again on the new pairs, starting from this preset.
4. Decide with the owner whether materials stay palette-plus-shader or are baked, since materials are the largest remaining gap.
