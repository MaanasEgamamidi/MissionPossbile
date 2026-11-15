# Rover and scout drone on Mars (research, 2026-11-14)

The upgrade curves and level names are game choices; the numbers they lean on are cited below.

## Crewed rover: gas vs electric

**Verdict: electric.** Mars air has almost no oxygen, so an engine must carry its oxidizer too. Zubrin's Mars Direct
(1993) did propose a methane/O₂ rover (12 t propellant ≈ 24,000 km total, up to 500 km from base), but NASA's later
studies chose batteries, H₂/O₂ fuel cells and nuclear power. Feeding H₂/O₂ straight to a fuel cell beats turning it
into methane and burning it.

| Source | Numbers |
|---|---|
| NASA Space Exploration Vehicle | 2 crew (4 emergency), ~10 km/h, ~3,000 kg, carries ~1,000 kg, battery powered, suitports, doubles as a 72 h radiation storm shelter. Apollo crews had to stay within ~6 miles walking distance; two SEVs that can rescue each other give > 125 miles (~200 km) |
| NASA TM-2022-0006678 (Mars pressurized rover power) | ~6,000 kg rover, 2 crew, 21-day trips, 2 km/day; 10 kWe driving, 1.8 kWe living, 250 W science. RPS + 52.7 kWh Li-ion: 970 kg. Rechargeable fuel cell (6-day trips): 1,868 kg. Self-contained fuel cell (21 days): 2,692 kg. Solar + battery rejected (needs a 73 m² array) |
| Apollo Lunar Roving Vehicle | 210 kg, carried 490 kg; two 36 V silver-zinc batteries (~8.7 kWh, not rechargeable); ~13 km/h; Apollo 17: 35.9 km total, longest drive 20.1 km, max 7.6 km from the lander |

**Suit oxygen limit (why the rover matters):** shuttle/ISS EMU ~8 h + 30 min reserve; Apollo backpack 7 h + 30 min;
NASA xEMU target 6 ± 2 h. On foot: a few hours of air, a few km walk-back, no storm shelter. A pressurized rover
removes all three.

**Suggested rover path:** bigger battery → pressurized cabin with suitport and storm shelter → H₂/O₂ fuel-cell range
extender fed by the colony's oxygen plant → nuclear (RPS) power cart for long trips. Solar skin only trickle-charges.

## Scout drone

**Ingenuity (NASA/JPL):** 1.8 kg; two 1.2 m rotors at ~2,400 rpm; six Li-ion cells (~35–40 Wh, secondary source);
~350 W in flight; small solar panel ≈ one 90 s flight per sol. Design: 300 m, 5 m up. Records: 704 m in 161 s at
5.5 m/s (flight 25), 10 m/s top, 24 m altitude, ~169 s longest. 72 flights, ~17 km, 128.8 min total; ended 18 Jan
2024 when navigation lost track over smooth sand. Motors heating (~+1 °C per second) often limited flights more than
the battery. Flew waypoint lists by itself (downward camera visual odometry, IMU, laser altimeter); no joystick from
Earth because of the 4–24 min light delay (a pilot on Mars can fly it live).

**Mars Science Helicopter concept (NASA Ames TM-2020-220485):** 31 kg hexacopter, 5 kg science payload, ~10 min hover
or ~5 km range (JPL later: up to 13.3 km). **Dragonfly (Titan):** charges its battery from an MMRTG between flights
and picks its own landing spots.

**Suggested curve** (turn-back radius ≈ 40 % of full range so it always gets home):

| Level | Flight | Range | Speed | Uses per sol | Sensor | Control |
|---|---|---|---|---|---|---|
| V1 | 90 s | 300 m | 3–5 m/s | 1 | Colour + navigation camera | Manual only |
| V2 | ~3 min | ~1 km | 5.5 m/s | 2 | Multispectral camera (mini CRISM): clays, sulfates, iron oxides | Semi-autonomous; pre-scouts and reports minerals; revisits explored areas |
| V3 | ~6 min | ~3 km | 7 m/s | 3 | Neutron/gamma spectrometer (Odyssey-style): hydrogen = water ice | Flies to KNOWN spots of a requested ore |
| V4 | ~10 min | 5 km | 10 m/s | 4 | Ground-penetrating radar (RIMFAX-style, 10–35 m deep) | Scans ANYWHERE for the requested ore |

More than one flight per sol is a game liberty (charged from the base, not its own panel). LIBS (ChemCam/SuperCam)
suits the rover better than the drone.

**Diminishing returns:** first Li-ion cells (1991) ~70–120 Wh/kg → ~250–300 Wh/kg today: 2–3× in 30 years with
shrinking yearly gains. NASA: Ingenuity → Mars Science Helicopter gave up to 11.1× range but only 1.3× hover time.

**MOXIE reality check:** 122 g O₂ total, 12 g/h peak; a crew needs ~2–3 kg/h.

## Sources
1. NASA SEV fact sheet — https://www.nasa.gov/wp-content/uploads/2015/08/464826main_sev_factsheet_508.pdf
2. NASA TM-2022-0006678, Mars pressurized rover power — https://ntrs.nasa.gov/citations/20220006678
3. Apollo LRV (NSSDC) — https://nssdc.gsfc.nasa.gov/planetary/lunar/apollo_lrv.html
4. Zubrin & Baker 1993 — https://marspapers.org/paper/Zubrin_1993_2.pdf
5. EMU (secondary) — https://en.wikipedia.org/wiki/Extravehicular_Mobility_Unit
6. xEMU EVA testing — https://ntrs.nasa.gov/api/citations/20210000827/downloads/Exporation%20EVA%20Testing%20and%20Analogs%2020210000827.pdf
7. Ingenuity fact sheet — https://mars.nasa.gov/files/mars2020/MarsHelicopterIngenuity_FactSheet.pdf
8. Ingenuity mission page — https://science.nasa.gov/mission/mars-2020-perseverance/ingenuity-mars-helicopter/
9. Flight 25 record — https://www.space.com/mars-helicopter-ingenuity-record-breaking-25th-flight
10. Mars Science Helicopter — https://ntrs.nasa.gov/citations/20200002139
11. Dragonfly — https://science.nasa.gov/mission/dragonfly/
12. Odyssey water ice — https://www.jpl.nasa.gov/news/odyssey-finds-water-ice-in-abundance-under-mars-surface/
13. First Sony Li-ion cells — https://www.osti.gov/biblio/7047720
14. MOXIE results (news) — https://www.freethink.com/space/oxygen-on-mars-isru
