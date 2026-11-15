# FPV drone reference (owner, 2026-11-15)

The owner's example Godot 4.7 project (`fpv-drone.zip`) for **how the scout drone should fly and what its screen
should look like**. Reference only: this folder has a `.gdignore`, so Godot never imports or runs it inside the
colony project. Speed and battery life are the variables the drone upgrades change.

- `flight_controller.gd`: CharacterBody3D flight. W A S D move relative to where the drone faces, the mouse turns
  (yaw), Space up, Ctrl down. Smooth exponential responses (horizontal 4.2, brake 6.5, vertical 7.5, yaw 28, pitch 8),
  the camera and model tilt forward 7° / back 5° with the stick. Exported `horizontal_speed` (18 m/s here) and
  `vertical_speed` (6 m/s).
- `flight_hud.gd`: the on-screen display: STAB mode tag + FPV/CHASE, a compass tape with heading, aircraft battery
  % with an icon and time left (low at 20 %, critical at 10 %, pulsing banner), ground speed, home distance, flight
  time, a centre reticle in FPV, and a progress pip row. Font IBM Plex Mono (OFL).
- `range.gd` / `range.tscn`: the practice range: `battery_life_seconds` (360 s here), telemetry each frame, C camera,
  R reset, Esc pause.
- `assets/fpv_racer.glb`: "FPV Racer" (Robots and Drones Kit, 3DAssets.dev, CC0 1.0).
- `project.godot.txt`: the original project settings (120 physics ticks, Jolt, physics interpolation).
