# Milestone handoff — Prompt 10: Salvage rover builder and driving

Date: 2026-11-14. Project: `G:\nasa app\mars_colony_godot`. Built by two parallel Claude subagents, P10A (economy, salvage, garage) and P10B (vehicle), from `docs\workers\SPEC_P10_P12.md`. The executor merged them, wired the rover into the game scene and fixed the joins between the two halves. Worker reports: `workers\P10A_NOTES.md`, `workers\P10B_NOTES.md`.

**Checks were headless only.** The rover was driven by scripted key presses on the real map collision at 60 Hz physics. Nobody has driven it with a keyboard or looked at it on screen.

## 1. Outcome

- **The rover and the garage.** `sf_rover`, parked in the 3D-printed garage `sf_print_garage` outside the base, is the drivable rover.
  - The garage opening (3.8 m) faces the rover's front.
  - The Hangar rover (`hb_rover`, 2.2 m wide) cannot leave the pressurised hangar, whose widest door is 1.36 m.
  - The static map copy is hidden; a RigidBody3D shows the same mesh.
  - Under the parked rover the garage has a cable or hose (up to 0.91 m high) whose collision trapped the rover. The 212 garage collision triangles inside the parked rover's space are dropped at load; the floor stays.
- **Salvage.** Nine new donors were added from damaged map objects (crash shield and debris, fault-alarm battery racks, a high-voltage alarm, a fault rack), for 14 donors in all. Each has compatible and incompatible parts with clues. They use the existing Prompt 08 flow: inspect, recover once, refurbish, bench test, one spare part.
- **Garage configurator** (`scripts\ui\stations\garage_station_panel.gd`):
  - Five level 1–5 sliders (speed, torque, battery range, cargo, traction) with step costs 1/2/3/4.
  - Shows invested, available and change in parts, current and projected stats, and the honest range with the cargo and crew aboard.
  - Shows the battery state, and says that a battery upgrade does not refill it.
  - Anyone can preview. Only the field engineer (⛏) can assemble or refit, through a three-step check for each changed stat: pick the module, pick its socket, answer a power/load question. Examples change; a wrong answer gets feedback and a new example at no cost.
- **Economy** (`RoverModel`, `RoverSystem`, `RoverActions`, `RoverBalance`):
  - Refits reuse invested parts and keep stored energy. On a smaller battery the extra energy is clamped and recorded in the ledger, never created.
  - A refit is refused while cargo would not fit the new bay, while anyone is seated, or while the rover is away from the garage.
  - A transaction number makes duplicates, replays and old requests after a load refund nothing.
  - Charging takes 5 kW from the colony battery (90 % reaches the rover). It pauses at the colony battery's 35 % reserve or during a power deficit. Both batteries balance in the ledger.
  - Driving energy grows with rover, crew and cargo mass and with climbing (g = 3.73 m/s², S01). Every map metre counts as 60 m, a labelled game rule so the battery matters.
  - An empty battery leaves coasting and braking only.
- **Vehicle** (`RoverBody`, `RoverPresenter`, `RoverHud`):
  - Six ray-cast wheels from the model, spring/damper suspension, grip from the traction stat × normal load.
  - Ackermann front/rear counter-steer; Space brakes; no autonomous driving.
  - E near the rover takes the driver's seat if free, else the first free passenger seat. E inside gets out through the first clear exit; if all are blocked it says so.
  - First-person seat view; Tab gives a 7.5 m chase camera with collision.
  - The driver's machine simulates the body and sends its pose about 20 times a second. The host accepts it only from the driver's peer and within a plausible step, stores it with `RoverSystem.note_pose` (cargo and seated crew follow), charges the drive with `RoverSystem.note_driven`, and broadcasts it. Everyone else shows a smoothed kinematic copy.
  - HUD shows speed, battery, range, cargo, seats and the keys.

## 2. Acceptance (headless; `tests\test_rover.gd` 80 checks, `tests\test_rover_drive.gd` 64 checks)

| Check | Result |
|---|---|
| Custom builds beyond any preset | Accepted; levels set one by one |
| Unaffordable change | Refused, with the parts needed |
| Full eventual upgrade | All five stats at 5 with exactly 50 parts invested |
| Partial battery refit | Energy kept; a smaller battery clamps and ledgers the extra; no refill |
| Over-capacity cargo | Load refused; a refit that would strand cargo refused |
| Four-person ride | Four crew seated (+640 kg); a taken seat refused; no fifth seat |
| Driver disconnect | Seat freed; the rover brakes where it is |
| Save/reload | Every rover field round-trips mid-refit and with cargo aboard |
| Charging costs | Exactly the ledgered energy; pauses at the reserve |
| Straight run | 0 → 2.7 m/s in 1.85 s; cruise 2.95 m/s (top 3.0) |
| Braking | 2.78 m from 2.97 m/s (friction limit 2.63 m at μ 0.45) |
| Tight turn | Radius 2.70 m at full lock (geometry 2.68 m) |
| Cargo load | 0 → 2 m/s: 2.22 s empty, 4.77 s with 800 kg |
| Rough terrain | Dunes and rock field, 181 m: height up to 3.1 m, max tilt 25.9°, wheel contact 99.6 %, no flips |
| Long driven route (no teleport) | Garage → salvage donor `sf_crash_shield` → dunes → rocks → back into the garage: 239 m in 140 s, 6.24 kWh charged to the rover battery through `RoverSystem.note_driven`, 0 stuck |
| Blocked exits | Refused while all six are boxed in; out through the one cleared |
| LAN | A client boards through the host, drives; the host accepts its poses (about 20 Hz), refuses spoofed ones, and charges the energy |

## 3. Merge fixes (executor)

- Each game scene now builds the rover itself (`GameMain.rover`). The tests use that presenter: a second presenter had put a second body on the rover.
- The presenter looked for `RoverSystem` at the wrong path, so energy went through its fallback (no ledger, trip or empty-battery alert). Fixed, and a check added.
- Pose updates go through `RoverSystem.note_pose`, so cargo and seated crew follow the rover.
- Rover reach: 6 m on the host, the vehicle's value (E-43). The garage station was moved beside the parked rover (E-43).
- The tests suit up the crew before boarding, as the real rule requires outside.

## 4. Numbers and sources

Every number is in `scripts\core\rover_balance.gd` and `data\rover.json` (`tuning`), with its category in `data\model_sources_rover.json`.
- Stat curves, energy per metre, charger power and the 60× map-distance factor are **fictional game tuning** built on real principles (rolling resistance, m·g·h under Mars gravity, drivetrain efficiency). They are not NASA crewed-rover specifications.
- Only Mars gravity is sourced (S01).

## 5. Limits

1. **Seats** (I-55): the model has no seats; four invisible anchors use the rig's seated pose.
2. **Wheels** (I-55): they are part of one mesh and do not turn on screen.
3. **Windows** (I-55): opaque from outside, so seated crew are not seen.
4. **Salvage shortfall** (I-56): at most 38 parts against a demand of 102, so a maximised rover is out of reach. This is an owner decision.
5. **Not seen on screen:** cameras, the seat view, the HUD layout and the rover lamps while driving were not checked visually.
6. **Network:** tested in one process over 127.0.0.1, not a real LAN.
7. **Weaker or heavier builds** may stall on the steepest dunes (17–20°).
