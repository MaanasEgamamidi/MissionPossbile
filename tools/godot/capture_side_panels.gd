extends SceneTree
## Screenshots of the three side panels a key opens during play: crew (C), cargo (I) and the Power & life support
## drawer (P). No map is loaded (GameServices + UiRoot, as tools/godot/capture_menus.gd does), so it starts in seconds.
## Needs a real window (headless cannot draw):
##   godot --path . --script res://tools/godot/capture_side_panels.gd -- --out <folder> [--hc] [--only crew,cargo,power]
## Each panel is opened through UiRoot at
##   1280x720 as the game shows it (the 1920x1080 canvas stretched to the window)           -> <name>_720.png
##   1280x720 and 1920x1080 in real pixels (content scale off: the layout tests' hardest case) -> <name>_720px / _1080px
##   1280x720 in real pixels with the largest text (x1.5)                                     -> <name>_720px_text150
## and UiLayoutCheck's findings are printed per shot. Saves go to res://_test_saves/capture_side_panels and are deleted
## at the end; the player's own settings are never read or written.

const SAVE_DIR := "res://_test_saves/capture_side_panels"
## [window size, text scale, real pixels, suffix]
const SIZES := [
	[Vector2i(1280, 720), 1.0, false, "720"],
	[Vector2i(1280, 720), 1.0, true, "720px"],
	[Vector2i(1920, 1080), 1.0, true, "1080px"],
	[Vector2i(1280, 720), 1.5, true, "720px_text150"],
]
const PLAN := ["crew", "crew_away", "crew_details", "cargo", "cargo_empty", "power", "power_low", "power_numbers"]

var out_dir := ""
var services: GameServices
var ui: UiRoot
var _stretch_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return def


func _frames(count := 3) -> void:
	for i in count:
		await process_frame


func _initialize() -> void:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.position = Vector2i.ZERO
	_stretch_mode = root.content_scale_mode
	PlayerInput.ensure_actions()
	out_dir = _arg("--out", ProjectSettings.globalize_path("res://_test_saves/capture_side_panels_shots"))
	var only := _arg("--only", "").split(",", false)
	var contrast := OS.get_cmdline_user_args().has("--hc")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var dir := ProjectSettings.globalize_path(SAVE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	services = GameServices.new()
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(12817)
	await _frames()
	services.set_process(false)              # no simulation ticks: the values stay as set
	var settings := GameSettings.new()
	settings.reduce_motion = true
	settings.high_contrast = contrast
	UiTheme.set_high_contrast(contrast)
	ui = UiRoot.new()
	root.add_child(ui)
	ui.setup(services, settings)
	await _frames()
	for s: Array in SIZES:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if bool(s[2]) else _stretch_mode
		root.size = s[0]
		UiTheme.apply_text_scale(float(s[1]))
		await _frames(4)
		for what: String in PLAN:
			if not only.is_empty() and not only.has(what.get_slice("_", 0)):
				continue
			var panel := _make(what)
			ui.open(panel)
			await _frames(12)
			_after_open(what, panel)
			panel.refresh()
			await _frames(45)                 # UiRoot fits a panel again after its next refresh
			await _shot("%s%s_%s" % ["hc_" if contrast else "", what, s[3]], panel)
			ui.close_all()
			await _frames(4)
	UiTheme.apply_text_scale(1.0)
	UiTheme.set_high_contrast(false)
	ui.queue_free()
	services.saves.delete_all()
	services.queue_free()
	await _frames()
	UiTheme.release()
	quit(0)


## Sets the colony up for a shot and returns the panel to open.
func _make(what: String) -> UiPanel:
	var st := services.state()
	var me := services.local_character()
	me.position = me.hub_spot
	me.cargo.clear()
	st.caches.clear()
	st.repair["collected_cassettes"] = []
	st.character(&"crew_3").owner_peer = 0
	for k in ColonyState.STORE_KEYS:
		st.stores[k] = float(st.capacities[k]) * 0.8
	st.power_deficit = false
	st.battery_kw = 3.4
	match what:
		"crew", "crew_details":
			st.character(&"crew_3").owner_peer = 2
			return CrewSelectPanel.new()
		"crew_away":
			st.character(&"crew_3").owner_peer = 2
			me.position += Vector3(40.0, 0.0, 0.0)
			return CrewSelectPanel.new()
		"cargo":
			var ids: Array = st.items.keys()
			ids.sort()
			for i in mini(3, ids.size()):
				me.cargo.append(StringName(ids[i]))
			st.caches.append({"id": "cache_shot", "position": [me.position.x + 6.0, 0.0, me.position.z + 3.0], "items": [1, 2]})
			var tapes: Array = []
			for entry: Dictionary in CassetteLibrary.metadata():
				if tapes.size() < 2:
					tapes.append(String(entry.id))
			st.repair["collected_cassettes"] = tapes
			return InventoryPanel.new()
		"cargo_empty":
			return InventoryPanel.new()
		"power_low":
			st.stores[&"battery_kwh"] = float(st.capacities[&"battery_kwh"]) * 0.12
			st.stores[&"oxygen_kg"] = 1.0
			st.battery_kw = -4.2
			st.power_deficit = true
	return PowerLifePanel.new()


## Steps a shot needs once its panel is open (a second look of the same panel).
func _after_open(what: String, panel: UiPanel) -> void:
	if what == "crew_details" and panel.has_method(&"show_details"):
		panel.call(&"show_details", true)
	if what == "power_numbers" and panel.has_method(&"show_numbers"):
		panel.call(&"show_numbers", true)


func _shot(label: String, panel: UiPanel) -> void:
	await _frames(10)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))
	var screen := root.get_visible_rect().size
	var alive := is_instance_valid(panel) and panel.is_inside_tree()
	var issues := UiLayoutCheck.problems(panel, screen) if alive else PackedStringArray(["panel closed itself"])
	var focus := UiLayoutCheck.focus_problems(panel) if alive else PackedStringArray()
	print("SHOT %s result=%d window=%s canvas=%s layout: %s focus: %s" % [label, error, root.size, screen,
		"none" if issues.is_empty() else " | ".join(issues), "none" if focus.is_empty() else " | ".join(focus)])
