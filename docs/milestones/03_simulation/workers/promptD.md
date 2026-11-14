Read ..\SPEC.md completely first: the ground rules, "What already exists", the shared game rules, and Part D.
Your project copy is the current folder. You are worker D.

Implement Part D exactly as specified: scripts/player/player_controller.gd, scripts/player/player_camera_rig.gd, scripts/player/player_input.gd, scripts/player/player_tuning.gd, scripts/player/player_visual.gd, scripts/player/carry_item.gd, tests/test_player.gd.

Do not create or edit any other project file (the .godot folder and *.uid files that Godot generates are fine,
and you may create throwaway files under tests\tmp\ or _test_saves\).
Then run your test with the Godot wrapper described in the spec and keep fixing until every check prints PASS and
the run prints no script errors. Work fast and do not over-engineer: straightforward, readable code.
Finish with the final message the spec asks for.
