# Revisions execution ledger

This ledger records the original PDF pages 1-17 assignment and the later authorized C01-C04 and S01-S04 batches. Their current scope and evidence are tracked in `CASSETTE_HANDOFF.md` and `SURVIVAL_HANDOFF.md`. Stop before T01 on page 26.

| Unit | Dependencies | Owner | Implementation / evidence |
| --- | --- | --- | --- |
| F01 audit | None | Orchestrator, parent verification | Complete: `FOUNDATION_AUDIT.md` records code/asset/reference findings, exact node IDs and points. HUD/arrival and six rooms captured under `evidence/anchors/`; wider views under `evidence/rooms/`. Fresh import passed; final newest results 30 suites, 2042/2042 checks. |
| F02 room/task/fault contract | F01 | Foundation specialist | Implemented: additive `RepairCatalog`, `RepairRuntime`, `RepairActions`. Reviewed fail-closed validator API; included in 119/119 foundation checks. |
| F03 specialist/claim lifecycle | F02 | Foundation specialist | Implemented: same role rules solo/LAN; lease lifecycle and safe crew switching. Tests include all 12 tasks x 4 roles and same-room specialist/helper concurrency. |
| F04 saves/replication | F02, F03 | Foundation specialist, orchestrator transport test | Implemented: nested repair v1, safe-resume save projection, durable exposure field, snapshot/session replication; no persisted leases. Old-save disk roundtrip included in foundation checks. Real ENet test 44/44 includes partial-puzzle late join, completed room/history propagation, disconnect lease release, rejoin and host LAN shutdown cleanup. |
| F05 task shell | F02 | UI specialist | Implemented: themed dummy sample, pending/rejection, keyboard/focus and critical interruption; 29/29 task-panel checks. Normal/enlarged/high-contrast images visually reviewed. |
| F06 anchors/spawn | F01, F02 | Parent integrator | Implemented: 12 repair stations, six future cassette anchors, one future playback station, collision-probed Med Bay arrival/recovery. Final rendered anchor walkthrough 102/102; all 19 local walk/aim/open approaches verified. |

## Shared contracts

- Stable tasks: `T01` through `T12`; station IDs `repair_t01` through `repair_t12`.
- Stable rooms: `command_center`, `power_supply`, `greenhouse`, `green_dome`, `med_bay`, `hangar`.
- Repair state is separate from pre-existing colony `tasks` and progression. `state.repair` owns room/task records, collected cassette IDs and seen beauty-shot IDs.
- Host task actions: `task_claim`, `task_resume`, `task_move`, `task_release`, targeting the task's anchor station. Accepted params use `generation` plus scalar move data; no completion flag or client-selected role is authoritative.
- Actual puzzle validators are future T-section work. The reusable foundation must reject attempted completion without an installed host validator. The F05 dummy sample is presentation-only.

## Decisions

- User-requested branch name is `revisions`, overriding the usual `codex/` prefix.
- Git push must authenticate as `HarshilSharma1`; author metadata alone is insufficient evidence of the push identity.
- Existing reference/output files are preserved. Test saves use isolated test directories.
- No main HUD redesign, replacement action architecture, actual room puzzles or hazard-rate changes are part of this batch.
- Runtime supports three child agents, all assigned for this batch: orchestrator/review lead, foundation engineer and UI engineer. Parent acts as integrator and world engineer. No additional child can be created while these slots are occupied.

## Verification record

F01-F06 were implemented and verified within the original assignment. `FINAL_VERIFICATION.md` records its final passing result for all 30 suites: 2042/2042 checks, with zero FAIL/SCRIPT ERROR/Parse Error lines in those selected logs. Its fresh broad-run import passed. Two initial collision/title failures remain in raw logs for transparency and were corrected and rerun successfully. `HANDOFF.md` records the foundation public APIs, decisions, visual evidence and remaining human/rendering verification limits. Subsequent C01-C04 changes and their fresh verification results are recorded separately in `CASSETTE_HANDOFF.md`; these foundation counts are not presented as the current cassette batch's final results.

## Subsequent cassette batch

C01-C04 are complete within the user's approved scope, including truthful preview briefings while T puzzles remain deferred. Current affected-suite verification is 17 suites and 1261/1261 checks; compilation covers 258 scripts and actual exported offline cassette assets pass 6/6. `CASSETTE_VERIFICATION.md` contains the selected current evidence matrix and corrected save-isolation/P07-mapping/suit-placement fixture explanations. `CASSETTE_HANDOFF.md` contains the C execution ledger, public APIs, six photo credits/content records and remaining human/rendering limits. Stop before S01; no later section is implemented by this batch.

## Subsequent survival batch

The user's "run next section" authorizes S01-S04 on pages 22-25; stop before T01 on page 26. `SURVIVAL_HANDOFF.md` and `SURVIVAL_VERIFICATION.md` record this batch. The existing orchestrator owns wear and the implementation audit, the foundation engineer owns exposure and local pressure, the UI engineer owns critical warnings and accessibility, and the parent integrates world doors, maintenance panels, LAN checks and Git delivery. The runtime still permits only three child agents.

Operational condition starts at full for the old F/C placeholder records while puzzle completion remains false. Role-checked twenty-second maintenance restores mapped condition without completing a future puzzle or replaying rewards. T12 is reachable from the safe interior; the 4-second hazard occupies only the explicit exit vestibule. The colony-wide gas ledger retains its single existing airlock-cycle accounting path. `main` was fetched during S work and contained no commits missing from `revisions`.
