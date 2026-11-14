# Mars Colony (Godot 4.7.2) — Prompt 09 build spec: NASA weather archive, refresh and varied weather

Two workers, each in its own project copy with a fixed file list. Same ground rules as `SPEC_P08.md` ("Ground rules
(all parts)", read it), with one difference: **Part D may use the internet** to find and download small public NASA/PDS
(or other primary research archive) files; Part W may not (it uses the fixture bundle). The game's power model already
reads `state.dust_tau` (sky dimming of solar output) and settles panel dust faster when it is high: read
`docs/MODEL_P07.md`, `scripts/sim/power_model.gd`. LAN co-op exists: the host sends the whole `ColonyState` to clients
and forwards `GameEvents` (read `docs/HANDOFF_P06.md`), so anything in `state.weather` / `state.weather_queue` /
`state.data_snapshot_id` reaches every player, late joiners included.

Rules from the brief and contract (binding):
- Ship a verified NASA archive subset; play continues offline with the last validated data. Check for published
  updates at startup and hourly while online, in the background, with conditional requests, timeouts, bounded
  downloads and retry backoff. A failed refresh keeps the last valid cache. Cache updates atomically and report the
  observation date and validation status. A source not publishing new data is not a failure.
- Pin a data snapshot for the active run; adopt newly validated data at the next session/load, so an issued forecast and
  a saved sequence are never silently rewritten. The host distributes the active snapshot id and weather events.
- Never call archived observations live weather or a forecast for the fictional colony. Distinguish observation time
  from game time; label accelerated intervals and progression adjustments as game transformation, not NASA-observed
  storm frequency.
- MEDA (Perseverance, Jezero) calibrated/derived products for local environmental values; prefer derived products when
  their documentation says they are the right combined sensor quantity; an orbital dust-opacity record or a published
  climatology for dust episodes. Preserve PDS ids/versions, dates, site, units, flags and transformation steps. Do not
  combine distant landing sites as if one place; do not download a whole multi-gigabyte archive; do not infer storm
  probability from a short arbitrary temperature range.
- Saved seed, RNG state, chosen episode ids and queued events. Observation-derived episodes or empirical conditional
  distributions vary gaps, duration and severity, preserving the relationships among wind, dust and solar effects.
- Teach before escalation: a minor first event only after the response has been taught (cleaning panels: the player
  has cleaned a panel at least once — `state.evidence` has `energy_diagnose_output_loss` or `state.ledger` shows a
  cleaning — or the colony has run 2 sols, whichever later); a warning and an attainable shelter/return margin based on
  real walkable routes; readiness-sensitive severity limits and recovery intervals with visible variation. Emphasise
  opacity, panel output and dust management. No destructive wind, instant death, radiation or radio interference.

## The bundle format (the contract between D and W)

`res://data/weather/bundle/manifest.json`:
```json
{"format": "mars_colony_weather_bundle", "schema": 1, "bundle_id": "jezero-meda-…-v1", "built_utc": "…",
 "products": [{"id": "meda_ps_…", "kind": "pressure|air_temperature|wind|dust_opacity|…", "file": "meda_ps.csv",
   "sha256": "…", "bytes": 123, "source_id": "S04 or new id", "pds_lid": "urn:nasa:pds:…", "version": "…",
   "mission": "Mars 2020", "instrument": "MEDA …", "site": "Jezero crater", "lat": 18.44, "lon": 77.45,
   "observation_start_utc": "…", "observation_end_utc": "…", "sol_start": 0, "sol_end": 0, "ls_start": 0.0, "ls_end": 0.0,
   "columns": {"name": "unit", …}, "units_ok": ["Pa", "K", "m/s", "deg", "1"], "missing_value": -999.0,
   "quality": "how flags were applied", "license": "…", "source_url": "https://…", "etag": "…", "last_modified": "…",
   "retrieved_utc": "…", "transform": ["step 1 …", "step 2 …"]}],
 "episodes_file": "episodes.json", "episodes_sha256": "…",
 "refresh": [{"product_id": "…", "url": "https://…", "max_bytes": 2000000, "timeout_s": 20}]}
```
Product files are small CSVs: a header row of column names matching `columns`, one row per time step, numbers in the
declared units, `missing_value` for gaps. `episodes.json`:
`{"episodes": [{"id", "source_product_ids": [...], "observed": "dates / Ls / sols in words", "duration_sols", "peak_tau",
"tau_curve": [values per 0.25 sol from start to end], "wind_ms_mean", "solar_factor_at_peak", "notes"}],
"background": {"tau_by_ls": [[ls, tau], …]}}` — every episode derived from the products in the bundle by
documented steps.

---

## Part D — the verified data bundle (`worker D`)

Files: `tools/weather/build_bundle.py`, `tools/weather/validate_bundle.py` (Python 3 standard library only),
`data/weather/bundle/*` (manifest, product CSVs, episodes.json), `data/weather/raw/*` (the downloaded original files,
small), `data/sources_weather.json`, `scripts/ui/source_library.gd` (**only** to also load `data/sources_*.json` and
`data/claims_*.json` files besides the existing ones), `data/claims_weather.json`, `docs/WEATHER_DATA.md`,
`tests/test_weather_data.gd`.

- Find the MEDA PDS4 bundle (start at https://atmos.nmsu.edu/data_and_services/atmospheres_data/PERSEVERANCE/meda.html,
  register entry S04) and read its documentation to choose **derived or calibrated products** for: pressure, air
  temperature, wind speed, and, if MEDA publishes it, dust optical depth (RDS). Pick a small set of sols that includes
  quiet periods and at least one documented dust event at Jezero if the products cover one; keep the raw download
  under ~30 MB total. Record exact PDS identifiers and versions, file URLs, dates, sols, Ls, units, flags and the
  licence (PDS data are public; quote what the archive says).
- For dust episodes use an orbital dust-opacity record or a published climatology covering Jezero (for example a
  NASA/PDS product, or Montabone et al.'s dust climatology from the LMD archive — a reputable research archive is
  allowed when NASA does not publish the needed product; record why). If a source cannot be downloaded or parsed with
  the standard library, say so and use what can be verified; never invent values.
- `build_bundle.py` reproduces the bundle from `data/weather/raw/` (offline) and records every transformation;
  `validate_bundle.py` checks manifest fields, sha256, units, missing values, monotonic time, plausible ranges (and
  prints a report). `episodes.json` is derived from the products by documented steps (for example: periods where the
  opacity exceeds the seasonal background by a threshold → an episode with its duration, peak and curve; wind and
  solar factor from the same period). Also write `tests/fixtures/weather_bundle_min/` — a tiny valid bundle in the same
  format (2 products, 2 episodes) — **first**, within your first steps, because Part W uses it.
- `data/sources_weather.json`: one register entry per product (same fields as `data/sources.json`, status VERIFIED
  only for pages/files you actually opened, with the values read). `data/claims_weather.json`: the claims the weather
  screens show (archive vs game-time vs balance categories).
- `docs/WEATHER_DATA.md`: what was chosen and why, identifiers, coverage, gaps, the transformation steps, the
  limitations (site is Jezero, not the fictional colony; archive dates; accelerated game intervals).
- Test: the shipped bundle validates in GDScript too (manifest fields, sha256 via `FileAccess.get_sha256`, units), the
  register entries and claims resolve in `SourceLibrary`, and the fixture is valid.

## Part W — weather service, scheduler and presentation (`worker W`)

Files: `scripts/sim/weather_system.gd` (replace stub), `scripts/session/weather_actions.gd` (replace stub),
`scripts/weather/weather_archive.gd`, `scripts/weather/weather_refresh.gd`, `scripts/weather/weather_presenter.gd`,
`scripts/weather/return_routes.gd`, `scripts/core/weather_config.gd`, `scripts/ui/stations/weather_station_panel.gd`
(the comms console or the colony computer can host a weather screen: add a station only through
`data/stations_weather.json` if needed), `data/model_sources_weather.json`, `tests/test_weather.gd`,
`tests/fixtures/weather_bundle_min/` (read only — Part D writes it; until it exists, make your own copy under
`tests/tmp/fixture/` in the same format and switch when it appears).

- `WeatherArchive` (RefCounted): loads and validates a bundle directory (format above): every manifest field, sha256,
  units in the allowed set, missing values, time monotonic; returns a typed result with problems listed. Loads the
  **shipped** bundle (`res://data/weather/bundle`) and the **cache** (`user://weather_cache/current`) and picks the newest
  valid one; `snapshot_id()` = bundle id + version. Never crashes on bad data: falls back to the shipped bundle.
- `WeatherRefresh` (Node, `HTTPRequest` children): at start and every `refresh_hours` (1 h) while online, for each
  `refresh` entry sends a conditional GET (If-None-Match / If-Modified-Since from the manifest), timeout, `max_bytes`
  cap (abort beyond it); 304 = up to date; 200 = write to a temp folder, validate a complete new bundle (copy the
  current, replace the changed product, recompute sha256 and episodes only if the transform is in GDScript — otherwise
  keep the episodes and mark the product updated), then swap atomically (rename temp → current, keep the previous as
  backup). Failures: retry with exponential backoff (1 min, 2, 4 … cap 1 h), keep the last valid cache. Status for the
  UI: observation period of the active data, last check time, last result in words. The **active session keeps its
  pinned snapshot** (`state.data_snapshot_id`); a newer validated bundle is used for the next new game or load (say so
  on screen). Make the HTTP layer injectable so tests can simulate 200, 304, timeout, oversize, HTTP 500, invalid
  units/flags, interrupted download (partial file) — no real network in tests.
- `WeatherSystem` (pre-system; host only — clients never step the simulation): owns `state.weather` (current episode
  id, phase, tau, wind, warning state, own RNG seed and state as strings) and `state.weather_queue` (future events with
  game-hour start, episode id, severity scale, warning time). Builds the queue deterministically from the seed and the
  pinned bundle: gaps, durations and severities vary per seed (scale and stretch observed episodes; keep wind/tau/solar
  relationships), never a fixed interval; first event minor and only after the teaching condition (above); severity
  capped by readiness (battery reserve, cleaner working, panels clean, life-support state) and spaced by recovery
  intervals; sets `state.dust_tau` every tick from the active episode (smooth; background tau from `tau_by_ls` with the
  game's Ls derived from sol count — say how). Emits `events.weather_changed(event)` on start/peak/end and a
  `system_alert` warning ahead of each event. A refresh of the cache never changes an issued queue or a running storm.
- **Return margin**: `ReturnRoutes` computes the walking time from any outdoor point to the nearest airlock entrance
  (the tunnel door and the hangar/airlock doors: find them in `data/colony_manifest.json` / the environment airlock
  ids 901/902 used by `scripts/world/environment_collision.gd`) along a walkable route (A* over a coarse grid, about 2 m,
  built from `data/terrain_height.res` slopes and rock/obstacle positions — rocks are in the manifest's
  `environment_objects` with `collection` "Terrain rocks (realised)"; you may bake the grid to `data/weather/route_grid.res`
  with a tool script you add under `tools/godot/`). Warnings are issued at least `return_margin` × the longest current
  outdoor return time (suit walking speed, `GameConfig.suit_speed_factor`) before the event's opacity rises.
- `WeatherPresenter` (Node): given the world scene, adjusts the sky/fog and sun energy smoothly with `state.dust_tau`
  (bounded; no new art), optional bounded `GPUParticles3D` dust near an outdoor player; `setup(world: Node3D, services)`.
  The integrator adds it to the game scene.
- Weather screen panel: active data (site, archive dates, status, last check), current conditions (opacity and solar
  output effect in words), upcoming warning, and the labels "archive observations from Jezero, played faster", "not a
  forecast for this colony".
- **Tests prove**: offline boot uses the shipped bundle; stale cache older than the shipped one is ignored; HTTP failure
  keeps the cache and backs off; invalid units/flags rejected; interrupted download leaves the cache untouched; a source
  update (200 with a new product) swaps atomically and is used only on the next session; deterministic replay (same
  seed → same queue and same tau curve, run twice); save → reload mid-storm continues identically; different seeds give
  different gaps/durations/severities (report the spread over 20 seeds); first event is minor and after the teaching
  condition; escalation stays recoverable (simulate 20 sols with no player action except cleaning once: nobody reaches
  zero health from weather, battery never below the life-support reserve for more than the event); warning lead time
  ≥ margin × return time at three outdoor test points; late join: a `ColonyState.from_dict(to_dict())` replica has the
  same weather; a refresh mid-storm does not change the running storm; panels pass layout.
