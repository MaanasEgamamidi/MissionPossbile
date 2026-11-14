# Prompt 12: tutorial graph, campaign checks, pacing log and story outline

Draft by worker P12, 2026-11-14, for the executor to place in `docs\milestones\12_tutorial_campaign\`.
Everything below was checked by **synthetic headless tests only** (`tests\test_tutorial.gd`). No person has played it.

## 1. Objective and learning dependency graph

Data: `data\tutorial.json`. Host logic: `scripts\sim\tutorial_system.gd`. Every check reads the real colony state or a
real action seen inside the action pipeline (`TutorialActions` wraps the watched actions' `apply`). Stages run in order;
inside a stage the objectives complete in order. A real action of the *current* stage done early is credited when its
objective opens; work from another stage never counts. A knowledge step the colony already knows is skipped (mastered).

| Stage | Teaches (control / procedure) | Objectives, in order (kind: what the host checks) | Needs from earlier |
|---|---|---|---|
| 1 Arrival and movement | WASD, mouse look, Shift, Space, Tab, M | `arrival_walk` moved: any active crew 8 m from where the step opened · `arrival_suit_rack` near: within 3 m of `al_suit_rack` | — |
| 2 Airlock interaction | E, suit check (1 s), airlock doors, suit tank | `airlock_suit` suit_on (real `begin_suit_check`) · `airlock_out` outside, same crew member (`CharacterState.outside` from the host's zone test) · `airlock_in` inside, same crew member | 1 (rack found) |
| 3 Hub monitoring and crew selection | hub, crew screen C, colony summary | `hub_go` at_hub (`GameConfig.hub_position`, `hub_radius_m`) · `hub_specialist` specialist_played ⚡ (solo: switch at the hub if needed; four players: automatic, names who) · `hub_reserves` knowledge `energy_q_battery_night` (real `answer_question`) | 2 |
| 4 Solar maintenance | cleaning (anyone), cleaner repair (⚡ only), dust → output | `solar_clean` action `clean_panel` · `solar_cleaner` cleaner_ok (condition ≥ `equipment_min_condition`) ⚡ · `solar_why` knowledge `energy_q_dust_output` → **Energy tier 1** | 2 (suit, airlock), 3 (⚡ chosen) |
| 5 Energy distribution | power panel supply/demand/battery, room circuits, machines draw power, shedding order | `energy_predict` knowledge `energy_q_net_power` (at the power panel; records `energy_predict_net_power`) · `energy_switch_off` action `set_zone_power` on=false, a non-critical room · `energy_oxygen_on` both oxygen makers on + electrolyser feed > 0 · `energy_two_paths` knowledge `ls_q_two_paths` (→ Life support tier 1 once both makers ran 1 h) | 4 (power concepts) |
| 6 Greenhouse operations | plant, water allocation, grow-light load, inspect | `greenhouse_plant` action `plant` (❀ expert cue, anyone) · `greenhouse_water` allocation ≥ 0.5 L/h · `greenhouse_inspect` action `inspect_bed` on a living bed · `greenhouse_light` knowledge `food_q_light` | 5 (loads, allocations) |
| 7 Personal health and body energy | health, stamina ≠ electricity, suit refill from the O₂ reserve, recovery | `health_exercise` action `exercise` · `health_suit` refill_suit seen, or every active tank ≥ 95 % | 2 (suit tank) |
| 8 Communications | comms console, radio stages (equipment buffering, not network or light time), cards | `comms_go` near `cm_comms_console` ⚡ cue · `comms_install` `CommsStage.stage(state) >= 1` ⚡ | 3–5 (cards, questions) |
| 9 Independent greenhouse-power problem | stage 5 reasoning in a changed form | `challenge_fix` the injected fault is fixed now · `challenge_hold` fixed continuously for 1 game hour | 4–6 |
| 10 Back to the hub, then explore | planning at the hub, field work | `explore_hub` at_hub · `explore_engineer` specialist_played ⛏ (solo: hub switch) · `explore_field` action `inspect_donor` or `take_sample` | all |

Specialist cues (`TutorialSystem.specialist_cue`): "You are the … specialist" / "The … specialist (played by another
player) does this step" / with one to three players and nobody playing it: "Switch at the hub crew screen (C)" / with
four players: "Ask the player of that crew member" — never a switch. Objectives with a switching text have a
`text_team` (and `hints_team`) for four players; the test checks every four-player text, hint and cue.

Hints: after 75 real seconds without progress, one more every 60 s, and one per request (H or the journal); progress
resets them; pause stops the clock. Stage 9's hints come from its variant and escalate from a question to the fix.

Mastery: an explanation is skipped when its question is in `state.knowledge` or its stage was already done in this
colony; a reminder (`tutorial_replay`, from the journal) always shows it. Reminders tick their own copy of the
objectives and record nothing else.

### Stage 9 variants (chosen by `variant_for_seed(state.rng_seed)`, a fixed integer mix)

| Variant | Injected (real state) | What the players see | Real fix | Why it is the stage 5 reasoning in a new form |
|---|---|---|---|---|
| `greenhouse_breaker` | `zones.Greenhouse.powered = false` | grow lights dark, beds stop growing, `leggy_pale` | `set_zone_power` Greenhouse on (power panel) or `set_grow_lights` on | a circuit switched off is not the same as no power |
| `trackers_stopped` | `equipment.trackers.on = false` | solar output lower; the 9 kW grow lights take more from the battery | `set_equipment` trackers on (power panel) | a supply problem, not a demand problem |
| `lighting_overload` | every non-critical room light on, Greenhouse off; a fiction "lighting line" breaker re-opens the Greenhouse circuit while room lights > 3.5 kW | the grow lights keep switching off | switch off empty rooms (≥ 1.7 kW), then Greenhouse on | priority: grow lights matter more than empty rooms |

All three only switch lights or trackers: nobody can be harmed (test: two sols unsolved, no health change, invariants
hold). Seeds 1, 2 and 3 give two different variants; all three occur among seeds 1–40. The fault is injected once
(the flag is saved); a reminder never injects it again.

## 2. Campaign completion checks (first milestone)

Rule (`TutorialSystem._step_certification`):
1. **Locked** until the tutorial is done.
2. **Waiting** until every sector operates — rule: `ProgressionSystem.tier(state, sector) >= 1` for energy, life support,
   food, resources and science (tier 1 = that sector's guided practical task plus its explanation question; tiers never
   go down) — and communications operate (`CommsStage.stage(state) >= 1`).
3. **Running**: counts game hours while the battery, clean water, oxygen and food are all above zero.
4. **Restart** (progress kept): a store at or below 1e-6 (checked every tick, after every watched action, and for food at
   the end of the last tick, because food is eaten after the post-systems run), or an emergency recovery
   (`events.character_recovered`). While a store is empty the status is **paused_reserve**; it runs again from zero once
   the stores are above zero.
5. **Complete** after one full sol (`GameConfig.SOL_HOURS`) of running. It never reverts; everything keeps working
   (blueprint, sources, upgrades, exploration, weather, save/load). The mystery and a maximised rover are not needed.

What a group still needs is shown on the tracker and in the journal (`requirements_missing`, `campaign_tips`).

## 3. Initial balance and pacing log (estimates, NOT measured)

No playtest exists. These are the designer's estimates for a first-time player aged 9–12 at the default 20-minute sol.

| Part | Estimate | Game time | Notes / risks |
|---|---|---|---|
| Stages 1–3 | 6–10 min | ~0.4 sol | Hub is a rehearsal position in the Med Bay (I-06); the colony computer is in the Command Room, so stage 3 walks there. |
| Stage 4 | 4–6 min | | Outside walk to the trackers; energy tier 1 here. |
| Stage 5 | 5–7 min | | Two rooms (Power Room, Life Support). |
| Stage 6 | 4–6 min | | Garden dome and Greenhouse console are in different rooms. |
| Stage 7 | 2–3 min | | Refill auto-completes if nobody's tank needs it. |
| Stage 8 | 3–8 min | | Depends on P11's `comms_radio_1` requirements (not in this copy). |
| Stage 9 | 3–6 min | +1 game hour hold (≈ 49 s) | Hints after 75 s. |
| Stage 10 | 2–3 min | | |
| **Tutorial** | **≈ 30–50 min** | **≈ 2 sols** | |
| Remaining sector tier 1 (food symptom, salvage, sample) | 15–30 min | ~1 sol | The food symptom needs a real symptom (stage 9 breaker/overload variants create one; otherwise nutrients run low near the end of a lettuce cycle). |
| Certification sol | 20 min | 1 sol | No forced waiting: players can upgrade, explore, salvage, drive meanwhile. |
| **First milestone** | **≈ 1.2–2 h** (estimate) | ≈ 4–5 sols | The 2–3 h target includes optional upgrades, rover and exploration; only playtests (P14) can tell. |

Food balance risk: 96 starting meals; one crew member eats 3 per sol. Solo: 32 sols. **Four players: 12 per sol → 8
sols (≈ 2 h 40 min)**. The tracker shows "plant more beds" when food drops below three sols. A lettuce bed gives 5 meals
per 3 sols, so a four-player group needs several beds well before sol 8. Unchanged here (not P12's balance); flagged.

## 4. Story outline: the first crew's power cascade (optional)

Premise (fiction, `data\lore.json`): in 2079 the first crew left because many small power problems failed together;
all four went home safely and put the base to sleep for the next crew. No remains, no aliens, no NPC, no cutscene.
12 records (each ≤ 60 words, counted by the test) on existing damaged objects and consoles; found by real actions.

| Discovery | Clue records (station, action) | Real science it touches (category) |
|---|---|---|
| A smaller battery than planned | Battery rack alarm (`pr_bat_rack_alarm`, inspect_donor) · Night shift note (`pr_fsp_console`, read_record) · Cargo lander record (`sf_crash_tank`, inspect_donor) | damaged cells taken out of use (general principle) · sol 24 h 39 min (S02) · Mars gravity 3.73 m/s² (S01) |
| Dust and a jammed cleaner | Solar junction box tag (`sf_junction_box`, read_record) · Greenhouse screen (`gr_w_hab_screen`, read_record) | dust in the air dims sunlight (W10 dust maps) · lettuce in Veggie on the ISS (S11) |
| Too much on one line | Switchgear incident card (`pr_swgr_burnt`, inspect_donor) · Panelboard sticker (`pr_panelboard`, read_record) · Old air filter tag (`ls_filter_old`, inspect_donor) | breakers stop wires overheating (general principle) · load order is a game rule · ISS CO₂ removal (S08) |
| Everyone went home safely | Command log (`cr_console_alarm`, inspect_donor) · Airlock log (`ak_terminal`, read_record) · Final health check (`mb_ct_console`, read_record) | radio delay = damaged equipment buffering (game rule) · airlock air loss (game balance) · food growing on the ISS (S11) |
| **The cascade, solved** (final) | the four discoveries above; plus the Handover note (`cr_console.001`, read_record) | the chain battery + sunlight + load (game summary) |

Every record carries "Fiction: a record left by the first crew (2079)."; every cited id is a VERIFIED register entry
(checked by the test); lines without a source say they are a game rule or a general principle. Developer or community
narrative advice was not used and is not evidence.

## 5. Genuine remaining content gaps

1. **Arrival at the landed spacecraft (C-09, PW-05) is not done.** New games still start at the hub (Med Bay). Moving the
   spawn to `ex_lander` needs `GameServices.start_new_game` (not P12's file) and an owner decision; stages 1–2 would then
   need a small data change (see NOTES.md).
2. **The hub is still a rehearsal position (I-06).** "Hub monitoring" uses the colony computer in the Command Room.
3. **Stage 8 depends on P11** (`comms_radio_1` must be installable with what stages 1–7 earn).
4. **No voice-over, no localisation;** all text is English for ages 9–12, not checked with children.
5. **The station cue on the HUD says "Use station"** for data-file kinds (record, bed, salvage); GameHud's name list is not
   P12's file.
6. **Remapping:** H (hint) and J (journal) work as fixed keys until PlayerInput gets the two actions.
7. **Story locations are not checked in a 3D view** (record stations sit on the objects' origins, as all stations do).
8. **Pacing and difficulty are estimates.** Hint timing (75/60 s) and the stage 9 hold (1 game hour) need playtests.
