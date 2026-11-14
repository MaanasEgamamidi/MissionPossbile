extends SceneTree
## Runs the real game in a window and connects it to the Godot MCP plugin (Funplay) that is open in ANOTHER project's
## editor, so the MCP tools capture_runtime_view, query_runtime_node and send_runtime_input work on this game without
## installing the plugin here (no autoload, no change to project.godot).
##
## How: the plugin's runtime bridge talks to its editor through three JSON files in the editor project's user folder.
## This script loads that bridge script from the plugin folder, points its files at the host project's user folder and
## adds it to the running game. query_runtime_node with node_path "harness:<command>" runs a command below.
##
## Run (needs a window, so no --headless):
##   godot --path . --resolution 1280x720 --position 0,0 --script res://tools/godot/ui_mcp_play.gd -- [--no-world]
##       [--addon <folder of funplay_mcp>] [--host-user <user folder of the editor project>]
## Saves go to _test_saves/diag/ui_mcp/saves, never to user://.
##
## Harness commands:
##   new | menu | close | closeall | pause | stations | panels
##   open <PanelClass>            station <station id>
##   size <W>x<H>                 text_scale <0.75..2>        contrast on|off
##   low <store key> <share 0..1> hour <0..24.6>              suit on|off|<charge %>
##   message <text>               subtitle <text>             status <text>
##   teleport <x> <y> <z> <yaw>   look <yaw> <pitch>          first_person on|off
##   cue <station id>|(nothing)   explain                     tour <folder>   (every screen, one picture each)
##   check                        (layout check of the top panel and the HUD: off-screen or clipped controls)

const DEFAULT_ADDON := "G:/aiclub projects/godot-mcp-project/addons/funplay_mcp"

var main: GameMain
var bridge: Node
var host_user := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var addon := DEFAULT_ADDON
	var with_world := true
	host_user = OS.get_environment("APPDATA").replace("\\", "/").path_join("Godot/app_userdata/godot-mcp-project")
	for i in args.size():
		match args[i]:
			"--addon": addon = args[i + 1]
			"--host-user": host_user = args[i + 1].replace("\\", "/")
			"--no-world": with_world = false
	# Never take the keyboard or the mouse away from whoever is using the computer.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_title("Mars Colony - MCP check (close me any time)")

	var save_dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/ui_mcp/saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir.path_join(f))
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate() as GameMain
	main.save_directory = save_dir
	main.load_world = with_world
	root.add_child(main)

	var source := FileAccess.get_file_as_string(addon.path_join("runtime/funplay_mcp_runtime_bridge.gd"))
	if source == "":
		push_error("MCP bridge script not found under %s" % addon)
		quit(1)
		return
	source = source.replace("\"user://funplay_mcp_runtime", "\"%s/funplay_mcp_runtime" % host_user)
	source = source.replace("func _normalize_runtime_path(", "func _normalize_runtime_path_orig(")
	source = source.replace("func _command_query_node(", "func _command_query_node_orig(")
	source += "\n\nvar harness: Object\nconst HOST_USER = \"%s\"\n" % host_user
	source += "\nfunc _normalize_runtime_path(path: String) -> String:\n"
	source += "\tvar t: String = path.strip_edges().replace(\"\\\\\", \"/\")\n"
	source += "\tif t.begins_with(\"user://\"):\n\t\tt = HOST_USER + \"/\" + t.substr(7)\n"
	source += "\tif t.begins_with(\"res://\") or t.begins_with(HOST_USER):\n\t\treturn t.simplify_path() if not t.contains(\"..\") else \"\"\n"
	source += "\treturn \"\"\n"
	source += "\nfunc _command_query_node(arguments: Dictionary) -> Dictionary:\n"
	source += "\tvar p: String = str(arguments.get(\"node_path\", \"\"))\n"
	source += "\tif harness != null and p.begins_with(\"harness:\"):\n\t\treturn harness.call(\"harness_command\", p.substr(8))\n"
	source += "\treturn _command_query_node_orig(arguments)\n"
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	if err != OK:
		push_error("MCP bridge script did not compile (%d)" % err)
		quit(1)
		return
	bridge = Node.new()
	bridge.name = "FunplayMcpRuntimeBridge"
	bridge.set_script(script)
	bridge.set("harness", self)
	root.add_child(bridge)
	print("MCP bridge up; files in %s; world=%s" % [host_user, with_world])


func _process(_delta: float) -> bool:
	# The game captures the mouse for play. This window is only looked at through MCP: give the mouse back at once.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return false


## Runs one harness command; the answer goes back through query_runtime_node.
func harness_command(text: String) -> Dictionary:
	var parts := text.strip_edges().split(" ", false, 1)
	var cmd := parts[0] if parts.size() > 0 else ""
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	var out := {"found": true, "command": cmd, "arg": arg}
	var st := main.services.state() if main.services.has_game() else null
	match cmd:
		"new":
			main._on_menu_new()
			if not main.services.has_game():
				main._on_menu_new()
		"menu":
			main._on_quit_to_menu()
		"close":
			main.ui.close_top()
		"closeall":
			main.ui.close_all()
		"pause":
			main.ui.open_pause_menu()
		"stations":
			var list := {}
			if st != null:
				for id: String in st.stations:
					list[id] = String((st.stations[id] as Dictionary).get("kind", ""))
			out["stations"] = list
		"panels":
			var names := PackedStringArray()
			for c: Dictionary in ProjectSettings.get_global_class_list():
				if String(c.path).begins_with("res://scripts/ui/") and String(c["class"]).ends_with("Panel") or String(c["class"]).ends_with("Menu"):
					names.append(String(c["class"]))
			out["panels"] = names
		"open":
			var panel := _new_panel(arg)
			if panel == null:
				out["found"] = false
				out["error"] = "No UiPanel class named %s" % arg
			else:
				main.ui.open(panel)
		"station":
			var result := main._submit(&"use_station", StringName(arg), {})
			out["ok"] = result.ok
			out["message"] = result.message
		"size":
			var wh := arg.split("x")
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		"text_scale":
			main.settings.text_scale = float(arg)
			main.settings.apply(self)
		"contrast":
			main.settings.high_contrast = arg == "on"
			main.settings.apply(self)
		"low":
			var kv := arg.split(" ", false)
			var key := StringName(kv[0])
			st.stores[key] = float(st.capacities.get(key, 0.0)) * float(kv[1])
		"hour":
			var clock := main.services.clock()
			clock.phase = clampf(float(arg) / 24.66, 0.0, 0.999)
			main._update_sun(true)
		"suit":
			var me := main.services.local_character()
			if arg == "on" or arg == "off":
				me.suit_on = arg == "on"
			else:
				me.suit_charge = float(arg)
		"message":
			main.hud.show_message(arg, 8.0)
		"subtitle":
			main.ui.show_subtitle(arg, 8.0, "Colony computer", true)
		"status":
			main.hud.set_status(arg)
		"teleport":
			var v := arg.split(" ", false)
			main.player.teleport(Vector3(float(v[0]), float(v[1]), float(v[2])), float(v[3]) if v.size() > 3 else 0.0)
		"look":
			var v := arg.split(" ", false)
			main.player.camera_rig().add_look(float(v[0]), float(v[1]))
		"first_person":
			main.player.set_first_person(arg != "off")
		"cue":
			# Freeze the game's own aiming so the cue for one station (or "" for none) stays up for a picture.
			main.set_process(arg == "")
			main.hud.set_target({"kind": "station", "id": arg, "node": null} if arg != "" else {})
			out["cue"] = main.hud.cue_text()
		"explain":
			var buttons := main.ui.top().find_children("*", "ExplainButton", true, false) if main.ui.top() != null else []
			if buttons.is_empty():
				out["found"] = false
				out["error"] = "The top panel has no ? button"
			else:
				(buttons[0] as BaseButton).pressed.emit()
		"check":
			out["problems"] = _layout_problems()
		"tour":
			_tour(arg if arg != "" else "tour")
			out["note"] = "Tour started; it writes tour_done.txt into the folder when it has finished."
		_:
			out["found"] = false
			out["error"] = "Unknown harness command '%s'" % cmd
	out["ui_depth"] = main.ui.depth()
	out["top"] = main.ui.top().name if main.ui.top() != null else ""
	out["playing"] = main.services.has_game()
	return out


func _new_panel(class_name_text: String) -> UiPanel:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if String(c["class"]) == class_name_text:
			var made: Variant = (load(String(c.path)) as Script).new()
			if made is SettingsPanel:
				# the check must never write the player's own settings or key bindings
				var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/ui_mcp")
				(made as SettingsPanel).settings_path = dir.path_join("settings.json")
				(made as SettingsPanel).input_path = dir.path_join("input.json")
			if made is UiPanel:
				return made as UiPanel
			if made is Node:
				(made as Node).free()
	return null


const TOUR_PANELS: Array[String] = ["BlueprintPanel", "InventoryPanel", "CrewSelectPanel", "ColonySummaryPanel",
	"UpgradeCardsPanel", "SettingsPanel", "SourceRegisterPanel", "CreditsPanel"]


## Opens every screen in turn and saves one picture of each into _test_saves/diag/ui_mcp/<folder>, with the layout
## problems found on each in problems.txt. Starts a new colony first if the title screen is still up.
func _tour(folder: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/diag/ui_mcp").path_join(folder)
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("tour_done.txt"))
	var report := PackedStringArray()
	if not main.services.has_game():
		await _tour_shot(dir, "00_main_menu", report)
		harness_command("new")
	main.ui.close_all()
	await _tour_shot(dir, "01_hud_ok", report)
	var st := main.services.state()
	var kept: Dictionary = st.stores.duplicate()
	harness_command("low battery_kwh 0.08")
	harness_command("low oxygen_kg 0.2")
	harness_command("low water_l 0.15")
	harness_command("suit on")
	harness_command("suit 8")
	main.hud.show_message("The greenhouse needs water before it can grow food.", 6.0)
	main.hud.show_message("You cannot carry two things at once.", 6.0)
	main.hud.set_status("Playing on your own")
	main.ui.show_subtitle("Dust storm on the horizon. Check the solar panels before night.", 6.0, "Colony computer", true)
	main.hud.set_target({"kind": "station", "id": "pw_panel", "node": null})
	main.hud.refresh()
	await _tour_shot(dir, "02_hud_busy", report)
	main.hud.set_target({})
	harness_command("suit off")
	harness_command("suit 100")
	for key: Variant in kept:
		st.stores[key] = kept[key]
	main.hud.set_status("")
	var n := 10
	for panel_class: String in TOUR_PANELS:
		main.ui.close_all()
		harness_command("open " + panel_class)
		await _tour_shot(dir, "%02d_%s" % [n, panel_class], report)
		n += 1
	for id: String in st.stations:
		main.ui.close_all()
		harness_command("station " + id)
		if main.ui.is_open():
			await _tour_shot(dir, "%02d_station_%s" % [n, id], report)
			n += 1
	main.ui.close_all()
	main.ui.open_pause_menu()
	await _tour_shot(dir, "%02d_PauseMenu" % n, report)
	main.ui.close_all()
	var file := FileAccess.open(dir.path_join("problems.txt"), FileAccess.WRITE)
	file.store_string("\n".join(report) + "\n")
	file = null
	file = FileAccess.open(dir.path_join("tour_done.txt"), FileAccess.WRITE)
	file.store_string("done\n")


func _tour_shot(dir: String, shot_name: String, report: PackedStringArray) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	for p: String in _layout_problems():
		report.append("%s: %s" % [shot_name, p])


## Visible controls that reach outside the screen, and labels whose text is cut off.
func _layout_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1.0)
	var roots: Array[Node] = []
	if main.ui.top() != null:
		roots.append(main.ui.top())
	if main.hud != null and main.hud.root_control() != null:
		roots.append(main.hud.root_control())
	for r: Node in roots:
		for n: Node in r.find_children("*", "Control", true, false):
			var c := n as Control
			if not c.is_visible_in_tree() or c.size.x <= 0.0 or c.size.y <= 0.0:
				continue
			var inside_scroll := false
			var p := c.get_parent()
			while p != null and p != r:
				if p is ScrollContainer:
					inside_scroll = true
					break
				p = p.get_parent()
			if not inside_scroll and not screen.encloses(c.get_global_rect()):
				problems.append("off screen: %s %s" % [r.get_path_to(c), c.get_global_rect()])
			if c is Label:
				var l := c as Label
				if l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.get_minimum_size().x > l.size.x + 1.0:
					problems.append("text cut: %s '%s'" % [r.get_path_to(c), l.text.left(40)])
				elif l.clip_text or l.get_line_count() > l.get_visible_line_count():
					problems.append("lines hidden: %s '%s'" % [r.get_path_to(c), l.text.left(40)])
	return problems
