extends SceneTree
## Incremental cassette progression and the pitch shortcut, using real host actions.

const Lock := preload("res://scripts/session/tutorial_lock.gd")
const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
const Trails := preload("res://scripts/cassettes/tape_trail_presenter.gd")
var passed := 0
var total := 0
var events: Array[GameEvents] = []
var zones: ColonyZones
var stations: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, okay: bool) -> void:
	total += 1
	if okay:
		passed += 1
	print(("PASS " if okay else "FAIL ") + label)

func session() -> SessionService:
	var ev := GameEvents.new()
	events.append(ev)
	var s := SessionService.new(GameConfig.new(), GameBalance.new(), ev)
	var st := ColonyState.new_game(s.balance, 741)
	st.stations = stations.duplicate(true)
	s.zone_at_position = func(p: Vector3) -> String: return zones.zone_at_world(p)
	s.begin(st, SolClock.new())
	st.character(&"crew_1").owner_peer = 1
	TutorialSystem.begin_tutorial_mode(st, true)
	return s

func at(s: SessionService, id: String) -> void:
	var actor := s.state.character_of_peer(1)
	s.report_position(1, actor.id, CharacterState._v3(s.state.stations[id].position), 0.0)

func _run() -> void:
	zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	stations = StationCatalog.from_manifest("res://data/colony_manifest.json", zones)
	for id: String in CassetteCatalog.TAPES:
		var s := session()
		check("fresh colony has locked repairs " + id, not TutorialSystem.repairs_unlocked(s.state))
		at(s, id)
		check("pickup succeeds " + id, s.request(&"cassette_collect", StringName(id)).ok)
		var room := String(CassetteCatalog.TAPES[id].room_id)
		for task: String in RepairCatalog.TASKS:
			check("only collected room unlocked %s %s" % [id, task], TutorialSystem.task_unlocked(s.state, task) == (String(RepairCatalog.TASKS[task][0]) == room))
		check("other features wait for first playback " + id, not TutorialSystem.specialty_features_unlocked(s.state))
		at(s, CassetteCatalog.PLAYER_ID)
		check("deck opens after one pickup " + id, s.request(&"cassette_open", StringName(CassetteCatalog.PLAYER_ID)).ok)
		check("one collected tape plays immediately " + id, s.request(&"cassette_select", StringName(CassetteCatalog.PLAYER_ID), {"cassette_id": id}).ok)
		check("playback restores station features " + id, TutorialSystem.specialty_features_unlocked(s.state))
		check("other station usability restored " + id, Lock.station_usable(s.state, {"kind": "power"}))
		check("still one found and played " + id, TutorialSystem.tapes_found(s.state) == 1 and TutorialSystem.tapes_played(s.state) == 1)
		var goals := ColonyGoals.all(s.state)
		check("all-tapes goal stays incomplete " + id, goals.any(func(g: Dictionary) -> bool: return g.id == "tapes_found" and not g.done and int(g.have) == 1 and int(g.need) == 6))
		var missing := "cassette_hangar" if id != "cassette_hangar" else "cassette_med_bay"
		check("uncollected tape still unavailable " + id, s.request(&"cassette_select", StringName(CassetteCatalog.PLAYER_ID), {"cassette_id": missing}).reason == &"cassette_missing")
		var other_task := "T11" if room != "hangar" else "T09"
		at(s, RepairCatalog.anchor_id(other_task))
		check("host rejects other room's puzzle " + id, s.request(&"task_claim", StringName(RepairCatalog.anchor_id(other_task)), {"generation": int(s.state.repair.tasks[other_task].fault_generation)}).reason == Lock.REASON)
		var saved := ColonyState.from_dict(JSON.parse_string(JSON.stringify(s.state.to_dict())))
		check("partial progress survives save and replica " + id, TutorialSystem.tapes_found(saved) == 1 and TutorialSystem.tapes_played(saved) == 1 and TutorialSystem.task_unlocked(saved, String(RepairCatalog.ROOMS[room].tasks[0])))
	var demo := session()
	check("non-host cannot grant demo tapes", demo.request(&"demo_collect_cassettes", &"", {}, 2).reason == &"host_only")
	var grant := demo.request(&"demo_collect_cassettes")
	check("demo collects all six", grant.ok and int(grant.changes.added) == 6 and TutorialSystem.tapes_found(demo.state) == 6)
	check("demo does not fake playback or repairs", TutorialSystem.tapes_played(demo.state) == 0 and TutorialSystem.fixed_count(demo.state) == 0 and not TutorialSystem.is_tutorial_done(demo.state))
	check("demo is idempotent", int(demo.request(&"demo_collect_cassettes").changes.added) == 0 and demo.state.repair.collected_cassettes.size() == 6)
	check("general repair is green", BrokenParts.glow_material(true).get_shader_parameter(&"gold") == BrokenParts.GLOW_CAN)
	check("own specialty is gold", BrokenParts.glow_material(true, true).get_shader_parameter(&"gold") == BrokenParts.GLOW_SPECIALTY)
	check("wrong specialty is red", BrokenParts.glow_material(false, true).get_shader_parameter(&"gold") == BrokenParts.GLOW_CANNOT)
	check("pickup box enlarged along every axis", CassettePresenter.TAPE_REACH.is_equal_approx(Vector3(0.75, 0.45, 0.66)))
	var collision := WorldCollision.build("res://data/colony_manifest.json", "res://data/colliders.json")
	for id: String in CassetteCatalog.TAPES:
		var area := collision.get_node("Stations/" + id) as Area3D
		check("pickup sphere enlarged " + id, is_equal_approx(((area.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius, 0.57))
	collision.free()
	for ev: GameEvents in events:
		ev.free()
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)
