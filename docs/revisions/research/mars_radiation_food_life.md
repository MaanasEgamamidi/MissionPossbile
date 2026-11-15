# Radiation, food, life support and medicine on Mars (research, 2026-11-14)

Figures marked (est.) are the researcher's arithmetic or design approximations, not sourced numbers.

## Radiation
- Curiosity RAD: **0.67 mSv/day** on the surface (≈ 245 mSv/yr, est.); cruise ≈ 1.8 mSv/day. Earth background 2–3 mSv/yr.
  Mars air ≈ 21–23 g/cm² at Gale.
- **Galactic cosmic rays**: steady, very hard to block. **Solar particle events**: rare, spiky, easy to block.
  Biggest seen by Curiosity: 20 May 2024, 8,100 µGy at once ("30 chest X-rays", not deadly). Warning: NASA wants ≥ 30
  min; some cases give ~20 min or none; a crew may shelter hours to days.
- NASA career limit **600 mSv** (≤ 3 % extra lifetime cancer risk). A full Mars mission ≈ 0.9–1 Sv, over the limit,
  which is why shielding matters. ~1,000 mSv at once → radiation sickness (est., textbook).
- Shielding:
  - Regolith 1–1.6 m keeps ≤ 100 mSv/yr (Zhang 2022). **The dose peaks ~30 cm down** (secondary neutrons): a thin
    layer can be slightly worse than none.
  - Hydrogen-rich (water, ice, polyethylene) is best; beyond ~20 g/cm² ordinary shielding barely cuts cosmic rays but
    ~20 g/cm² stops most solar-storm dose. Orion's storm shelter cut dose rate ~4× (Artemis I).
  - NASA Mars Ice Home (2016 concept): inflatable ring with a water-ice shell, ~400 days to fill.
  - Lava tubes: ~82 % lower in Earth tests; Hellas tube ≈ 0.06 vs 0.55 mSv/day outside.
  - 3D-printed regolith: NASA 3D-Printed Habitat Challenge 2019, AI SpaceFactory MARSHA (basalt fibre/biopolymer).
  - Magnetic shields, drugs: concepts only.

| Tier | Build | Cosmic dose/day (est.) | Solar-storm dose |
|---|---|---|---|
| 0 | Bare hab | ~0.67 mSv | full |
| 1 | Storm shelter (water tanks + supplies, ~20 g/cm²) | same | ÷4 inside |
| 2 | Regolith sandbags on roofs (~0.5 m) | ~0–10 % lower (the 30 cm twist) | ~90 % blocked |
| 3 | 3D-printed regolith shell (~1–1.5 m) | ~55–60 % lower | ~all blocked |
| 4 | Water/ice walls + buried 2–3 m, or a lava tube | ~80–90 % lower | ~all blocked |

## Food
- ISS Veggie ~0.17 m²; Advanced Plant Habitat ~25 % larger, ~4× the light.
- NASA Biomass Production Chamber (20 m², 1,200+ days), edible g/m²/day: potato 18.4 (90–105 d), wheat 11.3 (64–86 d),
  lettuce 7.1 (28–30 d), soybean 6.0 (90–97 d). Lifetime: 196 kg food, 540 kg O₂, 94,700 kg water.
- ~40–50 m² of crops feeds one person (35–40 m² with insects eating scraps); ~20–25 m² gives one person's O₂
  (11 m² of wheat did in a 1990s test).
- LEDs 3.4–4.1 µmol/J; lunar-greenhouse prototype 54 g lettuce/kWh (≈ 18.5 kWh/kg, est.). High-yield lighting ≈
  190 W per m² continuous (est.) → **~12–15 kW per person** for a full farm (est.) vs ~40 kW for a whole 4-crew base.
  Food is power-gated.
- Hydroponics proven; aeroponics uses less water. Mars soil perchlorate (to ~2 wt %) blocks germination; washing
  doesn't fully remove it. Dwarf crops preferred. Waste → fertiliser (ESA MELiSSA). Insects, lab meat: concepts.
- Packaged food: 5-year shelf life needed; only ~7 of 65 thermostabilised foods stay acceptable; nutrients fade in ~3 yr.

| Tier | Build | Calories (est.) | Power (est.) |
|---|---|---|---|
| 1 | Veggie pillow (~0.2 m²): salad, morale | ~0 % | ~0.1 kW |
| 2 | Salad and fruit rack (2–5 m²/person) | ~5 % | 0.5–1 kW/person |
| 3 | Staple farm (10–25 m²/person: potato, dwarf wheat, soy) | 25–50 % | 3–6 kW/person |
| 4 | Full farm (40–50 m²/person) | ~100 % | 12–15 kW/person |
| 5 | Closed loop (waste → fertiliser, insects, treated regolith beds) | ~100 % | ~12 kW/person |

## Life support
- ISS: water recovery ~98 % (93–94 % before the 2023 Brine Processor); CDRA CO₂ removal; OGA electrolysis;
  Sabatier recovers ~50 % of O₂ from CO₂ (methane vented). Next-gen target 75–90 %.
- MOXIE: 122 g total, 6 g/h normal, 12 g/h best, ~98 % pure, ~300 W. A person needs ~0.84 kg O₂/day; a 2–3 kg/h unit
  supports 6 crew.

| Tier | Build |
|---|---|
| 1 | Open loop: O₂ and water tanks, CO₂ canisters |
| 2 | ISS-style: scrubber, electrolysis, water recycling 93 % → 98 % (brine processor) |
| 3 | Sabatier: ~50 % O₂ recovered; methane → fuel tank |
| 4 | Mars resources: MOXIE-scale O₂ from air, ice mining for water |
| 5 | 75–90 % O₂ recovery + greenhouse O₂: nearly closed |

## Medicine
Earth is 3–22 min away one way, so the med bay must work alone. T1 first aid, medicines, dosimeter badges, delayed
telemedicine → T2 ultrasound with remote guidance, vitals monitors → T3 small lab (blood/urine), dental, minor
surgery, splints → T4 surgical bay, anaesthesia, imaging, long-life pharmacy, 3D-printed supplies.

## Sources
1. RAD dose (Hassler) — https://www.space.com/23875-mars-radiation-life-manned-mission.html
2. Hassler et al. 2014, Science — https://doi.org/10.1126/science.1244797
3. NASA OCHMO radiation brief (600 mSv) — https://www.nasa.gov/wp-content/uploads/2023/03/radiation-protection-technical-brief-ochmo.pdf
4. May 2024 storm — https://www.space.com/mars-aurora-radiation-solar-storm-curiosity-rover
5. Zhang et al. 2022, regolith depth — https://www.space.com/mars-radiation-protection-astronauts-underground
6. Löwe et al. 2025, storm nowcasting — https://arxiv.org/abs/2502.02469
7. Lava tubes — https://arxiv.org/pdf/2004.13156
8. Mars Ice Home — https://phys.org/news/2016-12-nasa-ice-house-mars.amp
9. 3D-Printed Habitat Challenge — https://www.space.com/nasa-3d-printed-habitat-competition-winners.html
10. Wheeler, Biomass Production Chamber — https://ntrs.nasa.gov/citations/20040089951
11. Wheeler 2017, Agriculture for Space — https://sciences.ucf.edu/class/wp-content/uploads/sites/23/2017/02/Wheeler_AgricultureForSpace_PeoplePlaces_OpenAgriculture_2017.pdf
12. Kusuma, Pattison, Bugbee 2020, LED efficacy — https://pubmed.ncbi.nlm.nih.gov/32257242/
13. ISS 98 % water recovery — https://www.space.com/astronaut-pee-iss-water-recycling-98-percent-milestone
14. ISS oxygen loop (ICES 2024) — https://ntrs.nasa.gov/api/citations/20240002161/downloads/ICES24%20Paper%20168.pdf
15. MOXIE first oxygen — https://www.jpl.nasa.gov/news/nasas-perseverance-mars-rover-extracts-first-oxygen-from-red-planet/
16. 40 kW fission surface power — https://ntrs.nasa.gov/api/citations/20220004670/downloads/40%20kW%20Deployable%20FSP%20Paper_FINAL.pdf
17. Perchlorate and plants (Oze et al. 2021) — https://mdpi.com/2571-8789/5/3/37
18. NASA food shelf life — https://ntrs.nasa.gov/api/citations/20140010665/downloads/20140010665.pdf
