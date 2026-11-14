# Milestone handoff — Prompt 11: Proximity voice and radio progression

Date: 2026-11-14. Project: `G:\nasa app\mars_colony_godot`. Built by one Claude subagent (P11) from `docs\workers\SPEC_P10_P12.md`, then merged and wired by the executor. Worker report: `workers\P11_NOTES.md`.

**Every check is synthetic.** A generated 440 Hz tone stood in for speech, all instances ran in one process on 127.0.0.1, and there was no microphone, speaker or second computer. The pack's acceptance needs real microphones and several clients; that remains to be done (I-57). A synthetic loop does not prove microphone-to-listener use.

## 1. Outcome

- **Dependency.** TwoVoip 6.1 GDExtension (`addons\twovoip`):
  - From the GitHub release `v6.1`, release asset SHA-256 `01825E1F…D098` (full value in `addons\twovoip\VERSION.txt`). MIT licence (`LICENSE.txt`); the libraries bundle Opus, SpeexDSP and RNNoise (BSD-style).
  - Only the Windows x86_64 debug and release libraries are kept.
  - Loads in Godot 4.7.2 headless, in this project, and the trial export includes the release DLL.
  - No MQTT backend and no public service. The game has its own adapter in `scripts\voice\`.
- **Capture and controls** (`VoiceService`, `VoiceHud`, `VoiceSettingsPanel`):
  - Push-to-talk on V, microphone choice, input level meter, mute my microphone, per-player volume and mute, voices volume.
  - An obvious indicator shows who is transmitting and by which route: "Speaking nearby", "Radio — heard after 15 s", "No radio link outside".
  - A missing, denied or disabled microphone leaves the game playable and says so; listening still works.
  - Microphone input is now enabled in `project.godot` (`audio/driver/enable_input`).
  - Nothing is ever written to disk.
- **Routing** (`VoiceRouter`, decided on each listener's machine):
  - **Both indoors:** full level to 5 m, fading to silence at 25 m. Other rooms are heard only through one open door between them, at half level along speaker → door → listener, scaled by how far the door is open. Closed doors, or no shared door, give silence (24 manifest doors plus the airlock doors).
  - **Either outside:** the radio, which includes a rover seat outside the garage. It is not spatial and is heard across the map, indoor listeners included, at the stage delay. At stage 0 nobody hears it and the HUD says why.
  - The route is fixed when an utterance starts, so nothing is heard twice.
- **Radio stages** (`CommsStage`, four upgrade cards `comms_radio_1..4`, E-44):
  - Stages give 30 s, 15 s, 5 s and near-immediate delivery, for 1, 2, 3 and 4 parts.
  - Cards are installed in order at the comms console by the electrical specialist, with questions, retry variants and a radio-check practice step.
  - The card and panel texts say the delay is the damaged radio's own buffering and processing, not network delay and not Earth–Mars light time. Earth messages are not made faster.
  - The comms console has a "Radio repairs" button.
- **Timing** (`VoiceScheduler`):
  - The delay is fixed per utterance from the stage at its start. Frame *n* plays at start + delay + 80 ms + *n* × 20 ms.
  - After that schedule: an 80 ms reorder window, Opus FEC for a missing frame, a 40 ms player buffer.
  - No catch-up and no speed change.
  - Utterances keep their order, so an upgrade only shortens new speech.
  - Bounds: 40 s or 16 utterances per speaker, 6000 frames in all; the oldest whole utterance is dropped with a note.
  - Buffers are cleared on mute, disconnect and leaving the session. Pause does not stop voice.
- **Transport:** NetSession channel 2. The host relays a client's packets to the other clients. Every packet is sent reliable and ordered (E-42).

## 2. Acceptance (`tests\test_voice.gd`, 84 checks, synthetic)

| Check | Result |
|---|---|
| Gain at 0 / 5 / 15 / 25 / 30 m indoors | 1.0 / 1.0 / 0.5 / 0 / 0 |
| Doors open / closed, mixed indoor/outdoor pairs, rover passenger outside | Routes as above |
| Stages 0–4 | No link, 30, 15, 5, 0 s; stage 0 silent with a reason |
| Disorder, loss | Reordered; a missing frame rebuilt by FEC from the next packet; a gap skipped |
| Upgrade mid-utterance | The queued utterance keeps its delay; the next uses the new one |
| Mute, disconnect, exit | Buffers cleared |
| Two speakers at once | Both heard, each in order |
| Real codec | TwoVoip encode → game packet → decode headless: 440 Hz back, peak 0.59 for input 0.5 |
| Three instances over 127.0.0.1 | A client's 30 frames all reach the host (after E-42; 14–17 of 30 before); nearby send → release mean 66 ms in one process, plus the 40 ms player buffer; audio output latency not measured |
| Radio stage 3 | Requested 5 s, measured 5.10 s in-process |

The pack's 200 ms near-immediate target has **not** been measured on a LAN with real audio.

## 3. Merge fixes (executor)

- **Frame loss** (E-42): unreliable frames were lost because ENet's packet throttle (read at 1 of 32) drops unreliable packets while the 5 Hz reliable snapshots make round-trip times vary. Holding the throttle with `throttle_configure` changed nothing in tests, so every voice packet now goes reliable on the voice channel; the test now requires all frames to arrive.
- **Positions** (E-45): unchanged client positions are re-sent every 0.5 s.
- **Wiring:** the voice presenter is wired into the game scene, and the "Radio repairs" button added at the comms console.

## 4. Limits

1. **Real-world checks are owed:** no real microphone, speaker or LAN (I-57). Checking an exported build with a microphone is part of Prompt 17.
2. Rooms connect through one door only.
3. Per-player mute and volume last for the session only.
4. The HUD voice corner hides while a panel is open; push-to-talk still works.
5. The full Opus, SpeexDSP and RNNoise licence texts are not yet in the package.
