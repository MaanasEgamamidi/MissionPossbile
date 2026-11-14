# Perf overhaul, Phase 3: exterior controller (Mars hidden only when sealed in)

Status: **implemented, ON by default, verified headless; with the default settings it never hides Mars.**

File: `perf/exterior_controller.gd`. Mars = `world/Terrain` + `world/Environment` (terrain chunks, 996 rocks, scenery,
the glass hall and tunnel) by `visible`, plus the 47 Exterior fixture lights (`ZoneLighting.set_zone_awake`) and the
Exterior render layer cleared from the gameplay camera. `ScoutWorld`, the sun and the WorldEnvironment are never
touched (`sun_off_when_exterior_hidden` stays false). Collision is separate, so hidden Mars still collides.

Rules as in the brief: shown when outside or unsure; hidden only after 1.5 s unneeded; re-checked on the frame any
door starts to open (`DoorController.opening_started`); kept shown within 4 m of a door toward a view or outside.

## Result

Headless walk of every zone (tests/test_perf.gd, `PERF-ROOM` lines): **Mars stays shown in all 17 zones.** Every
room is at most two glass doors/windows away from a zone with a view out (the plaza under the glass dome, or a room
with a glass door/window onto it), and 26 of 28 doors are glazed. With `exterior_check_hops = 2` (the brief's
default) the controller is correct but saves nothing on this map. That is reported, not hidden: it stays on because
it costs one graph walk per 0.1 s and becomes useful if doors lose their glass or the map grows.

`exterior_check_hops = 1` (`--perf-set=exterior_check_hops:1`) would hide Mars in rooms two hops from a view, at the
risk of a pop seen through two aligned glass panels; not recommended without a visual check.
