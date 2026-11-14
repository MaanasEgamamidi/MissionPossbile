# Prompt 06 — LAN multiplayer: handoff

Date: 2026-11-13. Built at the owner's request (D-13): local network only, no cloud, no voice.

## 1. What works

| Feature | State |
|---|---|
| Host from the main menu (continue the save or start a new colony) | Done. Hosting a new colony over an existing save asks twice, like New colony. |
| Join from the main menu (address and port) | Done. The menu says "Connecting…", then plain reasons on failure (nobody answering, wrong version, colony full). |
| Up to 4 players (host + 3) | Done. A fifth is turned away with a reason. |
| Late join | Done. A joining player gets the whole colony and the first crew member nobody is playing. |
| Shared colony | The host runs the simulation, validates every request and writes the save. Clients show a replica. |
| Seeing each other move | Bodies move smoothly and play idle, walk, sprint or carry from their real speed. |
| Doors and airlock | Open for every player on every screen; the host counts a client's airlock cycles. |
| Carrying | Clients pick up, put down and throw crates; everyone sees the crate in their hands. |
| Station screens | All 21 open on a client; every control is a request to the host. |
| Pause | Needs every player's vote; the pause menu shows the count on every machine. |
| Player leaves | Their crew member is parked at the hub (no supplies charged). |
| Host leaves | Clients go back to the menu with "The connection to the host was lost, or the host closed the colony." |
| Host's address | Shown in a subtitle when hosting starts and in the pause menu ("Hosting on 192.168.1.20:24680, 2 players"). |

## 2. How it works

`scripts/net/net_session.gd` (node `Services/Net`; the path must be the same on every machine). Decision E-32.

- Channel 0, reliable and ordered: requests, answers, colony snapshots and forwarded GameEvents. The host sends the whole
  colony, the clock and the session facts (peers, pause votes, suit checks) 5 times a second and at once after any
  action, followed by the events it emitted. A client copies state in place (`ColonyState.assign_from`), then re-emits
  the events, so the UI always reads the new state when it hears the event.
- Channel 1, unreliable: body poses at 20 Hz each way. Each client is the authority for its own body's pose; the
  host only accepts a pose from the peer that owns the character.
- `ActionResult.peer` is set by the host so each screen shows only its own answers.
- Clients never tick, never save, and never call `SessionService` directly (`GameMain._submit` routes old station
  calls to the host).

## 3. Playing on two computers

1. Both computers on the same network (same Wi-Fi or router). Same game version on both.
2. Host: main menu → Host on this network → Start hosting. **Windows Firewall asks the first time: allow it on Private
   networks**, or nobody can join. The address appears on screen and in the pause menu (Esc).
3. Others: main menu → Join a colony → type the host's address (and port, default 24680) → Join.
4. If several addresses are shown, the 192.168.x.x one is almost always right.

Development shortcuts (after `--` on the Godot command line): `--host` or `--host=PORT` hosts at once (continues the
save in `user://` if there is one), `--join=ADDRESS[:PORT]` joins at once. Two windows on one computer:
`--join=127.0.0.1`.

## 4. Checks

`tools/run_tests.ps1` now runs `test_net` (34 checks: real ENet on 127.0.0.1, host and client in one process with
separate SceneMultiplayer branches) and `test_net_game` (20 checks: two whole game scenes through the menu handlers,
without the map). All 14 suites pass on 2026-11-13.

Not verified: two real computers; the full 300 MB map loaded on both sides; a long session; Wi-Fi packet loss.

## 5. Known limits

1. No voice (Prompt 11) and no client-side prediction: a client's own actions wait for the host's answer (a LAN
   round trip, a few milliseconds).
2. Positions are trusted from the owning player (no speed or reach check, I-48).
3. A thrown or dropped crate falls under each machine's own physics. The host records it at the thrower's feet, so
   after a throw it can rest in slightly different places on different screens until someone picks it up.
4. The client's clock jumps 5 times a second instead of running smoothly (the sun moves in small steps).
5. A colony snapshot can occasionally arrive just after a newer pose and pull a remote player back for a frame; the
   smoothing hides most of it.
6. Pause needs every player, so one player who never opens the menu keeps the colony running (by design, SessionService).
