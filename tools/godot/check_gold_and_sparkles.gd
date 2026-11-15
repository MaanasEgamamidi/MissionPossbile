extends SceneTree
## Owner-requested headless check (2026-11-14): the green / red role glow on broken parts (green = this player can fix
## it, red = another specialist's job), the whole broken model as the aim target, the T12 vapour jet, and
## the sparkle burst when a broken part is fixed. Uses the real data/broken_parts.json and the real glbs, in an empty
## world (no 300 MB map), and completes each task the way the host does (first_completed in the replicated state).
## Run: godot --headless --path . --script res://tools/godot/check_gold_and_sparkles.gd
const BrokenParts := preload("res://scripts/tasks/broken_part_presenter.gd")
const SAVE_DIR := "res://_test_saves/check_gold_and_sparkles"

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
	host.start_new_game(7310)
	await process_frame
	var world := Node3D.new()
	world.name = "CheckWorld"
	root.add_child(world)
	# The repair stations' sensing areas, as WorldCollision makes them (the broken models add their aim shapes here).
	var stations := Node3D.new()
	stations.name = "Stations"
	root.add_child(stations)
	for entry: Dictionary in StationCatalog.extra_entries():
		if String(entry.get("kind", "")) == "repair_task" and entry.has("position"):
			var q: Array = entry.position
			stations.add_child(WorldCollision._station_volume(String(entry.id), "repair_task", Vector3(float(q[0]), float(q[1]), float(q[2]))))
	var p: BrokenParts = BrokenParts.new()
	root.add_child(p)
	p.set_process(false)
	p.setup(world, host, null)
	p.step(0.0)
	await physics_frame
	var st := host.state()
	var me := host.local_character()
	var my_spec := String(me.specialty) if me != null else ""
	var tasks: Array = p.parts.keys()
	tasks.sort()
	_check("all 10 broken parts are loaded from data/broken_parts.json", tasks.size() == 10, ", ".join(tasks))
	_check("this machine plays a crew member", me != null, my_spec)

	# ---- green (you can fix it) / red (another specialist's job) glow while broken, and the whole model is the target
	for task_id: String in tasks:
		var broken := p.shows_broken(task_id)
		var role := String(RepairCatalog.TASKS[task_id][2])
		var can := role == "general" or role == my_spec
		_check("%s (%s): broken at the start" % [task_id, role], broken)
		var model: Node3D = p.parts[task_id].model
		var lit := 0
		for g in BrokenParts._geometry(model):
			if g.material_overlay == BrokenParts.glow_material(can):
				lit += 1
		_check("%s: glows %s for a %s player" % [task_id, "GREEN" if can else "RED", my_spec], p.glow_of(task_id) == ("green" if can else "red") and lit > 0, "%d glowing meshes" % lit)
		_check("%s: the whole broken model is the aim target" % task_id, p.reach_on(task_id), "%d shapes" % (p.parts[task_id].reach as Array).size())
	var shader_ok := BrokenParts.glow_material(true).shader != null and BrokenParts.glow_material(true).shader.get_mode() == Shader.MODE_SPATIAL
	_check("glow shader loads and compiles as a spatial shader", shader_ok)
	var leak := (p.parts["T12"].model as Node3D).find_child("air_leak_vfx__broken", true, false) as MeshInstance3D
	var jet := leak.get_node_or_null("VapourJet") as CPUParticles3D if leak != null else null
	_check("T12: the ball cloud is gone and a vapour jet blows from the door gap", leak != null and leak.mesh == null and jet != null and jet.emitting)

	# ---- swapping to the specialist turns that part green
	var red_task := ""
	for task_id: String in tasks:
		if p.glow_of(task_id) == "red":
			red_task = task_id
			break
	if me != null and red_task != "":
		var old := me.specialty
		me.specialty = StringName(String(RepairCatalog.TASKS[red_task][2]))
		p.step(0.3)
		_check("%s: turns GREEN when the player becomes its specialist (%s)" % [red_task, me.specialty], p.glow_of(red_task) == "green")
		me.specialty = old
		p.step(0.3)
		_check("%s: back to RED after swapping back" % red_task, p.glow_of(red_task) == "red")

	# ---- sparkles when a part is fixed (from the replicated completed state, as on every client)
	for task_id: String in tasks:
		var before := p.transitions_started
		st.repair.tasks[task_id].first_completed = true
		st.repair.tasks[task_id].progress = 1.0
		p.step(0.016)
		var burst: Node3D = p.last_burst
		var started := p.transitions_started == before + 1 and p.in_transition(task_id)
		var stars := 0
		var emitting := false
		if burst != null:
			for c in burst.get_children():
				if c is GPUParticles3D:
					stars = (c as GPUParticles3D).amount
					emitting = (c as GPUParticles3D).emitting
				elif c is CPUParticles3D:
					stars = (c as CPUParticles3D).amount
					emitting = (c as CPUParticles3D).emitting
			if burst is GPUParticles3D:
				stars = (burst as GPUParticles3D).amount
				emitting = (burst as GPUParticles3D).emitting
			elif burst is CPUParticles3D:
				stars = (burst as CPUParticles3D).amount
				emitting = (burst as CPUParticles3D).emitting
		_check("%s: fixing it starts the sparkle burst" % task_id, started and burst != null and emitting and stars >= 60 and stars <= 120,
			"%d stars, emitting=%s" % [stars, emitting])
		for i in 80:
			p.step(0.016)
		await physics_frame
		_check("%s: after the burst the broken model, its glow and its model target are gone" % task_id, not p.shows_broken(task_id) and p.glow_of(task_id) == "" and not p.in_transition(task_id) and not p.reach_on(task_id))

	# ---- a loaded or late-joined colony that is already fixed shows no sparkles
	var count := p.transitions_started
	p.snap()
	p.step(0.016)
	_check("a colony that is already fixed shows no sparkles on load", p.transitions_started == count)
	host.saves.delete_all()
	print("RESULT %d/%d" % [_ok, _all])
	quit(0 if _ok == _all else 1)
