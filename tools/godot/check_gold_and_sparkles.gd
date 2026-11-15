extends SceneTree
## Owner-requested headless check (2026-11-14): the gold highlight on broken parts whose task needs a specialist, and
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
	var p: BrokenParts = BrokenParts.new()
	root.add_child(p)
	p.set_process(false)
	p.setup(world, host, null)
	p.step(0.0)
	var st := host.state()
	var tasks: Array = p.parts.keys()
	tasks.sort()
	_check("all 10 broken parts are loaded from data/broken_parts.json", tasks.size() == 10, ", ".join(tasks))

	# ---- gold highlight while broken
	for task_id: String in tasks:
		var specialist := BrokenParts.is_specialist_task(task_id)
		var broken := p.shows_broken(task_id)
		var gold := p.shows_gold(task_id)
		var role := String(RepairCatalog.TASKS[task_id][2])
		_check("%s (%s): broken at the start" % [task_id, role], broken)
		if specialist:
			var model: Node3D = p.parts[task_id].model
			var golden := 0
			var plain := 0
			for g in BrokenParts._geometry(model):
				if g.material_overlay == BrokenParts.gold_material():
					golden += 1
				else:
					plain += 1
			_check("%s: specialist task shows the gold highlight" % task_id, gold and golden > 0, "%d gold meshes, %d plain (effects)" % [golden, plain])
		else:
			_check("%s: general task has no gold highlight" % task_id, not gold)
	var shader_ok := BrokenParts.gold_material().shader != null and BrokenParts.gold_material().shader.get_mode() == Shader.MODE_SPATIAL
	_check("gold highlight shader loads and compiles as a spatial shader", shader_ok)

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
		_check("%s: after the burst the broken model and its gold are gone" % task_id, not p.shows_broken(task_id) and not p.shows_gold(task_id) and not p.in_transition(task_id))

	# ---- a loaded or late-joined colony that is already fixed shows no sparkles
	var count := p.transitions_started
	p.snap()
	p.step(0.016)
	_check("a colony that is already fixed shows no sparkles on load", p.transitions_started == count)
	host.saves.delete_all()
	print("RESULT %d/%d" % [_ok, _all])
	quit(0 if _ok == _all else 1)
