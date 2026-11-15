extends SceneTree
## Screenshots of the station surfaces (the panel E opens at a station), the cargo panel and the cassette player.
## Needs a real window (headless cannot draw):
##   godot --path . --script res://tools/godot/capture_stations.gd -- --out <dir> [--tag before] [--only power,cargo]
## GameServices + UiRoot, no world (as tests/test_station_panels.gd and tools/godot/capture_puzzles.gd do). Every panel
## is opened through UiRoot the way E opens it, at 1280x720 and 1920x1080 real pixels (content scale off, as the layout
## tests lay out), and once more at 1280x720 with the largest text. UiLayoutCheck's findings are printed per shot.
## A shot named "<panel>_help" is the same panel with its "?" switch on.
## Saves go to res://_test_saves/menu_sheet_capture_stations and are deleted at the end; the player's settings are never written.

const SAVE_DIR := "res://_test_saves/menu_sheet_capture_stations"
## [window size, text scale, suffix]
const SIZES := [[Vector2i(1920, 1080), 1.0, "1080"]]
## Shot name -> station kind (the first station of that kind is opened), or a special word.
const PLAN := [
	["power", "power"], ["lifesupport", "lifesupport"], ["computer", "computer"], ["comms", "comms"], ["heal", "heal"],
	["food", "food"], ["suits", "suits"], ["solar", "solar"], ["bed", "bed"], ["gym", "gym"], ["weather", "weather"],
	["workbench", "workbench"], ["maintenance", "@maintenance"], ["cargo", "@cargo"], ["cargo_empty", "@cargo_empty"],
	["cassette", "@cassette"], ["cassette_tape", "@cassette_tape"],
	["garage", "garage"], ["lab", "lab"], ["salvage", "salvage"], ["sample_site", "sample_site"], ["scout_bay", "scout_bay"],
	["drone_pad", "drone_pad"], ["rover_charger", "rover_charger"], ["ore_deposit", "ore_deposit"], ["record", "record"],
	["upgrade_console", "upgrade_console"], ["board", "board"], ["survivor", "survivor"],
	["lab_sample", "@lab_sample"], ["weather_warn", "@weather_warn"],
	# "+help": the same panel with its "?" switch on (the sentences, the notes and the "?" buttons of the readings).
	["power_help", "power+help"], ["lifesupport_help", "lifesupport+help"], ["suits_help", "suits+help"], ["bed_help", "bed+help"],
]

var out_dir := ""
var tag := ""
var services: GameServices
var ui: UiRoot


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
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	PlayerInput.ensure_actions()
	out_dir = _arg("--out", ProjectSettings.globalize_path("res://docs/revisions/evidence/stations"))
	tag = _arg("--tag", "")
	var only := _arg("--only", "").split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	services = GameServices.new()
	var dir := ProjectSettings.globalize_path(SAVE_DIR + ("" if tag.is_empty() else "_" + tag))
	DirAccess.make_dir_recursive_absolute(dir)
	services.saves = SaveService.new(dir, "colony", 1)
	root.add_child(services)
	services.start_new_game(12817)
	await _frames()
	ui = UiRoot.new()
	root.add_child(ui)
	var settings := GameSettings.new()
	settings.reduce_motion = true
	ui.setup(services, settings)
	await _frames()
	for s: Array in SIZES:
		root.size = s[0]
		UiTheme.apply_text_scale(float(s[1]))
		await _frames(4)
		for entry: Array in PLAN:
			if not only.is_empty() and not only.has(String(entry[0])):
				continue
			var panel := await _make(String(entry[1]))
			if panel == null:
				print("SKIP %s: no panel" % entry[0])
				continue
			ui.open(panel)
			await _frames(12)
			panel.refresh()
			await _shot("%s%s_%s" % [(tag + "_") if not tag.is_empty() else "", entry[0], s[2]], panel)
			ui.close_all()
			await _frames(4)
	UiTheme.apply_text_scale(1.0)
	ui.queue_free()
	services.saves.delete_all()
	services.queue_free()
	await _frames()
	UiTheme.release()
	quit(0)


func _first_of_kind(kind: String) -> String:
	var ids: Array = services.state().stations.keys()
	ids.sort()
	for id: String in ids:
		if String(services.state().stations[id].get("kind", "")) == kind:
			return id
	return ""


func _stand_at(id: String) -> void:
	var station: Dictionary = services.state().stations[id]
	services.report_position(services.local_character().id, CharacterState._v3(station.position), 0.0)
	services.local_character().position = CharacterState._v3(station.position)


func _make(what: String) -> UiPanel:
	if what.ends_with("+help"):
		var with_help := await _make(what.trim_suffix("+help"))
		if with_help is StationPanel:
			(with_help as StationPanel).set_help_shown(true)
		return with_help
	var me := services.local_character()
	match what:
		"@cargo", "@cargo_empty":
			me.cargo.clear()
			if what == "@cargo":
				var ids: Array = services.state().items.keys()
				ids.sort()
				for i in mini(3, ids.size()):
					me.cargo.append(StringName(ids[i]))
				if services.state().caches.is_empty():
					services.state().caches.append({"id": "cache_shot", "position": [me.position.x + 6.0, 0.0, me.position.z + 3.0], "items": [1, 2]})
			else:
				services.state().caches.clear()
			var inv := InventoryPanel.new()
			return inv
		"@cassette", "@cassette_tape":
			if what == "@cassette_tape":
				for id: String in CassetteCatalog.TAPES:
					if not CassetteCatalog.collected(services.state(), id):
						_stand_at(id)
						services.request(&"cassette_collect", StringName(id))
			_stand_at(String(CassetteLibrary.PLAYER_ID))
			var player := StationPanels.for_station(CassetteLibrary.PLAYER_ID, services) as CassettePlayerPanel
			if what == "@cassette_tape" and player != null:
				_select_later(player)
			return player
		"@lab_sample":
			# two samples carried: one measured and worked out (a lab result), one measured (its comparison shown)
			var site := _first_of_kind("sample_site")
			var lab := _first_of_kind("lab")
			if site == "" or lab == "":
				return null
			# samples are taken by the field engineering and geology specialist (crew_4, as tests/test_science.gd)
			me.position = me.hub_spot
			services.request(&"claim_character", &"crew_4")
			me = services.local_character()
			# (the same samples serve the later window sizes: a site gives only three)
			for i in maxi(0, 2 - ScienceActions.carried(services.state(), me, ScienceActions.SAMPLE_KIND).size()):
				_stand_at(site)
				var taken := services.request(&"take_sample", StringName(site))
				if not taken.ok:
					print("lab_sample: take_sample refused: %s %s" % [taken.reason, taken.message if "message" in taken else ""])
			_stand_at(lab)
			var samples: Array[String] = ScienceActions.carried(services.state(), me, ScienceActions.SAMPLE_KIND)
			for s: String in samples:
				services.request(&"analyze_sample", StringName(lab), {"sample": s, "reference": ScienceActions.default_reference()})
			if not samples.is_empty():
				for choice in 3:
					var r := services.request(&"interpret_sample", StringName(lab), {"sample": samples[0], "choice": choice})
					if r.ok and bool(r.changes.get("correct", false)):
						break
			return StationPanels.for_station(StringName(lab), services)
		"@weather_warn":
			var wx := _first_of_kind("weather")
			if wx == "":
				return null
			_stand_at(wx)
			var st := services.state()
			st.weather["warning"] = {"event_id": "wx_shot", "starts_at_hours": st.sim_hours + 6.0, "lead_hours": 6.0,
				"text": WeatherSystem.warning_text({"lead_hours": 6.0}, 31.0, services.clock().hours_per_real_second()), "acknowledged_by": []}
			st.weather["history"] = [{"at_hours": 30.0, "duration_hours": 12.0, "peak_tau": 1.4, "severity": 0.8, "episode_id": "ep_shot"}]
			return StationPanels.for_station(StringName(wx), services)
		"@maintenance":
			var id := _first_of_kind("repair_task")
			if id == "":
				return null
			_stand_at(id)
			var path := "res://scripts/ui/stations/repair_task_station_panel.gd"
			var p := (load(path) as Script).new() as StationPanel
			p.station_id = StringName(id)
			p.kind = "repair_task"
			p.set_meta(&"station_surface", true)
			p.set_meta(&"station_id", StringName(id))
			p.setup(services)
			return p
	var station_id := _first_of_kind(what)
	if station_id == "":
		return null
	_stand_at(station_id)
	return StationPanels.for_station(StringName(station_id), services)


func _select_later(player: CassettePlayerPanel) -> void:
	await _frames(6)
	if is_instance_valid(player):
		player.select_tape("cassette_command_center")


func _shot(label: String, panel: UiPanel) -> void:
	await _frames(10)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(path)
	var screen := root.get_visible_rect().size
	var issues := UiLayoutCheck.problems(panel, screen) if is_instance_valid(panel) and panel.is_inside_tree() else PackedStringArray(["panel closed itself"])
	var focus := UiLayoutCheck.focus_problems(panel) if is_instance_valid(panel) and panel.is_inside_tree() else PackedStringArray()
	print("SHOT %s result=%d window=%s rect=%s layout: %s focus: %s" % [label, error, root.size,
		panel.get_global_rect() if is_instance_valid(panel) else Rect2(), "none" if issues.is_empty() else " | ".join(issues),
		"none" if focus.is_empty() else " | ".join(focus)])
