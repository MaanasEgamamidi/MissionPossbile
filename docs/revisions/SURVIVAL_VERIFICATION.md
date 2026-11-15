# S01-S04 survival verification

This record covers the newly authorized S01-S04 section, PDF pages 22-25, stopping before T01. Historical F01-F06 and C01-C04 totals remain in their own verification files and are not added to this batch's results.

## Final regression selection

The user requested immediate wrap-up before the complete broad run finished. The confirmed documentation snapshot is 34 unique suites and 2332/2332 checks, with zero FAIL/SCRIPT ERROR/Parse Error lines in the selected newest per-suite logs. This is partial broad verification, not an all-38-suite acceptance claim. The performance and three cassette suites were outside that snapshot. Logs under evidence/s_survival_regression and evidence/s_survival_final retain raw initial failures and subsequent reruns; repeated suites are not added together. Later log arrivals do not retroactively change this snapshot.

## Focused coverage

- `test_survival.gd`: the foundation engineer's final focused run passes 118/118 in `evidence/survival_backend.log`. It covers exterior/cabin/chamber safety, real-time deadline and safe-interval reset, suit reserve/integrity, frame-step and sol-length invariance, saved exposure/pressure, exactly-once recovery, per-peer warning ownership, authority refusal, safe-side T12 repair, door pressure and unchanged global air accounting. Pressure-aware remote parking is covered at the real GameServices restore boundary.
- `test_wear_runtime.gd`: orchestrator's isolated run passes 53/53, including all twelve continuous conditions, migration preserving actual puzzle state/history, 30/120/240-second targets, pause, different frame/sol settings, mapped twenty-second repair, cooldown/recurrence, specialty and competing operators, future puzzle lease exclusion, direct hazardous start refusal and backend hazard cancellation, legacy cleaner single-owner wear, serialization and clients that never advance authoritative wear.
- `test_survival_hud.gd`: UI engineer's focused run passes 65/65. It exercises real maintenance cancellation, critical cassette interruption, death/recovery, peer-local warnings, audio preferences, maximum supported layout/contrast and a mouse-ignoring border. Final broad results below supersede focused repeats for the unique total.
- Real loopback ENet `test_survival_net.gd` passes 28/28 in `evidence/s_survival_final/test_survival_net.txt`: host plus two clients, late join, pressure and door replication, four-second recovery once, pause, denied client authority, one exclusive maintenance clock and converging repair result. No two-computer LAN playtest is claimed.

## Compilation and visual evidence

`evidence/s_survival_final/compile.txt` currently records `COMPILE OK 269 scripts`, using Godot `4.7.2.stable.official.ed1daf0bf`. This compile completed before the final small GameServices guard. A full recompile after that edit is not claimed at this freeze.

Ten final images under `evidence/survival_ui_compatibility/` cover 1280x720 and 1920x1080 normal/enlarged high-contrast warnings, explicit airlock cause, maintenance before/interruption, audio settings, cassette layering and cleared recovery. Independent inspection confirms readable cause/countdown/action, an unobstructed central retreat view, visible static border, safe panel cancellation and no stale recovery countdown. Maximum-scale legacy HUD overlap remains visible and is outside this warning implementation.

`evidence/survival_capture_compatibility.log` records all ten image writes with result 0, `MAINTENANCE_RELEASED true` and `CASSETTE_INTERRUPTED true`; the process exits 0. GLES3 instance-uniform allocation diagnostics and 124 ObjectDB/27 resource-at-exit warnings remain. The first Forward+ run (`evidence/survival_capture.log`, images under `evidence/survival_ui/`) produced all ten images but ended with SIG11 during teardown after light-unpair/softshadow renderer diagnostics. No GDScript/parse failure was observed in either capture log. A clean comparison does not establish that the renderer issue is pre-existing, and successful Compatibility captures do not establish crash-free Forward+ operation.

The capture helper deliberately suspends automatic GameServices processing and advances a host sample manually for matching screenshots. Timing acceptance comes from core and transport tests, not these static images. The cassette-layer frame deliberately reopens the reader after danger already exists to verify layer order; ordinary first danger interrupts it. No human audibility or uninterrupted traversal playtest is claimed.

After the action text was shortened to "Retreat through inner door. Field engineer repairs from safety.", the airlock-pressure image was regenerated in both renderers. `evidence/survival_airlock_copy_capture_forward.log` and `evidence/survival_airlock_copy_capture.log` record successful single-shot writes and successful process exits, with renderer/resource diagnostics retained. Independent review of the Forward+ image confirms a clearly visible inner door; its Compatibility counterpart has a dark world background but readable warning. This later single-shot success does not erase the original ten-shot teardown crash.

## Behavioral boundaries

The twenty-second Equipment maintenance flow restores current mapped condition only. It does not complete a T puzzle, grant a reward, clear collection/history or replay a beauty shot. T12 condition affects local seal leakage; the other eleven task conditions expose deterioration/status/maintenance without implementing their deferred T machinery or arbitrary new resource couplings. The already repairable legacy cleaner receives new wear; the six legacy units without mapped maintenance receive no new deterioration. Panel dust and colony power/gas resource ledgers retain their existing owners. These boundaries and the inventory are explicit in `SURVIVAL_HANDOFF.md`.

## Initial regression corrections

Raw initial failures remain in the broad-run logs. Final reruns supersede them only after a concrete correction:

- The source-classification audit initially lacked the seven new maintenance balance fields. `data/model_sources.json` now classifies all seven as gameplay balance with their real-second units; no scientific evidence claim is invented.
- Direct LifeSupportModel game-hour health checks explicitly select `sim.exposure_managed = false`. That is the pure-model fallback those tests exercise; the production SessionService keeps centralized real-time atmospheric harm. The separate survival suites verify the new deadline.
- The old SessionService recovery fixture uses empty food to exercise non-atmospheric recovery, since zero cabin gas now deliberately follows the new four-second exposure path. The crew-switch foundation fixture queries actual host atmosphere instead of relying on a stale `outside` flag.
- The rover fixture's helper now reports its safe Med Bay arrival, waits only the remainder of the required two continuous safe seconds and asserts the requested crew was actually claimed. Previously an immediate switch could be correctly refused while exposure debt remained, silently leaving the wrong driver and cascading into seat/panel assertions. The original eighty rover assertions remain.
- The full game-scene fixture still admitted a rack approach that collided with item/crew layers omitted by its WORLD/DOOR-only search probe. Physics pushed the actor upward and beyond the unchanged 2.6 m station reach. The probe now uses the actual player's complete collision mask, excludes that body's RID and settles the candidate for twenty physics frames. Strict grounded/height/reported-pose/reach checks remain, with contact diagnostics. The separate recovery fixture now asserts no legacy instant recovery at three seconds and checks the real deadline afterward.
- Weather's direct-model helper refreshes atmospheric poses after fixture teleports; stale `outside` flags no longer consume suits in an intended indoor model fixture. Weather source validation selects its extension records by weather IDs and still checks every weather field; cassette/photo records retain their own catalog validators.
- The scout-trip fixture equips its existing suit before waiting outside at the bay. Waiting unprotected now correctly triggers four-second recovery and moves the actor out of recall reach. The sixty original scout assertions remain; no recall-distance rule is weakened.

These fixture changes do not shorten the live hazard, weaken station reach, bypass role checks or reset a player's exposure budget.


