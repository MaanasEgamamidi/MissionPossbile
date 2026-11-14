# Crew looks verdict, round 1 (Fable) — NOT SHIP

Scores: unsuited front 7, unsuited back 5, suited back at gameplay distance 4, suited front 4, hair 6, gender read 4, accent colours 3, name tags 5, faces/visor 5.

Defects: ponytail hidden from the front, cap reads as a beanie; beard reads as a chin strap with white slivers at the ears, buzz colour close to skin; all four look bald inside the helmet; chin draws over the orange neck ring (clipping or visor sorting); Medical's face nearly black in the visor, eyes/brows vanish; heavy straight brows look stern; rust b96045 vanishes on orange, gold c0a34c and green 788e65 both read olive (and identical for deuteranopes); unsuited accent only on one shoulder, nothing from behind; heights 0.95-1.03 imperceptible; name tags ~9 px at gameplay distance, pale tinted text on busy orange.

## Accent set (crew_looks.gd)
| Crew | Colour | Hex | Symbol | Band pattern |
|---|---|---|---|---|
| 0 Electrical | Yellow | ffc400 | Triangle | one thick solid band |
| 1 Medical | Blue | 2a7bff | Plus | two thin bands |
| 2 Biology | Green | 1e9e48 | Circle | row of three dots/blocks |
| 3 Geology | Magenta | d2379b | Diamond | chevron (V) |

## BLENDER fixes (astronaut.glb)
1. Symbol meshes Ident_Symbol_Triangle, Ident_Symbol_Plus, Ident_Symbol_Circle, Ident_Symbol_Diamond (toggled per crew like Hair_*): backpack centre top ~0.14 m across, extruded 0.012 m; copy on helmet back ~0.08 m; chest left of the screen ~0.06 m. Mat_Ident on a 0.012 m Mat_SuitDark backing plate (so yellow reads on white).
2. Band pattern variants for helmet band and backpack band: Ident_Band_Solid, Ident_Band_Double, Ident_Band_Dots, Ident_Band_Chevron. Helmet band ~0.05 m tall (~1.6x), wrapping fully round the front above the visor.
3. Forearm rings ~0.06 m wide, thigh stripes ~0.05 m wide hip to knee, plus an upper-arm band on both arms.
4. Flight suit: patch on both shoulders ~0.10 x 0.08 m with a 0.008 m Mat_SuitWhite border; 0.04 m accent yoke stripe across the upper back; accent collar ring.
5. Feminine shape key incl. head: jaw ~10% narrower, smaller softer chin, reduced brow ridge; eyes ~15% taller, brows thinner and arched, one small lash triangle at each outer eye corner (Mat_Eye); shoulders ~8% narrower, slight waist taper, slightly slimmer neck. No bust or hip exaggeration.
6. Friendlier faces for all: raise brows 0.004-0.006 m, inner ends tilted up; small eye-white quad behind each pupil.
7. Hair_Ponytail: front hairline with a parting and two short temple strands; tail ~30% longer, ~20% thicker, tied high enough to show past the head outline from the front; soften the hard dark rim.
8. Hair_Beard: fuller (cheeks + moustache block, +0.01 m at the chin), merged into sideburns joining Hair_Buzz; close gaps/flipped faces at the ears.
9. Hair_Curly: spike amplitude -30%, hairline a little lower at the temples.
10. Under-helmet hair: HairIn_Ponytail, HairIn_Curly, HairIn_Bob, HairIn_Buzz fitting inside the helmet (hairline, fringe, sideburns only). Hair_Beard stays visible when suited.
11. Visor/collar: lower the visor bottom edge or raise the neck ring ~0.02 m so the chin clears; widen the clear visor area so cheeks and hairline show.

## GAME fixes
1. crew_looks.gd: the accents above; keys "symbol", "band", "hair_suited" per crew; Geology hair_color 6b4a2b; Medical skin_color 6e452e; heights 0.93 / 1.05 / 0.90 / 1.00 if door and interaction reach allow.
2. Mat_Ident: emission = accent at ~0.35-0.5 energy, roughness 1. Keep IDENT_DARK_AMOUNT 0.35 for trim.
3. Visor: check Mat_Visor transparency sorting / render priority vs the head; faint neutral interior helmet light or small face emission so faces aren't lost in dim scenes.
4. Name tags: near-white text f4f1ea with dark outline, crew symbol in the accent colour before the word; ~20-24 px tall at 1080p from 4 m to 25 m (fixed_size or clamped scaling); fade beyond ~30 m and closer than ~2 m; +0.15 m higher over a suited helmet.
5. HUD and portraits: same symbol and colour in the crew badge.
