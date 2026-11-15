extends SceneTree
## Broken parts integration (2026-11-14, docs/revisions/BROKEN_PARTS_BRIEF.md): the broken/intact swap, the fix
## sparkle, the prompts, the T12 door leaves, the T11 hangar dust, saving and co-op. Headless; it builds its own small
## stand-in world, so it works with or without the 300 MB map and with or without the assets worker's glbs. When
## data/broken_parts.json and its glbs exist, it also loads every real part.
## Run: godot --headless --path . --script res://tests/test_broken_parts.gd

const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
const SparkleBurst := preload("res://scripts/tasks/sparkle_burst.gd")
const HangarDust := preload("res://scripts/tasks/hangar_dust.gd")
const SAVE_DIR := "res://_test_saves/test_broken_parts"
## Tasks the stand-in world gives a broken part (T05 and T07 have none, as in the game).
const STAND_IN := ["T02", "T11", "T12"]

var _passed := 0
var _total := 0
var host: GameServices
var _free_later: Array[Node] = []


func _check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", label, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", label, ": ", detail)


func _note(text: String) -> void:
	print("NOTE ", text)


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	PlayerInput.ensure_actions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	# The stand-in parts count as broken whether or not their puzzle files are installed yet.
	BrokenParts.broken_override = func(state: ColonyState, task_id: String) -> bool:
		var task: Dictionary = state.repair.get("tasks", {}).get(task_id, {})
		return STAND_IN.has(task_id) and not task.is_empty() and not bool(task.get("first_completed", false))
	host = _services("host")
	host.start_new_game(4242)
	await _frames()
	host.set_process(false)

	var w := _world("HostWorld")
	var p := _presenter(w, host)
	_test_start(p, w)
	_test_door(p, w)
	_test_dust(p, w)
	await _test_prompts()
	await _test_transition_and_coop(p, w)
	_test_low_preset(p, w)
	_test_save_and_late_join(p)
	_test_real_data()
	_test_real_registry()

	BrokenParts.broken_override = Callable()
	host.saves.delete_all()
	for n in _free_later:
		if is_instance_valid(n):
			n.queue_free()
	await _frames()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- stand-in world

func _services(label: String) -> GameServices:
	var s := GameServices.new()
	s.name = "Services_" + label
	s.saves = SaveService.new(ProjectSettings.globalize_path(SAVE_DIR), label, 1)
	root.add_child(s)
	s.set_process(false)
	_free_later.append(s)
	return s


func _box(node_name: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	return mi


## A tiny map: the Command Room rack, the tunnel lining and door 901's two leaves (with a working DoorController),
## and two dusty hangar objects (dust-free materials, as HabitatFinish leaves them).
func _world(label: String) -> Dictionary:
	var zones := host.zones
	var world := Node3D.new()
	world.name = label
	root.add_child(world)
	_free_later.append(world)
	var rack := _box("cr_rack", Vector3(0.8, 2.0, 0.6), Vector3(25.1, 1.0, -17.4))
	rack.layers = zones.bit_of("Command Room")
	world.add_child(rack)
	rack.add_child(_box("RackScreen", Vector3(0.3, 0.2, 0.05), Vector3(0, 0.5, 0.3)))
	var hall := Node3D.new()
	hall.name = "Glass hall"
	world.add_child(hall)
	var tunnel := _box("SFX_tunnel_inside", Vector3(4.0, 3.2, 6.0), Vector3(22.0, 1.6, 12.5))
	tunnel.layers = zones.bit_of("Airlock") | zones.outdoor_mask()
	hall.add_child(tunnel)
	var door := DoorController.new()
	door.name = "TunnelDoorInner"
	door.door_id = 901
	for side: int in [-1, 1]:
		var leaf_name := "TunnelDoorInner_%s" % ("L" if side < 0 else "R")
		var x0 := 20.2 if side < 0 else 22.0
		var x1 := 22.0 if side < 0 else 23.8
		var centre := Vector3((x0 + x1) * 0.5, 1.505, 10.475)
		var half := Vector3((x1 - x0) * 0.5, 1.515, 0.175)
		door.add_leaf(leaf_name, Transform3D(Basis(), centre), EnvironmentCollision.SLIDE_M * side, [{"c": [0, 0, 0], "h": [half.x, half.y, half.z], "q": [0, 0, 0, 1]}])
		var visual := _box(leaf_name, half * 2.0, centre)
		visual.layers = tunnel.layers
		hall.add_child(visual)
	var doors := Node3D.new()
	doors.name = "Doors_" + label
	root.add_child(doors)
	_free_later.append(doors)
	doors.add_child(door)
	door.attach_visuals(world)
	door.set_physics_process(false)
	var shader := load("res://materials/colony_surface.gdshader") as Shader
	var clean := ShaderMaterial.new()
	clean.shader = shader
	clean.set_shader_parameter(&"dust_gain", 0.0)
	var hangar: Array[MeshInstance3D] = []
	for x: float in [16.0, 28.0]:
		var mi := _box("hg_crate_%d" % int(x), Vector3(1, 1, 1), Vector3(x, 0.5, -5.0))
		mi.set_meta("area", "Hangar")
		mi.set_surface_override_material(0, clean)
		world.add_child(mi)
		mi.set_instance_shader_parameter(&"dust", 0.0)
		hangar.append(mi)
	return {"world": world, "rack": rack, "tunnel": tunnel, "door": door, "hangar": hangar, "clean": clean,
		"leaf_l": hall.get_node("TunnelDoorInner_L"), "leaf_r": hall.get_node("TunnelDoorInner_R")}


## Broken models for the stand-in parts, built in code where the glbs would be.
func _parts() -> Array:
	var t02 := Node3D.new()
	t02.add_child(_box("loose_wires", Vector3(0.8, 2.0, 0.6), Vector3(25.1, 1.0, -17.4)))
	t02.add_child(_box("spray", Vector3(0.2, 0.2, 0.2), Vector3(25.1, 0.1, -17.0)))
	var t12 := Node3D.new()
	t12.add_child(_box("leaf_L", Vector3(1.7, 3.0, 0.2), Vector3(21.1, 1.5, 10.47)))
	t12.add_child(_box("leaf_R", Vector3(1.7, 3.0, 0.2), Vector3(22.9, 1.5, 10.47)))
	t12.add_child(_box("vapour", Vector3(0.3, 0.6, 0.3), Vector3(22.0, 1.5, 10.2)))
	var t11 := Node3D.new()
	t11.add_child(_box("hg_dust__broken_a", Vector3(6, 0.02, 8), Vector3(17.0, 0.01, -3.0)))
	t11.add_child(_box("hg_dust__broken_b", Vector3(6, 0.02, 8), Vector3(27.0, 0.01, -3.0)))
	return [
		{"task_id": "T02", "node": t02, "zone": "Command Room", "hide_objects": ["cr_rack"], "effect_nodes": ["spray"],
			"bounds": {"center": [25.1, 1.0, -17.4], "size": [0.9, 2.1, 0.7]}, "prompt": "[E] Patch the relay", "special": ""},
		{"task_id": "T12", "node": t12, "zone": "Airlock", "hide_objects": ["SFX_tunnel_inside"], "effect_nodes": ["vapour"],
			"bounds": {"center": [22.0, 1.5, 10.47], "size": [3.6, 3.0, 0.4]}, "prompt": "[E] Seal the airlock", "special": "door_901"},
		{"task_id": "T11", "node": t11, "zone": "Hangar bay", "hide_objects": [], "effect_nodes": [],
			"bounds": {"center": [22.0, 0.5, -3.0], "size": [16.0, 1.0, 10.0]}, "prompt": "[E] Clear the landing lines", "special": "dust"},
		{"task_id": "T09", "glb": "res://assets/broken_parts/not_made_yet.glb", "zone": "Med Bay", "hide_objects": ["mb_sink_counter"]},
	]


func _presenter(w: Dictionary, services: GameServices, use_parts := true) -> BrokenParts:
	var p: BrokenParts = BrokenParts.new()
	p.name = "BrokenPartPresenter_" + String((w.world as Node).name)
	if use_parts:
		p.parts_override = _parts()
	p.door_901 = w.get("door")
	root.add_child(p)
	_free_later.append(p)
	p.set_process(false)          # the test steps it by hand
	p.setup(w.world, services, null)
	return p


func _model(p: BrokenParts, task_id: String) -> Node3D:
	return p.parts[task_id].model


func _run(p: BrokenParts, seconds: float, dt := 0.05) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		p.step(dt)
		t += dt


# ---------------------------------------------------------------- checks

func _test_start(p: BrokenParts, w: Dictionary) -> void:
	_check("part without its glb is skipped", not p.parts.has("T09") and p.parts.has("T02"), str(p.parts.keys()))
	var rack: MeshInstance3D = w.rack
	_check("broken at start: broken model shown, intact rack hidden", p.shows_broken("T02") and _model(p, "T02").visible and not rack.visible)
	_check("intact object keeps its node (collision and station target untouched)", is_instance_valid(rack) and rack.get_parent() == w.world and host.state().stations.has("repair_t02"))
	var cmd := host.zones.bit_of("Command Room")
	var on_layers := true
	for g in _model(p, "T02").find_children("*", "GeometryInstance3D", true, false):
		on_layers = on_layers and ((g as GeometryInstance3D).layers & cmd) != 0
	_check("broken model on its room's render layers", on_layers)
	_check("no transition at start", p.transitions_started == 0 and not p.in_transition("T02"))
	_check("tunnel lining never hidden", (w.tunnel as Node3D).visible)
	_check("door 901's intact leaves hidden while broken", not (w.leaf_l as Node3D).visible and not (w.leaf_r as Node3D).visible)


func _test_door(p: BrokenParts, w: Dictionary) -> void:
	var door: DoorController = w.door
	var model := _model(p, "T12")
	var leaf_l := model.get_node("leaf_L") as Node3D
	var leaf_r := model.get_node("leaf_R") as Node3D
	var vapour := model.get_node("vapour") as Node3D
	var l0 := leaf_l.global_position
	var r0 := leaf_r.global_position
	var intact := w.leaf_l as Node3D
	var intact0 := intact.global_position
	door.open_amount = 1.0
	door._move_leaves()
	p.step(0.0)
	var slide := EnvironmentCollision.SLIDE_M
	_check("door 901 still opens while broken (its own hidden leaves slide)", is_equal_approx(intact.global_position.x - intact0.x, -slide), str(intact.global_position - intact0))
	_check("broken leaves slide with door 901", is_equal_approx(leaf_l.global_position.x - l0.x, -slide) and is_equal_approx(leaf_r.global_position.x - r0.x, slide),
		"%s %s" % [leaf_l.global_position - l0, leaf_r.global_position - r0])
	_check("vapour stays at the gap", vapour.visible and vapour.position == Vector3(22.0, 1.5, 10.2))
	door.open_amount = 0.0
	door._move_leaves()
	p.step(0.0)
	_check("broken leaves close again", leaf_l.global_position.is_equal_approx(l0) and leaf_r.global_position.is_equal_approx(r0))


func _test_dust(p: BrokenParts, w: Dictionary) -> void:
	var dust: RefCounted = p.parts["T11"].dust
	var west: MeshInstance3D = w.hangar[0]
	var east: MeshInstance3D = w.hangar[1]
	var amount := float(dust.get(&"amount"))
	var start_levels: Array[float] = dust.get(&"levels")
	var west0 := float(west.get_instance_shader_parameter(&"dust"))
	_check("dusty hangar while broken", dust != null and west0 > 0.0 and west0 <= amount + 1e-4
		and float((west.get_surface_override_material(0) as ShaderMaterial).get_shader_parameter(&"dust_gain")) == 1.0, "%s of %s, levels %s" % [west0, amount, start_levels])
	_check("dust patches shown while broken", _model(p, "T11").get_node("hg_dust__broken_a").visible and _model(p, "T11").get_node("hg_dust__broken_b").visible)
	var task: Dictionary = host.state().repair.tasks.T11
	task.puzzle_state = {"dust": [0.0, 1.0]}
	p.step(0.25)
	_check("T11 state cleans the west area first", float(west.get_instance_shader_parameter(&"dust")) == 0.0 and is_equal_approx(float(east.get_instance_shader_parameter(&"dust")), amount),
		"%s / %s" % [west.get_instance_shader_parameter(&"dust"), east.get_instance_shader_parameter(&"dust")])
	_check("cleaned area's dust patch goes", not _model(p, "T11").get_node("hg_dust__broken_a").visible and _model(p, "T11").get_node("hg_dust__broken_b").visible)
	var levels: Array[float] = HangarDust.levels_from_task({"puzzle_state": {"patches": [{"clean": true}, {"dust": 2, "max": 4}, false]}})
	_check("dust levels from patch records", levels == ([0.0, 0.5, 1.0] as Array[float]), str(levels))
	var rule := HangarDust.rule()
	if rule != null:
		# The real T11 rule: six floor areas, state {"seed", "step", "areas": {id: dust left}}.
		task.puzzle_state = {}
		var areas: Array = rule.get_script_constant_map().AREAS
		var by_id: Dictionary = rule.call(&"area_dust", task)
		_check("T11 rule start: every area dusty", HangarDust.levels_from_task(task).size() == areas.size() and HangarDust.levels_from_task(task).all(func(v: float) -> bool: return v > 0.0))
		var cleaned := by_id.duplicate()
		cleaned["back_left"] = 0.0
		task.puzzle_state = {"seed": int(task.puzzle_seed), "step": 3, "areas": cleaned}
		p.step(0.25)
		var east_want := amount * float(by_id.back_right)
		_check("T11 rule state: cleaned back-left area loses its dust, back-right keeps it", float(west.get_instance_shader_parameter(&"dust")) == 0.0
			and is_equal_approx(float(east.get_instance_shader_parameter(&"dust")), east_want), "%s / %s (want %s)" % [west.get_instance_shader_parameter(&"dust"), east.get_instance_shader_parameter(&"dust"), east_want])
		_check("T11 rule: completed task reads all clean", HangarDust.levels_from_task({"first_completed": true, "puzzle_seed": 1}).all(func(v: float) -> bool: return v == 0.0))
	else:
		_check("dust levels from progress when the puzzle has no areas", HangarDust.levels_from_task({"progress": 0.25, "puzzle_state": {}}) == ([0.75] as Array[float]))
		_note("t11_rule.gd not installed: the T11 state is read tolerantly (dust/levels/patches/cleaned).")
	task.puzzle_state = {}


func _test_prompts() -> void:
	var hud := GameHud.new()
	root.add_child(hud)
	_free_later.append(hud)
	hud.setup(host)
	await _frames(1)
	hud.set_target({"kind": "station", "id": &"repair_t02", "node": null})
	var want := "[E] " + BrokenParts.prompt_body(BrokenParts.prompt_for("T02"))
	_check("broken spot names its fault", hud.cue_text() == want and BrokenParts.prompt_for("T02") != "", hud.cue_text())
	_check("broken prompt uses the data file's words", BrokenParts.part_of("T02").is_empty() or BrokenParts.prompt_for("T02") == String(BrokenParts.part_of("T02").prompt))
	hud.set_target({"kind": "station", "id": &"repair_t05", "node": null})
	_check("task without a broken part: plain Use prompt", hud.cue_text() == "[E] Use elements station", hud.cue_text())
	hud.set_target({"kind": "station", "id": &"pw_panel", "node": null})
	_check("other stations unchanged", hud.cue_text() == "[E] Use power panel", hud.cue_text())
	_check("station name in words", GameHud.repair_station_name({"name": "T01 - Comms"}) == "comms station" and GameHud.repair_station_name({}) == "station")
	for task_id: String in BrokenParts.FALLBACK_PROMPTS:
		var words := BrokenParts.prompt_for(task_id).to_lower()
		# UI overhaul: each prompt is the repair's action title ("[E] Water the kale" = the goal "Water the Kale").
		_check("prompt %s names the job (the repair's action title)" % task_id, words.begins_with("[e] ") and words.substr(4) == String(TutorialSystem.fix_def(task_id).get("text", "?")).to_lower(), words)
	set_meta(&"hud", hud)


func _test_transition_and_coop(p: BrokenParts, w: Dictionary) -> void:
	# A client that joined at the start: its own world and presenter, fed only by replicated state.
	var client := _services("client")
	var st := ColonyState.from_dict(host.state().to_dict())
	st.assign_from(host.state().to_dict())
	client.session.begin(st, SolClock.new())
	var cw := _world("ClientWorld")
	var cp := _presenter(cw, client)
	_check("client starts broken too", cp.shows_broken("T02") and not (cw.rack as Node3D).visible)
	# Local input alone changes nothing: an answer that claims a first completion is not the state.
	host.events.action_resolved.emit(ActionResult.success("forged", {"task_id": "T02", "first_completion": true}))
	p.step(0.05)
	cp.step(0.05)
	_check("no transition from a local answer", p.transitions_started == 0 and cp.transitions_started == 0)
	# The host's rule completes T02 (the real RepairRuntime path with a stand-in rule).
	var me := host.local_character()
	var station: Dictionary = host.state().stations["repair_t02"]
	me.position = CharacterState._v3(station.position)
	me.specialty = &"electrical_comms"
	host.session.repair_runtime.register_rule("T02", func(_task: Dictionary, move: Dictionary) -> Dictionary:
		if String(move.move) != "finish":
			return {"accepted": false}
		return {"accepted": true, "puzzle_state": {"done": 1}, "progress": 1.0, "complete": true})
	var gen := int(host.state().repair.tasks.T02.fault_generation)
	var claim := host.request(&"task_claim", &"repair_t02", {"generation": gen})
	var finish := host.request(&"task_move", &"repair_t02", {"generation": gen, "move": "finish", "value": 1})
	_check("host rule completes T02", claim.ok and finish.ok and bool(host.state().repair.tasks.T02.first_completed), "%s / %s" % [claim.reason, finish.reason])
	p.step(0.0)
	_check("transition starts on the host from the state change", p.transitions_started == 1 and p.in_transition("T02"))
	var burst := p.last_burst
	var stars := burst.get(&"particles") as GeometryInstance3D if burst != null else null
	_check("sparkle burst: 60-120 stars", stars != null and int(stars.get(&"amount")) >= 60 and int(stars.get(&"amount")) <= 120 and bool(stars.get(&"emitting")))
	_check("sparkle burst on the room's layers", stars != null and (stars.layers & host.zones.bit_of("Command Room")) != 0, str(stars.layers if stars != null else -1))
	_check("sparkle burst over the part's bounds", burst != null and burst.global_position.is_equal_approx(Vector3(25.1, 1.0, -17.4)))
	_check("GPU particles outside the Low preset", stars is GPUParticles3D)
	cp.step(0.05)
	_check("client waits for the replicated state", cp.transitions_started == 0 and cp.shows_broken("T02"))
	_run(p, 0.2)
	var model := _model(p, "T02")
	var glow := (model.get_node("loose_wires") as GeometryInstance3D).material_overlay as StandardMaterial3D
	_check("warm glow and shrinking before the swap", model.visible and glow != null and glow.albedo_color.a > 0.1 and model.transform.basis.get_scale().x < 0.99)
	_check("broken model still there at 0.2 s", p.shows_broken("T02") and not (w.rack as Node3D).visible)
	_run(p, 0.2)
	_check("at 0.35 s: intact back, broken gone, effects stopped", (w.rack as Node3D).visible and not model.visible and not (model.get_node("spray") as Node3D).visible and not p.shows_broken("T02"))
	_run(p, 0.7)
	_check("transition ends after about 1 s, glow removed", not p.in_transition("T02") and (w.rack as MeshInstance3D).material_overlay == null and (model.get_node("loose_wires") as GeometryInstance3D).material_overlay == null)
	# Replication: the client applies the host's state the way NetSession._rpc_update does.
	client.state().assign_from(host.state().to_dict(), &"")
	cp.step(0.0)
	_check("client plays the transition from the replicated change", cp.transitions_started == 1 and cp.in_transition("T02"))
	_run(cp, 1.1)
	_check("client ends intact", (cw.rack as Node3D).visible and not cp.shows_broken("T02"))
	# T11: completion cleans the hangar and shows the floor markings again.
	var task: Dictionary = host.state().repair.tasks.T11
	task.first_completed = true
	p.step(0.0)
	_run(p, 0.4)
	var west: MeshInstance3D = w.hangar[0]
	_check("fixed hangar: clean materials and no dust", float(west.get_instance_shader_parameter(&"dust")) == 0.0 and west.get_surface_override_material(0) == w.clean)
	_run(p, 0.7)
	set_meta(&"client", client)


func _test_low_preset(p: BrokenParts, w: Dictionary) -> void:
	GraphicsQuality.apply(self, GraphicsQuality.Level.LOW)
	host.state().repair.tasks.T12.first_completed = true
	p.step(0.0)
	var stars := p.last_burst.get(&"particles") as GeometryInstance3D if p.last_burst != null else null
	_check("Low preset uses CPU particles", stars is CPUParticles3D and p.last_burst.call(&"is_cpu"))
	_check("CPU stars on the room's layers", stars != null and (stars.layers & host.zones.bit_of("Airlock")) != 0)
	GraphicsQuality.apply(self, GraphicsQuality.Level.HIGH)
	var vapour := _model(p, "T12").get_node("vapour") as Node3D
	_run(p, 0.4)
	_check("sealed: vapour stops and the intact leaves are back", not vapour.visible and (w.leaf_l as Node3D).visible and (w.leaf_r as Node3D).visible)
	var door: DoorController = w.door
	var leaf := w.leaf_l as Node3D
	var before := leaf.global_position
	door.open_amount = 1.0
	door._move_leaves()
	_check("fixed door 901 opens with its own leaves", is_equal_approx(leaf.global_position.x - before.x, -EnvironmentCollision.SLIDE_M))
	door.open_amount = 0.0
	door._move_leaves()
	_run(p, 0.7)


func _test_save_and_late_join(p: BrokenParts) -> void:
	var payload: Dictionary = JSON.parse_string(JSON.stringify(host.snapshot()))
	var before := p.transitions_started
	host.restore(payload)
	p.step(0.0)
	_check("save/load: completed parts load intact", not p.shows_broken("T02") and not p.shows_broken("T12") and not p.shows_broken("T11"))
	_check("save/load: no sparkles on load", p.transitions_started == before and not p.in_transition("T02"))
	var old := payload.duplicate(true)
	(old.colony as Dictionary).erase("repair")
	host.restore(old)
	p.step(0.0)
	_check("older save without repair records loads broken", p.shows_broken("T02") and p.shows_broken("T12") and p.shows_broken("T11") and p.transitions_started == before)
	var older := payload.duplicate(true)
	for t: Dictionary in (older.colony.repair.tasks as Dictionary).values():
		t.erase("first_completed")
	host.restore(older)
	p.step(0.0)
	_check("older save without completion flags loads broken", p.shows_broken("T02") and p.transitions_started == before)
	host.restore(payload)
	p.step(0.0)
	# Late join: a client that arrives after the fix sees it fixed, with no sparkles.
	var late := _services("late")
	var st := ColonyState.from_dict(host.state().to_dict())
	st.assign_from(host.state().to_dict())
	late.session.begin(st, SolClock.new())
	var lw := _world("LateWorld")
	var lp := _presenter(lw, late)
	lp.step(0.0)
	_check("late join: fixed parts intact, no sparkles", not lp.shows_broken("T02") and (lw.rack as Node3D).visible and lp.transitions_started == 0
		and lp.find_children("SparkleBurst*", "", true, false).is_empty())


func _test_real_data() -> void:
	BrokenParts.reload_data()
	var data := BrokenParts.load_data()
	if data.is_empty():
		_note("data/broken_parts.json not written yet: real parts not checked.")
		return
	_check("data file lists parts", data.size() >= 1, str(data.size()))
	var w := {"world": Node3D.new()}
	root.add_child(w.world)
	_free_later.append(w.world)
	var p := _presenter(w, host, false)
	host.state().repair = RepairCatalog.fresh(7)
	p.snap()
	var loaded := 0
	for entry: Dictionary in data:
		var task_id := String(entry.get("task_id", ""))
		var glb := String(entry.get("glb", ""))
		var ok_entry := RepairCatalog.TASKS.has(task_id) and entry.has("prompt") and entry.has("zone")
		_check("data entry %s has task, zone and prompt" % task_id, ok_entry, str(entry.keys()))
		if not ResourceLoader.exists(glb):
			_note("%s: %s not imported yet, skipped." % [task_id, glb])
			_check("missing glb %s skipped" % task_id, not p.parts.has(task_id))
			continue
		if not STAND_IN.has(task_id):
			continue          # only stand-in tasks count as broken in this test
		var model: Node3D = p.parts[task_id].model if p.parts.has(task_id) else null
		if model == null:
			_note("%s: %s exists but does not load yet (import pending), skipped." % [task_id, glb])
			continue
		var geoms: Array = model.find_children("*", "GeometryInstance3D", true, false)
		if String(entry.get("special", "")) == "door_901":
			_check("real T12 model: both broken leaves slide with door 901", (p.parts[task_id].leaves as Array).size() == 2,
				str((p.parts[task_id].leaves as Array).map(func(l: Dictionary) -> String: return String((l.node as Node).name))))
		var bit := host.zones.bit_of(String(entry.zone))
		_check("real part %s loads on its room's layers" % task_id, model != null and not geoms.is_empty()
			and geoms.all(func(g: Node) -> bool: return ((g as GeometryInstance3D).layers & bit) != 0))
		loaded += 1
	_note("%d real broken models loaded." % loaded)


func _test_real_registry() -> void:
	BrokenParts.broken_override = Callable()
	var st := ColonyState.new_game(host.balance, 11)
	for task_id: String in ["T05", "T07"]:
		_check("%s has no puzzle, never broken" % task_id, not PuzzleRegistry.is_broken(st, task_id) and not BrokenParts.is_task_broken(st, task_id))
	for task_id: String in RepairCatalog.TASKS:
		if PuzzleRegistry.has_puzzle(task_id):
			_check("installed puzzle %s: new colony starts broken" % task_id, BrokenParts.is_task_broken(st, task_id))
			st.repair.tasks[task_id].first_completed = true
			_check("installed puzzle %s: fixed after completion" % task_id, not BrokenParts.is_task_broken(st, task_id))
	var hud := get_meta(&"hud") as GameHud
	if hud != null:
		hud.set_target({"kind": "station", "id": &"repair_t07", "node": null})
		_check("T07 keeps the plain prompt", hud.cue_text() == "[E] Use pipes station", hud.cue_text())
