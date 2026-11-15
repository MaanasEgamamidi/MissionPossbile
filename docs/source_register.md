# Source register (cumulative)

Started in Prompt 01 on 2026-11-11; engine measurements added in Prompt 02. This is the development register. The in-game source screen (Shift + Backspace) is built from it in Prompt 05.

## How to read it

- **Status** says how far each entry was checked:
  - **VERIFIED** — the page was fetched on the date shown and the quoted values were read from it.
  - **PARTIAL** — the page was fetched, but something needed (an identifier, a class, a value) was not on it.
  - **SEARCH-ONLY** — found through a web search; the page itself was not opened. Values are leads, not citations.
  - **FAILED** — the page could not be fetched. Nothing is asserted from it.
- **Kind** separates an actual data archive from a document that describes or links to data.
- **Evidence category** follows the contract: measured Mars data; modelled or derived; ISS or Earth analog; technology study or demonstration; fictional 2080 equipment; game tuning.
- **Pack ID** is the pack's own citation where the topic could be inferred from the pages read (1 to 12). The pack's definitions of those IDs lie after page 12 and were not read (contradiction C-14), so every mapping below is an inference to confirm.

No game balance number is sourced from any entry here. Balance values are game tuning and must be labelled as such.

## 1. Mars constants

| ID | Pack ID | Source | Kind | Status | Values read | Evidence category | Supports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S01 | N01 | NASA NSSDCA, *Mars Fact Sheet*, D. R. Williams. https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html | Document (reference table) | VERIFIED 2026-11-11. Page says "Last Updated: 19 May 2025". | Surface gravity (mean) 3.73 m/s²; surface acceleration 3.69 (equator), 3.73 (pole) m/s²; solar irradiance 586.2 W/m²; sidereal rotation period 24.6229 h; length of day 24.6597 h; surface pressure 6.36 mb at mean radius, varying from 4.0 to 8.7 mb with season; average temperature about 214 K (−59 °C); atmosphere CO2 95.1%, N2 2.59%, Ar 1.94%, O2 0.16%, CO 0.06% by volume. | Reference values compiled by NASA; global, not site-specific | TS-03 gravity. Planet facts in the source screen. Not electrical panel output and not local weather. |
| S02 | — | NASA GISS, *Mars24 Sunclock — Technical Notes on Mars Solar Time*. https://www.giss.nasa.gov/tools/mars24/help/notes.html | Document | VERIFIED 2026-11-11. "(Updated 2023-05-15)". | Mean solar day (sol): 24 h 39 min 35.244 s. Sidereal day: 24 h 37 min 22.663 s. (88,775.244 s is arithmetic from the first figure; the page gives no seconds-only value.) | Reference value | TS-01: explains that the 20-minute sol is a game-time control, not the length of a Martian day. |

## 2. Weather and environment data

| ID | Pack ID | Source | Kind | Status | What was read | Evidence category | Supports and gaps |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S03 | N02 or N03 | PDS Planetary Atmospheres Node, *Rover Environmental Monitoring Station Data* (Curiosity REMS). https://atmos.nmsu.edu/data_and_services/atmospheres_data/MARS/curiosity/rems.html | Document that links to the archive at `https://atmos.nmsu.edu/PDS/data/PDS4/msl_rems_bundle/` | PARTIAL 2026-11-11 | Quantities archived: wind speed and direction, pressure, relative humidity, air temperature, ground temperature, ultraviolet radiation. Coverage text: 7 Aug 2012 (sol 1) to 22 March 2025 (sol 4488), marked ongoing; the volume links are labelled sols 1–4843. | Measured Mars data | WX-01, WX-02. **Gaps:** data set identifiers are not printed on the page; landing site is not named on the page; the two coverage figures disagree (C-16); no product was downloaded. |
| S04 | N02 or N03 | PDS Planetary Atmospheres Node, *MEDA - Mars Environmental Dynamics Analyzer* (Perseverance). https://atmos.nmsu.edu/data_and_services/atmospheres_data/PERSEVERANCE/meda.html | Document that links to the bundle at `https://atmos.nmsu.edu/PDS/data/PDS4/Mars2020/mars2020_meda/` | PARTIAL 2026-11-11 | DOI 10.17189/1522849. Levels: raw, partially processed, calibrated, derived, SkyCam. Calibrated quantities: pressure, humidity, wind, temperatures, radiation. Coverage from 19 Feb 2021, marked ongoing. Collection sizes listed: calibrated 10 GB, derived 2.9 GB. | Measured and derived Mars data | WX-01, WX-02. **Gaps:** no `urn:nasa:pds` identifier on the page; no product downloaded; dust opacity product not identified. |
| S05 | N02 or N03 | PDS Planetary Atmospheres Node, *Insight Archive Page* (TWINS and pressure sensor). https://atmos.nmsu.edu/data_and_services/atmospheres_data/INSIGHT/insight.html | Document that links to bundles | PARTIAL 2026-11-11 | DOIs: TWINS 10.17189/1518950; pressure 10.17189/1518939. Coverage sol 1 (2018-11-30) to sol 1188 (2022-03-29). | Measured Mars data | Optional third site. **Gap:** site name not on the page. |
| S18 | — | NASA/JPL news releases on InSight power and dust (for example "NASA's InSight Waits Out Dust Storm"). https://www.jpl.nasa.gov/news/nasas-insight-waits-out-dust-storm/ | Document (press release) | SEARCH-ONLY | Leads: about 5,000 Wh per sol after landing, about 500 by spring 2022; a regional storm cut 425 to 275 Wh per sol. | Measured spacecraft telemetry reported in a release | Solar dust teaching event (Prompts 07, 09). Open the pages before citing. No dust optical depth value was found. |

Site and season matter: Gale crater (REMS), Jezero crater (MEDA) and the InSight site are real places. None is the fictional colony. Archived observations must not be called live weather or a forecast.

## 3. Life support and oxygen

| ID | Pack ID | Source | Kind | Status | What was read | Evidence category | Supports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S08 | N04 | NASA, *Environmental Control and Life Support Systems (ECLSS)*. https://www.nasa.gov/reference/environmental-control-and-life-support-systems-eclss/ | Document | VERIFIED 2026-11-11. "Page Last Updated: Apr 04, 2025". | The oxygen generation assembly electrolyzes water supplied by the Water Recovery System into oxygen and hydrogen. Carbon dioxide is removed from cabin air with molecular sieves. The page puts water recovery at about 90 percent. | ISS analog | OX-01 (electrolysis path; CO2 removal as a separate function), water recycling. ISS evidence, not Mars evidence. |
| S09 | N05 | NASA JPL, *NASA's Oxygen-Generating Experiment MOXIE Completes Mars Mission*, release 2023-127, 6 Sept 2023. https://www.jpl.nasa.gov/news/nasas-oxygen-generating-experiment-moxie-completes-mars-mission | Document (press release) | VERIFIED 2026-11-11 | Total oxygen produced: 122 g over 16 runs. Best rate: 12 g per hour. Purity: 98% or better. Feedstock: carbon dioxide from the Martian atmosphere, one oxygen atom taken from each molecule. | Technology demonstration on Mars, small scale | OX-01 (atmospheric CO2 path), OX-02 (label the fictional scale-up). |
| S10 | N05 | MOXIE results paper, *Science Advances*, DOI 10.1126/sciadv.abp8636. https://www.science.org/doi/10.1126/sciadv.abp8636 | Peer-reviewed paper | **FAILED** (HTTP 403) | Nothing. Title, authors and year are not asserted. | — | Do not cite until opened. |
| S19 | N04 | NASA NTRS 20180006142, ISS ECLSS overview. https://ntrs.nasa.gov/api/citations/20180006142/downloads/20180006142.pdf | Document | SEARCH-ONLY | Lead: CDRA is a four-bed molecular sieve; Sabatier closes the loop only partly. | ISS analog | Detail for the life-support explanations. |

## 4. Agriculture

| ID | Pack ID | Source | Kind | Status | What was read | Evidence category | Supports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S11 | N07 | NASA, *Growing Plants in Space*. https://www.nasa.gov/exploration-research-and-technology/growing-plants-in-space/ | Document | VERIFIED 2026-11-11. "Page Last Updated: Dec 08, 2023". | Crops listed as grown in Veggie: three types of lettuce, Chinese cabbage, mizuna mustard, red Russian kale, zinnia flowers. The Advanced Plant Habitat is described as a second growth chamber for plant research. Tomatoes and peppers are named as produce the Kennedy team hopes to plant in future. | ISS analog | Lettuce as a supported crop. **This page does not say tomatoes were grown in Veggie**; it lists them as a future plan. |
| S13 | N07 or N08 | NASA NTRS 20180000694, flight definition for VEG-04 and VEG-05. https://ntrs.nasa.gov/citations/20180000694 | Document | SEARCH-ONLY | Lead: VEG-05 was planned for tomato. | ISS analog (planning) | Tomato. Needs a results source, not a plan. |
| S14 | N08 | NASA NTRS 20250001897, *Space Crop Considerations for Human Exploration* (July 2024). https://ntrs.nasa.gov/api/citations/20250001897/downloads/20231215%20Space%20Crops%20HRP%20FINAL%20STRIVES%203.pdf | Document | SEARCH-ONLY | Lead: 'Red Robin' tomato tested in Veggie. | ISS analog | Tomato; nutrient and fertilizer claims (LP-06). |
| S12 | N07 | NASA, *Veggie Fact Sheet*. https://www.nasa.gov/wp-content/uploads/2019/04/veggie_fact_sheet_508.pdf | Document | SEARCH-ONLY | — | ISS analog | Veggie hardware description. |

Crops growing in an ISS chamber do not establish Mars agriculture. No source for regolith, nitrogen or fertilizer claims has been checked yet.

## 5. Sample analysis

| ID | Pack ID | Source | Kind | Status | What was read | Evidence category | Supports and gaps |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S06 | — | PDS Geosciences Node, *MSL: CheMin (Chemistry and Mineralogy)*. https://pds-geosciences.wustl.edu/missions/msl/chemin.htm | Document that links to data sets `msl-m-chemin-2-edr-v1` and `msl-m-chemin-4-rdr-v1` | PARTIAL 2026-11-11 | CheMin measures mineral abundance by X-ray diffraction of powdered rock and soil. Latest notice on the page: MSL Release 42, 3 August 2026, adding raw and derived data for sols 4710–4843. | Measured and derived Mars data (Gale crater) | Field-sample to lab-comparison activity (Prompt 08). **Gap:** no specific sample product chosen. A Gale sample is not a measurement of the fictional map. |
| S07 | — | PDS Geosciences Node, *MSL: SAM (Sample Analysis at Mars)*. https://pds-geosciences.wustl.edu/missions/msl/sam.htm | Document that links to data sets | PARTIAL 2026-11-11 | Processing levels 0, 1A, 1B and 2. The page notes that raw SAM products are stored safely but are not formally archived in PDS. | Measured and derived Mars data | Alternative sample source. |

## 6. Rover principles

| ID | Pack ID | Source | Kind | Status | Leads | Evidence category | Supports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S16 | — | NASA NSSDCA, *The Apollo Lunar Roving Vehicle*. https://nssdc.gsfc.nasa.gov/planetary/lunar/apollo_lrv.html | Document | SEARCH-ONLY | Mass 210 kg, payload 490 kg, two 36 V silver-zinc batteries of 121 Ah, crew of two. | Lunar hardware; analog only | Explaining mass, payload, battery range and traction trade-offs. A two-seat lunar vehicle, not a four-seat Mars rover. |
| S17 | — | NASA-STD-3001 technical brief on surface transport vehicles. https://www.nasa.gov/wp-content/uploads/2023/12/ochmo-tb-023-extraterrestrial-surface-transport-vehicles-rovers.pdf | Document | SEARCH-ONLY | — | Requirements and study | Seating and crew-safety context. |

No primary source for Mars rover traction, motor torque or battery behaviour has been opened. Rover stat values are game tuning.

## 7. Communications

| ID | Pack ID | Source | Kind | Status | Leads | Evidence category | Supports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S15 | N06 | NASA pages on Earth–Mars signal delay, for example https://www.nasa.gov/wp-content/uploads/2024/01/mars-communications-disruption-and-delay.pdf and https://mars.nasa.gov/mgs/faqs/faq_mplan.html | Documents | SEARCH-ONLY. One attempt to find the range on https://science.nasa.gov/mars/facts/ found only Sun–Mars light time. | Ranges differ by page: 4 to 20 minutes; 4 to 21 minutes; about 22 minutes maximum (C-18). | Reference value | CM-02: Earth–Mars light time is separate from the fictional radio delay and from network jitter. |

## 8. Engine and tooling

| ID | Pack ID | Source | Status | What was read | Used for |
| --- | --- | --- | --- | --- | --- |
| T01 | G01 | Godot Engine, *Maintenance release: Godot 4.7.2*, 18 Aug 2026. https://godotengine.org/article/maintenance-release-godot-4-7-2/ | VERIFIED 2026-11-11 | Built from commit `ed1daf0bf` (`ed1daf0bf001b61586d9930840f2f1394092c079`); 57 fixes from 39 contributors; the page reports no known incompatibilities with 4.7.1. | Version pin. Matches the local binary. |
| T02 | G02 | Godot Engine, *Download Godot 4.7.2 (stable)*. https://godotengine.org/download/archive/4.7.2-stable/ | VERIFIED 2026-11-11 | Windows editor builds and `export_templates.tpz` are offered. | Export templates (not installed locally: C-11). |
| T03 | G04–G07 | Godot 4.7 class reference, *AreaLight3D*. https://docs.godotengine.org/en/4.7/classes/class_arealight3d.html | VERIFIED 2026-11-11 | Exists; inherits Light3D; properties `area_attenuation`, `area_normalize_energy`, `area_range`, `area_size`, `area_texture`; the page says area lights cost more GPU time than omni and spot lights, and that in Compatibility they cannot cast shadows. | Rectangular fixtures, used selectively. |
| T04 | G04–G07 | Godot 4.7 docs, *Introduction to global illumination*. https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/introduction_to_global_illumination.html | VERIFIED 2026-11-11 | ReflectionProbe, LightmapGI (baked), VoxelGI, SSIL, SDFGI; the last three are not available in Mobile or Compatibility. | Dynamic GI choice for switchable lights. |
| T05 | G03 | Godot 4.7 docs, *Environment and post-processing*. https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html | VERIFIED 2026-11-11 (page was truncated in the fetch) | Tonemappers: Linear, Reinhard, Filmic, ACES, AgX. | AgX tonemapping. Enum names not read. |
| T06 | G08 | Godot 4.7 docs, *Available 3D formats*. https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html | VERIFIED 2026-11-11 | glTF 2.0 is the recommended format; direct `.blend` import calls Blender's glTF exporter and needs Blender 3.0 or later. | Asset pipeline. |
| T07 | G08 | Godot 4.7 docs, *Node type customization using name suffixes*. https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html | VERIFIED 2026-11-11 | `-col`, `-convcol`, `-colonly`, `-convcolonly`, `-noimp`, `-navmesh`, `-occ`, `-occonly`, `-rigid`, `-vehicle`, `-wheel`, `-loop`, `-alpha`, `-vcol`. | Collision authoring in a derivative. |
| T08 | G12 | Godot 4.7 docs, *High-level multiplayer*. https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html | PARTIAL 2026-11-11 | ENetMultiplayerPeer documented. MultiplayerSpawner and MultiplayerSynchronizer are not on this page; their class pages were not opened. | Networking. `MultiplayerSpawner` does run under the local 4.7.2 (LAN Walk check). |
| T09 | G13, G14 | TwoVoip, `goatchurchprime/two-voip-godot-4`. https://github.com/goatchurchprime/two-voip-godot-4 | PARTIAL 2026-11-11 | GDExtension for VoIP; MIT licence; README refers to Godot 4.6; no release tag or Windows binary list was visible in the fetched page. | Voice. Version 6.1 and 4.7.2 compatibility are unconfirmed (C-17). |
| T10 | G10, G11 | Godot 4.7 class reference, *VehicleBody3D* and *SpringArm3D*. https://docs.godotengine.org/en/4.7/classes/class_springarm3d.html | VERIFIED 2026-11-11 | Both exist. SpringArm3D is a raycast that pulls its children toward the collision point. | Camera collision. The contract asks for a RigidBody3D rover with raycast suspension, not VehicleBody3D. |
| T11 | G08 | Blender manual, *glTF 2.0* exporter. https://docs.blender.org/manual/en/4.5/addons/import_export/scene_gltf2.html | PARTIAL 2026-11-11. The `latest` URL returned 404; the 4.5 LTS page was read, and through a summary, not verbatim. | Principled BSDF base colour, metallic and roughness export; directional, point and spot lights export; cameras export; vertex colours export in selected modes; instancing through `EXT_mesh_gpu_instancing`. Area lights and procedural textures: not found on the page. | Export planning. Re-check against the Blender 5.3 manual. |

Not yet opened at all (pack topics G09 performance, G15 and D01 UI, G16 HTTPRequest): find and verify in the milestone that uses them.

### Engine behaviour measured in this project

These are local test results on this machine with Godot 4.7.2 and the current map. They are not documentation and may not hold elsewhere.

| ID | Finding | How it was measured | Evidence |
| --- | --- | --- | --- |
| M01 | AreaLight3D lights gave no contribution to SDFGI. | Raising `light_indirect_energy` from 1 to 4 on 417 area lights changed no regional luminance value in three views. | `milestones\02_import\evidence\pairs\experiments\exp1\experiment_results.json` |
| M02 | SDFGI let sky light into closed rooms of this map. | With SDFGI on, lowering the sky energy darkened indoor ceilings; SDFGI on versus off changed interiors by 0.01 to 0.10 EV. | `exp1`, `exp3` in the same folder |
| M03 | 417 AreaLight3D cost about twice the GPU time of 417 SpotLight3D. | 9 to 12 ms against 5 to 6.5 ms per view at 960 × 540 in three views. | `exp2` |
| M04 | Exact property and enum names of the classes used in Prompt 02. | Class reference generated locally with `--doctool` from the pinned 4.7.2 binary. | Not stored; regenerate with `godot --headless --doctool <dir>` |

## 9. Assets and dependencies

| ID | Asset | Licence evidence | Status |
| --- | --- | --- | --- |
| L01 | Blender Studio Human Base Meshes 1.4.1 | Two statements inside the file disagree (CC0 in README; CC BY 4.0 in a block that names "Rain Rig"). | Unresolved (C-19). |
| L02 | three.js r160, cannon-es 0.20.0 | Not checked. | Browser demo only. |
| L03 | TwoVoip | MIT, per the repository page. | Not adopted yet. |
| L04 | Godot Engine 4.7.2 | Not checked in this milestone. | Add the engine's licence notice at packaging. |

## 10. Claims with no checked source yet

| Claim area | Needed by | State |
| --- | --- | --- |
| Dust opacity and its effect on solar output | Prompts 07, 09 | No product identified. |
| A specific sample product for the lab activity | Prompt 08 | Not chosen. |
| Tomato grown on the ISS (results) | Prompt 08 | Plan-level sources only. |
| Nitrogen, fertilizer and regolith statements | Prompt 08 | Nothing checked. |
| Radiation | Not in the brief's scope; the old demo has a "solar flare" mechanic | The contract forbids treating DONKI events as a measured Mars surface dose. Nothing checked. |
| Earth–Mars light time | Prompt 11 | Range not verified on an opened page. |
| Rover engineering principles for Mars | Prompt 10 | Lunar analog leads only. |
| Old demo database text (for example "around −63 °C") | Prompt 05 | Must be re-sourced before reuse (C-15). |

## 11. Crew use, night energy and life-support power (energy and NASA worker, 2026-11-14)

Added by the energy and NASA worker of the upgrade batch. The id uses the prefix E so it does not collide with S ids
that other workers may add at the same time; it is not yet in `data/sources.json` (the in-game source screen), which
the integrator should add (or renumber it to the next free S id in both places).

| ID | Pack ID | Source | Kind | Status | Values read | Evidence category | Supports |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S20 | — | NASA, *Life Support Baseline Values and Assumptions Document*, NASA/TP-2015-218570/REV2, eds. M. K. Ewert, T. T. Chen, C. D. Powell, Johnson Space Center, February 2022. NTRS 20210024855. https://ntrs.nasa.gov/api/citations/20210024855/downloads/BVAD_2.15.22-final.pdf | Document (reference tables) | VERIFIED 2026-11-14 (PDF downloaded from NTRS and read) | Table 3-31 (82 kg reference crew member, respiratory quotient 0.86, daily exercise): oxygen consumed 0.895 kg/CM-d; carbon dioxide load 1.085 kg/CM-d; food solids 0.800 kg/CM-d; food energy 12.778 MJ/CM-d; potable water 3.217 kg/CM-d; water in food 0.760; metabolic water 0.490; respiration and perspiration water 2.946; urine water 1.420; fecal water 0.101 kg/CM-d. Notes to Table 3-31: 1.56 kg/CM-d of food eaten at 48.7 % water. Table 4-20, Early Planetary Base: drinking 2.00, food rehydration 0.50, urinal flush 0.50, personal hygiene 0.4, hand wash 1.08, total water consumption 4.48 kg/CM-d; ISS column total 3.20. Table 4-21, ISS: total wastewater 3.77 kg/CM-d. Table 3-2: ISS average ECLSS power 5.31 kW. Table 3-17: lithium-ion (liquid electrolyte) 100 to 150 Wh/kg, 1,500 cycles at 60 % depth of discharge. Table 4-91: lettuce 7.78 g O2 produced and 10.70 g CO2 taken up per m² per day. Section 4.3.3: ISS urine processor recovers about 85 % of urine water (US segment). | NASA design reference values (ISS analog and planning values; not measured on Mars) | GameBalance crew rates (oxygen, CO2, water, food energy per meal), wastewater share, battery sizing for scale, life-support power cross-check, Garden dome plant oxygen. |

### Crew use per crew member: NASA per day and the game

Time base: one game hour is one hour of colony time, so a NASA per-day value becomes a per-game-hour rate by
dividing by 24. A sol is 24.6598 game hours (S02), so one sol uses 24.6598 / 24 = 1.0275 NASA days. At the default
20-minute sol one game hour takes 48.7 real seconds; no resource rate is per real second. Suit oxygen is the same
breathing rate taken from the suit tank instead of the cabin (only crew inside breathe cabin air), and the S01 suit
exposure rule is a separate real-second rule that uses no oxygen, so nothing is counted twice.

| Quantity | NASA per day (S20) | Game per game hour | Game per sol | Was (balance) |
| --- | --- | --- | --- | --- |
| Oxygen breathed | 0.895 kg (Table 3-31) | 0.03729 kg | 0.9196 kg | 0.035 kg/h |
| CO2 breathed out | 1.085 kg (Table 3-31) | 0.04521 kg | 1.1148 kg | 0.042 kg/h |
| Water (drink, food, flush, hygiene, hand wash) | 4.48 kg = 4.48 L (Table 4-20, Early Planetary Base) | 0.18667 L | 4.603 L | 0.25 L/h |
| Share of used water returned as wastewater | 3.77 / 4.45 = 0.85 (Tables 4-20, 4-21, 3-31, ISS) | 0.85 | 0.85 | 0.85 (unlabelled) |
| Food energy | 12.778 MJ = 3,054 kcal (Table 3-31) | 0.5324 MJ | 13.13 MJ = 3 meals of 1,046 kcal | 3 meals per sol, no energy |
| Food eaten | 1.56 kg as eaten, 0.800 kg dry (Table 3-31) | 0.065 kg | 1.603 kg = 3 meals of 0.534 kg | — |

A meal stays a game unit (3 per sol); GameBalance.meal_mj(), meal_kcal() and meal_kg() say what it holds. None of
these real rates makes the game unwinnable for 4 crew (water 18.4 L per sol from 900 L with a 90 % recycler; oxygen
3.68 kg per sol against a 60 kg reserve and 4.8 kg per day of electrolysis), so no scale factor is applied.

### Night energy (balance, sized with S01, S02 and S20)

| Number | Value | Evidence |
| --- | --- | --- |
| Night length | 12.33 game hours (sunset phase 0.75 to sunrise phase 0.25), 10 real minutes at the default sol | S02 sol length / 2 (equator at equinox) |
| Solar at night | exactly 0 kW, at every tracker, upgrade and area level | model rule (PowerModel.sun_term) |
| Night load at arrival (every room on) | 23.1 kW = 285 kWh per night, 41 % of the battery | balance loads |
| Careful night load (critical lights only, greenhouse lights off) | 8.9 kW = 110 kWh per night, 16 % | balance loads |
| Wasteful night load (every room, both oxygen machines) | 27.3 kW = 337 kWh per night: from a 40 % battery it runs flat about 2 h before sunrise | balance loads |
| Battery | 700 kWh usable at V1 (875, 1,050, 1,400 at V2 to V4); 630 kWh at arrival | balance; for scale 1,167 kWh of Li-ion at 60 % depth of discharge, S20 Table 3-17 |
| Life-support power cross-check | 4.3 kW for 4 crew in the game; ISS ECLSS 5.31 kW average | S20 Table 3-2 |
| Garden dome plant oxygen | 0.010, 0.020, 0.035 kg/h at V2 to V4 (31, 62, 108 m² of leafy plants) | S20 Table 4-91 lettuce 7.78 g O2/m²/d; areas are balance |
