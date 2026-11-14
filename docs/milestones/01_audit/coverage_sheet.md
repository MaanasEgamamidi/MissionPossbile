# Prompt 01 — Camera manifest summary and coverage sheet

Audit date: 2026-11-11. Source scene: `grand_colony\grand_colony.blend` (B1). The full machine-readable manifest is `camera_manifest.json` (184 cameras with world matrices) and `camera_manifest.csv`.

This manifest describes the **current** map. The improved map has not been supplied. Prompt 02 must regenerate the manifest from the improved map's own scene; these cameras are a starting list, not parity references.

## 1. Scene state the cameras were authored for

| Setting | Value saved in B1 |
| --- | --- |
| Resolution | 1920 × 1080 at 100%, 24 fps |
| Render engine | EEVEE in B1; Cycles in B2 and B3 (otherwise identical scenes) |
| Cycles settings stored | 128 samples, adaptive sampling 0.02, denoising on, 10 max bounces, 1 volume bounce, GPU |
| View transform, look | AgX, "AgX - Punchy" |
| Exposure, gamma | −0.45 EV, 1.0 |
| Display device | sRGB |
| Compositor | Active: glare, lens distortion, colour balance, elliptical vignette with blur |
| World | `GC_World`, procedural gradient sky, background strength 1.0 |
| Suns | `GC_MarsSun` strength 2.6, colour (1.00, 0.93, 0.84), angular size 0.0157 rad; `Sun_key` strength 0.35 |
| Units | Metric, scale 1.0 (1 unit = 1 m) |
| Cameras | All perspective, 36 mm sensor, horizontal fit, no depth of field, none animated. Clip 0.05–2000 m (168), 0.05–3000 m (15), 0.05–600 m (1). |

The compositor and the "Punchy" look change final pixels. A Cycles-to-Godot pair is only comparable if both sides treat them the same way, so each pair must record whether the compositor was on.

## 2. Camera groups

| Group | Count | Collection | Purpose | Existing render? |
| --- | ---: | --- | --- | --- |
| `Shot_01` … `Shot_15` | 15 | Beauty Shots | One hero view per major room plus three exteriors. Lenses 16–26 mm (horizontal FOV 69°–97°). | Yes: Cycles 1080p, 2026-11-08, in `grand_colony_drive\beauty_shots_cycles_1080p.zip`. *Historical.* |
| `Rv_<area>_<view>` | 163 | Review Cameras | Close-ups and walk views defined by each area module. | 161 of 163 have at least one saved PNG of the same name under `grand_colony\work\` (one Command Room and one East quarters view have none). They come from the area harness, whose defaults are 1280 × 720 and EEVEE. *Historical.* |
| `Cam_Hangar_1..4`, `Cam_Library`, `Cam_Overview` | 6 | Cameras | Legacy v1–v11 views. | Yes, in `grand_colony\renders\`. *Historical.* |

## 3. Coverage by area

"Reference" means a saved Cycles beauty shot exists. None of these is a parity reference for the improved map.

| Area | Cycles beauty shot | Review cameras | With a saved render | Gap for Prompt 02 |
| --- | --- | ---: | ---: | --- |
| Med Bay | `Shot_01_MedBay` | 12 | 12 | — |
| Mess hall | `Shot_02_MessHall` | 5 | 5 | — |
| Rec kitchen | `Shot_03_RecKitchen` | 6 | 6 | — |
| Crew corridor | `Shot_04_CrewCorridor` | 3 | 3 | — |
| Hangar bay | `Shot_05_Hangar` | 9 (+4 legacy) | 9 | — |
| Airlock | `Shot_06_Airlock` | 6 | 6 | — |
| Power Room | `Shot_07_PowerRoom` | 5 | 5 | — |
| Life Support | `Shot_08_LifeSupport` | 7 | 7 | — |
| Command Room | `Shot_09_Command` | 8 | 7 | — |
| East quarters | `Shot_10_EastQuarters` | 6 | 5 | — |
| Greenhouse | `Shot_11_Greenhouse` | 13 | 13 | — |
| West bunk room | `Shot_12_WestBunk` | 4 | 4 | — |
| Exterior (crater floor) | `Shot_13_Exterior_Airlock`, `Shot_14_Exterior_Wide` | 21 | 21 | No night view. |
| Garden dome | `Shot_15_GardenDome` | 22 | 22 | Exterior view only; no interior beauty shot. |
| Pipe gallery | **none** | 5 | 5 | Needs a reference camera. |
| Service corridor | **none** | 3 | 3 | Needs a reference camera. |
| Blast-door passage | **none** | 3 | 3 | Needs a reference camera. |
| Dome plaza (under the glass hall) | **none** | 7 | 7 | Needs a reference camera. |
| Roofs, shell (walls and doors) | none | 18 | 18 | Construction review only. |

## 4. Coverage by asset class

Views come from existing renders only; nothing was re-rendered. Contact sheet: `evidence\contact_sheets\asset_classes_existing_renders.jpg`.

| Class | Existing view | Camera | What it shows | Missing for the lighting protocol |
| --- | --- | --- | --- | --- |
| Rover (hangar) | `work\hangar\final\a05_hangar_rover.png`, `work\hangar\r3\a05_hangar_rover_rear.png` | `Rv_a05_hangar_rover`, `Rv_a05_hangar_rover_rear` | Open-frame rover with **two** seats. | Driving view, exterior view, four-seat configuration. |
| Rover (surface) | Visible small in `Shot_13_Exterior_Airlock` only | — | `sf_rover` parked outside. | No close view exists. Seat count not established. |
| Suit | `work\hangar\final\a07_airlock_suits.png`, `work\people\p3\rk_suit.png` | `Rv_a07_airlock_suits` | Three EVA suits standing on the airlock rack; chest unit close-up. | A worn suit in first and third person. |
| Character | `work\medbay\final_v12\a01_medbay_cu_survivor.png` | `Rv_a01_medbay_cu_survivor` | One figure lying in a Med Bay bed. | Any standing, walking or seated crew member. Four specialists. |
| Ship | `work\exterior\r4\a13_exterior_close_lander.png`, `…close_orbiter.png` | `Rv_a13_exterior_close_lander`, `Rv_a13_exterior_close_orbiter` | Shuttle-style stack on the landing pad. | Arrival view from the hatch or ramp. |
| Crash site | `work\exterior\r5\a13_exterior_close_crash.png`, `…eye_crash.png` | `Rv_a13_exterior_close_crash`, `Rv_a13_exterior_eye_crash` | Wrecked stage, heat shield, debris, cordon. | — |
| Solar array | `work\exterior\r4\a13_exterior_close_solar.png` | `Rv_a13_exterior_close_solar` | Tracker rows. | Dusty versus cleaned state. |
| Oxygen equipment | `work\engineering\o1\a09_lifesupport_cu_moxie.png` | `Rv_a09_lifesupport_cu_moxie` | MOXIE-style unit. | Electrolysis rack close view. |

## 5. States the engineering contract requires that no existing image covers

| Required view | Exists today? |
| --- | --- |
| Day and night for each exterior | Day only. |
| Powered and unpowered for each room | Powered only. The scene has no unpowered light state. |
| Suit view (first and third person) | No. |
| Rover view (seated, driving) | No. |
| Godot capture for any camera | No. There is no Godot world scene. |
| Matched pair (Cycles + Godot, same state) | **None.** Zero pairs exist. |
