# Perf overhaul, Phase 4: ViewActivator (gameplay gating, fast-turn safe)

Status: **implemented, ON by default, verified headless (3 crew models tagged), spin test not measured.**

File: `perf/view_activator.gd` (the brief's code; follows the main viewport's current camera). Tagging:
`PerfRig._tag_crew()` puts each other crew member's **model node** (`PlayerVisual._model`: skeleton +
AnimationPlayer) in group `view_gated`, re-checked every second so rebuilt crew are picked up. The crew body itself is
never gated: it carries the door-sensing `Presence` AnimatableBody3D, and disabling processing would remove it from
physics (doors would stop opening for that player). GameMain keeps moving the bodies; only animation pauses.

No enemies or turrets exist; nothing else in the game is expensive per entity (stations are Area3D, rovers are
gameplay and stay untagged).

Defaults as the brief: near 12 m, far 90 m, margin 20 deg, sleep +10 deg after 1.5 s, look-ahead 0.25 s up to +60 deg,
10 Hz, 6 wakes per tick. Expected gain is small (at most three skinned models); it is kept because it is cheap and
cannot change a visible pixel (a model outside the cone + margin is not on screen).
