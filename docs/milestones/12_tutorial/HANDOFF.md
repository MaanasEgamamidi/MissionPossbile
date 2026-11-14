# Milestone handoff — Prompt 12: Tutorial campaign and optional narrative

Date: 2026-11-14. Project: `G:\nasa app\mars_colony_godot`. Built by one Claude subagent (P12, also the lore specialist) from `docs\workers\SPEC_P10_P12.md`, then merged by the executor. Worker report: `workers\P12_NOTES.md`. Dependency graph, pacing log, story outline and content gaps: `TUTORIAL_GRAPH.md`.

**Checks were headless only.** Scripted runs used real actions on the real model. Nobody has played the tutorial, so the pacing figures are estimates.

## 1. Outcome

- **Ten stages in the supplied order** (`data\tutorial.json`, `TutorialSystem`):
  1. Arrival: walk 8 m, then reach the suit rack.
  2. Airlock: the real suit check, then out and back in by the same crew member.
  3. Hub: be at the hub, someone plays the electrical specialist, answer a battery-at-night question.
  4. Solar: clean a panel, the electrical specialist repairs the cleaner, answer a dust question. This earns Energy tier 1.
  5. Energy distribution: a net-power question at the power panel, switch off a non-critical room, both oxygen makers on with feed water, answer a two-paths question.
  6. Greenhouse: plant, water at least 0.5 L/h, inspect a living bed, answer a light question.
  7. Health: exercise, then refill the suit tank (or every tank is already at 95 % or more).
  8. Communications: reach the comms console and install radio stage 1 with real actions (Prompt 11's card).
  9. An independent problem: one of three greenhouse-power faults, chosen from the colony seed and fixed with stage 5's reasoning in a new form:
     - the Greenhouse circuit is switched off;
     - the sun trackers are stopped;
     - room lights overload a made-up breaker.

     All three are harmless if left: two sols unsolved change nobody's health. The fault is injected once and not again after a save or load.
  10. Back to the hub and on to exploration: the field engineer inspects a salvage donor or takes a sample.
- **How objectives are checked:** only from real state or real actions. `TutorialActions` wraps the watched actions' `apply` without changing what they do or answer. Inside a stage, objectives complete in order; a real action done early is credited when its step opens.
- **Hints and cues:**
  - A hint appears after 75 s without progress, then every 60 s; N gives one on request. L opens the colony journal (H and J belong to the mission HUD, E-46).
  - Explanations already mastered are skipped. Stages can be replayed as reminders without double-counting.
  - With four players nobody is ever asked to switch crew; the cue names who should act. With one to three players a switch cue appears only when nobody plays the specialist needed.
- **Certification** (first campaign milestone):
  - It unlocks after stage 10.
  - It needs every sector at tier 1 or more and radio stage 1 or more.
  - It then needs one full sol with battery, water, oxygen and food all above zero and no emergency rescue.
  - A failure restarts the sol, never progress. Once complete it never reverts, and play continues.
- **Optional story:** the first crew left in 2079 after a smaller battery, a jammed cleaner, a dusty sky and too many loads on one line failed together; all four went home safely and left notes.
  - 12 records of at most 60 words: five found by inspecting salvage donors, seven at existing consoles and boxes (`data\lore.json`, `data\stations_lore.json`).
  - Four discoveries plus a final one, kept in `state.discoveries`.
  - Every record is labelled fiction, and its science line cites a register source (S01, S02, S08, S11, W10) or says it is a game rule.
  - No aliens, NPC helper, new level or cutscene. Solving it is never required.

## 2. Acceptance (`tests\test_tutorial.gd`, 59 checks)

| Check | Result |
|---|---|
| New solo run reaches free exploration | Yes, using only real actions with hub crew switches, including the real install of radio card 1 after the merge |
| Four-player onboarding | No objective asks for a switch; no step needs two players at once |
| Objective order | Enforced; work from another stage never counts |
| Repeatability | Replays record nothing twice |
| Hints, skip of mastered explanations | Timing and skipping checked |
| Save/load at every stage boundary | Resumes the same stage and objectives |
| Stage 9 changed example | Chosen per seed: seeds 1–3 give two different variants, all three occur in seeds 1–40; each one solvable |
| Certification reset | A rescue or an empty store restarts the sol; progress kept |
| Continued play after completion | Yes |
| Story | Records found once; optional (the solo run finished with 1 of 12) |

## 3. Merge changes (executor)

- The test's stand-in for radio card 1 was removed: the solo and four-player runs now install the real card.
- N (hint) and L (journal) are remappable input actions (H and J were taken by the mission HUD, E-46).
- `TutorialActions` stays registered after every other part's actions, and `RoverActions` before it.

## 4. Limits

1. Play starts at the hub, not the landed spacecraft (PW-05, C-09). This needs an owner decision; see `workers\P12_NOTES.md` for the change it would take.
2. The hub is still the rehearsal point (Med Bay), so the stage 3 question is answered at the Command Room computer.
3. Four players have 96 meals, which last 8 sols (about 2 h 40 min at 20 min per sol). The tracker warns below three sols; the balance is unchanged.
4. Pacing is an estimate (30–50 min tutorial, 1.2–2 h to the milestone); nobody has played it (I-58).
