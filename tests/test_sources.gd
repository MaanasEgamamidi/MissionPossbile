extends SceneTree
## Part B checks: source register data, claims, explanations, credits, the "?" button and the register and credits
## panels. Runs offline and never opens a web browser (SourceLibrary.open_url_hook is replaced).
## Run: godot --headless --path . --script res://tests/test_sources.gd

const REGISTER_PATH := "res://docs/source_register.md"
const REQUIRED_EXPLANATIONS: PackedStringArray = [
	"battery", "solar_power", "load", "power_deficit", "stamina_vs_electricity", "stock_vs_flow", "oxygen", "water",
	"food", "parts", "suit_tank", "health", "stamina", "sol_clock", "sol_length", "cargo", "pause_vote",
	"specialists", "crew_switching", "upgrades", "recovery", "zones_power", "blueprint", "sources",
]
## Required claim -> [category, source id it must cite ("" = none), text it must contain].
const REQUIRED_CLAIMS := {
	"gravity": ["archive", "S01", "3.73 m/s²"],
	"sol_length": ["archive", "S02", "24 h 39 min 35 s"],
	"sol_compression": ["game_time", "", "20 real minutes"],
	"oxygen_from_water": ["archive", "S08", "oxygen"],
	"oxygen_from_co2": ["archive", "S09", "MOXIE"],
	"water_recycling": ["archive", "S08", "90 percent"],
	"plants_in_space": ["archive", "S11", "lettuce"],
	"solar_dust": ["archive", "", "solar"],
	"crew_rates": ["balance", "", "game balance"],
	"battery_numbers": ["balance", "", "game balance"],
	"colony_premise": ["fiction", "", "made up"],
}
const CLAIM_CATEGORIES: PackedStringArray = ["archive", "game_time", "fiction", "balance"]
const SOURCE_CATEGORIES: PackedStringArray = ["measured", "modelled", "analog", "technology", "fiction", "tuning", "engine"]
const STATUSES: PackedStringArray = ["VERIFIED", "PARTIAL", "SEARCH-ONLY", "FAILED"]
const MY_SCRIPTS: PackedStringArray = [
	"res://scripts/ui/source_library.gd", "res://scripts/ui/explanations.gd", "res://scripts/ui/explain_button.gd",
	"res://scripts/ui/source_register_panel.gd", "res://scripts/ui/credits_panel.gd",
]
const SIZES: Array[Array] = [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]

var _passed := 0
var _total := 0
var _opened: PackedStringArray = []
var _services: GameServices
var _text_scale_simulated := false
var _register_urls: Dictionary = {}
var _register_status: Dictionary = {}


func _check(name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", name, ("  " + detail) if detail != "" else "")
	else:
		print("FAIL ", name, ": ", detail)


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	SourceLibrary.open_url_hook = func(url: String) -> void: _opened.append(url)
	# The project stretches a 1920x1080 canvas (canvas_items). Turn that off so a 1280x720 window really lays out
	# 1280x720 units: the strictest case for fitting text.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var dir := ProjectSettings.globalize_path("res://").path_join("_test_saves/wB")
	DirAccess.make_dir_recursive_absolute(dir)
	_services = GameServices.new()
	_services.saves = SaveService.new(dir, "colony", 2)
	root.add_child(_services)
	_services.start_new_game(1)
	await _frames()

	_parse_register()
	_check_sources()
	_check_claims()
	_check_explanations()
	_check_credits_data()
	_check_scripts()
	await _check_register_panel()
	await _check_explain_button()
	await _check_credits_panel()
	_check("no browser opened except by the one button press", _opened.size() == 1, str(_opened))

	_set_text_scale(1.0)
	SourceLibrary.open_url_hook = Callable()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- data

## Re-reads docs/source_register.md on its own: id -> first https address in the row, and id -> status word.
func _parse_register() -> void:
	var text := FileAccess.get_file_as_string(REGISTER_PATH)
	_check("register file readable", text.length() > 1000, REGISTER_PATH)
	var id_re := RegEx.create_from_string("^[STML]\\d\\d$")
	var url_re := RegEx.create_from_string("https://[^\\s|`<>()]+")
	for line in text.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 3:
			continue
		var id := cells[1].strip_edges()
		if id_re.search(id) == null:
			continue
		var m := url_re.search(line)
		var url := ""
		if m != null:
			url = m.get_string()
			while url.length() > 0 and ".,;:".contains(url[url.length() - 1]):
				url = url.substr(0, url.length() - 1)
		_register_urls[id] = url
		if id.begins_with("S") or id.begins_with("T"):
			var status_cell := ""
			# S rows: | ID | Pack | Source | Kind | Status |...; T rows: | ID | Pack | Source | Status |...
			status_cell = cells[5] if id.begins_with("S") else cells[4]
			status_cell = status_cell.replace("*", "").strip_edges()
			for word in STATUSES:
				if status_cell.begins_with(word):
					_register_status[id] = word
					break


func _check_sources() -> void:
	var srcs := SourceLibrary.sources()
	var ids: Array = []
	for s: Dictionary in srcs:
		ids.append(String(s.get("id", "")))
	var missing: PackedStringArray = []
	for id: String in _register_urls.keys():
		if not ids.has(id):
			missing.append(id)
	_check("every S, T, M and L register entry is in sources.json", missing.is_empty() and srcs.size() == _register_urls.size(),
		"%d entries; missing %s" % [srcs.size(), missing])
	var bad_status: PackedStringArray = []
	for s: Dictionary in srcs:
		var id := String(s.get("id", ""))
		if not STATUSES.has(String(s.get("status", ""))):
			bad_status.append(id + " has no status")
		elif _register_status.has(id) and _register_status[id] != String(s.status):
			bad_status.append("%s is %s in the register but %s in sources.json" % [id, _register_status[id], s.status])
	_check("source statuses match the register", bad_status.is_empty() and _register_status.size() >= 30,
		"%d statuses compared; %s" % [_register_status.size(), "; ".join(bad_status)])
	var bad_cat: PackedStringArray = []
	for s: Dictionary in srcs:
		var cat := String(s.get("category", ""))
		if cat != "" and not SOURCE_CATEGORIES.has(cat):
			bad_cat.append("%s: %s" % [s.id, cat])
	_check("source categories use the contract words", bad_cat.is_empty(), "; ".join(bad_cat))
	var bad_url: PackedStringArray = []
	var with_url := 0
	for s: Dictionary in srcs:
		var url := String(s.get("url", ""))
		if url == "":
			continue
		with_url += 1
		if not SourceLibrary.is_safe_url(url):
			bad_url.append("%s malformed: %s" % [s.id, url])
		if url != String(_register_urls.get(String(s.id), "")):
			bad_url.append("%s differs from the register: %s" % [s.id, url])
	for id: String in _register_urls:
		if String(_register_urls[id]) != "" and String(SourceLibrary.source(id).get("url", "")) == "":
			bad_url.append(id + " lost its address")
	_check("every https:// address is well formed and equals the register's", bad_url.is_empty() and with_url >= 30,
		"%d addresses; %s" % [with_url, "; ".join(bad_url)])
	_check("is_safe_url refuses anything that is not a plain https address",
		not SourceLibrary.is_safe_url("http://nasa.gov/") and not SourceLibrary.is_safe_url("https://") \
		and not SourceLibrary.is_safe_url("file:///C:/x") and not SourceLibrary.is_safe_url("https://a b.com/") \
		and SourceLibrary.is_safe_url("https://www.nasa.gov/x"))
	var words := [SourceLibrary.status_text({"status": "VERIFIED", "checked_on": "2026-11-11"}),
		SourceLibrary.status_text({"status": "PARTIAL"}), SourceLibrary.status_text({"status": "SEARCH-ONLY"}),
		SourceLibrary.status_text({"status": "FAILED"})]
	_check("status in plain words", words == ["Checked on 11 Nov 2026", "Partly checked", "Not yet checked", "Could not be opened"], str(words))
	_check("citable means VERIFIED or PARTIAL only",
		SourceLibrary.is_citable(SourceLibrary.source("S01")) and SourceLibrary.is_citable(SourceLibrary.source("S03")) \
		and not SourceLibrary.is_citable(SourceLibrary.source("S18")) and not SourceLibrary.is_citable(SourceLibrary.source("S10")))


func _check_claims() -> void:
	var problems: PackedStringArray = []
	var ids: Array = []
	for c: Dictionary in SourceLibrary.claims():
		var id := String(c.get("id", ""))
		ids.append(id)
		if String(c.get("text", "")) == "" or String(c.get("title", "")) == "":
			problems.append(id + " has no text or title")
		if not CLAIM_CATEGORIES.has(String(c.get("category", ""))):
			problems.append(id + " has category " + String(c.get("category", "")))
		for sid: Variant in (c.get("source_ids", []) as Array) + (c.get("lead_ids", []) as Array):
			if SourceLibrary.source(String(sid)).is_empty():
				problems.append("%s names unknown source %s" % [id, sid])
	_check("every claim's source ids exist and categories are valid", problems.is_empty() and ids.size() >= REQUIRED_CLAIMS.size(),
		"%d claims; %s" % [ids.size(), "; ".join(problems)])

	var cite_problems: PackedStringArray = []
	var unsourced: PackedStringArray = []
	for c: Dictionary in SourceLibrary.claims():
		if String(c.category) != "archive":
			continue
		var listed: Array = c.get("source_ids", [])
		if not listed.is_empty() and SourceLibrary.citable_sources_of(c).is_empty():
			cite_problems.append("%s cites only unchecked sources %s" % [c.id, listed])
		if SourceLibrary.is_unsourced(c):
			unsourced.append(String(c.id))
			if SourceLibrary.claim_category_text(c) != "source not yet checked":
				cite_problems.append(String(c.id) + " is not shown as unsourced")
	_check("no archive claim cites only SEARCH-ONLY or FAILED sources", cite_problems.is_empty(),
		"unsourced claims: %s; %s" % [unsourced, "; ".join(cite_problems)])

	var req: PackedStringArray = []
	for id: String in REQUIRED_CLAIMS:
		var want: Array = REQUIRED_CLAIMS[id]
		var c := SourceLibrary.claim(id)
		if c.is_empty():
			req.append(id + " missing")
			continue
		if String(c.category) != String(want[0]):
			req.append("%s category %s" % [id, c.category])
		if String(want[1]) != "" and not (c.get("source_ids", []) as Array).has(want[1]):
			req.append("%s does not cite %s" % [id, want[1]])
		if not String(c.text).contains(String(want[2])):
			req.append("%s text lacks '%s'" % [id, want[2]])
	_check("required claims present with the right sources", req.is_empty(), "; ".join(req))

	var dust := SourceLibrary.claim("solar_dust")
	var s18 := SourceLibrary.source("S18")
	var dust_ok := false
	if SourceLibrary.is_citable(s18):
		dust_ok = (dust.get("source_ids", []) as Array).has("S18")
	else:
		dust_ok = not (dust.get("source_ids", []) as Array).has("S18") and SourceLibrary.is_unsourced(dust)
	_check("solar dust claim follows S18's status", dust_ok, "S18 is %s; claim category words: %s" % [s18.get("status", ""), SourceLibrary.claim_category_text(dust)])


func _check_explanations() -> void:
	var problems: PackedStringArray = []
	var all_ids := Explanations.ids()
	for id in REQUIRED_EXPLANATIONS:
		var e := Explanations.get_entry(id)
		if e.is_empty():
			problems.append(id + " missing")
			continue
		if String(e.title) == "" or String(e.short) == "" or String(e.long) == "":
			problems.append(id + " has empty text")
		var short_n := _sentences(String(e.short))
		var long_n := _sentences(String(e.long))
		if short_n != 1:
			problems.append("%s short has %d sentences" % [id, short_n])
		if long_n < 2 or long_n > 5:
			problems.append("%s long has %d sentences" % [id, long_n])
	for id in all_ids:
		var e := Explanations.get_entry(id)
		if not (e.source_ids is PackedStringArray) or not (e.claim_ids is PackedStringArray):
			problems.append(id + " ids are not PackedStringArray")
			continue
		for sid in e.source_ids:
			if SourceLibrary.source(sid).is_empty():
				problems.append("%s unknown source %s" % [id, sid])
			elif not SourceLibrary.is_citable(SourceLibrary.source(sid)):
				problems.append("%s cites unchecked source %s" % [id, sid])
		for cid in e.claim_ids:
			if SourceLibrary.claim(cid).is_empty():
				problems.append("%s unknown claim %s" % [id, cid])
	_check("every required explanation exists with short and long text and valid ids", problems.is_empty(),
		"%d explanations; %s" % [all_ids.size(), "; ".join(problems)])
	_check("unknown explanation id gives an empty entry", Explanations.get_entry("no_such_id").is_empty())


func _sentences(text: String) -> int:
	var n := 0
	var re := RegEx.create_from_string("[.!?](\\s|$)")
	for m in re.search_all(text.strip_edges()):
		n += 1
	return n


func _check_credits_data() -> void:
	var problems: PackedStringArray = []
	var by_id: Dictionary = {}
	for c: Dictionary in SourceLibrary.credits():
		by_id[String(c.get("id", ""))] = c
		var url := String(c.get("url", ""))
		if url != "" and not SourceLibrary.is_safe_url(url):
			problems.append("%s url malformed: %s" % [c.id, url])
		for sid: Variant in c.get("source_ids", []):
			if SourceLibrary.source(String(sid)).is_empty():
				problems.append("%s unknown source %s" % [c.id, sid])
		if String(c.get("licence_words", "")) == "":
			problems.append(String(c.id) + " has no licence words")
	for id in ["godot", "blender", "human_base_meshes", "player_character_fbx", "walking_fbx", "nasa_sources"]:
		if not by_id.has(id):
			problems.append(id + " missing")
	if problems.is_empty():
		if not String(by_id.godot.licence).contains("MIT") or not String(by_id.blender.licence).contains("GPL"):
			problems.append("engine or tool licence wrong")
		var hbm := String(by_id.human_base_meshes.licence_words)
		if not (hbm.contains("CC0") and hbm.contains("Attribution 4.0")):
			problems.append("Human Base Meshes does not record both licence statements")
		for id in ["player_character_fbx", "walking_fbx"]:
			if String(by_id[id].licence) != "Unknown":
				problems.append(id + " licence should be stated as unknown")
	_check("credits data: every required credit, licences stated (unknown where unknown), urls well formed", problems.is_empty(), "; ".join(problems))


func _check_scripts() -> void:
	var network_words: PackedStringArray = ["HTTPRequest", "HTTPClient", "StreamPeerTCP", "PacketPeerUDP", "WebSocket", "ENetConnection"]
	var problems: PackedStringArray = []
	var shell_calls := 0
	for path in MY_SCRIPTS:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			problems.append(path + " unreadable")
		for word in network_words:
			if text.contains(word):
				problems.append("%s mentions %s" % [path, word])
		var n := text.count("OS.shell_open(")
		shell_calls += n
		if n > 0 and path != "res://scripts/ui/source_library.gd":
			problems.append(path + " calls OS.shell_open directly")
	_check("panels use no network classes and open the browser only through SourceLibrary.open_url", problems.is_empty() and shell_calls == 1,
		"shell_open calls: %d; %s" % [shell_calls, "; ".join(problems)])


# ---------------------------------------------------------------- layout helpers

## Sets the text scale; the stub theme ignores apply_text_scale, so the test then scales the default font itself.
func _set_text_scale(s: float) -> void:
	UiTheme.apply_text_scale(s)
	var th := UiTheme.get_theme()
	if not th.get_font_size_list(&"Label").has(&"font_size"):
		var want := int(roundf(UiTheme.BASE_FONT_SIZE * s))
		if th.default_font_size != want:
			th.default_font_size = want
			_text_scale_simulated = true


func _layout_checks(panel: Control, label: String) -> void:
	for size_and_scale: Array in SIZES:
		var screen: Vector2i = size_and_scale[0]
		var s: float = size_and_scale[1]
		root.size = screen
		_set_text_scale(s)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames()
		var where := "%s at %dx%d, text %.1f" % [label, screen.x, screen.y, s]
		var probs := UiLayoutCheck.problems(panel, Vector2(screen))
		_check(where + ": layout", probs.is_empty() and Vector2(root.size) == Vector2(screen),
			("root %s; " % root.size) + "; ".join(probs) + (" (text scale simulated: stub theme)" if s != 1.0 and _text_scale_simulated else ""))
		var focus := UiLayoutCheck.focus_problems(panel)
		_check(where + ": focus", focus.is_empty(), "; ".join(focus))
	root.size = Vector2i(1280, 720)
	_set_text_scale(1.0)


## Labels and buttons in a scrolling pane that do not wrap, stick out sideways, or are cut off.
func _wrap_problems(scroll: ScrollContainer) -> PackedStringArray:
	var out := PackedStringArray()
	var area := scroll.get_global_rect()
	for c: Control in _controls_under(scroll):
		if not (c is Label or c is Button) or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		var min_size := c.get_combined_minimum_size()
		var words: String = c.text
		var short := words.substr(0, 30)
		if r.end.x > area.end.x + 1.0 or r.position.x < area.position.x - 1.0:
			out.append("'%s' is wider than the pane" % short)
		if r.size.y + 0.5 < min_size.y or r.size.x + 0.5 < min_size.x:
			out.append("'%s' is cut off (%s < %s)" % [short, r.size, min_size])
		if c is Label:
			var l := c as Label
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF or l.clip_text:
				out.append("'%s' does not wrap" % short)
			if l.get_visible_line_count() < l.get_line_count():
				out.append("'%s' hides %d of %d lines" % [short, l.get_line_count() - l.get_visible_line_count(), l.get_line_count()])
		elif c is Button and (c as Button).autowrap_mode == TextServer.AUTOWRAP_OFF and r.size.x > area.size.x:
			out.append("button '%s' does not wrap" % short)
	return out


func _controls_under(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			out.append(child as Control)
		out.append_array(_controls_under(child))
	return out


func _labels_text(node: Node) -> String:
	var parts: PackedStringArray = []
	for c: Control in _controls_under(node):
		if c is Label or c is Button:
			parts.append(String(c.text))
	return "\n".join(parts)


# ---------------------------------------------------------------- register panel

func _check_register_panel() -> void:
	var panel := SourceRegisterPanel.new()
	panel.setup(_services)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	var text := _labels_text(panel)
	var help: ExplainButton
	for candidate in panel.find_children("*", "ExplainButton", true, false):
		if (candidate as ExplainButton).custom_title == "Sources":
			help = candidate as ExplainButton
	help.open_popup()
	await _frames()
	_check("register explains its purpose in help", not text.contains("This register lists where the facts") and _labels_text(help.popup_window()).contains("This register lists where the facts"))
	help.close_popup()
	var total := SourceLibrary.claims().size() + SourceLibrary.sources().size()
	_check("register lists every claim and source", panel.visible_entry_ids().size() == total, "%d of %d" % [panel.visible_entry_ids().size(), total])
	await _layout_checks(panel, "SourceRegisterPanel")

	# Search and category filter.
	panel.set_filter("moxie")
	var shown := panel.visible_entry_ids()
	_check("search 'moxie' finds S09 and the MOXIE claim, not S01", shown.has("S09") and shown.has("oxygen_from_co2") and not shown.has("S01"), str(shown))
	panel.set_filter("", 7)
	shown = panel.visible_entry_ids()
	var only_engine := not shown.is_empty()
	for id in shown:
		if not (id.begins_with("T") or id.begins_with("M") or id.begins_with("L")):
			only_engine = false
	_check("category 'Engine and tools' shows only T, M and L entries", only_engine and shown.has("T01") and shown.has("M01") and shown.has("L01"), str(shown))
	panel.set_filter("", 3)
	shown = panel.visible_entry_ids()
	_check("category 'ISS and Earth tests' shows ISS sources and their claims", shown.has("S08") and shown.has("S11") and shown.has("water_recycling") and shown.has("plants_in_space") and not shown.has("S01") and not shown.has("gravity"), str(shown))
	panel.set_filter("", 6)
	shown = panel.visible_entry_ids()
	_check("category 'Game balance' shows balance and game-time claims", shown.has("crew_rates") and shown.has("battery_numbers") and shown.has("sol_compression") and not shown.has("gravity"), str(shown))
	panel.set_filter("oxygen", 1)
	shown = panel.visible_entry_ids()
	_check("search and category combine", shown.has("mars_air") and not shown.has("oxygen_from_water") and not shown.has("S09") and not shown.has("S08"), str(shown))
	panel.set_filter("zzzz no such thing")
	await _frames()
	_check("no match shows an empty list and a hint", panel.visible_entry_ids().is_empty() and _labels_text(panel).contains("Nothing matches"))
	panel.show_entry("S01")
	await _frames()
	_check("show_entry clears a filter that hides the entry", panel.current_entry_id() == "S01" and panel.visible_entry_ids().size() == total and panel.entry_list().is_selected(panel.visible_entry_ids().find("S01")))

	# Every displayed link equals the register's address; status words; unchecked sources never shown as citations.
	var link_problems: PackedStringArray = []
	var claim_problems: PackedStringArray = []
	var wrap_problems: PackedStringArray = []
	root.size = Vector2i(1280, 720)
	_set_text_scale(1.5)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s: Dictionary in SourceLibrary.sources():
		var id := String(s.id)
		panel.show_entry(id)
		await _frames()
		var want := String(_register_urls.get(id, ""))
		if panel.displayed_url() != want:
			link_problems.append("%s shows '%s', register has '%s'" % [id, panel.displayed_url(), want])
		var b := panel.open_button()
		if want != "" and (b == null or b.disabled):
			link_problems.append(id + " has no working Open in browser button")
		if want == "" and b != null:
			link_problems.append(id + " has a button but no address")
		var detail := _labels_text(panel.detail_pane())
		if not detail.contains(SourceLibrary.status_text(s)):
			link_problems.append(id + " does not show its status in words")
		if want != "" and not detail.contains("Opens your web browser. The game works without it."):
			link_problems.append(id + " lacks the browser note")
		for p in _wrap_problems(panel.detail_pane()):
			wrap_problems.append(id + ": " + p)
	for c: Dictionary in SourceLibrary.claims():
		panel.show_entry(String(c.id))
		await _frames()
		for ctrl: Control in _controls_under(panel.detail_pane()):
			if ctrl is Button and String((ctrl as Button).text).begins_with("✓"):
				var sid := String((ctrl as Button).text).substr(2).split(" ")[0]
				if not SourceLibrary.is_citable(SourceLibrary.source(sid)):
					claim_problems.append("%s shows unchecked %s as a source" % [c.id, sid])
		if SourceLibrary.is_unsourced(c) and not _labels_text(panel.detail_pane()).contains("Source not yet checked"):
			claim_problems.append(String(c.id) + " does not say 'Source not yet checked'")
		for p in _wrap_problems(panel.detail_pane()):
			wrap_problems.append(String(c.id) + ": " + p)
	_check("every displayed link equals the register's address for that id", link_problems.is_empty(), "; ".join(link_problems))
	_check("unchecked sources are shown as 'not yet checked', never as a citation", claim_problems.is_empty(), "; ".join(claim_problems))
	_check("long entries wrap without clipping (1280x720, text 1.5)", wrap_problems.is_empty(), "; ".join(wrap_problems))
	_set_text_scale(1.0)

	# Claim -> source navigation by keyboard-reachable buttons.
	panel.show_entry("gravity")
	await _frames()
	var link: Button = null
	for ctrl: Control in _controls_under(panel.detail_pane()):
		if ctrl is Button and String((ctrl as Button).text).begins_with("✓ S01"):
			link = ctrl
	_check("a claim lists its source as a button", link != null and link.focus_mode == Control.FOCUS_ALL,
		"shown: %s; %s" % [panel.current_entry_id(), _labels_text(panel.detail_pane()).replace("\n", " | ")])
	if link != null:
		link.pressed.emit()
		await _frames()
		_check("pressing the source button shows the source", panel.current_entry_id() == "S01", panel.current_entry_id())

	# Open in browser only when pressed, only https, through the hook.
	_check("nothing opened before a button press", _opened.is_empty(), str(_opened))
	panel.show_entry("S01")
	await _frames()
	panel.open_button().pressed.emit()
	_check("Open in browser opens exactly the register's address once", _opened.size() == 1 and _opened[0] == String(_register_urls["S01"]), str(_opened))
	_check("open_url refuses a non-https address", not SourceLibrary.open_url("http://example.com/") and _opened.size() == 1)
	panel.show_entry("M01")
	await _frames()
	_check("an entry without an address has no browser button", panel.open_button() == null and panel.displayed_url() == "")
	_check("first focus lands on the list when an entry is shown", panel.first_focus() == panel.entry_list())

	# show_entry before setup (the way ExplainButton and UiRoot use it).
	var early := SourceRegisterPanel.new()
	early.show_entry("sol_length")
	early.setup(_services)
	root.add_child(early)
	early.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	_check("show_entry called before setup opens at that entry", early.current_entry_id() == "sol_length" and _labels_text(early.detail_pane()).contains("24 h 39 min 35 s"))
	var closed := [false]
	early.close_requested.connect(func() -> void: closed[0] = true)
	(early.find_child("CloseButton", true, false) as Button).pressed.emit()
	_check("Close button asks to close", closed[0])
	_check_no_network_nodes()
	early.queue_free()
	panel.queue_free()
	await _frames()


# ---------------------------------------------------------------- explain button

func _check_explain_button() -> void:
	var sentinel_script := GDScript.new()
	sentinel_script.source_code = "extends Node\nvar seen := 0\nfunc _unhandled_input(e: InputEvent) -> void:\n\tif e.is_action_pressed(&\"ui_cancel\"):\n\t\tseen += 1\n"
	sentinel_script.reload()
	var sentinel := Node.new()
	sentinel.set_script(sentinel_script)
	root.add_child(sentinel)

	var host := UiPanel.new()
	host.name = "HostPanel"
	host.setup(_services)
	var box := VBoxContainer.new()
	host.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var reading := Label.new()
	reading.text = "Oxygen 60 kg"
	row.add_child(reading)
	var eb := ExplainButton.make("oxygen")
	row.add_child(eb)
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	await _frames()

	var e := Explanations.get_entry("oxygen")
	_check("? button shows '?' with the short text as tooltip", eb.text == "?" and eb.tooltip_text == String(e.short) and eb.focus_mode == Control.FOCUS_ALL, eb.tooltip_text)
	var asked: PackedStringArray = []
	eb.sources_requested.connect(func(id: String) -> void: asked.append(id))
	var opened_panels: Array = []
	host.open_requested.connect(func(p: UiPanel) -> void: opened_panels.append(p))

	eb.grab_focus()
	eb.pressed.emit()
	await _frames(3)
	var popup := eb.popup_window()
	_check("pressing ? opens the popup", popup != null and popup.visible)
	if popup == null:
		return
	var words := _labels_text(popup)
	var cats_ok := words.contains(String(e.title)) and words.contains(String(e.long)) and words.contains("measured on Mars") \
		and words.contains("ISS or Earth test") and words.contains("made up for the game") and words.contains("game balance")
	_check("popup shows title, long text and each claim's kind in words", cats_ok, words.replace("\n", " | "))
	_check("popup is inside the same window", popup.is_embedded())
	_check_no_network_nodes()
	var focus_owner := popup.gui_get_focus_owner()
	_check("keyboard focus moves to the popup's Sources button", focus_owner == eb.sources_button(), str(focus_owner))
	for size_and_scale: Array in SIZES:
		var screen: Vector2i = size_and_scale[0]
		root.size = screen
		_set_text_scale(size_and_scale[1])
		eb.close_popup()
		await _frames()
		eb.open_popup()
		await _frames(3)
		var content := popup.get_child(0) as Control
		var probs := UiLayoutCheck.problems(content, Vector2(popup.size))
		var on_screen := Rect2(Vector2.ZERO, Vector2(screen)).grow(1.0).encloses(Rect2(Vector2(popup.position), Vector2(popup.size)))
		var wraps := _wrap_problems(content as ScrollContainer)
		var fits := (content as ScrollContainer).get_v_scroll_bar().max_value <= float(popup.size.y)
		_check("popup layout at %dx%d, text %.1f" % [screen.x, screen.y, size_and_scale[1]], probs.is_empty() and on_screen and wraps.is_empty(),
			"popup %s at %s; fits without scrolling: %s; %s %s" % [popup.size, popup.position, fits, "; ".join(probs), "; ".join(wraps)])
		var focus := UiLayoutCheck.focus_problems(content)
		_check("popup focus at %dx%d, text %.1f" % [screen.x, screen.y, size_and_scale[1]], focus.is_empty(), "; ".join(focus))
	root.size = Vector2i(1280, 720)
	_set_text_scale(1.0)

	# Esc closes the popup first and does not reach the game.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	var esc_up := esc.duplicate() as InputEventKey
	esc_up.pressed = false
	root.push_input(esc_up)
	await _frames(3)
	var seen_after_first: int = sentinel.get("seen")
	_check("Esc closes the popup first", not popup.visible and seen_after_first == 0, "popup visible %s, game saw Esc %d times" % [popup.visible, seen_after_first])
	_check("focus returns to the ? button", eb.has_focus())
	root.push_input(esc)
	root.push_input(esc_up)
	await _frames()
	_check("with the popup closed, Esc goes on to the game (sentinel works)", int(sentinel.get("seen")) == 1, str(sentinel.get("seen")))

	# Sources button opens the register at the right entry.
	eb.open_popup()
	await _frames()
	eb.sources_button().pressed.emit()
	await _frames()
	var target := eb.sources_target()
	_check("Sources emits sources_requested with the first linked claim", asked.size() == 1 and asked[0] == "mars_air" and target == "mars_air", str(asked))
	_check("Sources asks the owning panel to open a SourceRegisterPanel", opened_panels.size() == 1 and opened_panels[0] is SourceRegisterPanel and not popup.visible)
	if opened_panels.size() == 1:
		var reg := opened_panels[0] as SourceRegisterPanel
		reg.setup(_services)
		root.add_child(reg)
		reg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames()
		_check("the register opens at that entry", reg.current_entry_id() == "mars_air" and _labels_text(reg.detail_pane()).contains("95.1%"), reg.current_entry_id())
		reg.queue_free()

	# An explanation with no claims or sources opens the register at the start; a button outside a panel still signals.
	var loose := ExplainButton.make("cargo")
	root.add_child(loose)
	var loose_asked: PackedStringArray = []
	loose.sources_requested.connect(func(id: String) -> void: loose_asked.append(id))
	loose.open_popup()
	await _frames()
	loose.sources_button().pressed.emit()
	await _frames()
	_check("a button outside any panel still emits sources_requested", loose_asked.size() == 1 and loose_asked[0] == "" and loose.last_register == null, str(loose_asked))
	loose.queue_free()

	var custom := ExplainButton.make("", "Panel-specific guidance.", "Station help")
	root.add_child(custom)
	custom.open_popup()
	await _frames()
	var custom_text := _labels_text(custom.popup_window())
	_check("custom help shows its title and guidance without a sources button", custom_text.contains("Station help") and custom_text.contains("Panel-specific guidance.") and not custom.sources_button().visible)
	custom.close_popup()
	custom.queue_free()

	var unknown := ExplainButton.make("no_such_id")
	root.add_child(unknown)
	unknown.open_popup()
	await _frames()
	_check("an unknown id shows a plain 'not written yet' popup without errors", _labels_text(unknown.popup_window()).contains("not been written yet"))
	unknown.close_popup()
	unknown.queue_free()
	host.queue_free()
	sentinel.queue_free()
	await _frames()


# ---------------------------------------------------------------- credits

func _check_credits_panel() -> void:
	var panel := CreditsPanel.new()
	panel.setup(_services)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	_check("credits grouped by kind", panel.group_titles() == PackedStringArray(["Engine", "Tools", "Assets", "Science sources"]), str(panel.group_titles()))
	var text := _labels_text(panel)
	_check("credits show licences in words", text.contains("MIT licence") and text.contains("GPL licence") and text.contains("CC0") \
		and text.contains("Creative Commons Attribution 4.0") and text.contains("Licence unknown") and text.contains("Mixamo") and text.contains("PlayerCharacter.fbx"))
	await _layout_checks(panel, "CreditsPanel")
	root.size = Vector2i(1280, 720)
	_set_text_scale(1.5)
	await _frames()
	var wraps := _wrap_problems(panel.credit_list())
	_check("credit entries wrap without clipping (1280x720, text 1.5)", wraps.is_empty(), "; ".join(wraps))
	_set_text_scale(1.0)
	var opened: Array = []
	panel.open_requested.connect(func(p: UiPanel) -> void: opened.append(p))
	(panel.find_child("OpenRegister", true, false) as Button).pressed.emit()
	_check("science credits link to the source register", opened.size() == 1 and opened[0] is SourceRegisterPanel)
	for p: Variant in opened:
		(p as Node).free()
	_check_no_network_nodes()
	panel.queue_free()
	await _frames()


func _check_no_network_nodes() -> void:
	var found: PackedStringArray = []
	_find_network(root, found)
	_check("no HTTPRequest nodes anywhere in the tree (register works offline)", found.is_empty(), "; ".join(found))


func _find_network(node: Node, found: PackedStringArray) -> void:
	if node is HTTPRequest:
		found.append(String(node.get_path()))
	for child in node.get_children(true):
		_find_network(child, found)
