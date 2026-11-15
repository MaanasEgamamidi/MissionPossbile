# S01-S04 survival handoff

This batch implements the subsequently authorized survival section, PDF pages 22-25, on `revisions`. Stop before T01 on page 26. The document supplies requirements; it does not override the user's scope or authorize later puzzles, restoration art or cinematics. The earlier F and C handoffs are historical records of their respective batches.

## Ownership and scope

The parent integrates world doors, the maintenance station panel, LAN checks and Git delivery. The foundation engineer owns authoritative exposure, suit protection, pressure and session scheduling. The UI engineer owns the local critical warning, alarm and accessibility. The orchestrator owns continuous wear, mapped maintenance, contracts and this audit. Three child slots are available; all three are assigned.

| Unit | Delivered behavior | Evidence contract |
| --- | --- | --- |
| S01 exposure | Host-only four-second unprotected exposure, functional-suit checks, persistent elapsed time, continuous-safe reset and existing recovery exactly once. | Core survival matrix, real host/two-client transport and existing session/model regressions. |
| S02 warning | Local-player banner, border, cause, countdown and actionable escape instruction above panels; native short alarm with mute/volume; static default and reduced-flash support. | HUD behavior/layout/audio checks and ten final Compatibility-renderer captures. |
| S03 wear | Twelve mapped operational conditions, six room means and the already repairable legacy cleaner wear by unpaused real seconds; exclusive, role-checked timed maintenance restores its mapped system only. | Isolated wear matrix, full-map panel checks, saves and actual LAN convergence. |
| S04 pressure | Explicit exit-vestibule pressure proxy driven by T12 seal fault and actual doors; safe-side seal maintenance and existing door interlocks. | Pressure/boundary matrix, door integration, HUD and LAN checks. |

Exact final counts and selected raw logs belong in `SURVIVAL_VERIFICATION.md`. No human or two-computer playtest is claimed.

## Host timing and protection

`SessionService` alone advances survival and wear, with substeps no larger than `GameConfig.hazard_step_seconds` (0.05 real seconds). Only unpaused authoritative time advances these systems. Changing playable sol length, opening a panel or culling an unvisited room does not change their rate. Clients reconstruct replicas and never integrate wear or decide death.

An unprotected actor in nonbreathable air accumulates `lethal_exposure_seconds`; the default deadline is four seconds. A functional suit requires suit-on, integrity at least 0.5, positive oxygen charge and a positive configured tank capacity. Its ordinary suit consumption remains in the existing path. Empty or damaged suits do not suppress danger. The warning shows the current cause and remaining host budget; its display smoothing cannot resolve damage or recovery.

Exposure is cumulative across brief boundary crossings, suit toggles and save/load. Two continuous seconds of safe air or working protection clear it. A fresh hazard resets that safe interval. Existing recovery runs once at the deadline and retains its established food/water cost and Med Bay destination; it clears exposure without refilling suit equipment. Crew switching, release, disconnect parking and restore use pressure-aware safety, preventing a free teleport from a hazardous saved pose. The central production session delegates atmospheric harm to this timer; it does not also apply the legacy game-hour no-air health loss. Pure `ColonySim` model tests retain their standalone fallback, and food/water health effects retain their existing owners.

The local `SurvivalHud` uses CanvasLayer 60, a mouse-ignoring border and an opaque banner. Critical task, cassette and maintenance panels close on danger, including a hidden panel in the stack. Local settings remain reachable. The short native PCM alarm respects warning mute/volume and the Master bus. `reduce_flashes` defaults true; the optional gentle pulse is not needed to communicate danger. Remote-player danger does not produce this player's banner or the old colony-wide no-air alert. Recovery clears the countdown and border.

## Wear ownership and operational limits

| Condition-bearing system | Owner in this batch | Repair / operational effect |
| --- | --- | --- |
| Twelve `state.repair.tasks.T01` through `T12` records | One `WearRuntime` call per host real-time substep. Six room conditions are means of their two records. | Existing canonical `repair_t01` through `repair_t12` anchors offer Equipment maintenance. T12 fault controls local seal leakage. The other eleven expose current condition, warning/fault and mapped maintenance; they do not yet implement T puzzle machinery or invent new resource couplings. |
| Legacy `cleaner` | The same real-time `WearRuntime`, after its existing repair makes it operational. | Existing electrical-specialist `repair_cleaner` restores it; its condition controls the existing PowerModel cleaner functionality. Durable repair grace is applied immediately. |
| Legacy `trackers`, `recycler`, `scrubber`, `electrolyser`, `co2_unit`, `cabin_fans` | Existing conditions and resource models remain their owners. No additional deterioration is introduced. | These six lack equivalent mapped maintenance routes. Keeping them stable avoids new unrepairable failures. Recycler upgrade's existing condition floor is retained. |
| Solar-panel dust | Existing PowerModel game-hour dust accumulation/cleaning. | No second dust or condition ticker is added. |

The distinction above is intentional scope: all twelve mapped systems can be maintained now, while their actual minigames and additional operational effects remain later T work. For example, the Med Bay mixture anchor does not arbitrarily reset the scrubber. No resource store, power ledger or colony gas mass is directly changed by task-condition wear or generic maintenance.

Default `GameBalance` tuning is explicit gameplay balance, not a physiological or NASA prediction:

| Setting | Default | Meaning |
| --- | --- | --- |
| `maintenance_enabled` | true | Enables task and cleaner deterioration. Existing faults can still be maintained when deterioration is disabled. |
| `maintenance_wear_per_second` | 1/480 | Full task condition becomes 0.9375 after 30 ungraced real seconds. |
| `maintenance_warning_condition` | 0.75 | Approximately 120 seconds from full condition without grace. |
| `maintenance_fault_condition` | 0.5 | Approximately 240 seconds from full condition without grace; advances a fault generation once. |
| `maintenance_repair_seconds` | 20 | Exclusive host-timed maintenance duration. |
| `maintenance_repair_cooldown_seconds` | 15 | Saved grace after a repair; the next default fault is approximately 255 seconds after completion. |
| `cleaner_wear_per_second` | 1/480 | Sole new legacy-condition deterioration rate. |

A warning/fault is latched until repair, so threshold jitter cannot repeatedly restart a generation. Repair sets condition to one and clears its current warning/fault, but retains the fault generation. A later neglected cycle can generate a new fault. Maintenance crossing the fault threshold remains one authorized job rather than becoming stranded on its old generation.

## Maintenance actions and security

| Action / API | Contract |
| --- | --- |
| `maintenance_start` | Canonical `repair_tNN` target and `generation: int`. Host checks ownership, alive actor, role, actual room, station identity/kind, reach, current generation and absence of active exposure. Refuses another maintenance operator or a future puzzle lease. |
| `maintenance_cancel` | Same canonical target; idempotent cleanup for the requesting operator, including pause, lost actor or lost reach. Another peer cannot cancel the job. |
| `session.wear_runtime.status(task_id)` | Transient operator, elapsed/duration and progress; panel duration comes from the authoritative tuning. |
| `restore_task(session, task_id, generation)` | Host-only mapped condition/fault/cooldown restoration. Shared by maintenance and the future real host puzzle-completion hook. |
| `force_fault(session, task_id, condition)` | Internal host test hook. No registered player action exposes it. |

Every active job revalidates the operator. Leaving reach/room, ownership or role changes, death, exposure, recovery and disconnect release it. Thus direct LAN requests cannot continue a maintenance job through atmospheric danger merely because a UI cancellation is delayed. The panel also sends cancellation for an in-flight start before closing, using ordered transport. Different tasks can be maintained concurrently by appropriate specialist/helper crew.

Equipment maintenance never sets task progress, puzzle state, `first_completed`, room completion, collection, rewards or beauty-shot history. It is visibly labeled Equipment maintenance and is not a substitute completion for a future T puzzle. Future valid puzzle completion calls the same mapped restoration hook without restoring unrelated systems.

## Local airlock pressure

`LocalPressure.VOLUME` is the explicit AABB at `(20.2, -0.2, 10.3)`, size `(3.6, 3.7, 4.55)`, with 0.15 m exit hysteresis. Only this exit vestibule uses the local proxy. The Hangar, inhabited corridor and Garden dome are not globally reclassified by a seal leak.

Nominal local pressure is 101.3 kPa and the vent target is 0.6 kPa. A T12 `maintenance_fault` or open outer door drives leakage at 200 kPa per real second. The outer door's first motion vents immediately. Closing it does not instantly restore breathable pressure: the nominal recovery takes five seconds, with unsafe at or below 70 kPa and safe at or above 80 kPa. These thresholds are gameplay tuning. Actual doors 901/902 feed transient door facts; their existing partner interlock remains in force. Native signs show local pressure and seal/door/repressurization status.

The existing `repair_t12` anchor `(19.5, 0.04, 4.2)` is on the safe interior side, before z=10.3; the existing suit rack is also before the dangerous volume. A field engineer can perform the twenty-second seal maintenance without first crossing the fatal volume. No extra independent repair anchor or job state is introduced. A working suit protects an engineer entering the depressurized chamber. Repair stops leakage, then pressure must recover before an unprotected actor is safe.

This proxy does not subtract colony oxygen/nitrogen. The existing `note_airlock_cycle` / LifeSupportModel path remains the sole global airlock gas-mass accounting path. Cabin safety elsewhere still derives from existing O2/CO2/total pressure. `session.survival.debug_trigger_airlock_fault()` requires an authoritative debug build and has no player ActionService endpoint.

## Saves, replicas and integration APIs

Nested repair schema becomes version 2 with `maintenance_schema: 1`; the save envelope and network protocol remain compatible. Old F/C generation-one, zero-condition, empty-progress placeholders migrate to operational condition one without earning a milestone. Real partial puzzles, explicit fault generations, completed milestones, collected tapes and seen shots are retained. Task elapsed wear, warning/fault flags and grace are persisted. Legacy cleaner grace has its own persisted metadata.

`ColonyState.pressure` separately stores local kPa/breathability/leak/repressurization. Actor suit integrity, exposure budget and safe interval are serialized. Reload does not clear danger or manufacture a safe pressure pocket. Offline wall time does not wear equipment. Operator jobs and door motion facts are session-only: replicas include them for late join, disk saves do not preserve a stale operator or open-door animation.

Public survival queries are `session.survival.status(actor_id)`, `functional_suit(actor)`, `breathable_at(point, was_in_chamber)`, `pressure_info()` and `set_airlock_door_open(901/902, opened)`. Central refresh occurs before requests/pruning and after relevant position/equipment changes. Actual gameplay runs these systems independently of capture helpers and room visibility.

## Evidence and remaining limits

`evidence/survival_ui_compatibility/` contains ten final normal/enlarged/high-contrast, panel/settings, maintenance-interruption, local-pressure and cleared-recovery views. Independent review confirms legible cause/countdown, a visible static border, an unblocked central retreat view, safe cancellation and no stale post-recovery survival banner. Maximum-scale legacy HUD overlap is visible and has not been redesigned. The cassette-layer capture deliberately reopens a reader after danger is already active to verify overlay order; normal first-entry danger interrupts that reader.

The capture helper holds automatic GameServices processing and steps an authoritative sample manually to obtain comparable frames. These screenshots prove presentation, not live deadline timing; separate core and transport tests exercise the running clock. They do not constitute an uninterrupted human traversal or audibility playtest.

The initial Forward+ capture produced all ten images and then terminated with SIG11 during renderer teardown after light-unpair/softshadow diagnostics. Final Compatibility capture exits successfully, with all ten writes successful and maintenance/cassette cleanup reported true, but still reports GLES3 instance-uniform and exit-resource diagnostics. The updated single-shot airlock warning also exits successfully in both renderers; Forward+ clearly shows the retreat door, while the Compatibility background is dark. Its instruction explicitly says to retreat through the inner door and have the field engineer repair from safety. No clean baseline comparison establishes that these renderer problems are pre-existing. A crash-free Forward+ renderer is not claimed. Exact logs and final test results are retained in `SURVIVAL_VERIFICATION.md`.

No T01-T12 minigame, restoration art, cinematic or later section is implemented by this batch.
