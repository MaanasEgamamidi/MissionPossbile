# Requirements matrix (cumulative)

Started in Prompt 01 on 2026-11-11; states updated in Prompts 02 to 04 the same day and in Prompts 05 and 07 on 2026-11-12 (Prompt 06 skipped). One row per confirmed requirement. Each row names the input it depends on and the milestone that implements it.

**Basis.** The three governing documents are missing (issue I-01), so every row comes from the Execution Prompt Pack, pages 1 to 12: the shared brief, the engineering contract and the common execution instruction. The pack says those sections record the owner's decisions. When the governing documents arrive, each row must be checked against them and the "Doc check" column filled.

**Milestones.** P01 to P08 are the prompts read in full. P09 (NASA weather), P10 (rover), P11 (voice and radio), P12 (tutorial and campaign), P13 (performance and visual integration), P14 to P16 (playtests and improvement) and P17 (Windows build) are known from the pack's milestone route and section titles only; their text was not read.

**State** is what exists in the workspace today. "None" means nothing in the workspace implements the row. After Prompt 04 the import, lighting, simulation-foundation, save, crew, time, control and camera rows have a Godot state. The map is still a rehearsal on the current map, and everything was checked by automated tests, not by a human player.

Inputs: A1–A3 governing documents; A6 improved map; A7 browser game; A8 Godot port; A9 current Blender scene; S/T ids are entries in `source_register.md`.

## Product and world

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| PW-01 | Five sectors: health and life support; food production; resources and manufacturing; energy; science and research. Communications supports them. | A1–A3 | P07, P08, P09–P12 | All five sectors have working systems: energy and life support (P07), food, resources/manufacturing and science/research (P08). Communications upgrades wait for P11. | Pending |
| PW-02 | One continuous colony world with a small main hub; detailed work at specialist facilities. The owner supplies the improved map. No replacement map, no procedural terrain. | A6 | P01 (request), P02 (import) | Current map imported into Godot as a rehearsal (P02). Improved map not supplied. No hub designated. | Pending |
| PW-03 | Reuse existing spaceship, rover, human, suit, equipment and environment assets. Preserve original Blender files. Derivative rigs, exports, bakes and functional adaptations only. | A9, A12 | P01, P02, P04, P10 | Originals hashed and unchanged after P02. A derivative GLB export of the map exists (P02). A derivative rigged crew member and suit exist (P04); source hashes unchanged after building them. | Pending |
| PW-04 | Construction means upgrading equipment in existing facilities. No new buildings, free placement, terrain editing, extra sectors, autonomous inhabitants, or tasks needing simultaneous players. | — | P08 and all | Construction is equipment upgrades installed at existing stations (P08: 16 cards); no new buildings or placement. | Pending |
| PW-05 | No video or cutscene work. Play starts at the landed spacecraft. The fictional 2080 premise stays distinct from NASA observations and forecasts. | A6 | P12, P05 | Current spawn is the Med Bay (C-09). | Pending |

## Crew and control

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| CR-01 | Four specialists: electrical and communications; medical and life support; biology and food; field engineering and geology. Science is shared. | A12, I-04 | P04, P05, P06 | Four `CharacterState` records with the four specialties exist (P03). One rigged body shared by all four, told apart only by a coloured shoulder patch and chest stripe (P04). No approved character art, portraits or names. | Pending |
| CR-02 | Any character may read instruments, allocate resources, carry supplies, clean accessible solar panels, drive a built rover and use ordinary charging controls. Specialist interventions are marked with a symbol, text, portrait and tool. No facility is locked to one role. | — | P05, P07, P08 | General actions open to all (read instruments, allocate water, clean panels, carry, plant, inspect); specialist steps marked and enforced by the host: cleaner repair (electrical), sampling, part recovery and refurbishing (field engineering), upgrade installs by sector specialist (P07/P08). | Pending |
| CR-03 | Four characters arrive in every mode. One to four humans can join from the start. With fewer than four, a player at the hub may take an unoccupied character at that character's location; the released one stays at its hub spot. With four players switching is off. The host prevents two peers taking one character. | Hub (I-06) | P06 | Service rules implemented and tested without a network (P03): four characters always exist; claim; switch only at the hub and only with fewer than four peers; two peers cannot hold one character. Interim keys 1–4 switch at the hub (P04). No join flow or crew screen yet. | Pending |
| CR-04 | Inactive characters wait at protected hub spots, consume nothing, keep frozen condition, and do no work. Equipment, cargo, health, stamina and suit charge stay with the character through a switch. | — | P03, P06 | Implemented and tested (P03): parked crew consume nothing and keep their condition; cargo, equipment, health, stamina and suit charge survive a switch. Hub spots are at a rehearsal position (I-06). | Pending |

## Time, survival and session

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| TS-01 | Default sol of 20 real minutes with a labelled host setting (default range 5 to 120 minutes). Changing it keeps the current phase and replicates to clients. | S02 | P03, P05, P06 | Implemented and tested (P03): 20-minute default, host-only `set_sol_minutes` 5–120, phase and sol number unchanged, stores unchanged. Replication to clients waits for P06; the labelled setting control waits for P05. | Pending |
| TS-02 | Solo menus pause. Co-op pauses only on unanimous agreement. No offline deterioration. Movement, animation, the one-second suit check, network latency and radio delay do not scale with sol length. Voice stays available while paused. | — | P03, P05, P06, P11 | Implemented and tested at the service level (P03): solo pause at once, co-op pause only when every peer votes, no offline effect, suit check in real seconds. Esc pauses in the playable scene (P04). Latency, radio delay and voice do not exist yet. | Pending |
| TS-03 | Mars gravity everywhere, using the fact sheet's mean 3.73 m/s². Jump and locomotion are retuned for it. | S01 | P04 | Implemented and measured (P04): gravity 3.73 m/s² for the player and for carried props; jump retuned to 0.5 m, 1.0 s in the air; walk 3.0 m/s. Tuning values are designer choices. | Pending |
| TS-04 | At zero condition: recover at the hub, keep suit and signature tools, leave ordinary cargo in one persistent cache at the incident location, charge 0.1 sol of one astronaut's food and water without blocking recovery, show the cost and cache location, do not refill tanks. | — | P03, P07 | Implemented and tested (P03, shown in P04): recovery at the hub, suit and equipment kept, cargo in one cache at the incident position, 0.1 sol of food and water charged without blocking, tank not refilled, cost and cache location shown on screen. What triggers zero condition is a placeholder until P07. | Pending |
| TS-05 | A client's connection loss returns its character and inventory to the hub with no cargo drop and no charge, frees the slot and allows reconnection. Host loss returns clients to the menu. No host migration. | — | P06 | Client loss implemented and tested at the service level (P03): character and inventory to the hub, no charge, slot freed. Reconnection, host loss and the menu wait for P06. | Pending |

## Controls and presentation

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| CT-01 | Bindings: WASD and mouse; Shift sprint; Space jump (brake when driving); E interact; G and left mouse for grab, drop, use, throw; Tab first/third person; M blueprint; V push to talk; Esc close then pause; Shift + Backspace source register; F5 unbound. | — | P04, P05, P10, P11 | All bindings exist with the listed defaults and F5 is unbound (P04, tested). Working now: move, sprint, jump, E, G / left mouse, Tab, Esc. M, V and Shift + Backspace are bound but their features belong to later prompts. Space as rover brake waits for P10. | Pending |
| CT-02 | Remapping and clear input focus. New games start in first person with connected arms and hands, visible torso and legs, matching suit parts. Local head surfaces are hidden by render layers; remote players see the whole character. | Rigged crew (I-04) | P04, P05 | Remapping with save and load exists (P04, tested); no remapping screen yet. Starts in first person; one body in both views; head and helmet hidden from the local camera by render layer 19 (tested). The body is a first-build rigged derivative of the human base mesh and the wall-stowed suit (not yet approved, I-04); a capsule stand-in remains as the fallback. | Pending |
| CT-03 | Third person sits close behind, uses camera collision and never clips through walls. Initial tuning in configuration: 72° FOV, about 2.5 m distance, 20% suit speed reduction (defaults). | — | P04 | Implemented and tested (P04): SpringArm3D with a sphere shape and the player's body excluded; 72° FOV in both views; 2.5 m; suit slows walking by 20 % (measured 2.40 against 3.00 m/s). Values live in `GameConfig`. | Pending |

## Learning and facility progression

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| LP-01 | One progression framework. An upgrade needs the knowledge answers, practical tasks, demonstrated competence and current tier. Paying parts is necessary where parts are consumed but is not enough. Repeating an answer cannot farm progress. | — | P08 | Implemented (P08): eligibility needs tier + knowledge answers + practical evidence + parts + installer at the station; payment alone is not enough; repeating an answer adds nothing. | Pending |
| LP-02 | Upgrades are branching cards naming function, tier, knowledge checks, practical evidence, materials, specialist, location and resulting change. The player sees why a card is locked. | — | P05, P08 | Implemented (P08): 16 branching cards with function, tier, questions, evidence, parts, installer, station, effect and source labels; locked reasons in words; eligible cards shown together. | Pending |
| LP-03 | Tiers 0 to 3 as implementation defaults (unfamiliar; guided task and check; independent diagnosis; controlled comparison or transfer). Knowledge and competence are shared colony progress. | — | P08 | Implemented (P08): tiers 0–3 per sector as shared colony progress; tier 2 needs a diagnosis in a changed example. | Pending |
| LP-04 | Short contextual questions with explanations and retry variants. No health loss for a wrong answer; no mastery for answer count. Terminals show locked requirements, eligible choices, expected effects and the install action separately. | — | P05, P08 | Implemented (P08): 32 contextual questions with explanations and retry variants; no health loss; terminal shows requirements, eligible choices, effects and a separate Install action. | Pending |
| LP-05 | Initial upgrade choices and practical evidence per sector as tabled in the brief (energy; health and life support; food; resources and manufacturing; science and research). Costs and tests are defined in the progression milestone. | — | P08 | Implemented (P08) from the brief's sector table; owner approval of the concrete cards, questions and costs pending (I-52). | Pending |
| LP-06 | Gravity is the same in all facilities; pressure, safe oxygen and dust exclusion are common constraints. Greenhouse nitrogen is crop nutrition; do not enrich the air with nitrogen or prescribe one fertilizer recipe. | S13, S14 (unverified) | P08 | Gravity unchanged everywhere; greenhouse nutrients are crop nutrition (no air enrichment, no single recipe) (P08). No new source checked. | Pending |

## Oxygen

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| OX-01 | Water electrolysis and atmospheric CO2-to-oxygen processing are distinct equipment paths with their own inputs. CO2 removal from cabin air is separate. Oxygen production does not prove habitat pressure. | S08, S09 | P07 | Implemented (P07): electrolyser (water + power) and CO2-oxygen unit (Mars air + power, never water) as separate equipment; CO2 scrubber separate; cabin pressure and safe air tracked apart from the oxygen reserve. 88 model checks. | Pending |
| OX-02 | Separate source labels for ISS life support, the Mars MOXIE experiment and the fictional 2080 installations. Simplifications are labelled; balance numbers are not attributed to NASA. | S08, S09 | P05, P07 | Implemented (P05/P07): ISS (S08), MOXIE (S09) and the fictional colony-scale unit are labelled separately in `model_sources.json`, claims and panels; balance numbers are never attributed to NASA. | Pending |

## Rover

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| RV-01 | One configurable four-seat rover on the approved chassis. Sliders for speed, motor torque, battery range, cargo capacity and traction, showing current and projected stats, part cost, battery state and cargo load effects. Presets may not replace sliders. | Approved chassis (I-05) | P10 | Implemented (P10), headless checks only: one shared rover (sf_rover, parked in sf_print_garage) with five level 1-5 sliders, current and projected stats, part costs, battery state and the effect of the cargo aboard; presets only as explanations. Four seats exist as invisible anchors in a hollow cabin (the model has no seats; I-55). | Pending |
| RV-02 | Five stats, levels 1 to 5, 10 starting parts, step costs 1, 2, 3, 4 (10 per stat, 50 for all). Tunable. No permanent cap. | — | P10 | Implemented (P10): levels 1-5, 10 starting parts (shared `state.parts`), steps 1/2/3/4, no cap. The approved map salvage supplies at most 38 parts against a demand of 102 (facility cards 42, radio 10, rover 50), so all five stats at 5 cannot be reached yet (I-56, owner decision). | Pending |
| RV-03 | Only the field engineer assembles or refits, at the garage, through an assembly challenge. Anyone gathers salvage, drives, rides and charges. Parts are recovered and refurbished hardware. | A6 | P10 | Implemented (P10): only the field engineer assembles or refits, at the garage, through a three-step module/socket/power-load check with changed examples and no penalty. Anyone gathers salvage, loads cargo, drives, rides and charges. | Pending |
| RV-04 | Refitting fully reuses invested parts, preserves stored battery energy, enforces cargo capacity and blocks duplicate refunds. Part locations come from approved map objects. Campaign completion does not need every stat maxed. | A6 | P10 | Implemented (P10): refits reuse invested parts, keep stored energy (clamped and ledgered on a smaller battery, never refilled), refuse stranded cargo, and use a transaction number so duplicates and replays after a load refund nothing. 14 donors are existing damaged map objects (5 from P08, 9 new). | Pending |

## Communications

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| CM-01 | Indoors, proximity speech is immediate, full volume to 5 m, silent by 25 m, with room and door separation. If speaker or listener is outside, radio covers the map. Five radio stages: no link, 30 s, 15 s, 5 s, near-immediate. Upgrades install at the base communications station. | T09 | P11 | Implemented (P11), synthetic tests only: indoors 1.0 to 5 m fading to 0 at 25 m, other rooms only through one open door; either outside -> radio across the map at the stage delay (stage 0: no link, HUD says why); one route per utterance. Not yet tried with real microphones or two computers (I-57). | Pending |
| CM-02 | The delay is damaged-equipment buffering, separate from network jitter and from Earth–Mars light time. No always-on team channel. No recordings. | S15 (unverified) | P11 | Implemented (P11): the delay is the radio's own buffering, fixed per utterance; jitter handling after the schedule, no catch-up; bounded queues; buffers cleared on mute, disconnect and exit; no recordings; no team channel. Card texts say it is not network delay or Earth-Mars light time. | Pending |

## Weather and replayability

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| WX-01 | Ship a verified NASA archive subset; run offline on the last validated data; check for updates at startup and hourly; cache atomically; report observation date and validation status; never call archive data live weather or a forecast. | S03, S04, S05 | P09 | Implemented (P09): verified Jezero bundle (MEDA derived/calibrated pressure, wind, temperature; LMD dust maps), offline by default, background conditional refresh with backoff and atomic cache, pinned snapshot per game; never called live weather or a forecast. | Pending |
| WX-02 | Saved seeds and observation-derived episode variation. A minor teaching event comes first. Escalation stays recoverable. No fixed disaster intervals. | S03, S04 | P09 | Implemented (P09): seeded, observation-derived episodes with varied gaps/durations/severity, saved RNG and queue, minor first event after cleaning is taught, readiness holds, warnings at 2x the walk back to the airlock. | Pending |

## Campaign

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| CP-01 | First sustainable-colony milestone in two to three hours: finish the tutorial, restore five sectors and communications, hold positive reserves for a full sol. Play continues afterwards in the same world. | A1–A3 | P12 | Implemented (P12), headless checks only: ten stages in the supplied order, every objective checked from real state or real actions; certification after stage 10 needs every sector at tier 1, radio stage 1, and one full sol with all essential stores above zero and no rescue; failure restarts the sol, never progress. Pacing is an estimate (30-50 min tutorial, 1.2-2 h milestone); nobody has played it. | Pending |
| CP-02 | Optional mystery about an earlier power, reserve and distribution cascade, told through short records and evidence. Hopeful, non-graphic. No new NPCs, no cutscenes. | A1–A3 | P12 | Implemented (P12): optional first-crew story, 12 records (at most 60 words) on existing damaged objects and consoles, four discoveries plus a final one, labelled fiction with real-science lines; not needed to finish. | Pending |

## Engineering contract

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| EN-01 | Godot 4.7.2 stable with matching Windows export templates; typed GDScript; native scenes and resources; extend the existing port. | T01, T02, A8 | P01, P17 | Engine verified. New project `mars_colony_godot` created (no port to extend, C-01). Templates missing (C-11). | n/a |
| EN-02 | Forward+, PBR, AgX, MSAA, bounded real-time shadows, reflection probes, local dynamic GI; features only where they improve verified views within budget. | T03–T05 | P02, P13 | Forward+, AgX, MSAA 4×, sun shadows and 51 fixture shadows, 15 reflection probes. Dynamic GI replaced by a per-room ambient stand-in (I-31). | n/a |
| EN-03 | Preserved Blender sources to reproducible GLB exports and external Godot materials; bake unsupported procedural detail in derivatives; keep instances, LODs, transforms and terrain colours. | A6, T06, T07, T11 | P02 | Reproducible GLB export and 238 external materials for the current map. Procedural detail approximated in a shader, not baked (I-30). Instances, transforms and terrain colour verified; geometry is the game detail level. | n/a |
| EN-04 | CharacterBody3D for people; SpringArm3D and Camera3D for camera collision; RigidBody3D rover with raycast suspension under Mars gravity. | T10 | P04, P10 | Player: CharacterBody3D with SpringArm3D/Camera3D (P04). Rover (P10): RigidBody3D with six ray-cast wheels, spring/damper suspension and grip from the traction stat under 3.73 m/s2; driven headless on the real map collision (239 m route, 0 flips, wheels down 99.6 %). | n/a |
| EN-05 | Typed state and resources, signals, fixed simulation tick, versioned JSON snapshots under `user://`, atomic replacement, rolling backups. No database or server framework. | — | P03 | None. | n/a |
| EN-06 | Godot high-level multiplayer with ENet. The host validates ownership, position, prerequisites, costs and transactions. Separate channels for reliable actions, motion and voice. | T08 | P03, P06 | LAN Walk shows ENet and a spawner working under 4.7.2. | n/a |
| EN-07 | TwoVoip 6.1 adapter over the ENet session with a pinned, tested build verified on 4.7.2 Windows editor and release. No MQTT. | T09 | P11 | TwoVoip 6.1 (MIT) installed with Windows debug and release libraries; loads in Godot 4.7.2 headless and in the editor's project; the release DLL is included by the trial export. Adapter over ENet channel 2, no MQTT. A real microphone in an exported build is still to be checked (P17). | n/a |
| EN-08 | Native Control and CanvasLayer UI with one shared Theme, containers, focus navigation, icons with text. Reference UI is for study only. | — | P05 | Implemented (P05): native Control/CanvasLayer UI built in code, one shared Theme (`UiTheme`), containers, keyboard focus everywhere, symbols with words. Checked by `UiLayoutCheck` at three sizes; 118 framework checks. | n/a |
| EN-09 | Small NASA/PDS CSV or XML subsets, a validated runtime cache, HTTPRequest background checks and a local provenance register. Play must start without a cloud feed. | S03–S07 | P05, P09 | Implemented (P09): small PDS/LMD subset (29 MB raw), validated runtime cache, HTTPRequest background checks, provenance in the register (W01–W12). | n/a |
| EN-10 | No web frameworks, cloud databases, analytics, AI runtime services or image generation in ordinary gameplay. Licence notices kept for every adopted dependency and asset. | L01–L04 | all, P17 | One licence ambiguity (C-19). | n/a |
| EN-11 | Node responsibilities as listed in the contract; consult the pinned class reference before using a node or property. | T03–T10 | all | — | n/a |

## State interfaces

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| ST-01 | Split the legacy gameplay script into bounded services with a compatibility facade; keep station identifiers stable; keep working tests. | A8 | P03 | Implemented (P03): bounded services (config, state, clock, simulation, actions, session, saves, events, glue) and `LegacyStations` as the facade. Station ids are the map object names and are stable. 172 automated checks. | n/a |
| ST-02 | Types: GameConfig and GameBalance; ColonyState and CharacterState; ActionRequest and ActionResult; UpgradeDefinition; SourceRecord and DataSnapshot; SaveGame; signals for state, objective, weather, upgrade eligibility and crew ownership. | — | P03 | All listed types exist (P03). `UpgradeDefinition`, `SourceRecord` and `DataSnapshot` are field lists only; `SaveGame` is the envelope written by `SaveService` plus the payload built by `GameServices.snapshot()`. | n/a |
| ST-03 | 5 Hz colony tick and 60 Hz physics (defaults to profile). Host snapshot every 60 real seconds, after important transactions and on orderly exit. A corrupt newest snapshot falls back to an intact one. Explicit migrations. | — | P03 | Implemented and tested (P03): 5 Hz tick, autosave every 60 real seconds, save after important transactions and on orderly quit, fallback to an intact older file, explicit migration steps. Tick rate not profiled on the target laptop. | n/a |

## Scientific data policy

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| SD-01 | NASA/PDS first. Match target, site, season, instrument, units and processing level. Never use Earth land-surface temperature for Mars, Reddit for science, or DONKI events as a measured Mars surface dose. | S01–S07 | P01, P09 | P09 data matched to target, site (Jezero), season (Ls), instrument, units and processing level; flags and missing values handled; register entries VERIFIED only for files opened. | n/a |
| SD-02 | Source-specific quality rules. Keep measured, modelled, ISS or Earth analog, technology study, fictional equipment and game tuning distinct. | — | P05, P09 | Evidence category per source and per claim, shown in words in the game (P05). | n/a |
| SD-03 | Fetch without blocking play: conditional requests, timeouts, bounded products, backoff. Pin a data snapshot per run; adopt new data at the next session. The host distributes the snapshot id and weather events. | — | P09 | None. | n/a |
| SD-04 | Shift + Backspace opens a searchable source screen: claim, child-readable explanation, institution or mission, data dates, evidence category, clickable primary source, plus a separate note on game-time conversion or fictional scaling. Credits and licences included. | `source_register.md` | P05 | Implemented (P05): Shift + Backspace opens the searchable register from anywhere; claims with plain explanation, institution, dates, units, evidence category in words, status ("not yet checked" for leads), a link opened only on request; game-time and fiction marked; credits screen. Works offline (76 checks). | n/a |

## Lighting and performance

| ID | Requirement | Depends on | Milestone | State 2026-11-11 | Doc check |
| --- | --- | --- | --- | --- | --- |
| LT-01 | Lighting matching is the first visual task after import. References come from the improved map's own Blender scene with its authored cameras, projection, aspect, resolution, exposure, colour management, light state and time of day. | A6 | P02 | Still blocked for the final map. Protocol rehearsed on the current map in P02. | n/a |
| LT-02 | Per reference camera: a converged Cycles image and a Godot capture with overlays off and the same state, at 1920 × 1080 where the camera supports it. Parameters go in a camera manifest. Cover every major room and exterior plus day/night, powered/unpowered, suit and rover views. | A6, `camera_manifest.json` | P02, P13 | 15 rehearsal pairs at 1920 × 1080 on the current map (`camera_pairs.json`). No night, unpowered, suit or rover reference. Four rooms lack a hero camera. | n/a |
| LT-03 | 100-point rubric (brightness and contrast 30, colour and white balance 25, shadows and contact 25, reflections and transmission 15, atmosphere and haze 5). Target 95 per view, stated as a rubric score. SSIM and luminance differences reported separately. Three calibration passes, then list the shortfalls. | — | P02, P13 | Rehearsal scores 60 to 77, mean 69.1, none at 95. Three passes run. Metrics reported separately (I-29). | n/a |
| LT-04 | AreaLight3D used selectively. No arbitrary wattage-to-energy conversion presented as calibration. Day/night and switchable sources stay out of permanent lightmaps. | T03, T04 | P02 | 39 AreaLight3D and 378 SpotLight3D. Energies are fits to the references and labelled so. No lightmaps; fixtures and sun are dynamic and switchable. | n/a |
| LT-05 | 60 FPS at 1080p on the available Windows laptop, including dust, rover motion and four players. Record CPU and GPU frame time, p95 and p99, draw calls, memory counters and process memory; run capped and uncapped. Keep spatial rock tiles, detail transitions, collision connectivity, terrain colours and transparent dome glass unless evidence requires a change. | Target machine (C-10) | P13 | No performance test. Capture-time GPU 9 to 28 ms per static view on a desktop; 5 of 15 over 16.7 ms (I-32). Target laptop unidentified. | n/a |

## Common execution rules

| ID | Requirement | Milestone | State 2026-11-11 |
| --- | --- | --- | --- |
| CE-01 | Inspect actual files and the current handoff before changing anything; preserve sources and unrelated edits; implement only the current milestone; ask when a conflict, missing asset or new product decision affects the result and continue independent work. | all | Followed in P01. |
| CE-02 | Scope discipline: no NPCs, levels, cinematics, extra modes, new buildings, unrelated survival meters, public services or speculative databases; do not restyle Blender assets. | all | Followed in P01. |
| CE-03 | Run relevant checks, exercise gameplay through real input where required, inspect screenshots, record environment and versions. State what was automated, walked, visually reviewed and observed by humans. Fabricate nothing. | all | P01 checks are labelled automated. No human playtest. |
| CE-04 | One handoff per milestone, plus a cumulative requirements matrix, source register, change decisions and issue list under the project documentation. | all | Kept under `G:\nasa app\docs\` until 2026-11-12, now `G:\nasa app\mars_colony_godot\docs\` (E-25); updated in every milestone. |

## Exclusions recorded in the pack

New buildings; free placement; terrain editing; extra sectors; autonomous inhabitants; tasks requiring simultaneous players; video and cutscenes; new NPC inhabitants; automatic host migration; accounts, matchmaking, paid hosting; an always-available team voice channel; stored voice recordings; web frameworks, cloud databases, analytics SDKs, AI runtime services; image generation in ordinary gameplay; motion blur, forced head bob, combat features, floating-hands view; fixed disaster intervals and catastrophic first storms; a dozen crop meters.

## Coverage check

62 requirements. Every row names a milestone. Rows whose input is missing today: PW-02, LT-01, LT-02 (A6); CR-01, CT-02 (I-04); RV-01, RV-03, RV-04 (I-05, A6); EN-01, ST-01 (A8); LT-05 (C-10). All rows marked "Pending" in "Doc check" wait for A1–A3.
