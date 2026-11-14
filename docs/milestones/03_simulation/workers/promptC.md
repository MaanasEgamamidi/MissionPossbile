Read ..\SPEC.md completely first: the ground rules, "What already exists", the shared game rules, and Part C.
Your project copy is the current folder. You are worker C.

Implement Part C exactly as specified: scripts/world/world_collision.gd, scripts/world/door_controller.gd, scripts/world/terrain_height.gd, tools/godot/build_heightmap.gd, tests/test_collision.gd.

Do not create or edit any other project file (the .godot folder and *.uid files that Godot generates are fine,
and you may create throwaway files under tests\tmp\ or _test_saves\).
Then run your test with the Godot wrapper described in the spec and keep fixing until every check prints PASS and
the run prints no script errors. Work fast and do not over-engineer: straightforward, readable code.
Finish with the final message the spec asks for.
