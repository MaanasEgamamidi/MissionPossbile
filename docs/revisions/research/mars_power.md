# Power on Mars (research, 2026-11-14)

For the energy upgrade paths (day power, night power, storm/wind, use less). Numbers marked (est.) are the researcher's
own estimates, not sourced figures.

## Crew power needs
- Habitat alone ~12.1 kW for 4 crew; ~17.3 kW for 6 crew long stay (NASA habitat sizing; quoted, not opened).
- Hartwick et al. use 24 kW minimum for 6 crew ≈ 590 kWh per sol (est.).
- Whole surface base incl. propellant oxygen plant ~33.6 kWe (Rucker 2015); older DRA plans: two 40 kWe reactors.

## Options

| Option | Kid line | Real numbers | Maturity | Game verdict |
|---|---|---|---|---|
| Solar PV | Panels turn sunlight into electricity; Mars gets < half of Earth's | 586 W/m² top of atmosphere (Earth 1,361). Opportunity ~0.7 kWh/m²/sol at start. Night = 0. Dust factor down to 0.64; cleaning events +40 %. InSight 5,000 → <700 Wh/sol, then 425 → 275 in a 2022 storm (mission ended). 2018 storm: tau 10.8, Opportunity 645 → 22 Wh/sol, never woke | Flown | Base tier |
| Dust shield (electrodynamic) | Electric fields push dust off | Near-new output in lab at Mars pressure; worked on the Moon (Blue Ghost, Mar 2025); never flown to Mars | Tested on the Moon | Mid tier |
| Sun trackers | Panels turn to follow the Sun | Clearly better in clear skies, small gain in dust; ~+25 % clear sols near the equator (est.) | Flown on Earth | Mid tier |
| Multi-junction cells | Better cells | ~28–30 % vs ~20 % (est.) | Flown (spacecraft) | Late tier |
| Li-ion batteries | Store power for night | 150–200 Wh/kg packaged | Flown | Tier 1 night |
| Regenerative fuel cell (H₂/O₂) | Split water by day, recombine at night | 2–4× battery Wh/kg (456–830 Wh/kg lunar studies); ~50 % round trip (est.). Solar + H₂ 8.3 t vs reactor 9.5 t near equator (Abel 2022) | Earth breadboards | Tier 3 night |
| Wind | Thin air pushes ~100× weaker | 33 m turbine (330 kW on Earth) averages ~10 kW on Mars; strongest at night, in storms and winter; adding wind raised time above 24 kW from 40 % to 60–90 % | Model + wind tunnel | Storm/night side branch, windy sites only |
| Geothermal | Mars leaks a tiny trickle of heat | ~20–30 mW/m² estimated (never measured: InSight HP3 failed); ~7,000 m² leaks ~150–200 W (est.). No confirmed hot spot (Cerberus Fossae is the best guess) | — | **Not a power source.** Science quest only; any "hot spot" event must be labelled fiction |
| Fission (Kilopower / FSP) | Splitting uranium makes heat day and night | KRUSTY 2018: 28 h test; designs 1–10 kWe. 4 × 10 kW ≈ 7,000 kg vs ~9,800 kg solar + batteries for storm survival at Jezero (Rucker 2016). FSP 40 kWe contracts 2022; 100 kWe lunar goal ~2030 | Ground-tested | Night capstone; **not renewable** badge; parked far away / buried |
| MMRTG | Nuclear battery | 110 W (≈ 2.7 kWh/sol, est.) from 4.8 kg PuO₂ | Flown (Curiosity, Perseverance) | Rover / beacon item, not base power |
| Solar thermal, orbit beaming | Mirrors / beams from space | Mirrors fail in diffuse dusty light; beaming is concept only | Concept | Skip, or "future dream" label |
| Use less | LEDs, insulation, heat recovery, run the oxygen plant by day | −10 %, −10 %, −15 % stacking (est.) | Earth tech | Cheap, kid-friendly branch |

Storm rule for the game: solar = clear × e^(−0.4·tau) (est. fit; tau 5 → 14 %, tau 10 → 2 %, matches Opportunity's 645 → 22 Wh).

## Sources
1. NASA Mars fact sheet — https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html
2. JPL, InSight waits out dust storm (2022) — https://www.jpl.nasa.gov/news/nasas-insight-waits-out-dust-storm/
3. Planetary Society, Opportunity dust storm — https://www.planetary.org/articles/06-mer-update-opportunity-dust-storm-sleep
4. NASA dust shield on the Moon (2025) — https://www.nasa.gov/image-article/nasas-dust-shield-successfully-repels-lunar-regolith-on-moon/
5. Hartwick et al. 2023, Nature Astronomy 7 (online Dec 2022), wind on Mars — https://www.nature.com/articles/s41550-022-01851-4
6. KRUSTY results (NTRS) — https://ntrs.nasa.gov/citations/20180005435
7. Rucker 2016, Solar vs fission surface power for Mars — https://ntrs.nasa.gov/citations/20160002628
8. Rucker 2015, Integrated surface power strategy for Mars — https://ntrs.nasa.gov/citations/20150000526
9. NASA MMRTG fact sheet — https://science.nasa.gov/wp-content/uploads/2024/02/mmrtg-factsheet-updated-5-18-20-1.pdf
10. Spohn et al. 2018, HP3 heat probe — https://link.springer.com/article/10.1007/s11214-018-0531-4
11. NASA TM-20210024659, fuel cells vs Li-ion — https://ntrs.nasa.gov/api/citations/20210024659/downloads/TM-20210024659.pdf
12. Abel et al. 2022 (UC Berkeley), solar vs nuclear by site — https://news.berkeley.edu/2022/04/27/solar-beats-nuclear-at-many-potential-settlement-sites-on-mars/
