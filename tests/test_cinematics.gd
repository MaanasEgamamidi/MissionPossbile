extends SceneTree
## Cinematics (2026-11-14 owner whiteboard; Prompt Pack V01-V07): the new-game intro fly-in and the "base operational"
## tour of every restored room. Checks the authored paths against the real map collision, durations, captions, skip,
## once-per-colony intro, the tour starting only from the replicated flag (never on a load or late join that is
## already operational), player input blocked and given back, danger aborting, the host simulation running on, and
## the camera's cull mask drawing every zone on the path (rooms woken through the perf ZoneManager).
## Run: godot --headless --path . --script res://tests/test_cinematics.gd

const Rail := preload("res://scripts/cinematics/cinematic_rail.gd")
const PresenterScript := preload("res://scripts/cinematics/cinematics_presenter.gd")
const SAVE_ROOT := "res://_test_saves/test_cinematics"
const TOUR_ROOMS := ["Command Room", "Power Room", "Greenhouse", "Garden dome", "Med Bay", "Hangar bay", "Airlock"]

var _passed := 0
var _total := 0


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data_checks()
	await _world_checks()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# ================================================================ data only

func _data_checks() -> void:
	Rail.reload()
	var intro := Rail.sequence("intro")
	var tour := Rail.sequence("tour")
	_check("data: data/cinematics.json has an intro and a tour", not Rail.segments(intro).is_empty() and not Rail.segments(tour).is_empty())
	var intro_s := Rail.seq_seconds(intro)
	_check("intro: 15 to 25 seconds long", intro_s >= 15.0 and intro_s <= 25.0, "%.1f s" % intro_s)

	var cfg := GameConfig.new()
	var seg: Dictionary = Rail.segments(intro).back()
	var end := Rail.sample(seg, Rail.seg_seconds(seg))
	var spawn := cfg.tutorial_spawn_position
	var fwd := Vector3(-sin(cfg.tutorial_spawn_yaw), 0.0, -cos(cfg.tutorial_spawn_yaw))     # where the crew face
	var behind := (end[0] - spawn).dot(fwd) < -1.0
	_check("intro: ends behind the crew (2-7 m back from the spawn, looking the way they face, at the tunnel door)",
		behind and Vector2(end[0].x - spawn.x, end[0].z - spawn.z).length() < 7.0 and (end[1] - end[0]).normalized().dot(fwd) > 0.8,
		"camera %s look %s spawn %s" % [end[0], end[1], spawn])
	var start := Rail.sample(Rail.segments(intro)[0], 0.0)
	_check("intro: starts high and far outside the base (a fly-in)", start[0].y > 15.0 and start[0].distance_to(spawn) > 40.0, str(start[0]))
	var words := ""
	var speakers := {}
	for s: Dictionary in Rail.segments(intro):
		for c: Dictionary in s.get("captions", []):
			words += " " + String(c.text).to_lower()
			speakers[String(c.speaker)] = true
	var story := ["2060s", "earth", "home", "second team", "first team", "silent", "tapes"]
	var missing := story.filter(func(w: String) -> bool: return not words.contains(w))
	_check("intro: Mission Control tells the story (2060s, Earth, a new home, second team, the silent first team, the tapes)",
		missing.is_empty() and speakers.keys() == ["Mission Control"], "missing %s, speakers %s" % [missing, speakers.keys()])

	var segs := Rail.segments(tour)
	var inside := []
	var bad := PackedStringArray()
	for s: Dictionary in segs:
		inside.append_array(s.get("inside", []))
		var secs := Rail.seg_seconds(s)
		var cap := String(s.get("caption", ""))
		if cap == "" or not cap.contains(":"):
			bad.append("%s has no 'Room: what was fixed' caption" % s.id)
		if s.id != "hangar" and s.id != "airlock" and (secs < 4.0 or secs > 6.0):
			bad.append("%s lasts %.1f s" % [s.id, secs])
	var hangar_pair := 0.0
	for s: Dictionary in segs:
		if s.id == "hangar" or s.id == "airlock":
			hangar_pair += Rail.seg_seconds(s)
	_check("tour: every restored room has its own 4-6 s shot with a caption (Hangar and sealed airlock share 4-6 s)",
		bad.is_empty() and hangar_pair >= 4.0 and hangar_pair <= 6.0 and TOUR_ROOMS.all(func(r: String) -> bool: return inside.has(r)),
		"; ".join(bad) + " hangar+airlock %.1f s, rooms %s" % [hangar_pair, inside])
	_check("tour: ends on 'Base operational'", String((tour.get("end_card", {}) as Dictionary).get("text", "")) == "Base operational")


# ================================================================ in the real map

func _world_checks() -> void:
	var dir := ProjectSettings.globalize_path(SAVE_ROOT).path_join("world")
	SaveService.new(dir, "colony", 2).delete_all()
	var seen_file := ProjectSettings.globalize_path(SAVE_ROOT).path_join("seen.json")
	DirAccess.make_dir_recursive_absolute(seen_file.get_base_dir())
	if FileAccess.file_exists(seen_file):
		DirAccess.remove_absolute(seen_file)
	var main := (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.load_world = true
	main.show_menu = false              # as tests and capture tools start: no cinematics unless forced
	main.check_weather_updates = false
	main.save_directory = dir
	root.add_child(main)
	await _frames(30)
	var services := main.services
	var st := services.state()
	var pres: Node = main.get_node_or_null(PresenterScript.NODE_NAME)
	_check("hook: GameMain attached the cinematics presenter", pres != null)
	if pres == null:
		return
	pres.set("seen_path", seen_file)
	var cine: Node = pres.get("player_node")
	_check("gate: a game started without the main menu (tests, capture tools) and headless plays nothing",
		not bool(pres.call(&"is_playing")) and not bool(pres.get("intro_played")) and not bool(pres.call(&"enabled")))

	# ---- every authored path against the map's collision
	var player := main.player
	var space := player.get_world_3d().direct_space_state
	var zones := services.zones
	var problems := PackedStringArray()
	var checked := 0
	for id: String in ["intro", "tour"]:
		for seg: Dictionary in Rail.segments(Rail.sequence(id)):
			var found := Rail.check_segment(seg, space, zones)
			if not found.is_empty():
				problems.append("%s: %d problem samples, first: %s" % [seg.id, found.size(), " | ".join(found.slice(0, 3))])
			checked += 1
	_check("paths: no camera path touches a wall, prop, rock or door leaf, leaves its room, nears a ceiling or the dome glass, or loses its focus behind collision (%d shots, %.2f m camera ball)" % [checked, Rail.radius()],
		problems.is_empty() and checked >= 8, "\n  " + "\n  ".join(problems.slice(0, 25)))
	var collider_count := 0
	for n in main.collision.find_children("*", "CollisionShape3D", true, false):
		collider_count += 1
	_check("paths: checked against the full map collision (walls, props, rocks, terrain)", collider_count > 1000, "%d shapes" % collider_count)

	# ---- intro: once per new colony, only in tutorial mode
	pres.set("force", true)
	_check("intro: wanted on a new tutorial-mode colony this machine has not seen", bool(pres.call(&"wants_intro")))
	services.config.tutorial_start_outside = false
	_check("intro: never when the tutorial switches are off", not bool(pres.call(&"wants_intro")))
	services.config.tutorial_start_outside = true
	var hours0 := st.sim_hours
	pres.set("_intro_decided", false)
	await _frames(3)
	_check("intro: starts by itself at the start of play", bool(pres.call(&"is_playing")) and pres.get("last_started") == &"intro")
	var cam: Camera3D = cine.get("camera")
	_check("intro: the cinematic camera is the one on screen", cam != null and main.get_viewport().get_camera_3d() == cam)
	_check("intro: the player takes no keys or mouse while it plays", not player.input_enabled)
	_check("intro: the HUD steps aside", main.hud != null and not main.hud.visible)
	_check("intro: the player's own spot and body are not moved", player.global_position.distance_to(st.character(&"crew_1").position) < 0.5)
	_check_mask("intro", main, cine)
	cine.call(&"advance", 1.5)
	_check("intro: Mission Control speaks", String(cine.get("caption_speaker")) == "Mission Control" and String(cine.get("caption_text")).contains("2060s"), String(cine.get("caption_text")))
	await _frames(20)
	_check("intro: the host simulation keeps running underneath", st.sim_hours > hours0, "%.5f -> %.5f h" % [hours0, st.sim_hours])
	_check("intro: remembered for this colony on this machine", bool(pres.call(&"has_seen_intro", str(st.rng_seed))) and not bool(pres.call(&"has_seen_intro", "another colony")))
	# skip with E
	_press(KEY_E)
	await _frames(2)
	_check("skip: E ends the intro", not bool(pres.call(&"is_playing")) and cine.get("result") == &"skipped")
	_check_restored("skip (E)", main, cine)
	pres.set("_intro_decided", false)
	await _frames(3)
	_check("intro: not shown a second time for the same colony (save, load, rejoin)", not bool(pres.call(&"is_playing")) and not bool(pres.call(&"wants_intro")))
	# Esc and Space skip too, and Esc does not open the pause menu
	for key: Key in [KEY_ESCAPE, KEY_SPACE]:
		pres.call(&"start", &"intro")
		await _frames(2)
		_press(key)
		await _frames(2)
		_check("skip: %s ends the intro%s" % [OS.get_keycode_string(key), " and opens no pause menu" if key == KEY_ESCAPE else ""],
			cine.get("result") == &"skipped" and main.ui.pause_menu() == null and not main.ui.is_open())
	# a full run
	pres.call(&"start", &"intro")
	await _frames(2)
	var t := 0.0
	while bool(cine.call(&"is_playing")) and t < 40.0:
		cine.call(&"advance", 0.1)
		t += 0.1
	_check("intro: plays to its end and gives control back", cine.get("result") == &"done" and t >= 15.0 and t <= 25.5, "%.1f s" % t)
	await _frames(3)
	_check_restored("intro end", main, cine)

	# ---- tour: only from the replicated flag
	_check("tour: nothing while the base is not operational", not bool(pres.get("tour_pending")) and not bool(pres.get("tour_played")))
	st.campaign[PresenterScript.OPERATIONAL_KEY] = {"done": true, "at_hours": st.sim_hours}
	await _frames(3)
	_check("tour: starts when state.campaign.base_operational turns true", bool(pres.call(&"is_playing")) and pres.get("last_started") == &"tour")
	_check("tour: the player takes no keys or mouse while it plays", not player.input_enabled)
	var shots := PackedStringArray()
	var mask_bad := PackedStringArray()
	var guard := 0
	while bool(cine.call(&"is_playing")) and guard < 2000:
		guard += 1
		var seg: Dictionary = cine.call(&"segment")
		if not seg.is_empty() and not shots.has(String(seg.id)):
			shots.append(String(seg.id))
			await _frames(1)
			mask_bad.append_array(_mask_problems(String(seg.id), main, cine))
			var cap := String(cine.get("caption_text"))
			var room := String((seg.get("inside", [""]) as Array)[0]).replace(" bay", "")
			if not cap.to_lower().contains(room.to_lower().split(" ")[0]):
				mask_bad.append("%s: caption '%s' does not name the room" % [seg.id, cap])
		if bool(cine.get("in_end_card")) and not shots.has("end"):
			shots.append("end")
			_check("tour: 'Base operational' card at the end", String(cine.get("caption_text")) == "Base operational")
		cine.call(&"advance", 0.1)
	_check("tour: visits every restored room in turn", shots.size() == 8 and TOUR_ROOMS.size() == 7, ", ".join(shots))
	_check("tour: every room on the path is drawn and in the camera's cull mask (woken through the ZoneManager), captions name the room", mask_bad.is_empty(), "; ".join(mask_bad))
	_check("tour: ends by itself", cine.get("result") == &"done")
	await _frames(3)
	_check_restored("tour end", main, cine)
	await _frames(10)
	_check("tour: shown once, not again while the flag stays true", not bool(pres.call(&"is_playing")) and not bool(pres.get("tour_pending")))

	# ---- a load or late join that is already operational sees no tour
	var late: Node = PresenterScript.new()
	main.add_child(late)
	late.call(&"setup", main, main.world, services)
	late.set("force", true)
	late.set("seen_path", seen_file)
	await _frames(5)
	_check("tour: a loaded save or late joiner that is already operational gets no tour", not bool(late.call(&"is_playing")) and not bool(late.get("tour_pending")))
	late.queue_free()
	await _frames(2)

	# ---- danger stops it at once; an unsafe player is not taken
	st.campaign[PresenterScript.OPERATIONAL_KEY] = {}
	await _frames(2)
	st.campaign[PresenterScript.OPERATIONAL_KEY] = {"done": true, "at_hours": st.sim_hours}
	var me := st.character(&"crew_1")
	var health := me.health
	me.health = 12.0
	await _frames(3)
	_check("safety: the tour waits while the player is hurt", bool(pres.get("tour_pending")) and not bool(pres.call(&"is_playing")))
	me.health = health
	await _frames(3)
	_check("safety: and starts once they are safe", bool(pres.call(&"is_playing")))
	me.health = 12.0
	await _frames(3)
	_check("safety: danger mid-shot stops it and gives control back", cine.get("result") == &"danger" and not bool(pres.call(&"is_playing")))
	me.health = health
	_check_restored("danger", main, cine)

	main.queue_free()
	await _frames(5)


func _press(key: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = down
		root.push_input(ev)


func _mask_problems(label: String, main: GameMain, cine: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var cam: Camera3D = cine.get("camera")
	if cam == null or main.get_viewport().get_camera_3d() != cam:
		out.append("%s: cinematic camera not current" % label)
		return out
	var zm := main.get_tree().get_first_node_in_group(&"zone_manager")
	var woken: PackedStringArray = cine.get("woken")
	var zones := main.services.zones
	for name in woken:
		if (cam.cull_mask & zones.bit_of(name)) == 0:
			out.append("%s: zone %s not in the cull mask" % [label, name])
		var z: Node = zm.call(&"zone", name) if zm != null else null
		if z != null and not bool(z.get("drawn")):
			out.append("%s: zone %s asleep" % [label, name])
	var seg: Dictionary = cine.call(&"segment")
	for name in Rail.zones_on_path(seg, zones):
		if not woken.has(name):
			out.append("%s: zone %s on the path was not woken" % [label, name])
	if zm == null:
		out.append("no ZoneManager in the game (perf rig missing)")
	return out


func _check_mask(label: String, main: GameMain, cine: Node) -> void:
	var bad := _mask_problems(label, main, cine)
	_check("%s: every zone on the path is drawn and in the camera's cull mask" % label, bad.is_empty(), "; ".join(bad))


func _check_restored(label: String, main: GameMain, cine: Node) -> void:
	var p := main.player
	var zm := main.get_tree().get_first_node_in_group(&"zone_manager")
	var ec := main.get_tree().get_first_node_in_group(&"exterior_controller")
	var ok := main.get_viewport().get_camera_3d() == p.camera_rig().camera() and p.input_enabled and main.hud.visible \
		and cine.get("camera") == null and (zm == null or zm.is_processing()) and (ec == null or ec.is_processing())
	_check("%s: camera, controls, HUD and room sleep/wake are back" % label, ok,
		"cam=%s input=%s hud=%s zm=%s" % [main.get_viewport().get_camera_3d(), p.input_enabled, main.hud.visible, zm.is_processing() if zm != null else null])
