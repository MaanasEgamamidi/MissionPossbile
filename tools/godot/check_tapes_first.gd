extends SceneTree
## Owner-requested headless check (2026-11-14, "tapes first"): in a new tutorial game nothing but the room tapes (and
## the suit rack) can be used until all tapes are found, the broken parts show no green / red glow, gold lines lead
## from just inside the base to every tape, a tape picked up while the game runs sparkles and its line goes, and once
## every tape is found the repair spots, the cassette player and the green / red glow come back while the lines go.
## Uses the real data files and models in an empty world (no 300 MB map). Collects tapes the way CassetteRuntime does
## (state.repair.collected_cassettes), so the presenters see the replicated state as on every client.
## Run: godot --headless --path . --script res://tools/godot/check_tapes_first.gd
const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
const TutorialLock := preload("res://scripts/session/tutorial_lock.gd")
const SAVE_DIR := "res://_test_saves/check_tapes_first"

var _ok := 0
var _all := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_all += 1
	if ok:
		_ok += 1
	print(("PASS " if ok else "FAIL ") + label + (("  " + detail) if detail != "" else ""))


func _initialize() -> void:
	PlayerInput.ensure_actions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var host := GameServices.new()
	host.name = "Services_check"
	host.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), "check", 1)
	root.add_child(host)
	host.set_process(false)
	host.start_new_game(7311)
	var st := host.state()
	TutorialSystem.begin_tutorial_mode(st, true)
	await process_frame
	# The stations' sensing areas, as WorldCollision makes them (tapes, the player and the repair spots).
	var collision := Node3D.new()
	collision.name = "Collision"
	root.add_child(collision)
	var stations := Node3D.new()
	stations.name = "Stations"
	collision.add_child(stations)
	for entry: Dictionary in StationCatalog.extra_entries():
		if entry.has("id") and entry.has("position"):
			var q: Array = entry.position
			stations.add_child(WorldCollision._station_volume(String(entry.id), String(entry.kind), Vector3(float(q[0]), float(q[1]), float(q[2]))))
	var world := Node3D.new()
	world.name = "CheckWorld"
	root.add_child(world)
	var parts: BrokenParts = BrokenParts.new()
	root.add_child(parts)
	parts.set_process(false)
	parts.setup(world, host, null)
	parts.step(0.3)
	var tapes := CassettePresenter.new()
	tapes.name = "CassettePresenter"
	root.add_child(tapes)
	tapes.set_process(false)
	tapes.setup(host, collision)
	var trails = tapes.trails
	if trails != null:
		trails.set_process(false)
	await physics_frame
	var n := TutorialSystem.tape_count()
	var ids: Array = CassetteCatalog.TAPES.keys()
	ids.sort()
	var tasks: Array = parts.parts.keys()
	tasks.sort()

	# ---- a new tutorial game: tapes first
	_check("new game: tutorial mode on, no tape found, repairs not unlocked", TutorialSystem.tutorial_active(st) and TutorialSystem.tapes_found(st) == 0
		and not TutorialSystem.repairs_unlocked(st))
	var locked_spots := 0
	var spots := 0
	for sid: String in st.stations:
		var rec: Dictionary = st.stations[sid]
		if String(rec.get("kind", "")) == "repair_task":
			spots += 1
			if not TutorialLock.station_usable(st, rec):
				locked_spots += 1
	var player_rec: Dictionary = st.stations.get(CassetteCatalog.PLAYER_ID, {})
	var want := "Find all %d tapes first: follow the gold lines." % n
	_check("lock: every repair spot is locked before the tapes (no [E] on the HUD)", spots >= 10 and locked_spots == spots, "%d of %d locked" % [locked_spots, spots])
	_check("lock: the Command Room cassette player is locked, with the plain message", not player_rec.is_empty() and not TutorialLock.station_usable(st, player_rec)
		and TutorialLock.message_for(st, player_rec) == want, TutorialLock.message_for(st, player_rec))
	var tapes_usable := 0
	for id: String in ids:
		if TutorialLock.station_usable(st, st.stations.get(id, {"kind": "missing"})):
			tapes_usable += 1
	var suits_ok := false
	for sid: String in st.stations:
		if String(st.stations[sid].get("kind", "")) == "suits":
			suits_ok = TutorialLock.station_usable(st, st.stations[sid])
	_check("lock: every tape pickup and the suit rack still work", tapes_usable == n and suits_ok, "%d tapes usable, suits %s" % [tapes_usable, suits_ok])
	var open := host.request(&"cassette_open", StringName(CassetteCatalog.PLAYER_ID))
	var claim := host.request(&"task_claim", &"repair_t01", {"generation": int(st.repair.tasks.T01.fault_generation)})
	var collect := host.request(&"cassette_collect", StringName(String(ids[0])))
	_check("host: the player and a repair spot are refused with the message; a tape pickup is not refused by the lock",
		not open.ok and open.reason == TutorialLock.REASON and open.message == want and not claim.ok and claim.reason == TutorialLock.REASON
		and collect.reason != TutorialLock.REASON, "%s / %s / %s" % [open.reason, claim.reason, collect.reason])
	var glowing := 0
	var broken := 0
	for task_id: String in tasks:
		if parts.shows_broken(task_id):
			broken += 1
		if parts.glow_of(task_id) != "":
			glowing += 1
		for g in BrokenParts._geometry(parts.parts[task_id].model):
			if g.material_overlay == BrokenParts.glow_material(true) or g.material_overlay == BrokenParts.glow_material(false):
				glowing += 1
	_check("broken parts: still broken-looking, but no green / red glow before the tapes", tasks.size() == 10 and broken == 10 and glowing == 0,
		"%d broken, %d glows" % [broken, glowing])

	# ---- the gold lines
	_check("tapes: every tape glows rich gold", _tape_glow_ok(tapes, ids))
	var trail_ids: Array = trails.trails.keys() if trails != null else []
	trail_ids.sort()
	_check("lines: one gold line per tape is loaded from data/tape_trails.json and shown", trails != null and trail_ids == ids and trails.visible_count() == n,
		"%d lines, %d shown" % [trail_ids.size(), trails.visible_count() if trails != null else 0])
	var entries := {}
	for entry: Dictionary in StationCatalog.extra_entries():
		entries[String(entry.get("id", ""))] = entry
	var start: Vector3 = trails.start if trails != null else Vector3.INF
	_check("lines: they start together just inside the base (airlock side of the exit tunnel's inner door)",
		start.distance_to(Vector3(22.0, 0.0, 9.0)) < 1.0, str(start))
	for id: String in ids:
		var end: Vector3 = trails.end_point(id) if trails != null else Vector3.INF
		var anchor: Array = (entries.get(id, {}) as Dictionary).get("position", [0, 0, 0])
		var prop: Array = (entries.get(id, {}) as Dictionary).get("prop_position", anchor)
		var to_anchor := Vector2(end.x, end.z).distance_to(Vector2(float(anchor[0]), float(anchor[2])))
		var to_prop := Vector2(end.x, end.z).distance_to(Vector2(float(prop[0]), float(prop[2])))
		var first: Vector3 = (trails.trails[id].points as PackedVector3Array)[0] if trails != null and trails.trails.has(id) else Vector3.INF
		_check("lines: %s starts at the start and ends at its tape" % id, minf(to_anchor, to_prop) < 1.0 and first.distance_to(start) < 1.2,
			"end %.2f m from the anchor, %.2f m from the tape" % [to_anchor, to_prop])
	# Owner 2026-11-14: the ribbons were replaced by sparkle particles (one GPUParticles3D per line).
	var line: GPUParticles3D = trails.trails[ids[0]].node if trails != null else null
	var proc := line.process_material as ParticleProcessMaterial if line != null else null
	_check("lines: drawn as gold sparkles along the path, on every zone's render layer", proc != null
		and proc.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS and proc.emission_point_count > 10
		and line.amount > 10 and line.emitting and line.visibility_aabb.size.length() > 1.0
		and (line.layers & host.zones.sun_bit()) != 0 and (line.layers & host.zones.bit_of("Airlock")) != 0)

	# ---- picking up a tape (the replicated state, as CassetteRuntime.apply writes it)
	var first_id: String = ids[0]
	var before := tapes.bursts_started
	(st.repair.collected_cassettes as Array).append(first_id)
	tapes.refresh()
	var burst: Node3D = tapes.last_burst
	var stars := 0
	var emitting := false
	if burst != null and burst.get(&"particles") != null:
		var pnode: GeometryInstance3D = burst.get(&"particles")
		stars = int(pnode.get(&"amount"))
		emitting = bool(pnode.get(&"emitting"))
	_check("pickup: collecting %s starts a sparkle burst over the tape" % first_id, tapes.bursts_started == before + 1 and burst != null and emitting and stars >= 60,
		"%d stars, emitting=%s" % [stars, emitting])
	for i in 40:
		tapes.step_vanish(0.05)
		trails.step(0.05)
	_check("pickup: the tape is gone after its sparkle and its line has faded out; the other lines stay",
		not (tapes.cassette_nodes[first_id] as Node3D).visible and not trails.shown(first_id) and not (trails.trails[first_id].node as Node3D).visible
		and trails.visible_count() == n - 1, "%d lines shown" % trails.visible_count())
	_check("pickup: one tape found is not enough: repair spots, the player and the glow stay off",
		not TutorialLock.station_usable(st, player_rec) and not TutorialLock.station_usable(st, st.stations["repair_t01"]) and parts.glow_of("T01") == "")

	# ---- a loaded colony with tapes already collected: no sparkles
	var count := tapes.bursts_started
	tapes._on_game_loaded("check")
	_check("load: a colony with a tape already collected shows it gone without sparkles", tapes.bursts_started == count)

	# ---- every tape found
	for id: String in ids:
		if not CassetteCatalog.collected(st, id):
			(st.repair.collected_cassettes as Array).append(id)
			tapes.refresh()
	for i in 40:
		tapes.step_vanish(0.05)
		trails.step(0.05)
	parts.step(0.3)
	_check("all tapes: repairs unlocked; Tapes found %d/%d" % [TutorialSystem.tapes_found(st), n], TutorialSystem.repairs_unlocked(st) and TutorialSystem.tapes_found(st) == n)
	var usable_spots := 0
	for sid: String in st.stations:
		var rec: Dictionary = st.stations[sid]
		if String(rec.get("kind", "")) == "repair_task" and TutorialLock.station_usable(st, rec):
			usable_spots += 1
	_check("all tapes: the broken repair spots and the cassette player work", usable_spots == 10 and TutorialLock.station_usable(st, player_rec),
		"%d spots usable" % usable_spots)
	var me := host.local_character()
	var spec := String(me.specialty) if me != null else ""
	var right := 0
	for task_id: String in tasks:
		if parts.glow_of(task_id) == ("green" if BrokenParts.can_do(task_id, spec) else "red"):
			right += 1
	_check("all tapes: the green / red glow is back on every broken part", right == 10, "%d of 10" % right)
	_check("all tapes: every gold line is hidden", trails.visible_count() == 0)
	TutorialSystem.skip_tutorial(st, null)
	trails.refresh(true)
	_check("after the tutorial: no lines, everything usable", trails.visible_count() == 0 and TutorialLock.station_usable(st, player_rec))
	host.saves.delete_all()
	print("RESULT %d/%d" % [_ok, _all])
	quit(0 if _ok == _all else 1)


func _tape_glow_ok(tapes: CassettePresenter, ids: Array) -> bool:
	for id: String in ids:
		var station := tapes.cassette_nodes.get(id) as Node3D
		if station == null:
			return false
		var lit := false
		for g in station.find_children("*", "MeshInstance3D", true, false):
			var m := (g as MeshInstance3D).material_overlay as ShaderMaterial
			if m != null and Color(m.get_shader_parameter(&"gold")).is_equal_approx(CassettePresenter.TAPE_GLOW):
				lit = true
		if not lit or not CassettePresenter.TAPE_GLOW.is_equal_approx(Color(1.0, 0.75, 0.2)):
			return false
	return true
