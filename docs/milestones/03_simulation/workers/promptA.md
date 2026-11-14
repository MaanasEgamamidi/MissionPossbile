Read ..\SPEC.md completely first: the ground rules, "What already exists", the shared game rules, and Part A.
Your project copy is the current folder. You are worker A.

Implement Part A exactly as specified: scripts/session/action_service.gd, scripts/session/builtin_actions.gd, scripts/session/session_service.gd, scripts/session/legacy_stations.gd, scripts/world/station_catalog.gd, tests/test_session.gd.

Do not create or edit any other project file (the .godot folder and *.uid files that Godot generates are fine,
and you may create throwaway files under tests\tmp\ or _test_saves\).
Then run your test with the Godot wrapper described in the spec and keep fixing until every check prints PASS and
the run prints no script errors. Work fast and do not over-engineer: straightforward, readable code.
Finish with the final message the spec asks for.
