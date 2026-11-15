# Mars weather and natural events (research, 2026-11-15)

Items marked [UNVERIFIED] were not confirmed against a fetched source. The game already plays real dust-storm
episodes from Perseverance's MEDA weather station and NASA dust optical-depth maps (sources W01–W12,
`scripts/sim/weather_system.gd`); this note checks and extends that.

## Dust storms
- **Local**: < ~2,000 km, a few days, very common. **Regional**: up to ~1/3 of the planet, up to ~3 weeks; three
  regional storms (A, B, C) recur at about the same season every Mars year; dust can warm the air up to 35 °C (JPL).
  **Global**: about once every 3 Mars years on average (irregular; another NASA page says every 6–8 Earth years); all
  known ones began between Ls 180° and 310°.
- Growth: 2001 storm went from Hellas to half the planet in ~3 weeks; 2018 went local → global in ~2–4 weeks.
- Darkness (tau): clear 0–1 (~1 normal in the dusty season); 2007 ~5.5 at Opportunity; **2018: 10.8 at Opportunity**
  (record), ~8.5 at Gale. Opportunity's power: ~700 → 123 → 22 Wh/sol, then it never woke.
- Warning: MRO's MARCI camera makes a daily global weather map (a 2008 warning saved Spirit's energy). At Gale in 2018
  the daily pressure wave changed before the sky darkened (a real "barometer" warning).
- Temperature: dust shrinks the day–night swing (2018 at Curiosity: ground swing −35 K; daily mean only −2 to −4 K).

## Dust devils
~30 m wide and 800 m tall (HiRISE example). Perseverance: ≥ 4 per sol, > 1 per hour after noon, ~1/4 carry dust.
InSight: ~6,000 vortices in 400 sols (~13,000 total), one ~101 km/h, but only +0.7 % and +2.7 % panel boosts and no
real cleaning; it ran out of power in Dec 2022. Spirit, March 2005: a cleaning event roughly doubled its power.

## Wind
InSight: gusts ~17 m/s common, strongest ~31 m/s in a dust storm (secondary source); average ~4–6 m/s. Air ~0.020
kg/m³ at ~6.4 mbar, ~1 % of Earth's. **A 30 m/s Mars wind pushes like a 4 m/s Earth breeze** ("The Martian" storm
can't tip a rocket); the real danger is dust blocking sunlight. Sand moves: Nili Patera ripples up to 4.5 m in 105 days.
Viking, Curiosity REMS and Perseverance MEDA m/s values: [UNVERIFIED] here.

## Temperature, pressure, frost, clouds
Curiosity: air swing > 55 °C a day; Gale ground highs −23 to +17 °C, lows −103 to −63 °C. Pressure ~25 % yearly
change (CO₂ freezing on the winter pole) and ~10 % daily. Humidity > 60 % on winter nights at Gale. Viking 2 saw
thin frost ~100 days each winter. Clouds: north polar hood; equatorial water-ice cloud belt in northern spring/summer.

## Seasons
Sol 24 h 39 m 35 s; year 668 sols (687 Earth days). Northern seasons ~194 / 178 / 143 / 154 sols. Perihelion at
Ls 250° (southern summer) = the dusty season (storms from ~Ls 180°).

## Space weather and quakes
20 May 2024: the biggest solar particle event recorded at Mars (~8,100 µGy at Curiosity, ~30 chest X-rays, not
deadly); MAVEN saw planet-wide aurora. No global magnetic field [UNVERIFIED here, standard fact]. Warning timing from
physics [UNVERIFIED]: flare light ~13 min, fast particles minutes to hours later, a CME 1–3+ days.
Marsquakes: InSight heard 1,319; the biggest M4.7 (4 May 2022). Harmless: science data, not a hazard.

## Suggested game rules
- Normal sky tau 0.3–0.6 (clear season), 0.8–1.0 (dusty season). Solar = clear × e^(−0.3·tau) (fit to Opportunity:
  tau 10.8 → ~4 %).
- Local storm: 10–20 per Mars year, 1–3 sols, tau 1–2. Regional: 3 per year (A, B, C), Ls 200–330, 5–20 sols, tau 2–5,
  3–7 sols' warning from the orbiter map. Global: ~1 in 3 Mars years, Ls 180–310, grows over 15–30 sols, lasts
  60–100+ sols [estimate], tau 8–11, pressure-wave warning first.
- Dust devils: 4–15 per sol near noon; ~1 % chance per sol of a panel cleaning (+20–100 % of lost power); none in a
  global storm.
- Wind 2–7 m/s, gusts 15–30 m/s: no knockdowns; lower visibility; rovers drive slower in blowing dust.
- Temperature ground −90 to +15 °C; in a storm −60 to −10 °C. Pressure yearly ±12 %, daily ±5 %.
- Solar particle event: 1–3 big ones per Mars year near solar maximum, 15–60 min warning, 1–3 sols: get to shelter.
- Marsquakes: M2–3 every 1–2 sols, seismometer only.

## Sources
1. NASA, fact and fiction of Martian dust storms — https://www.nasa.gov/content/the-fact-and-fiction-of-martian-dust-storms
2. JPL, seasonal dust-storm pattern — https://www.jpl.nasa.gov/news/nasa-mars-orbiters-reveal-seasonal-dust-storm-pattern/
3. Planetary Society, Opportunity sleeps (tau 10.8) — https://www.planetary.org/articles/08-mer-update-opportunity-sleeps
4. JPL, Opportunity hunkers down — https://www.jpl.nasa.gov/news/opportunity-hunkers-down-during-dust-storm/
5. JPL, 2001 storm swallows half of Mars — https://www.jpl.nasa.gov/news/dust-storm-swallows-half-of-mars/
6. Guzewich et al. 2019, GRL — https://ui.adsabs.harvard.edu/abs/2019GeoRL..46...71G
7. Viúdez-Moreiras, 2018 storm at Gale — https://www.inta.es/export/sites/default/.galleries/cpess6-Descarga/Viudez-Moreiras-D_The-Impact-of-the-MY34-2018-Global-Dust-Storm-on-the-near-surface-atmosphere-in-Gale-Crater-Mars.pdf
8. MRO MARCI weather report — https://www.jpl.nasa.gov/images/pia11418-mro-marci-weather-report-for-the-week-of-3-november-2008-9-november-2008/
9. NASA, Jezero winds (Perseverance) — https://www.nasa.gov/missions/mars-2020-perseverance/perseverance-rover/nasas-perseverance-studies-the-wild-winds-of-jezero-crater/
10. Spiga et al. 2020, InSight vortices — https://arxiv.org/pdf/2005.01134
11. Spirit 2005 cleaning event — https://spaceflightnow.com/mars/mera/050314dustdevil.html
12. JPL, Curiosity's seasonal cycles — https://www.jpl.nasa.gov/images/pia20600-seasonal-cycles-in-curiositys-first-two-martian-years/
13. NASA Mars fact sheet — https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html
14. Planetary Society, Mars calendar — https://www.planetary.org/articles/mars-calendar
15. NASA, Mars during the May 2024 solar storm — https://www.nasa.gov/solar-system/planets/mars/nasa-watches-mars-light-up-during-epic-solar-storm/
16. InSight's biggest marsquake — https://www.space.com/mars-insight-most-powerful-marsquake
17. HiRISE, Nili Patera dunes — https://hirise.lpl.arizona.edu/ESP_028575_1890
