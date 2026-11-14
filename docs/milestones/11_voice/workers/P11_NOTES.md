# Worker P11 — proximity voice and radio stages (Prompt 11)

Copy: `G:\nasa app\_work\p11`. Godot 4.7.2, headless only. TwoVoIP 6.1 (MIT) over the game's own ENet session.
Everything below that says "heard" in a test means **decoded into the Opus playback buffer** in a headless run with a
**synthetic** 440 Hz sine instead of a microphone. No real microphone, speaker or second computer was used.

## 1. What was built (files)

New (owned):
- `scripts/voice/comms_stage.gd` — `CommsStage` (extended stub): stage 0..4, delays (−1, 30, 15, 5, 0 s), card ids,
  `CARD_PARTS` (1,2,3,4), install station/kind/specialty, `has_link`, `next_card`, `delay_words`, `stage_text`,
  `explanation()` (equipment buffering, not network, not Earth–Mars light time).
- `scripts/voice/voice_router.gd` — `VoiceRouter`, pure routing rules + HUD words.
- `scripts/voice/voice_scheduler.gd` — `VoiceScheduler`, the packet format (header codec) and the listener's timed buffer.
- `scripts/voice/voice_service.gd` — `VoiceService` (presenter Node): capture (push-to-talk V), Opus encode, send,
  receive, schedule, decode, play, per-player volume/mute, mic states, HUD lines. Adds `VoiceHud` under `game.hud`.
- `scripts/voice/voice_hud.gd` — `VoiceHud`, bottom-right HUD corner.
- `scripts/ui/voice_settings_panel.gd` — `VoiceSettingsPanel` (device list, level meter, mute me, voices volume,
  per-player volume + mute, how voice works, radio stage and why it is slow, privacy line).
- `data/model_sources_voice.json` — category of every voice number.
- `tests/test_voice.gd` — 83 checks (synthetic).

Shared, small edits (exactly these):
- `data/upgrades.json` — 4 cards `comms_radio_1..4`, evidence entry `comms_radio_check`, a `comms_note` key, and the
  catalogue `note` sentence extended ("plus the four Prompt 11 colony radio cards…").
- `data/questions.json` — 5 questions appended: `comms_q_buffer_delay`, `comms_q_radio_check` (records
  `comms_radio_check`, `answer_at_kind: "comms"`), `comms_q_earth_delay`, `comms_q_inside_outside`,
  `comms_q_plan_delay` (each 2 variants, 3 answers, explanation).
- `scripts/ui/settings_panel.gd` — one button `VoiceSettingsButton` ("Voice and microphone…") in the Controls tab
  that opens `VoiceSettingsPanel` with the same `settings` and `settings_path`.
- `scripts/ui/game_settings.gd` — fields `voice_input_device` (String, "" = default), `voice_mic_muted` (bool),
  `voice_volume` (0..2, default 1) added to `KEYS`; `load_or_default` also reads String values; doc line.
- `scripts/ui/credits_panel.gd` — const `VOICE_CREDITS` (TwoVoIP 6.1 MIT; Opus, SpeexDSP, RNNoise BSD-style) shown
  in the existing "Tools" group (`SourceLibrary.credits() + VOICE_CREDITS`); group titles unchanged.
- `tests/test_progression.gd` and `tests/test_station_panels.gd` — minimal count edits, see §6.
- Not edited: `progression_system.gd`, `progression_actions.gd` (no new sector key needed), `net_session.gd`,
  `game_main.gd`, `game_hud.gd`, `ui_root.gd`, `project.godot`.

## 2. Design

### Routing (VoiceRouter, decided on the listener's machine)
- **Either outside** (zone `Exterior` at the current position — the host's own `outside_test` rule — or seated in the
  rover (`state.rover.seats`) while the rover pose is outside) → **radio**: not spatial, full level anywhere on the map
  (indoor listeners included), delay = stage delay. Stage 0 → route **none** (silent, reason `no_radio_link`; both
  HUDs say so). Suit-to-suit outside is radio too (thin air).
- **Both inside** → **proximity**, immediate. Same zone: gain 1 to 5 m, `1 − smoothstep(5, 25, d)` (0.5 at 15 m),
  0 from 25 m; distance across the floor (x, z). Different zones: only through **one** open door joining exactly those
  two zones, along speaker→door→listener, × 0.5 (DOOR_FACTOR), × door open amount (`DoorController.open_amount`);
  < 5 % open = closed = silent; no door between the zones = silent. Chains of doors are not followed (stated limit).
- Door portals: the 24 manifest doors (zones sampled 0.6 m each side of the door line; from `colony_manifest.json`)
  plus any other `DoorController` the game builds (exit-tunnel and garden airlock doors), measured from their leaves.
- A seated rover rider is placed at the rover pose; in the garage (Hangar bay) that is inside → nearby voice.
- **One route per utterance**: chosen when its first packet arrives, kept until it ends. A proximity utterance's gain is
  re-read every frame (people move); if the pair stops being both inside mid-utterance it simply fades (route kept, no
  duplicate on the radio). A radio utterance stays radio even if both come inside.

### Packet (VoiceScheduler) — 19 bytes + character id (25 bytes for `crew_3`)
`'V' | version 1 | kind (1 start, 2 frame, 3 end) | flags | u16 stream id | u16 utterance seq | u16 frame number (end:
frame count) | u32 utterance start ms (speaker clock) | u32 send ms | u8 id length | id` + start: u32 48000, u16 960,
u8 1 channel; frame: one Opus packet (the header is passed to TwoVoIP `encode_chunk` as its prefix and to
`push_opus_packet(packet, header_len, fec)`). Start/end reliable, frames unreliable (`NetSession.send_voice`). Any
packet can open an utterance (start lost → first frame back-dates the start from its own elapsed time).

### Schedule, jitter, catch-up
- `due(i) = start_local + delay + JITTER_S + i × 20 ms`; delay fixed per utterance from the stage at its start.
- Jitter handling after the schedule: 80 ms reorder window; missing frame with the next one present → Opus FEC from
  the next packet; missing with later ones present → "lost" (skipped); nothing newer at all → wait (stall), then go on
  from the late frames (schedule only ever moves later); 1 s with no packet → utterance ended (`timeout`). Player
  starts when 40 ms are queued (`PLAYBACK_TARGET_S`).
- **No catch-up**: pitch_scale is never touched (tested = 1.0); nothing is released before its due time.
- **Order**: per speaker one lane per route; within a lane utterances play strictly in order — a later one (e.g. after
  an upgrade to a shorter delay) waits for the earlier one and then starts at once, never overtaking. Proximity speech
  is not radio speech: it plays immediately even while an older radio message from the same person is still in the radio.
- **Bounds**: per speaker ≤ 2000 frames (40 s) and ≤ 16 utterances waiting; all speakers ≤ 6000 frames; over a bound
  the oldest whole utterance is dropped with a note (`scheduler.notes`). Utterance ≤ 3000 frames (60 s): the speaker
  splits longer holds. Frame numbers ≥ 3000 rejected.
- **Clearing**: mute a player → that speaker's waiting/playing speech cleared and the rest of that utterance dropped;
  peer disconnect (host signal, or on clients the session's peer list, checked every 0.5 s) → speaker forgotten;
  session exit (net goes offline, host lost, node exit) → everything cleared and players stopped.
- Capture never waits on the buffer; `VoiceService` runs `PROCESS_MODE_ALWAYS` (pause does not stop voice).

### Controls and states
V (`push_to_talk`, existing action) — ignored while a LineEdit/TextEdit has focus or the Settings panel is capturing a
key. Mic opens only while V is held or the voice settings are open (meter), and stays open 3 s after release.
Mic states: ready / synthetic (tests) / headless / no_library / input_off (project setting) / no_device / failed /
no_signal (3 s without samples) / muted — each with a plain sentence; "you can still listen" everywhere. Per-player
volume and mute are **session-only, keyed by peer id** (no accounts). No audio is ever written to disk (test scans the
voice scripts for file/recording calls; the colony state has no voice data).

### HUD corner (VoiceHud, bottom right, above the hint/status strip)
"● Speaking nearby" (+ " · crew outside hear you by radio after 15 s" / "· crew outside cannot hear you (no radio
link)"), "● Radio — heard after 15 s" / "… almost at once", "✖ No radio link outside — nobody can hear you yet",
"✖ No microphone — you can still listen", idle hints; 6 s transition note when you go outside / come in; heard lines
"♪ Ana — nearby", "♪ Ben — by radio, said 15 s ago", "… Radio message from Ben, heard in 12 s", "✖ Ben is talking
outside, but there is no radio link yet". It is a child of GameHud, so it hides with the HUD while a panel is open
(push-to-talk still works then).

### Communications cards (data only, no new sector key)
`ProgressionSystem` has five tier sectors; communications is not one. The four cards are in the **energy** sector
(electrical systems; its installer is already `electrical_comms`), install at `cm_comms_console` (kind `comms`,
Command Room), and install **in order** through `prerequisites` plus Energy levels 0, 1, 2, 3:

| card | parts | Energy level | prerequisite | questions | evidence | effect |
|---|---|---|---|---|---|---|
| comms_radio_1 | 1 | 0 | — | buffer_delay, radio_check | comms_radio_check | 30 s |
| comms_radio_2 | 2 | 1 | radio_1 | earth_delay, radio_check | comms_radio_check | 15 s |
| comms_radio_3 | 3 | 2 | radio_2 | inside_outside, radio_check | comms_radio_check, res_assembly_test | 5 s |
| comms_radio_4 | 4 | 3 | radio_3 | plan_delay, inside_outside | comms_radio_check | near-immediate |

Practical evidence `comms_radio_check` is recorded by the existing `answer_question` action at the comms console
(`comms_q_radio_check`, `answer_at_kind: "comms"`, same pattern as `energy_q_net_power` at the power panel); card 3
also needs the existing workbench bench-test evidence (a refurbished board). Effect texts say the delay is the damaged
radio's buffering and processing, not network delay and not Earth–Mars light time, and that Earth messages are not
made faster. For P12: "communications operate" = `CommsStage.stage(state) >= 1`.

## 3. Numbers and categories
All in `data/model_sources_voice.json` (test checks every constant is listed): contract — delays, card costs, 5 m /
25 m; balance — door factor 0.5, Energy levels 0–3; engineering — 48 kHz mono 20 ms Opus, 24 kbit/s, complexity 5,
80 ms reorder window, 40 ms playback target, 40 s / 2000 / 16 / 6000 bounds, 1 s stall, 60 s utterance, 3 s mic hang,
1.6 m mouth height; physics (uncited) — Earth–Mars light time shown only as "many minutes". No NASA data.

## 4. Test results (this copy, final run)
`tools\run_tests.ps1 -Import -Tests …` → ALL TESTS PASSED:

| suite | result |
|---|---|
| test_voice (new, synthetic) | 83/83 |
| test_saves | 56/56 |
| test_session | 91/91 |
| test_game_services | 25/25 |
| test_progression | 84/84 |
| test_science | 76/76 |
| test_life_support | 88/88 |
| test_net | 34/34 |
| test_net_game | 20/20 |
| test_station_panels | 108/108 |
| test_ui_framework | 125/125 |
| test_hud_panels | 89/89 |
| test_sources | 76/76 |
| extra: test_graphics_quality 23/23, test_p07_panels 54/54, test_food 85/85, test_weather 66/66, test_player 112/112 | pass |

Compile check: `COMPILE OK 169 scripts`. test_voice ran 4× in a row at 83/83.

Measured (in-process only, one process, 127.0.0.1 — not LAN, not hardware):
- Scheduler alone at stage 4 (frame complete → released, 60 Hz loop): mean 68 ms, max 77 ms.
- Real TwoVoIP round trip of a synthetic 440 Hz sine: 79–108 B packets incl. 25 B header; decoded peak 0.59 (input
  0.5), 440.0 Hz; one frame rebuilt by FEC.
- Three headless machines over ENet: nearby route send→release mean ≈ 75 ms (max ≈ 190–250 ms) + 40 ms player
  target + audio output latency (not measured); radio stage 3 requested 5.000 s, measured 5.09–5.10 s from V to the
  first decoded frame.

## 5. Limits and defects found (honest list)
1. **Not tested with real microphones, speakers, two computers or real players.** The 200 ms LAN target is not
   measured; synthetic tone ≠ microphone-to-ear usability. Windows mic privacy/denial paths are coded, not exercised.
2. **Voice frame loss client→host in-process (transport, unexplained).** In the 3-machine test, A's first nearby
   utterance (30 unreliable frames, real-time pace, often 2 per game frame) arrives at the host with only 12–17 of 30,
   deterministically in windows (e.g. frames 14–22 and 24–29 missing), while a raw 30-packet unreliable relay of the
   same size and rate usually arrives 30/30 and a 1-frame-per-game-frame pace arrived 30/30 once. `ENetPacketPeer
   PEER_PACKET_THROTTLE` reads 1 or 32 with loss either way, and `throttle_configure(…, deceleration 0)` did not help,
   so the cause is not identified. The scheduler copes (lost/FEC; the test asserts ≥ 5 frames heard and reports the
   ratio), but this must be checked on a real LAN (see request E).
3. **NetSession position resend gap** (found while testing): `send_position` skips a pose equal to the last one sent,
   and positions are unreliable, so a single lost report of a player standing still is never repeated — other machines
   keep a stale position (affects voice routing and everything else). The test works around it; see request D.
4. `project.godot` has no `audio/driver/enable_input=true`: without it the game shows "microphone input is switched
   off in this build" (state `input_off`) and nobody can talk. Request A.
5. No UI path to install the radio cards: `UpgradeCardsPanel` opens only from the colony computer, and install needs
   the specialist at the comms console (6.6 m away). Request C (same gap exists for the other cards' stations).
6. One door hop only; no acoustic modelling beyond the factor. Garden dome ↔ base indoor is silent (only connected
   through the exterior).
7. The HUD corner hides while a panel is open (it is under GameHud); push-to-talk still works then.
8. Per-player mute/volume reset on reconnect (new peer id) and are not saved.
9. Third-party licence texts of Opus/SpeexDSP/RNNoise are not in this build (only TwoVoIP's MIT `LICENSE.txt`); the
   credits say "BSD-style" as `addons/twovoip/VERSION.txt` does. Noise suppression is not switched on.
10. Outside, two people side by side hear each other by radio with the stage delay (follows the brief's rule).

## 6. Existing checks changed (rule 6) — why
The brief requires the four cards in `data/upgrades.json`, which makes three counts wrong:
- `tests/test_progression.gd`: `EVIDENCE_IDS` + `"comms_radio_check"`; catalogue check expects `16 + CommsStage.CARD_IDS.size()`
  cards and all contract + radio ids; the per-card cost check compares radio cards with `CommsStage.CARD_PARTS`
  (contract 1–4) instead of `ProgressionBalance.card_parts` (left at its 16 cards); the raw JSON cost loop skips the
  radio cards; the cards-panel check expects `16 + 4` cards.
- `tests/test_station_panels.gd`: the "16 cards" count → `16 + CommsStage.CARD_IDS.size()`.
No other check was weakened.

## 7. Requests for the executor

**A. `project.godot`** — enable microphone input (needed for any capture; checked in `VoiceService._probe_mic`):
```
[audio]

driver/enable_input=true
```

**B. `scripts/game/game_main.gd`** — wire the presenter. Verified in this copy (then reverted): headless game scene
gets `VoiceService` in the tree, `VoiceHud` under the HUD, 24 portals/doors without the map; `test_game_scene` 32/32
and `test_net_game` 20/20 passed with this applied.
Under `var weather_presenter: WeatherPresenter` add:
```gdscript
## Prompt 11: private proximity voice and the colony radio (VoiceService adds its HUD corner itself).
var voice: VoiceService
```
In `_begin_play()`, directly after `weather_presenter.setup(world, services)` add:
```gdscript
	# Prompt 11: voice. After the HUD (its corner goes under GameHud) and the doors (it reads them for sound).
	voice = VoiceService.new()
	add_child(voice)
	voice.setup(world, services, self)
```
(`setup` reads `game.settings`, `game.hud`, `game.collision` "Doors", `game.airlock_doors`,
`game.garden_airlock_doors`; it must run after `add_child`.)

**C. `scripts/ui/station_panel.gd`** (install path at the comms console) — in `_build_body()`, case `"comms":`,
after `why.add_child(ExplainButton.make("sources"))` add (verified in this copy, then reverted: test_station_panels
108/108, test_p07_panels 54/54, test_ui_framework 125/125):
```gdscript
			# Prompt 11: the colony radio's stage and its repair cards (installed at this console).
			var radio := HBoxContainer.new()
			_body.add_child(radio)
			var radio_text := _add_text(radio, CommsStage.stage_text(CommsStage.stage(services.state())))
			radio_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_add_open_button(radio, "Radio repairs", func() -> UiPanel: return UpgradeCardsPanel.new())
```
Optionally add `"Repair the colony radio (radio repairs)."` to the `"comms"` list in `_what_you_can_do()`.

**D. `scripts/net/net_session.gd`** (UNTESTED suggestion, defect 3): let `send_position` repeat an unchanged pose
about twice a second, e.g. keep `var _same_pose_left := 0.0`, decrement it in `_process` for clients, and replace the
skip test with
`if not last.is_empty() and (last[0] as Vector3).distance_squared_to(position) < 1e-6 and absf(float(last[1]) - yaw) < 1e-3 and _same_pose_left > 0.0: return`
setting `_same_pose_left = 0.5` whenever a pose is sent.

**E. LAN check of voice transport** (defect 2): on two real computers, log at the host the count of `KIND_FRAME`
packets per utterance from a client vs the client's `VoiceService.counters.sent_frames`, and
`ENetPacketPeer.get_statistic(PEER_PACKET_THROTTLE)`. If frames are lost, options are ENet tuning in NetSession or
sending frames reliable-unordered; the voice code needs no change for either.

**F. Optional**: move `CreditsPanel.VOICE_CREDITS` into `data/credits.json` (then drop the const) if the executor
prefers credits in data; and copy the Opus/SpeexDSP/RNNoise licence texts from the TwoVoIP release when available.
