# Weather data bundle (Prompt 09, Part D)

The game ships a small, verified subset of archived Mars weather observations in `data/weather/bundle/`. Everything
in it comes from one place, **Jezero crater** (the Perseverance landing area), and from **2019 to 2022**. It is not
the fictional colony's weather, not live weather and not a forecast. The game plays the observations faster and
scales them; those changes are game transformation (see "Limitations").

- Bundle: `jezero-meda-lmd-my36-v1`, version `1`, built `2026-11-14T03:13:15Z` (the time of the newest raw download,
  so a rebuild from the same raw files is byte-identical; checked).
- 10 products, 9 dust episodes, a seasonal background sky. Fixture for tests: `tests/fixtures/weather_bundle_min/`
  (2 products, 2 episodes, **synthetic numbers**, labelled as such in every file).
- Build: `py -I tools/weather/build_bundle.py` (offline, from `data/weather/raw/`); fixture: `--fixture`.
- Check: `py -I tools/weather/validate_bundle.py` (shipped bundle and fixture; prints a report; exit code 0 = valid).
- Godot check: `tests/test_weather_data.gd`.
- Register entries: `data/sources_weather.json` (W01-W12, all VERIFIED, opened 2026-11-14 UTC). Claims for the
  weather screens: `data/claims_weather.json`.

## What was chosen and why

| Need | Choice | Why |
| --- | --- | --- |
| Pressure | MEDA **derived** PS (`DER_PS`) | The MEDA readme: "the recommended dataset ... is the derived level when available"; derived pressure is the combined sensor quantity (based on barocap 3). |
| Wind speed | MEDA **derived** WS (`DER_WS`) | Derived wind is a single speed and direction chosen from the most appropriate boom, spurious data filtered (release notes, release 3). |
| Air temperature | MEDA **calibrated** ATS (`CAL_ATS`) | The readme lists derived products only for PS, humidity, certain TIRS channels and wind: there is no derived ATS, so the calibrated level is used. |
| Dust optical depth | LMD Mars dust climatology, **kriged daily maps v2.5**, Mars years 35 and 36 (`dustscenario_MY35_v2-5.nc`, `dustscenario_MY36_v2-5.nc`) | The MEDA bundle has no derived dust-opacity product (RDS is only at calibrated radiance level and needs models to give opacity). No NASA/PDS daily column-dust map record covering Jezero was identified in this work, so a reputable research archive is used, as SPEC_P09 allows: the Montabone et al. climatology (MRO Mars Climate Sounder retrievals, gridded and kriged at LMD; the climatology used by the Mars Climate Database). |

Sols. MEDA products cover four mission sols: **289** (quiet sky, Ls 140.6, 12 Dec 2021), **313** (the day a regional
dust storm arrived, Ls 153.1, 5-6 Jan 2022), **317** (storm peak at Jezero, Ls 155.2, 9-10 Jan 2022) and **579**
(the largest dust event of the record, Ls 316.5, 6 Oct 2022). 289, 313 and 317 are odd sols, so they cover the same
local hours (the readme: odd hours on odd sols). Raw MEDA files are about 2-5 MB per sensor per sol, so the set was
kept to these sols to stay near the 30 MB limit.

Wind is in the archive only for **sols 36 to 315**. The MEDA release notes (section B.4): "wind data beyond sol 315 is
not provided due to certain damage to some components of the wind sensor, as a result of harsh weather conditions".
So only the quiet sol (289) and the storm's first sol (313) have wind; later episodes have none.

## Identifiers and coverage

MEDA bundle `urn:nasa:pds:mars2020_meda` version 6.0 (bundle.xml), DOI 10.17189/1522849; derived and calibrated
collections version 16.0; release 16 (2026-08-11, sols 1740-1859). Every MEDA CSV matched the `file_size` and
`md5_checksum` in its PDS4 label.

| Product | Register | PDS LID::version | Observation | Columns | Raw file |
| --- | --- | --- | --- | --- | --- |
| meda_ps_sol0289 | W01 | urn:nasa:pds:mars2020_meda:data_derived_env:we__0289___________der_ps__________________p::1.0 | sol 289, 2021-12-12T03:05:08Z to 2021-12-13T03:44:36Z, Ls 140.620-141.130 | sol 1, pressure Pa, samples 1 | 2,711,613 B, md5 67f7782be54e3eb792499deb40c54710 |
| meda_ws_sol0289 | W02 | ...:we__0289___________der_ws__________________p::2.0 | sol 289, 2021-12-12T03:05:32Z to 2021-12-13T03:44:36Z, Ls 140.620-141.130 | sol 1, wind_speed m/s, wind_speed_max m/s, wind_dir deg, samples 1 | 3,081,774 B, md5 458382440a640bdd7bb51dde3673e439 |
| meda_ats_sol0289 | W03 | urn:nasa:pds:mars2020_meda:data_calibrated_env:we__0289___________cal_ats_________________p::1.0 | sol 289, 2021-12-12T03:05:05Z to 2021-12-13T03:44:36Z, Ls 140.620-141.130 | sol 1, air_temperature K, samples 1 | 3,999,471 B, md5 fab114dcb8c08df02bec2bd105d201e3 |
| meda_ps_sol0313 | W04 | ...:we__0313___________der_ps__________________p::3.0 | sol 313, 2022-01-05T18:55:08Z to 2022-01-06T19:34:42Z, Ls 153.115-153.647 | sol 1, pressure Pa, samples 1 | 4,111,401 B, md5 a4da65191c0ce9fcfc286013153024cd |
| meda_ws_sol0313 | W05 | ...:we__0313___________der_ws__________________p::2.0 | sol 313, 2022-01-05T18:55:08Z to 2022-01-06T19:24:38Z, Ls 153.115-153.643 | sol 1, wind_speed m/s, wind_speed_max m/s, wind_dir deg, samples 1 | 1,995,142 B, md5 2aee0520b6c267f9cf62c719e50649ca |
| meda_ps_sol0317 | W06 | ...:we__0317___________der_ps__________________p::1.0 | sol 317, 2022-01-09T21:33:35Z to 2022-01-10T22:09:43Z, Ls 155.248-155.782 | sol 1, pressure Pa, samples 1 | 3,283,203 B, md5 c0640b13afb5a236ae33540f9bb4a222 |
| meda_ats_sol0317 | W07 | ...calibrated_env:we__0317___________cal_ats_________________p::1.0 | sol 317, 2022-01-09T21:33:32Z to 2022-01-10T22:10:07Z, Ls 155.248-155.782 | sol 1, air_temperature K, samples 1 | 4,825,100 B, md5 171cddb686a40b2a9eb8665f6950fa1f |
| meda_ps_sol0579 | W08 | ...:we__0579___________der_ps__________________p::1.0 | sol 579, 2022-10-06T02:25:29Z to 2022-10-07T02:18:55Z, Ls 316.468-317.038 | sol 1, pressure Pa, samples 1 | 1,976,241 B, md5 da39cd835391ccd1c2fe436afbf66af4 |
| lmd_cdod_my35 | W09 | not PDS: `dustscenario_MY35_v2-5.nc`, version 2.5, created 25-November-2021, ETag "3727280-5eedf887564c0" | Mars year 35, maps 1-669; observations used 2019-03-19 to 2021-02-10; Ls 359.93 (first map, as in the file) to 359.62 | sol 1, ls deg, cdod610 1, cdodtot 1, tau_vis 1, reliability 1 | 57,832,064 B file; byte ranges only |
| lmd_cdod_my36 | W10 | not PDS: `dustscenario_MY36_v2-5.nc`, version 2.5, created 08-February-2023, ETag "3727288-5f463e9065800" | Mars year 36, maps 1-669; observations used 2021-02-03 to 2022-12-29; Ls 0.133-359.826 | same | 57,832,072 B file; byte ranges only |

URLs: MEDA files are under `https://atmos.nmsu.edu/PDS/data/PDS4/Mars2020/mars2020_meda/data_{derived,calibrated}_env/sol_XXXX_YYYY/sol_NNNN/`;
LMD files under `https://www-mars.lmd.jussieu.fr/mars/dust_climatology/dataset_v2/`. Every URL, size, sha256, ETag,
Last-Modified and retrieval time is in `data/weather/raw/downloads.json` and in each manifest product.

Licences. MEDA: PDS archive data (public). The PDS Atmospheres MEDA page asks for the citation "J.A. Rodriguez-Manfredi
et al. (2021), The Mars Environmental Dynamics Analyzer, MEDA, NASA Planetary Data System, DOI 10.17189/1522849"; no
other licence text was found on the pages read. LMD: Creative Commons Attribution-ShareAlike 3.0 Unported (stated in
each file's `copyright` attribute and on the LMD page); credit Montabone et al.; changes are listed in `transform`.

Site. All products are Jezero crater. `lat 18.44, lon 77.45` are the approximate landing-site coordinates from
SPEC_P09; they were not read from a downloaded file (the rover's exact position per sol is in the MEDA
`DER_ANCILLARY` files, 6-8 MB per sol, not downloaded). No other landing site is used.

## Raw files (`data/weather/raw/`, about 29.0 MB, ignored by Godot through `.gdignore`)

- `meda/`: the 8 CSV tables and their 8 PDS4 labels, as downloaded (25.98 MB of CSV).
- `lmd/`: for each Mars year, `*.head.bin` (bytes 0..30463 or 0..30471 of the NetCDF file: the header and every 1-D
  variable), `*.jezero.bin` (2007 byte ranges of 488 bytes, concatenated: for each of the 669 maps and for `cdodrel`,
  `cdod610` and `cdodtot`, grid cell (19.5 N, 75 E) through (16.5 N, 78 E)) and `*.jezero.json` (the list of ranges
  and the response headers). The ranges were fetched twice; both times gave identical bytes.
- `docs/`: the MEDA readme, release notes, bundle and collection labels, the derived collection inventory, the PDS
  Atmospheres wind index, the PDS Atmospheres MEDA page and the LMD dust climatology page.
- `downloads.json`: every file with URL, bytes, sha256, ETag, Last-Modified and retrieval time.

## Transformation steps (all in `tools/weather/build_bundle.py`; also listed per product in the manifest)

MEDA (every product):
1. Check the CSV against its label (size, md5, record count, header).
2. Time: LMST `sssssMhh:mm:ss.sss` becomes a fractional mission sol (sol + seconds of the local mean solar day / 86400).
3. Filters. Pressure: skip empty or invalid `PRESSURE`. Wind: keep a sample only when `ROVER_STILL` = 1 and
   `HORIZONTAL_WIND_SPEED` and `WIND_DIRECTION` are present and below the invalid value (999999999 in these files).
   Air temperature: per sample, the median of the three mast sensors `ATS_LOCAL_TEMP1-3` reading 100-350 K (two
   needed); the two rover-body sensors are not used. (This median is this project's processing choice, not a MEDA
   quantity.) Flags that are empty in these files (`PRESSURE_UNCERTAINTY`, `BOTH_BOOMS_USED_FOR_RETRIEVAL`, wind
   uncertainties) are not used; `TRANSDUCER` is 1 throughout.
4. Bins of 1/144 sol (10 Mars minutes): row time = bin centre, value = mean of the kept 1 Hz samples, `samples` = how
   many; empty bins hold the missing value -999.0. Wind also gets the largest 1 Hz speed and the direction of the mean
   unit vector.

LMD:
1. Check the header and the ranges against the sha256 in the range index; check the grid indices against the file's
   longitude and latitude variables and that the four cells surround Jezero.
2. Bilinear interpolation to 18.44 N, 77.45 E (weights 0.8167 towards 78 E, 0.3533 towards 16.5 N).
3. Columns: `cdod610` (9.3 micron absorption CDOD normalised to 610 Pa; file unit Pa/Pa, written as 1), `cdodtot`
   (total column to the grid point surface), `tau_vis` = 2.6 x `cdodtot` (the LMD page's factor for an equivalent
   visible column optical depth), `reliability` = `cdodrel`. One row per map; `sol` is the file's fractional Time.

Episodes (`episodes.json`, documented inside the file too):
1. tau = `tau_vis` at Jezero for every sol of Mars years 35 and 36.
2. Background: for Ls 0, 10, ..., 350 the 25th percentile of tau over both years within +-15 degrees of Ls; 360
   repeats 0. Range 0.23 (Ls 130) to 0.91 (Ls 240).
3. An episode opens on a sol whose tau is at least 0.35 above the background and extends while the excess is at least
   0.175; episodes 2 sols or less apart are merged.
4. `tau_curve`: the daily values from the sol before the episode to the sol after it, linearly interpolated every
   0.25 sol; `duration_sols` is the curve length in sols; `peak_tau` the largest daily value (also the curve maximum).
5. Mars year 36 maps are matched to mission sols through Ls: LMD Time minus mission sol = 10.658 (mean over the 8
   MEDA labels). MEDA products whose sol falls inside an episode are added to its `source_product_ids`.
6. `wind_ms_mean`: mean of the kept MEDA 1 Hz wind samples on downloaded sols inside the episode; -999.0 (the missing
   value) when there is none, with `wind_source` saying why.
7. `solar_factor_at_peak` = exp(-0.6 x (peak_tau - 0.5)): **the game's power-model rule** from `docs/MODEL_P07.md`
   (game balance, not a measurement).
8. Extra fields per episode: Mars year, Ls start/peak/end, dates (from the maps' average MJD), mission sols,
   `background_tau`, `excess_at_peak`, `episode_sols`, `meda_products_in_period`.

| Episode | Observed | Curve sols | Peak tau | Background | Excess | Wind | Solar factor (game rule) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| jezero_my35_ls234 | MY35, Ls 229.3-242.2, 29 Jun - 20 Jul 2020 (before landing) | 20 | 1.34 | 0.83 | 0.51 | not measured | 0.603 |
| jezero_my35_ls323 | MY35, Ls 318.5-326.6, 21 Nov - 6 Dec 2020 (before landing) | 14 | 1.28 | 0.59 | 0.69 | not measured | 0.627 |
| jezero_my36_ls155 | MY36, Ls 153.0-156.8, 5-12 Jan 2022, sols ~312-319 | 7 | 0.81 | 0.28 | 0.53 | 4.26 m/s (sol 313) | 0.832 |
| jezero_my36_ls166 | MY36, Ls 157.9-167.7, 14 Jan - 1 Feb 2022, sols ~321-339 | 18 | 0.85 | 0.33 | 0.52 | not measured | 0.812 |
| jezero_my36_ls172 | MY36, Ls 168.9-173.9, 4-13 Feb 2022, sols ~341-350 | 9 | 0.76 | 0.35 | 0.42 | not measured | 0.853 |
| jezero_my36_ls221 | MY36, Ls 218.6-223.1, 30 Apr - 7 May 2022, sols ~424-431 | 7 | 1.12 | 0.60 | 0.52 | not measured | 0.688 |
| jezero_my36_ls230 | MY36, Ls 224.4-232.1, 9-22 May 2022, sols ~433-445 | 12 | 1.18 | 0.79 | 0.40 | not measured | 0.663 |
| jezero_my36_ls316 | MY36, Ls 312.9-335.3, 29 Sep - 10 Nov 2022, sols ~572-611 | 39 | 2.03 | 0.52 | 1.51 | not measured | 0.399 |
| jezero_my36_ls346 | MY36, Ls 345.1-355.2, 26 Nov - 16 Dec 2022, sols ~629-648 | 19 | 0.95 | 0.60 | 0.35 | not measured | 0.762 |

Reference values in `episodes.json`: the quiet sol 289 (tau 0.22; pressure mean 628.3 Pa; air temperature 194.9-265.3 K
at 1 Hz; wind mean 3.10 m/s, `background.wind_ms_mean_quiet`) and the MEDA storm sols (`meda_storm_sols`: sol 313
pressure 583.5-642.9 Pa, wind mean 4.26 m/s; sol 317 air temperature 197.6-261.5 K; sol 579 pressure mean 735.7 Pa).

## Refresh entries

One per product, pointing at the archive file the product was built from, with that file's ETag and Last-Modified
(the product's `etag` / `last_modified` are the same values), `timeout_s` 20 and `max_bytes` about 1.5 x the MEDA file
size (2,000,000 for the LMD files). A conditional GET normally answers 304. A 200 means the archive changed the file:
the product can only be rebuilt with the Python tool (the transform is not in GDScript), so the game should keep its
bundle and say that an update was published. MEDA updates normally appear as a **new file name** (the `P01/P02/P03`
suffix is the version), so the old URL may also answer 404. The LMD files are 57.8 MB: a changed file is expected to
be refused as oversize. A source that publishes nothing new is not a failure.

## Godot notes

- Every bundle and fixture CSV has a `<file>.csv.import` with `importer="keep"`: Godot would otherwise import each
  CSV as a translation table. The build script writes these files.
- `SourceLibrary` now also loads `data/sources_*.json` and `data/claims_*.json`. Weather entries are found by
  `SourceLibrary.source("W01")`, `extra_sources()` and `all_sources()`; they are **not** in `sources()`, which stays the
  list of `docs/source_register.md` rows (`tests/test_sources.gd` requires that). The weather claims are in
  `claims()`, so the register panel lists them and links to their W sources.

## Limitations

- **Site**: Jezero crater, a real place, is not the fictional colony. Observations are from 2019-2022 (archive time),
  not game time.
- **Game time**: the game plays episodes faster, scales their duration and strength, and chooses the gaps. That is game
  transformation and says nothing about how often storms happen at Jezero. Nothing here is a storm probability: two
  Mars years at one place are far too few for that.
- **Dust record**: kriged maps are interpolations of orbital retrievals (worked out from Mars data, not measured at
  the rover); one map per sol is a diurnal average, so curves are smooth; 2.6 is an approximate conversion to visible
  optical depth; the 3 x 3 degree grid is coarse compared with the crater.
- **Episode definition** (threshold 0.35, edge 0.175, 25th percentile background, merge gap 2 sols) is this project's
  choice. The first and last curve points are real daily values (the sols just outside the episode), so curves do not
  start exactly at the background.
- **Wind**: measured for one episode only (its first sol); all others are -999.0 (not measured). The game must not
  present a value for them as measured.
- **MEDA coverage**: about 12 hours per sol; empty bins are -999.0. MEDA measured only the four chosen sols here.
- **Solar factor**: from the game's own rule, not from MEDA radiation data.
- **MY35 Ls**: its first map carries Ls 359.93 (as in the file), so the product's `ls_start` (359.928) is larger than
  `ls_end` (359.621); the year still runs from map 1 to 669.

## Not verified or left out

- The MEDA RDR SIS (`document/meda_env_rdr_sis.pdf`, 1.7 MB) was downloaded but its text could not be extracted with
  the Python standard library (custom font encoding). Column meanings and flags come from the PDS4 labels, the readme
  and the release notes.
- No MEDA derived dust-opacity product exists; MEDA RDS radiances were not used.
- Mars year 34 (the 2018 global dust storm) was left out: its file has no observation-date (MJD) variables, so dates
  could not be read.
- Humidity, TIRS, ancillary (rover position, sun angles) and SkyCam products were not downloaded.
- The Montabone et al. papers (2015, 2020) were not opened; the method notes come from the LMD page and the file
  attributes.
- The landing-site coordinates were not read from a downloaded file.
- The wind index on the PDS Atmospheres site lists one extra product for sol 898 that is not in the current derived
  collection inventory; it was not used.
- The S18 register entry (InSight power and dust) stays SEARCH-ONLY; it was not opened in this work.
