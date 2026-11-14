# Worker specification — Prompts 10, 11 and 12 (four parallel workers)

Date: 2026-11-13. Executor: the main Claude session. Workers: four Claude subagents, each in its **own project copy**
(`G:\nasa app\_work\<worker>\`). The executor merges by copying each worker's owned files back, three-way merges the few
shared files, wires the presenters into the game scene and re-runs every suite.

## 0. Rules for every worker (read all of this first)

1. **Project facts.** Godot **4.7.2** (console exe `C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`,
   or `G:\nasa app\_work\godot.cmd`). Typed GDScript. Ages 9–12 co-op Mars colony game. Read
   `docs\README.md`, `docs\requirements_matrix.md`, `docs\milestones\08_food_science_upgrades\HANDOFF.md`,
   `docs\milestones\09_weather\HANDOFF.md`, and the pack text `docs\workers\PACK_P10_P17.txt` (Prompts 10–17 and the
   brief's rover, communications and campaign paragraphs; the copy in your folder).
2. **Headless only.** Run tests and tools with `--headless`. Never open a window, never run the game windowed, never use
   the Godot or Blender MCP (another session drives the editor). The owner tests run time and gameplay.
3. **Work only inside your copy.** Never write to `G:\nasa app\mars_colony_godot` or another worker's copy. Never use git.
   Never download anything; everything needed is in your copy (`addons\twovoip` is already installed).
4. **File ownership.** Create and edit only the files your section lists as yours. For a shared file marked
   "shared (small edit)", keep the edit to the lines named. If you need something from a file you do not own, write it in
   `NOTES.md` under "Requests for the executor" instead of editing it.
5. **Existing architecture (follow it, do not replace it):**
   - Host authority: only `SessionService` changes `ColonyState`, through the 5 Hz tick (`ColonySim.step` with
     `pre_systems` / `post_systems`) or a validated action (`ActionService.Definition`, registered in
     `SessionService._init`). Clients call `GameServices.request(action, target, params)`.
   - Every action that changes the colony is an `ActionService.Definition` with checks for actor, distance
     (`config.interact_distance_m`), specialty and prerequisites. Repeated request ids are already de-duplicated.
     Mark save-worthy actions `important = true`.
   - Per-part state is plain JSON in `ColonyState` (`rover`, `science`, `progress`, `crops`, `weather`, `campaign`, …).
     It is saved and replicated (full state 5 Hz on channel 0). Do not add Objects to the state.
   - Practical evidence: `ProgressEvidence.record(state, events, id, sector, actor, detail)`.
   - Stations come from `data\stations_<part>.json` (`StationCatalog.extra_entries`); a station panel for kind `k` is
     found by convention at `res://scripts/ui/stations/<k>_station_panel.gd` extending `StationPanel`.
   - UI: native Control nodes through `UiRoot` / `UiPanel` / `UiTheme`; panels must fit 1280×720 (see `UiLayoutCheck`
     and `tests\test_station_panels.gd`). Plain words for ages 9–12. Specialist steps show the specialist symbol and text.
   - Every number is either a cited scientific value (source register) or labelled game balance with its category, in
     a `data\model_sources_<part>.json` file like the existing ones. Do not present invented values as NASA data.
   - E is the default key for every interaction (`interact`). Controls in `scripts\player\player_input.gd`.
   - GDScript gotchas met before: no variable named like a class; typed loops `for x: T in`; `var x: T = dict[...]`
     for Variants; JSON numbers are floats; node names cannot contain "."; after adding a `class_name` script run
     `--headless --import` once.
6. **Tests.** Add your own suite(s) under `tests\` following the existing pattern (`extends SceneTree`, a `check()`
   helper, a final `RESULT passed/total` line, exit code 1 on failure — copy the skeleton from `tests\test_weather.gd`).
   Before you finish, run in your copy:
   - `tools\run_tests.ps1 -Import -Tests <your suites>,test_saves,test_session,test_game_services,test_progression,test_science,test_life_support,test_net,test_net_game,test_station_panels`
   - the compile check: `--headless --path . --script res://tools/godot/check_compile.gd` → must print `COMPILE OK`.
   Every suite must pass. Do not weaken an existing check to make it pass; if an existing check is wrong for a reason
   your work makes true, change it minimally and explain it in NOTES.md.
7. **Honesty.** Synthetic tests are labelled synthetic. Nothing is "verified with players" or "measured on hardware"
   unless it was. Do not claim real microphones were used. Anything you could not do goes in NOTES.md under "Limits".
8. **Deliver** `NOTES.md` in your copy's root: what you built (files), design decisions, numbers and their categories,
   test results (suite → passed/total), limits, requests for the executor (exact text of any edit you need in a file you
   do not own), and what the executor must wire into `scripts\game\game_main.gd` (exact code).
9. **Presentation nodes.** Do not edit `game_main.gd`, `game_hud.gd` or `ui_root.gd`. Put your scene-side code in your
   own Node (a "presenter") with `func setup(world: Node3D, services: GameServices, game: Node) -> void`; the executor
   adds it in `GameMain._begin_play()`. A HUD widget is your own Control that your presenter adds under the `GameHud`
   node (`game.hud`), anchored so it does not overlap the existing HUD (top-left status, bottom-centre messages,
   centre crosshair/target).

## Shared interfaces already written by the executor (do not change their signatures)

- `scripts\vehicle\rover_model.gd` — `RoverModel` (STUB; **owned by worker P10A**, who replaces the bodies and may add
  functions). Fixed signatures: `ensure(state)`, `step_cost(level)`, `invested(levels)`, `stats(levels, cargo_kg)` with
  keys `top_speed_mps, drive_force_n, battery_capacity_kwh, cargo_capacity_kg, traction_mu, mass_kg, range_km`,
  `energy_kwh_for_move(levels, cargo_kg, distance_m, climb_m)`, `cargo_mass_kg(state)`. `state.rover` schema is in its
  header comment: `built, levels, battery_kwh, cargo, seats[4] (index 0 driver), pose {position, quat}`.
- `scripts\voice\comms_stage.gd` — `CommsStage` (**owned by worker P11**). `stage(state) -> 0..4`, `delay_seconds(stage)`
  (−1 = no link, 30, 15, 5, 0). Card ids `comms_radio_1` … `comms_radio_4`, installed in order.
- `ColonyState.campaign := {}` (saved and replicated) — **owned by worker P12**.
- `NetSession` (`scripts\net\net_session.gd`), already extended:
  - `send_voice(packet: PackedByteArray, reliable := false)`; signal `voice_packet_received(from_peer, packet)` on every
    receiving machine (the host relays clients' packets to the other clients, channel 2). Packets ≤ 4000 bytes.
  - `send_motion_extra(key: String, value)` (client → host, unreliable, channel 1); host signal
    `motion_extra_received(sender, key, value)` (the receiver checks the sender may set it); host property
    `motion_extras_provider: Callable` returning `{key: value}` broadcast ~20 Hz; client signal `motion_extras_received(extras)`.
  - `PROTOCOL` is 2, three ENet channels.

## Fixed ids used across workers

| Thing | Id | Owner |
|---|---|---|
| Garage configurator station | kind `garage`, on the map object of the garage the rover uses (P10A decides, see below) | P10A |
| Rover charger station | kind `rover_charger` | P10A |
| Rover actions | `rover_preview` (none needed; preview is local), `rover_assemble`, `rover_refit`, `rover_enter` (params `{"seat": int}`), `rover_exit` (params `{"exit_index": int}`), `rover_load_cargo` (target item), `rover_unload_cargo` (target item), `rover_set_charging` (params `{"on": bool}`) | P10A |
| Host-side drive accounting | `RoverSystem.note_driven(state, events, distance_m, climb_m) -> float kWh used` | P10A |
| Rover geometry data | `data\rover.json`: model object name, wheel local positions/radius, seat local positions (4), exit local positions (≥ 4), cargo bay box, garage park pose | P10B |
| Rover body node | `RoverBody` (`scripts\vehicle\rover_body.gd`, RigidBody3D) and `RoverPresenter` | P10B |
| Comms upgrade cards | `comms_radio_1..4` in `data\upgrades.json`, sector key of communications as P11 decides, install station kind `comms` (the existing communications station), specialty `electrical_comms` | P11 |
| Voice presenter | `VoiceService` (`scripts\voice\voice_service.gd`) | P11 |
| Tutorial | `TutorialSystem` (`scripts\sim\tutorial_system.gd`, a post-system), `data\tutorial.json`, `TutorialPresenter` | P12 |
| Story records | `data\lore.json`, kind `record` stations in `data\stations_lore.json` | P12 |

---

## Worker P10A — rover economy, salvage supply, garage configurator (Prompt 10, part 1)

Copy: `G:\nasa app\_work\p10a`. You own: `scripts\vehicle\rover_model.gd` (fill in), new `scripts\vehicle\rover_system.gd`,
new `scripts\session\rover_actions.gd`, new `scripts\core\rover_balance.gd` (designer values, `@export`), new
`data\stations_rover.json`, new `data\model_sources_rover.json`, new `scripts\ui\stations\garage_station_panel.gd`,
new `scripts\ui\stations\rover_charger_station_panel.gd`, new `tests\test_rover.gd`. Shared (small edit):
`data\salvage.json` and `data\stations_science.json` (add donors only, do not change the five existing ones),
`scripts\session\session_service.gd` (one `RoverActions.register(actions)` line and one
`sim.post_systems.append(RoverSystem.new())` line), `scripts\state\colony_state.gd` (only if needed for the rover
ledger key, below), `scripts\session\science_actions.gd` (only if a new donor needs it; prefer data only).

1. **Pick the garage and the rover object from the map, with evidence.** The map has `sf_print_garage` with `sf_rover`
   beside it (Exterior) and `hb_rover` inside the Hangar (`data\colony_manifest.json`; Blender coordinates, Godot =
   (x, z, −y)). Choose the drivable rover and its garage from the map (P10B decides the body from the same evidence;
   agree through the fixed ids: the garage station sits on the garage object you choose, near the rover's park pose
   in `data\rover.json`). Record the choice and why in NOTES.md. Do not add new meshes.
2. **Salvage supply.** The approved rule: start with 10 usable parts (`state.parts`, shared with facility upgrades);
   rover steps cost 1/2/3/4 parts per stat (10 per stat, 50 for all five at level 5); refits fully reuse invested parts.
   Count the supply (start + every compatible donor part, each yields one spare part after refurbish + bench test in the
   existing P08 flow) against demand (all 16 facility cards' `cost_parts` in `data\upgrades.json`, the 4 comms cards
   P11 adds at 1, 2, 3 and 4 parts, and the rover's 50). Add donors **only from damaged or derelict objects that exist
   in the map** (candidates found: `sf_crash_stage`, `sf_crash_shield`, `sf_crash_debris_a/b/c`, `pr_bat_hv_alarm`,
   `pr_bat_rack_alarm.001`, `pr_bat_rack_alarm.002`, `mb_crash_cart`, `ls_manifold`, `rf_tile_*_dead`, `ex_lander`,
   and the non-drivable rover if one is derelict; check each in the manifest and say why it is a credible donor).
   Mechanical/electrical parts that a rover could use (wheel hub motors, bearings, cable harness, battery modules from
   a healthy rack, suspension arms) are fine; raw rock never becomes a part. Each donor keeps compatible and
   incompatible parts with clues like the existing five. Write a supply/demand table in NOTES.md and in
   `data\model_sources_rover.json`. If the map cannot supply everything, **flag the shortfall** (do not spawn debris).
   The campaign must not need a maximised rover.
3. **RoverModel** (fill the stub). Levels 1..5 per stat; curves are labelled "fictional game tuning supported by real
   principles" (more motor power → higher top speed; more torque → climbing and acceleration with load; more battery →
   capacity; traction → tyre/ground friction coefficient; cargo → capacity in kg and **never** passenger count).
   Energy per metre grows with total mass (rover + crew 4 × suit mass + cargo) and with climbing (m·g·h with Mars
   g = 3.73 m/s², source S01, at a stated drivetrain efficiency). `range_km` is honest: from the current stored energy,
   the actual cargo and crew aboard and a terrain factor; say what it assumes. Put every tunable number in
   `RoverBalance` (`config` resource like `science_balance.gd`), with categories in `model_sources_rover.json`.
4. **Actions** (`RoverActions`, all host-validated; distance checks to the rover's `pose` or the garage station):
   - `rover_assemble` (first build) and `rover_refit`: params `{"levels": {stat: int}, "challenge": {...}}`.
     Field engineer (`field_engineering_geology`) only, at the garage station. Cost = `invested(new) − invested(old)`
     (negative = parts returned to `state.parts`); refused with a plain reason if unaffordable. Battery energy is
     **preserved** (clamped to the new capacity, never refilled; the clamped-away energy is recorded, not created).
     Cargo above the new capacity refuses the refit until unloaded (say so). No refund twice: a repeated or replayed
     request changes nothing; save/load mid-transaction cannot duplicate. Levels can all reach 5; no hidden cap.
   - **Assembly challenge** (short, not rapid-input, not the same every time): the panel shows the modules for the
     changed stats and asks the engineer to (a) pick the compatible module from 2–3 candidates by its connector/rating
     clue, (b) connect it to the right port, (c) check the power/load result (for example: which battery current is
     safe for the new motor, or does the new load fit the battery's rating). The host checks the answers; a wrong answer
     gives feedback and a changed example to retry, no penalty. Different stats/levels give different examples
     (seeded from the state RNG or the request, deterministic for tests). Record evidence (`ProgressEvidence`) for
     `res_rover_assembly`.
   - `rover_enter` (`{"seat": 0..3}`, seat 0 = driver; anyone may drive or ride; a free seat only; actor near the rover;
     suit on if the rover is outside) and `rover_exit` (`{"exit_index": int}` from `data\rover.json`; the client picks a
     clear exit, the host checks the index and sets the character's position from the pose + offset). A character in a
     seat is recorded in `rover.seats`; leaving control, disconnect (`SessionService.peer_left` → the character returns
     to the hub; free their seat) and recovery free the seat. Driver disconnect: the rover stops where it is (P10B brakes
     it; you free seat 0). Four people can ride.
   - `rover_load_cargo` / `rover_unload_cargo`: move a carried item (actor's cargo, `items[id].holder`) into
     `rover.cargo` (`holder = "rover"`) and back, within `cargo_capacity_kg` (give item kinds a mass in your balance:
     salvage parts, samples, supply crates; say these are game values). Anyone may load. Loaded items travel with the
     rover (their position follows `rover.pose` — update `items[id].position` when the pose changes so caches and saves
     stay right).
   - `rover_set_charging`: anyone, at the charger station, rover parked within the charge radius.
5. **RoverSystem** (post-system on the 5 Hz tick): while charging, move energy from the colony battery
   (`stores.battery_kwh`) into `rover.battery_kwh` at the charger's kW, never above capacity, and count it in the
   **ledger** so `now = start + in − out` still holds for the battery (add a ledger key such as `rover_charge_kwh` in
   `ColonyState._empty_ledger` and use it where the battery identity is checked — see `tests\test_life_support.gd`; run
   that suite). Charging is a real load: if the colony battery is at its reserve or a power deficit is active, charging
   pauses with a reason. `note_driven(state, events, distance_m, climb_m)` takes energy from the rover battery
   (`energy_kwh_for_move` with the actual cargo and crew), returns the kWh used, and keeps running totals in
   `rover.trip` (distance, energy) for the HUD. An empty battery leaves the rover able to coast/brake only (P10B reads
   `battery_kwh`).
6. **Garage panel** (`garage_station_panel.gd`): five sliders (level 1–5) for speed, torque, battery range, cargo and
   traction; for each the current level, the previewed level and the parts it costs; totals: invested, available
   (`state.parts`), change in parts; live stats (current and projected) incl. the honest range with the cargo now
   aboard; the battery's stored energy and that a battery upgrade does not refill it; example builds may be shown as
   explanations but **sliders are the control**. Anyone can preview; only the field engineer gets the Assemble/Refit
   button (others see who can do it, with the symbol). The challenge runs in the same panel. Must fit 1280×720.
   Charger panel: battery state, charge on/off, the colony battery cost in kWh.
7. **Tests** (`tests\test_rover.gd`, headless, no scene): custom builds beyond any preset; unaffordable change refused;
   all five stats reach 5 with enough parts (exactly 50 invested); partial battery refit preserves energy (and clamps
   on a downgrade without creating energy); over-capacity cargo refused and a refit that would strand cargo refused;
   four riders; fifth refused; driver disconnect frees the seat; save/load round trip of every rover field mid-refit
   and with cargo aboard; duplicate request and replay after load refund nothing; charging moves exactly the ledgered
   energy and pauses at the reserve; `note_driven` uses more energy with cargo and on a climb; wrong specialty and
   too far refused; challenge wrong answer → retry with a changed example; salvage supply table numbers match the data.

## Worker P10B — the vehicle: body, seats, driving, cameras, network pose (Prompt 10, part 2)

Copy: `G:\nasa app\_work\p10b`. You own: new `scripts\vehicle\rover_body.gd` (RigidBody3D raycast suspension),
new `scripts\vehicle\rover_presenter.gd` (scene side: builds the body from the map's rover object, seats, cameras, HUD
widget, network pose), new `scripts\vehicle\rover_hud.gd`, new `data\rover.json`, new `tools\godot\rover_drive_check.gd`
(headless driving harness), new `tests\test_rover_drive.gd`. Shared (small edit): `scripts\player\player_controller.gd`,
`scripts\player\player_camera_rig.gd`, `scripts\player\player_visual.gd` (seated pose / hiding / camera attach only).
You may read but not edit `RoverModel` — use its fixed signatures (the stub returns fixed numbers; P10A replaces them).

1. **Evidence first.** Inspect the map's rover objects (`sf_rover` by `sf_print_garage`, `hb_rover` in the Hangar) in
   `scenes\world\colony_world.tscn` / the imported glTF (headless scene load), the manifest and `data\colliders.json`:
   wheel count and positions (from wheel meshes or bounds), seats and the open space for four people, the garage
   opening. Choose the drivable rover (coordinate through `data\rover.json`'s `object` field; P10A puts the garage
   station on the matching garage). If the model has fewer than four real seats, place four seat anchors where seated
   bodies fit without clipping (cargo/rear deck) and **flag it** in NOTES.md (four seats are required in every
   configuration). Keep the original mesh; hide the static map copy and drive a body that shows the same mesh
   (reparent or duplicate the visual into the RigidBody3D; keep its collision as simple convex/box shapes).
2. **RoverBody** (RigidBody3D, Mars gravity 3.73 m/s², the project's gravity setting or `MARS_GRAVITY`): one RayCast3D or
   shape-cast per wheel at the model's wheel positions; spring/damper suspension; drive force at the wheels along the
   ground from `RoverModel.stats(...)` (`drive_force_n`, `top_speed_mps`), lateral grip from `traction_mu` × normal
   load (so the rover does not slide in tight turns but can slip on steep slopes), steering by front (or skid) wheel
   angle that reduces at speed, Space brakes, no autonomous driving. Low centre of mass and anti-roll so it does not
   flip on the dunes at sensible speeds. Energy: the driver's machine accumulates distance and climb and the host
   charges it with `RoverSystem.note_driven(...)` (P10A) — call through a `Callable` you look up at run time with
   `has_method` / `ClassDB`-free `get_script` checks so your copy runs before P10A's file exists, or define a local
   fallback that calls `RoverModel.energy_kwh_for_move`. Zero battery → no drive force (coast and brake work).
3. **Seats and views.** E near the rover enters (seat choice: driver if free, else the first free passenger seat;
   request `rover_enter` and wait for the host's answer); E inside exits through the first clear exit point
   (shape-query each `exit` offset; if all are blocked say so and stay seated; request `rover_exit` with that index).
   Seated characters show a seated pose (reuse the rig's seated/idle pose if one exists; otherwise a fixed sitting
   offset — flag it), local first-person camera at the seat's head height with visible hands/body, Tab third-person
   chase camera with collision (SpringArm3D), mouse look. WASD steer/accelerate only for the driver. The player
   controller must not move or collide while seated (disable its body and input; restore on exit).
4. **Network.** The driver's machine simulates the body and sends its pose (position, quaternion, linear/angular
   velocity) ~20 Hz: client → `services.net.send_motion_extra("rover", pose_dict)`; the host accepts it only from the
   peer whose character is in seat 0, stores it in `state.rover.pose` and broadcasts via
   `net.motion_extras_provider` (`{"rover": pose}`). Everyone else shows a kinematic copy smoothly interpolated
   (freeze the RigidBody3D in kinematic mode when not the driver's). Seated crew are drawn at their seats on every
   screen. When nobody drives, the host simulates the parked/coasting body (brake held) so the rover settles and the
   pose stays authoritative. The 5 Hz state replication must not fight the live pose (use the motion extras for live
   motion; `state.rover.pose` for save and late join).
5. **Presenter** (`RoverPresenter.setup(world, services, game)`): find the map rover object, build the RoverBody, add
   the HUD widget (speed m/s and km/h, battery kWh and %, honest range, cargo kg/capacity, seat list, "E: exit",
   "Space: brake") under `game.hud`, hook E/seat handling when the player aims at the rover (station-like target: add
   a target entry the player's `aimed_target()` can see, or handle E yourself when within reach and not aiming at a
   station — say which in NOTES.md), connect the network signals. Exact wiring code for `game_main.gd` goes in NOTES.md.
6. **Headless driving checks** (`tools\godot\rover_drive_check.gd` and `tests\test_rover_drive.gd`): load the real world
   collision (as `tests\test_collision.gd` / `tests\test_game_scene.gd` do), spawn the rover at the garage park pose and
   drive it by scripted input frames (no teleporting): a straight run, a tight turn (record the turning radius), rough
   terrain over the dunes/rocks (no flip, wheels keep contact most of the time), a long route from the garage to a
   salvage donor and back (record distance, time, energy, min/max height, stuck count), braking distance, a blocked exit
   (put a box at each exit; the exit must be refused until one is clear), four seats occupied, cargo mass slows
   acceleration. Print a table; the test checks bounds you justify. Physics at 60 Hz.

## Worker P11 — proximity voice and radio stages (Prompt 11)

Copy: `G:\nasa app\_work\p11`. You own: `scripts\voice\comms_stage.gd` (extend), new `scripts\voice\voice_service.gd`
(Node: capture, encode, send, receive, decode, play), new `scripts\voice\voice_router.gd` (pure routing rules), new
`scripts\voice\voice_scheduler.gd` (pure timed buffer), new `scripts\voice\voice_hud.gd`, new
`scripts\ui\voice_settings_panel.gd`, new `data\model_sources_voice.json`, new `tests\test_voice.gd`. Shared (small
edit): `data\upgrades.json` and `data\questions.json` (add the communications cards and their questions),
`scripts\ui\settings_panel.gd` (one button that opens the voice settings), `scripts\ui\game_settings.gd` (voice
settings fields, saved with the other settings), `scripts\ui\credits_panel.gd` (TwoVoip MIT notice and Opus/speexdsp/
rnnoise BSD notices; see `addons\twovoip\VERSION.txt` and `LICENSE.txt`), `scripts\sim\progression_system.gd` /
`progression_actions.gd` only if the card catalogue needs a new sector key (prefer data only).

1. **TwoVoip 6.1** is installed at `addons\twovoip` (Windows x86_64 debug + release libraries; verified to load in 4.7.2
   headless: classes `TwovoipOpusEncoder`, `AudioStreamOpus`, `AudioStreamPlaybackOpus`). The original helper scripts
   (`two_voip_mic.gd`, `two_voip_speaker.gd`) are at `G:\nasa app\_tools\twovoip_6.1\extracted\project\addons\twovoip\voiphelper\`
   (read them for the API; adapt the logic into your own files with a credit comment; MIT). Do **not** use its MQTT
   backend or any public service. Microphone capture uses `AudioServer.set_input_device_active(true)` and
   `AudioServer.get_input_frames(n)` (as the helper does), encoder `create_sampler(AudioServer.get_input_mix_rate(), 48000, 1 or 2, denoise)`,
   `create_opus_encoder(bitrate, complexity, optimize_for_voice)`, `calc_audio_chunk_size`, `process_pre_encoded_chunk`,
   `encode_chunk(prefix, gain)`; playback `AudioStreamOpus` + `AudioStreamPlaybackOpus.push_opus_packet(packet, prefix_len, fec)`.
   Check every method you use exists (`ClassDB.class_has_method`) and fail soft.
2. **Transport**: `services.net.send_voice(...)` / `voice_packet_received` (above). Add a small header of your own to each
   packet (stream id, utterance sequence, frame number, the speaker's monotonic send time in ms, the speaker's character
   id or peer) so the listener can order frames and schedule them. Headers/footers reliable, frames unreliable.
3. **Routing (`VoiceRouter`, pure, decided on the listener's machine every frame)**: both indoors → proximity: gain 1.0
   up to 5 m, smooth fade to 0 at 25 m, room/door treatment (same zone: distance fade; different zones: only through an
   open door between them with extra attenuation, otherwise silent — use `ColonyZones` and the game's door
   controllers; describe your rule). Either outside (`CharacterState.outside`, or seated in a rover outside) → radio:
   non-spatial, across the playable map, including indoor listeners, at the stage delay; stage 0 → no exterior link
   (silent, and the HUD says why). Never both routes for one speaker. A route change mid-utterance keeps the
   utterance on the route it started on (say so) or ends it cleanly; no duplicate.
4. **Intentional delay vs network (`VoiceScheduler`)**: the delay is equipment buffering, fixed per utterance from the
   stage at its start; queue timestamped encoded frames and present them at `utterance_start_local + delay + frame_index × frame_time`;
   jitter handling (reorder window, FEC for a missing frame, playback buffer target) runs after that schedule; helper
   catch-up (pitch/speed changes) must never shorten a 30 s delay or change speech speed (disable it). Bound the queue
   (say the bound in seconds and frames; drop oldest whole utterances with a note when exceeded), preserve utterance
   order per speaker, a stage upgrade applies only to new utterances. Clear buffers on mute (that speaker), on that
   peer's disconnect, and on session exit. Mic capture and game RPCs never wait on the buffer. Pause does not stop voice.
5. **Controls and states**: push-to-talk on V (`push_to_talk`), input device list and choice, input level meter, own mic
   mute, per-player volume and mute, an obvious transmitting indicator (and which route: "Speaking nearby" /
   "Radio — heard after 15 s" / "No radio link outside"), and an indicator when someone is heard. No accounts, no
   recordings stored (no file writes of audio). Missing or denied microphone: the game stays playable, the HUD and the
   voice settings say "No microphone" and listening still works. Headless: no capture.
6. **Communications stages**: add four cards to `data\upgrades.json` in the existing format (read
   `scripts\core\upgrade_definition.gd`, `data\upgrades.json`, `data\questions.json`, `scripts\sim\progression_system.gd`):
   `comms_radio_1..4`, costs 1, 2, 3, 4 parts, specialty `electrical_comms`, install at the existing communications
   station (kind `comms`), each with contextual questions (with retry variants) and a practical-evidence requirement
   you can satisfy with existing actions; tiers/prerequisites so they install in order. Effect text: "the radio passes
   speech after 30 s / 15 s / 5 s / near-immediately"; the explanation says the delay is the damaged radio's
   buffering and processing, **not** network delay and **not** Earth–Mars light time (Earth messages stay separate and
   are not improved). If the communications sector does not fit the existing five-sector tier scheme, add the cards in
   a way `ProgressionSystem` already supports and explain it.
7. **Tests** (`tests\test_voice.gd`, labelled **synthetic**: no microphone, no speaker): router gains at 0/5/15/25/30 m,
   doors open/closed, indoor/outdoor pairs both ways, rover passenger outside; stage delays 0..4 and stage 0 silence;
   scheduler order with disorder and loss (FEC request on a gap), bounds, mid-utterance upgrade keeps the old delay,
   mute/disconnect/exit clear; two utterances from two speakers at once; packet header round trip; an encode → packet →
   decode round trip with the real TwoVoip encoder on a synthetic sine buffer if it works headless (otherwise say so);
   relaying through two headless NetSession instances if `tests\test_net.gd` shows how (packet arrives at the third
   peer unchanged and in order). Measure in-process scheduling latency for stage 4 and report it as in-process only.

## Worker P12 — ten-stage tutorial, campaign certification, optional story (Prompt 12)

Copy: `G:\nasa app\_work\p12`. You own: new `scripts\sim\tutorial_system.gd`, new `scripts\session\tutorial_actions.gd`,
new `scripts\game\tutorial_presenter.gd` (objective tracker, hints, specialist cues, story log) and its HUD widget,
new `scripts\ui\story_log_panel.gd`, new `scripts\ui\stations\record_station_panel.gd`, new `data\tutorial.json`,
new `data\lore.json`, new `data\stations_lore.json`, new `data\model_sources_campaign.json`, new `tests\test_tutorial.gd`,
new `docs_draft\TUTORIAL_GRAPH.md` (objective/learning dependency graph, balance and pacing log, story outline with
science/fiction labels, content gaps). Shared (small edit): `scripts\session\session_service.gd` (register
`TutorialActions` and `sim.post_systems.append(TutorialSystem.new())`), `scripts\core\game_services.gd` only for
`start_new_game` initialisation of `state.campaign` if a system cannot do it lazily.

1. **Ten stages in the supplied order**: (1) arrival and movement; (2) airlock interaction; (3) hub monitoring and
   character selection; (4) solar maintenance; (5) energy distribution; (6) greenhouse operations; (7) personal health
   and stamina; (8) communications; (9) an independent greenhouse-power problem; (10) return to the hub and continued
   exploration. Each stage lists what it teaches (control or procedure) and objectives checked **from the real
   simulation state and resolved actions** on the host (`events.action_resolved`, `state.evidence`, `state.ledger`,
   character positions/zones, `CommsStage.stage(state)` for stage 8, etc.). Teach each control and specialist
   procedure before it is tested. Every tutorial action is a real action that changes the simulation (no tutorial-only
   fake actions). State lives in `state.campaign` (saved, replicated); the presenter only shows it.
2. **Player counts**: all required tasks are sequentially solvable by one player (switching crew at the hub when a
   specialist is needed — say which crew and give a clear preparation cue: "This step needs the Electrical specialist ⚡;
   switch at the hub crew screen"). With four players, never ask anyone to switch (switching is disabled): name who
   should act instead. No objective needs two players at once, and nobody must watch another player's whole terminal.
3. **Hints and mastery**: a hint appears after a period without progress (real seconds, configurable) and on request;
   explanations already mastered (knowledge answers in `state.knowledge`, or the stage done in this colony) are
   skipped; stages can be replayed as reminders without double-counting. Stored food and survivable starting
   supplies stay as the balance already has them (check with `tests\test_life_support.gd`).
4. **Stage 9 — changed example**: a real greenhouse-power fault that uses the energy-distribution reasoning of stage 5
   in a different form (for example the greenhouse grow lights are shed because the battery is near its reserve at
   night, or a breaker/priority change), chosen deterministically from the colony seed from at least three variants,
   injected into the real simulation, and solved with real actions. It must be recoverable and never kill anyone.
5. **Continuation and certification** (after stage 10, same world): the first campaign milestone completes when all
   five sectors operate (define "operate" from existing state: each sector's tier ≥ 1 or its key equipment working —
   state your rule), communications operate (`CommsStage.stage(state) >= 1`), and the essential reserves (battery,
   water, oxygen, food) stay above zero for one full sol of game time with no emergency recovery (`character_recovered`)
   during that period. A failure resets the period, never progress. After completion everything keeps working (blueprint,
   sources, upgrades, exploration, weather, save/load). The mystery and a maximised rover are optional.
6. **Story (you are the lore specialist)**: a compact, optional mystery about how weak power reserves and shared
   failures (a power/reserve/distribution cascade) affected the former colony — hopeful tone, no graphic remains, no
   aliens, no NPC helper, no new level, no cutscene. 8–14 short records (≤ 60 words each, ages 9–12) attached to
   **existing** damaged objects and logs in the map (the salvage donors, burnt switchgear, alarm racks, crash debris,
   dead roof tiles, consoles — see `data\colony_manifest.json` and `data\salvage.json`). A record is found by a real
   action at that object (a `read_record` action at a `record` station, or a hook on an existing action such as
   `inspect_donor` — host-side, through `events.action_resolved`, without editing other workers' files). Each record
   labels what is fiction and links the real science it touches (by source id from the register when one exists).
   Discoveries go in `state.discoveries`; the story log panel lists them with their clue→discovery chain. Solving it is
   never required. Developer/community narrative advice is not scientific evidence.
7. **Dependencies on other workers**: stage 8 uses `CommsStage.stage(state) >= 1` (cards `comms_radio_1..4` arrive from
   P11; in your copy they do not exist yet — in tests you may set `state.upgrades["comms_radio_1"]` directly, marked
   "until P11 merges"; the executor will switch the test to the real install). Rover use after stage 10 is optional:
   read `state.rover` through `RoverModel` only.
8. **Tests** (`tests\test_tutorial.gd`, headless, no scene): a scripted solo run through all ten stages using only real
   actions (with hub crew switches) reaching free exploration; a four-player run (four peers) where no objective asks
   for a switch and no step needs two players at once; objective order enforced; repeating a stage does not
   double-count; hint timing and skip of mastered explanations; save/load at every stage boundary resumes the same
   stage and objectives; stage 9 variant chosen deterministically per seed (three seeds → at least two different
   variants) and solvable; certification completes after a full sol, resets on a recovery and on a reserve hitting zero,
   keeps progress; play continues after completion; lore records found once, optional.
