extends SceneTree
## Field-sample science and salvage fabrication (Prompt 08, Part S). Every PASS below is measured on the running game:
## stations and walkable sample sites, provenance of every number, specialist and distance rules, sample labels,
## lab comparisons (right and wrong), results used once, salvage recovered once (also after save/load, with a
## duplicate request and by a second player), refurbishing without making matter, the bench test and the upgrades,
## evidence recorded once, the four panels and their layout.
## Run: ..\godot.cmd --headless --path . --script res://tests/test_science.gd


## Collects engine and script errors raised while the test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SIZES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.5]]
const SITES: Array[String] = ["site_east_rocks", "site_mast_boulders", "site_crash_crust"]
const DONORS: Array[String] = ["ls_filter_old", "pr_bat_rack_alarm", "pr_swgr_burnt", "sf_crash_tank", "cr_console_alarm"]
const LAB := &"mb_glovebox"
const BENCH := &"hg_control_board"
const GREENHOUSE := &"gh_console"
## Outside door of the airlock (Godot x, z): the airlock room ends at Blender y = -15 at x = 22 (colony_manifest.json).
const AIRLOCK_DOOR := Vector2(22.0, 15.0)
const EVIDENCE: Array[String] = ["sci_record_context", "sci_compare_controls", "sci_apply_result", "res_identify_compatible", "res_assembly_test"]

var _passed := 0
var _total := 0
var _catcher := ErrorCatcher.new()
var services: GameServices
var _eligibility := {}


func _initialize() -> void:
	OS.add_logger(_catcher)
	PlayerInput.ensure_actions()
	services = GameServices.new()
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/science"), "colony", 2)
	root.add_child(services)
	services.start_new_game(1)
	await _frames()
	services.set_process(false)          # ticks only by hand
	services.events.upgrade_eligibility_changed.connect(func(id: StringName) -> void: _eligibility[String(id)] = int(_eligibility.get(String(id), 0)) + 1)

	_test_stations()
	_test_walkable_sites()
	_test_sources()
	_test_specialists_and_distance()
	_test_take_sample()
	_test_lab()
	_test_apply_result()
	_test_salvage_once()
	await _test_save_load()
	_test_refurbish()
	_test_upgrades()
	_test_evidence_once()
	await _test_panels()
	await _test_layouts()

	_check("no script or engine errors during the test", _catcher.errors.is_empty(), "\n".join(_catcher.errors))
	OS.remove_logger(_catcher)
	services.queue_free()
	await process_frame
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


# ---------------------------------------------------------------- helpers

func _check(test_name: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS %s" % test_name)
	else:
		print("FAIL %s: %s" % [test_name, detail])


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func st() -> ColonyState:
	return services.state()


func me() -> CharacterState:
	return services.local_character()


func _pos(id: String) -> Vector3:
	return CharacterState._v3(st().stations[id].position)


## The local player's crew member stands at station `id`.
func _at(id: String) -> void:
	me().position = _pos(id)


## Hands the local player over to crew member `id` (the old one is walked to the hub first).
func _become(id: StringName) -> void:
	if me() != null and me().id == id:
		return
	me().position = me().hub_spot
	services.session.request(&"claim_character", id)


func _req(action: StringName, target: StringName, params := {}) -> ActionResult:
	return services.session.request(action, target, params)


func _upgrade(id: String, on := true) -> void:
	if on:
		st().upgrades[id] = {"installed": true}
	else:
		st().upgrades.erase(id)


## Runs the simulation for at least `hours` game hours, tick by tick.
func _run_hours(hours: float) -> void:
	var target := st().sim_hours + hours
	var guard := 0
	while st().sim_hours < target and guard < 20000:
		services.session.advance(1.0 / services.config.sim_tick_hz)
		guard += 1


## The index of the right interpretation for a sample's current retry variant.
func _right_choice(sample_id: String) -> int:
	var lab: Dictionary = ScienceActions.read(st(), "lab")[sample_id]
	var site := String((ScienceActions.read(st(), "samples")[sample_id] as Dictionary).site)
	var truth := String(ScienceActions.site_info(site).rock_type)
	var options := ScienceActions.interpretation_options(int(lab.variant))
	for i in options.size():
		if String((options[i] as Dictionary).id) == truth:
			return i
	return -1


func _wrong_choice(sample_id: String) -> int:
	return (_right_choice(sample_id) + 1) % 3


## As the field specialist: takes a sample at `site` and carries it to the lab. Returns the sample id.
func _sample_at(site: String) -> String:
	_become(&"crew_4")
	_at(site)
	var r := _req(&"take_sample", StringName(site))
	_at(String(LAB))
	return String(r.changes.get("item", ""))


## As the field specialist: identifies and takes out `part` of `donor`. Returns the salvaged item id ("" if refused).
func _salvage(donor: String, part: String) -> String:
	_become(&"crew_4")
	_at(donor)
	_req(&"inspect_donor", StringName(donor), {"choice": part})
	var r := _req(&"recover_part", StringName(donor), {"part": part})
	return String(r.changes.get("item", "")) if r.ok else ""


func _cargo_kinds(c: CharacterState) -> PackedStringArray:
	var out := PackedStringArray()
	for id in c.cargo:
		out.append(String((st().items.get(String(id), {}) as Dictionary).get("kind", "?")))
	return out


## Puts down everything the local crew member carries (test setup).
func _empty_pack() -> void:
	for id in me().cargo.duplicate():
		_req(&"drop", id)


# ---------------------------------------------------------------- stations

func _test_stations() -> void:
	var kinds := {}
	for id: String in st().stations:
		var kind := String(st().stations[id].kind)
		if not kinds.has(kind):
			kinds[kind] = []
		(kinds[kind] as Array).append(id)
	var sites: Array = kinds.get("sample_site", [])
	sites.sort()
	var donors: Array = kinds.get("salvage", [])
	# The scout update adds a sixth donor with no map object (the broken-down rover, data/stations_scout.json); it is
	# checked in tests/test_scout.gd. This check stays about the five damaged map objects of Part S.
	donors.erase("broken_rover")
	donors.sort()
	var want_sites := SITES.duplicate()
	want_sites.sort()
	_check("stations: 3 sample sites, the lab glovebox, the 5 P08 salvage donors (more from Prompt 10) and the workbench",
		sites == want_sites and kinds.get("lab", []) == ["mb_glovebox"] and DONORS.all(func(x: String) -> bool: return donors.has(x)) and kinds.get("workbench", []) == ["hg_control_board"],
		str(kinds.get("sample_site", [])) + str(kinds.get("lab", [])) + str(kinds.get("salvage", [])) + str(kinds.get("workbench", [])))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameServices.MANIFEST_PATH))
	var names := {}
	for o: Dictionary in manifest.objects:
		names[String(o.name)] = true
	var damaged := true
	# Prompt 10 (rover economy) adds donors; every salvage station, old and new, must be a damaged map object
	for d: String in donors:
		damaged = damaged and names.has(d) and (d.contains("old") or d.contains("alarm") or d.contains("burnt") or d.contains("crash") or d.contains("fault")) and not ScienceActions.donor_info(d).is_empty()
	_check("stations: every donor is an existing damaged object of the map with data in salvage.json", damaged)
	var outside := true
	for s: String in SITES:
		outside = outside and String(st().stations[s].zone) == ColonyZones.EXTERIOR and not ScienceActions.site_info(s).is_empty()
	_check("stations: sample sites are in the Exterior zone and have data in samples.json", outside)
	var classes_ok := true
	var hook_ok := true
	for id: String in SITES + [String(LAB), String(BENCH)] + DONORS:
		var kind := String(st().stations[id].kind)
		var hooked := StationPanels.for_station(StringName(id), services)
		hook_ok = hook_ok and hooked != null and _is_own_class(hooked, kind)
		if hooked != null:
			hooked.free()
		var panel := _make_panel(id)
		classes_ok = classes_ok and panel != null and _is_own_class(panel, kind) and bool(panel.get_meta(&"station_surface", false))
		if panel != null:
			panel.free()
		classes_ok = classes_ok and ResourceLoader.exists("res://scripts/ui/stations/%s_station_panel.gd" % kind)
	_check("stations: each new station kind has its own panel at scripts/ui/stations/<kind>_station_panel.gd", classes_ok)
	_check("stations: StationPanels.for_station opens those panels", hook_ok,
		"for_station returns the plain StationPanel: in scripts/ui/station_panels.gd the `_:` branch of `match kind if panel == null else \"\"` also matches \"\" and replaces the custom panel (file outside Part S)")


func _is_own_class(panel: Object, kind: String) -> bool:
	match kind:
		"sample_site": return panel is SampleSiteStationPanel
		"lab": return panel is LabStationPanel
		"salvage": return panel is SalvageStationPanel
		"workbench": return panel is WorkbenchStationPanel
	return false


## The station's panel, built the way StationPanels.for_station intends (its custom-panel lookup), set up.
func _make_panel(id: String) -> StationPanel:
	var hooked := StationPanels.for_station(StringName(id), services) as StationPanel
	var kind := String(st().stations[id].kind)
	if hooked != null and _is_own_class(hooked, kind):
		return hooked
	if hooked != null:
		hooked.free()
	var path := "res://scripts/ui/stations/%s_station_panel.gd" % kind
	if not ResourceLoader.exists(path):
		return null
	var panel := (load(path) as Script).new() as StationPanel
	panel.station_id = StringName(id)
	panel.kind = kind
	panel.set_meta(&"station_surface", true)
	panel.set_meta(&"station_id", StringName(id))
	panel.setup(services)
	return panel


## Sample sites on walkable ground: on the height grid, nearly flat, clear of every map object's collision box and of
## the outdoor rocks, and within a walk of the airlock.
func _test_walkable_sites() -> void:
	var height := load("res://data/terrain_height.res") as TerrainHeight
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameServices.MANIFEST_PATH))
	var colliders: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/colliders.json")) as Dictionary).get("assets", {})
	var problems := PackedStringArray()
	var details := PackedStringArray()
	for s: String in SITES:
		var p := _pos(s)
		var ground := height.height_at(p.x, p.z) if height != null else INF
		var slope := 0.0
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			slope = maxf(slope, absf(height.height_at(p.x + d.x, p.z + d.y) - ground) if height != null else INF)
		var gap := INF
		var nearest := ""
		for o: Dictionary in manifest.objects:
			var m: Array = o.matrix_world
			var q := Vector2(float(m[0][3]), -float(m[1][3]))
			var r := 0.0
			for c: Dictionary in (colliders.get(String(o.get("gc_asset", "")), {}) as Dictionary).get("cols", []):
				r = maxf(r, Vector2(absf(float(c.c[0])) + float(c.h[0]), absf(float(c.c[2])) + float(c.h[2])).length())
			var g := q.distance_to(Vector2(p.x, p.z)) - r
			if g < gap:
				gap = g
				nearest = String(o.name)
		var rock_gap := INF
		for o: Dictionary in manifest.environment_objects:
			if String(o.name).begins_with("rock"):
				var m: Array = o.matrix_world
				rock_gap = minf(rock_gap, Vector2(float(m[0][3]), -float(m[1][3])).distance_to(Vector2(p.x, p.z)))
		var walk := AIRLOCK_DOOR.distance_to(Vector2(p.x, p.z))
		details.append("%s: ground %.3f vs %.3f, slope %.3f, %s %.2f m clear, rock %.2f m, %.0f m from the airlock" % [s, p.y, ground, slope, nearest, gap, rock_gap, walk])
		if height == null or absf(p.y - ground) > 0.15 or slope > 0.15 or gap < 1.0 or rock_gap < 1.5 or walk > 45.0:
			problems.append(details[details.size() - 1])
	_check("sample sites stand on walkable ground (height grid, flat, clear of objects and rocks, near the airlock)", height != null and problems.is_empty(),
		"; ".join(problems) if not problems.is_empty() else "no height grid")
	print("  " + "\n  ".join(details))


# ---------------------------------------------------------------- sources

func _test_sources() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/model_sources_science.json"))
	var register := FileAccess.get_file_as_string("res://docs/source_register.md")
	var allowed := ["balance", "physics", "illustrative", "S06", "index"]
	var missing := PackedStringArray()
	if data is Dictionary:
		for p: Dictionary in ScienceBalance.new().get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and String(p.name) != "current":
				var e: Variant = (data as Dictionary).get(String(p.name))
				if not (e is Dictionary) or not allowed.has(String((e as Dictionary).get("category", ""))):
					missing.append(String(p.name))
		for key: String in data:
			for sid: Variant in ((data as Dictionary)[key] as Dictionary).get("source_ids", []):
				if not register.contains("| %s |" % String(sid)):
					missing.append("%s cites %s, not in the register" % [key, sid])
	_check("sources: every ScienceBalance field has a category in model_sources_science.json; every cited id is in the register",
		data is Dictionary and missing.is_empty(), ", ".join(missing))
	var refs_ok := true
	for r: Dictionary in ScienceActions.samples_data().references:
		refs_ok = refs_ok and String(r.source_id) == "S06" and String(r.values_label).contains("illustrative, not from the archive") \
			and String(r.site).contains("Gale crater") and String(r.archive).contains("msl-m-chemin-4-rdr-v1") and register.contains("msl-m-chemin-4-rdr-v1")
	_check("sources: references cite S06 for mission/instrument/site/archive only and label their mineral values illustrative", refs_ok
		and String(ScienceActions.control_info().category) == "illustrative" and String(ScienceActions.samples_data()._about).contains("ILLUSTRATIVE, NOT FROM THE ARCHIVE"))
	var sb := ScienceBalance.new()
	_check("sources: nutrient settings come from the balance resource (0..1)", sb.nutrient_setting_for("volcanic") > sb.nutrient_setting_for("clay")
		and sb.nutrient_setting_for("clay") > sb.nutrient_setting_for("sulfate") and sb.nutrient_setting_for("sulfate") > 0.0 and sb.nutrient_setting_for("volcanic") <= 1.0)


# ---------------------------------------------------------------- rules

func _test_specialists_and_distance() -> void:
	_become(&"crew_1")
	_at(SITES[0])
	var r := _req(&"take_sample", StringName(SITES[0]))
	_check("specialist: the electrical specialist cannot take a sample (wrong_specialty)", not r.ok and r.reason == &"wrong_specialty", String(r.reason))
	_at(DONORS[0])
	r = _req(&"inspect_donor", StringName(DONORS[0]), {"choice": "fan_motor"})
	var r2 := _req(&"recover_part", StringName(DONORS[0]), {"part": "fan_motor"})
	_check("specialist: anyone may inspect a donor, but taking a part out needs the field specialist", r.ok and not r2.ok and r2.reason == &"wrong_specialty",
		"%s / %s" % [r.reason, r2.reason])
	_become(&"crew_4")
	var far := _pos(SITES[0]) + Vector3(services.config.interact_distance_m + 0.5, 0.0, 0.0)
	me().position = far
	var reasons := PackedStringArray()
	for pair: Array in [[&"take_sample", SITES[0], {}], [&"recover_part", DONORS[0], {"part": "fan_motor"}], [&"inspect_donor", DONORS[1], {}],
			[&"analyze_sample", String(LAB), {"sample": "sample_1"}], [&"refurbish", String(BENCH), {"item": "none"}]]:
		me().position = _pos(String(pair[1])) + Vector3(services.config.interact_distance_m + 0.5, 0.0, 0.0)
		reasons.append(String(_req(pair[0], StringName(String(pair[1])), pair[2]).reason))
	_check("distance: every science and salvage action is refused from too far away", Array(reasons).all(func(x: String) -> bool: return x == "too_far"), ", ".join(reasons))
	r = _req(&"take_sample", BENCH)
	_check("stations: take_sample only works at a sample site (wrong_target)", not r.ok and (r.reason == &"wrong_target" or r.reason == &"too_far"), String(r.reason))


func _test_take_sample() -> void:
	_become(&"crew_4")
	_at(SITES[0])
	var items_before := st().items.size()
	var clock := services.clock()
	var tau := st().dust_tau
	var r := _req(&"take_sample", StringName(SITES[0]))
	var id := String(r.changes.get("item", ""))
	var label: Dictionary = ScienceActions.read(st(), "samples").get(id, {})
	var item: Dictionary = st().items.get(id, {})
	var cond: Dictionary = label.get("conditions", {})
	_check("take_sample: a sample item goes into the field specialist's pack", r.ok and me().cargo.has(StringName(id)) and String(item.get("kind", "")) == "sample"
		and String(item.get("holder", "")) == "crew_4" and st().items.size() == items_before + 1, str(r.changes))
	_check("take_sample: provenance stored (site, game time, sol, time of day, sky conditions, who)", String(label.get("site", "")) == SITES[0]
		and is_equal_approx(float(label.get("at_hours", -1.0)), st().sim_hours) and int(label.get("sol", 0)) == clock.sol_index + 1
		and is_equal_approx(float(label.get("phase", -1.0)), clock.phase) and String(label.get("time_text", "")).begins_with("Sol %d" % (clock.sol_index + 1))
		and is_equal_approx(float(cond.get("dust_tau", -1.0)), tau) and cond.has("daylight") and String(cond.get("sky", "")) != ""
		and String(label.get("taken_by", "")) == "crew_4", str(label))
	var ev: Dictionary = st().evidence.get("sci_record_context", {})
	_check("take_sample: evidence sci_record_context with the site, time and conditions", String(ev.get("sector", "")) == "science"
		and String((ev.get("detail", {}) as Dictionary).get("site", "")) == SITES[0] and (ev.get("detail", {}) as Dictionary).has("conditions") and String(ev.get("by", "")) == "crew_4", str(ev))
	_req(&"take_sample", StringName(SITES[0]))
	_req(&"take_sample", StringName(SITES[0]))
	var count := int(ScienceActions.read(st(), "site_counts").get(SITES[0], 0))
	r = _req(&"take_sample", StringName(SITES[0]))
	_check("take_sample: a site gives at most %d samples, then says so" % ScienceBalance.get_current().samples_per_site,
		count == ScienceBalance.get_current().samples_per_site and not r.ok and r.reason == &"insufficient" and r.message.contains("another site"), "%d, %s" % [count, r.message])
	# a full pack
	var keep := me().cargo.duplicate()
	while me().cargo.size() < services.balance.cargo_slots:
		me().cargo.append(&"filler")
	_at(SITES[1])
	r = _req(&"take_sample", StringName(SITES[1]))
	me().cargo = keep
	_check("take_sample: refused with a full pack (cargo_full)", not r.ok and r.reason == &"cargo_full", String(r.reason))
	# put the extra two samples down by the lab so they do not fill the pack later
	_at(String(LAB))
	for extra in me().cargo.duplicate():
		if String(extra) != id:
			_req(&"drop", extra)


func _test_lab() -> void:
	_become(&"crew_4")
	_at(String(LAB))
	var sample := ""
	for c in me().cargo:
		if String((st().items.get(String(c), {}) as Dictionary).get("kind", "")) == "sample":
			sample = String(c)
			break
	var r := _req(&"interpret_sample", LAB, {"sample": sample, "choice": 0})
	_check("lab: interpreting before measuring is refused", not r.ok and r.reason == &"missing_prerequisite", String(r.reason))
	r = _req(&"analyze_sample", LAB, {"sample": sample, "reference": "ref_clay_mudstone"})
	_check("lab: the second reference needs the sample comparison upgrade", not r.ok and r.reason == &"missing_prerequisite", String(r.reason))
	r = _req(&"analyze_sample", LAB, {"sample": sample, "reference": "ref_basaltic_sand"})
	var lab: Dictionary = ScienceActions.read(st(), "lab").get(sample, {})
	_check("lab: analyze_sample measures the sample against the reference and the blank control", r.ok and String(lab.get("reference", "")) == "ref_basaltic_sand"
		and String(lab.get("control", "")) == "blank_holder" and (r.changes.readout as Dictionary).has("volcanic") and (r.changes.options as Array).size() == 3, str(r.changes))
	var health := {}
	for c: CharacterState in st().characters.values():
		health[c.id] = c.health
	var stores_before: Dictionary = st().to_dict().stores
	var options_before: Array = (r.changes.options as Array).duplicate()
	var wrong := _wrong_choice(sample)
	r = _req(&"interpret_sample", LAB, {"sample": sample, "choice": wrong})
	lab = ScienceActions.read(st(), "lab").get(sample, {})
	var health_same := true
	for c: CharacterState in st().characters.values():
		health_same = health_same and c.health == float(health[c.id])
	var options_after := ScienceActions.interpretation_options(int(lab.variant)).map(func(o: Dictionary) -> String: return String(o.text))
	_check("lab: a wrong interpretation gives feedback in words and a retry variant (new numbers, new order)", r.ok and not bool(r.changes.correct)
		and String(r.changes.text).begins_with("Not quite.") and int(lab.variant) == 1 and options_after != options_before
		and ScienceActions.sample_readout(SITES[0], 1) != ScienceActions.sample_readout(SITES[0], 0), String(r.changes.get("text", "")))
	_check("lab: a wrong interpretation costs nothing: no health change, no store change, no result, no evidence, sample kept",
		health_same and st().to_dict().stores == stores_before and ScienceActions.read(st(), "results").is_empty() and not st().evidence.has("sci_compare_controls")
		and me().cargo.has(StringName(sample)))
	r = _req(&"interpret_sample", LAB, {"sample": sample, "choice": _right_choice(sample)})
	var results := ScienceActions.read(st(), "results")
	var rid := String(r.changes.get("result_id", ""))
	var res: Dictionary = results.get(rid, {})
	_check("lab: the right interpretation gives a lab result: a nutrient setting with its uncertainty", r.ok and bool(r.changes.correct) and results.size() == 1
		and String(res.get("kind", "")) == "nutrient_setting" and is_equal_approx(float(res.value), ScienceBalance.get_current().nutrient_setting_volcanic)
		and is_equal_approx(float(res.uncertainty), ScienceBalance.get_current().result_uncertainty) and String(res.site) == SITES[0], str(res))
	var ev: Dictionary = st().evidence.get("sci_compare_controls", {})
	_check("lab: evidence sci_compare_controls names the reference and the control", String((ev.get("detail", {}) as Dictionary).get("reference", "")) == "ref_basaltic_sand"
		and String((ev.get("detail", {}) as Dictionary).get("control", "")) == "blank_holder", str(ev))
	_check("lab: the worked-out sample leaves the pack (kept in the lab's store) and cannot be worked out twice", not me().cargo.has(StringName(sample))
		and not st().items.has(sample) and bool((ScienceActions.read(st(), "samples")[sample] as Dictionary).analysed)
		and not _req(&"interpret_sample", LAB, {"sample": sample, "choice": 0}).ok)

	# calibration and the second reference
	_upgrade("sci_instrument_calibration")
	_upgrade("sci_sample_comparison")
	var other := ""
	for c in me().cargo:
		if String((st().items.get(String(c), {}) as Dictionary).get("kind", "")) == "sample":
			other = String(c)
	if other == "":
		for id: String in st().items:
			if String((st().items[id] as Dictionary).kind) == "sample" and String((st().items[id] as Dictionary).holder) == "":
				_req(&"pick_up", StringName(id))
				other = id
				break
	r = _req(&"analyze_sample", LAB, {"sample": other, "reference": "ref_clay_mudstone"})
	var r3 := _req(&"interpret_sample", LAB, {"sample": other, "choice": _right_choice(other)})
	var res2: Dictionary = ScienceActions.read(st(), "results").get(String(r3.changes.get("result_id", "")), {})
	_check("upgrades: sample comparison opens the second reference; calibration gives a smaller uncertainty", r.ok and r3.ok
		and String(res2.get("reference", "")) == "ref_clay_mudstone" and float(res2.get("uncertainty", 1.0)) < float(res.uncertainty)
		and ScienceActions.mineral_uncertainty(st()) < ScienceBalance.get_current().mineral_uncertainty_pct, "%s / %s" % [r.reason, res2])
	_upgrade("sci_instrument_calibration", false)
	_upgrade("sci_sample_comparison", false)


func _test_apply_result() -> void:
	_become(&"crew_3")
	var ids: Array = ScienceActions.read(st(), "results").keys()
	ids.sort()
	var rid := String(ids[0])
	_at(String(LAB))
	var r := _req(&"apply_result", LAB, {"result_id": rid})
	_check("apply_result: from the lab it needs the evidence-based settings upgrade", not r.ok and r.reason == &"missing_prerequisite", String(r.reason))
	_at(String(GREENHOUSE))
	var req := ActionRequest.make("apply-once", SessionService.HOST_PEER, me().id, &"apply_result", GREENHOUSE, {"result_id": rid})
	r = services.session.submit(req)
	var res: Dictionary = ScienceActions.read(st(), "results")[rid]
	_check("apply_result: at the greenhouse console the result is used for a real setting", r.ok and bool(res.applied) and String(res.applied_to) == String(GREENHOUSE)
		and is_equal_approx(ScienceActions.nutrient_target(st(), String(GREENHOUSE)), float(res.value)) and st().evidence.has("sci_apply_result"), str(res))
	var at := float(res.applied_at_hours)
	var again := services.session.submit(ActionRequest.make("apply-once", SessionService.HOST_PEER, me().id, &"apply_result", GREENHOUSE, {"result_id": rid}))
	var fresh := _req(&"apply_result", GREENHOUSE, {"result_id": rid})
	_check("apply_result: a result is used once (repeat request is a duplicate, a new request is refused)", again.duplicate and again.ok
		and not fresh.ok and fresh.reason == &"missing_prerequisite" and float((ScienceActions.read(st(), "results")[rid] as Dictionary).applied_at_hours) == at, "%s %s" % [again.duplicate, fresh.reason])
	_upgrade("sci_evidence_settings")
	_at(String(LAB))
	r = _req(&"apply_result", LAB, {"result_id": String(ids[1])})
	_check("upgrades: evidence-based settings applies a lab result straight from the lab to every bed", r.ok
		and String((ScienceActions.read(st(), "results")[String(ids[1])] as Dictionary).applied_to) == "all_beds"
		and is_equal_approx(ScienceActions.nutrient_target(st(), "gd_planter"), float((ScienceActions.read(st(), "results")[String(ids[1])] as Dictionary).value)), String(r.reason))
	_upgrade("sci_evidence_settings", false)


# ---------------------------------------------------------------- salvage

func _test_salvage_once() -> void:
	var donor := DONORS[0]
	_become(&"crew_2")
	_at(donor)
	var r := _req(&"inspect_donor", StringName(donor))
	_check("inspect_donor: shows every part of the donor with a clue", r.ok and (r.changes.parts as Array).size() == 4
		and (r.changes.parts as Array).all(func(p: Dictionary) -> bool: return String(p.clue) != ""), str(r.changes.get("parts", [])))
	var health := me().health
	var before := st().evidence.has("res_identify_compatible")
	r = _req(&"inspect_donor", StringName(donor), {"choice": "filter_mesh"})
	_check("inspect_donor: choosing a part that does not fit says why, with no penalty and no evidence", r.ok and not bool(r.changes.fits)
		and String(r.changes.text).contains("Clogged") and me().health == health and st().evidence.has("res_identify_compatible") == before, String(r.changes.get("text", "")))
	_check("inspect_donor: the compatible part was already chosen by the electrical specialist earlier (evidence res_identify_compatible)",
		String((st().evidence.get("res_identify_compatible", {}) as Dictionary).get("by", "")) == "crew_1")

	var items_before := st().items.size()
	_become(&"crew_4")
	_empty_pack()
	_at(donor)
	var req := ActionRequest.make("recover-fan", SessionService.HOST_PEER, &"crew_4", &"recover_part", StringName(donor), {"part": "fan_motor"})
	r = services.session.submit(req)
	var item := String(r.changes.get("item", ""))
	_check("recover_part: the field specialist takes the part out as a salvaged_<part> item", r.ok and String((st().items.get(item, {}) as Dictionary).get("kind", "")) == "salvaged_fan_motor"
		and me().cargo.has(StringName(item)) and ScienceActions.is_recovered(st(), donor, "fan_motor"), str(r.changes))
	var dup := services.session.submit(ActionRequest.make("recover-fan", SessionService.HOST_PEER, &"crew_4", &"recover_part", StringName(donor), {"part": "fan_motor"}))
	var again := _req(&"recover_part", StringName(donor), {"part": "fan_motor"})
	var count := 0
	for id: String in st().items:
		if String((st().items[id] as Dictionary).kind) == "salvaged_fan_motor":
			count += 1
	_check("recover_part: a donor part is recovered once (duplicate request repeats the answer only; a new request is refused)", dup.duplicate
		and not again.ok and again.reason == &"missing_prerequisite" and count == 1 and st().items.size() == items_before + 1, "%s %s %d" % [dup.duplicate, again.reason, count])
	_req(&"inspect_donor", StringName(donor), {"choice": "blower_wheel"})
	r = _req(&"recover_part", StringName(donor), {"part": "blower_wheel"})
	_check("recover_part: a donor gives %d part, then says nothing more can be saved" % ScienceActions.donor_limit(st()), not r.ok and r.reason == &"insufficient", String(r.reason))
	r = _req(&"recover_part", StringName(donor), {"part": "housing_seal"})
	_check("recover_part: a part that does not fit cannot be taken out", not r.ok and r.reason == &"wrong_target", String(r.reason))


func _test_save_load() -> void:
	_become(&"crew_4")
	var samples_before := ScienceActions.read(st(), "samples").duplicate(true)
	var results_before := ScienceActions.read(st(), "results").duplicate(true)
	var parts_before := st().parts
	var err := services.save_now(&"test")
	var loaded := services.continue_game()
	await _frames()
	var same_labels := samples_before.size() == ScienceActions.read(st(), "samples").size()
	for id: String in samples_before:
		var a: Dictionary = samples_before[id]
		var b: Dictionary = ScienceActions.read(st(), "samples").get(id, {})
		same_labels = same_labels and String(a.site) == String(b.get("site", "")) and is_equal_approx(float(a.at_hours), float(b.get("at_hours", -1.0)))
		same_labels = same_labels and String(a.time_text) == String(b.get("time_text", "")) and is_equal_approx(float((a.conditions as Dictionary).dust_tau), float((b.get("conditions", {}) as Dictionary).get("dust_tau", -1.0)))
	_check("save/load: sample labels, lab results and spare parts come back the same", err == OK and loaded.is_usable() and same_labels
		and ScienceActions.read(st(), "results").size() == results_before.size() and st().parts == parts_before and me() != null and me().id == &"crew_4",
		"err %s, labels %s" % [err, same_labels])
	_at(DONORS[0])
	var r := _req(&"recover_part", StringName(DONORS[0]), {"part": "fan_motor"})
	_check("save/load: a recovered donor part stays recovered after a reload", not r.ok and r.reason == &"missing_prerequisite" and ScienceActions.is_recovered(st(), DONORS[0], "fan_motor"), String(r.reason))
	# a second player as the field specialist cannot recover it again either
	_become(&"crew_1")
	services.session.peer_joined(2)
	var claim := services.session.request(&"claim_character", &"crew_4", {}, 2)
	st().character(&"crew_4").position = _pos(DONORS[0])
	var second := services.session.request(&"recover_part", StringName(DONORS[0]), {"part": "fan_motor"}, 2)
	_check("a second player (as the field specialist) cannot recover the same part again", claim.ok and not second.ok and second.reason == &"missing_prerequisite",
		"%s %s" % [claim.reason, second.reason])
	services.session.request(&"release_character", &"", {}, 2)
	services.session.peer_left(2)


# ---------------------------------------------------------------- workbench

func _test_refurbish() -> void:
	_become(&"crew_4")
	var item := ""
	for c in me().cargo:
		if String((st().items.get(String(c), {}) as Dictionary).get("kind", "")).begins_with("salvaged_"):
			item = String(c)
	_at(String(BENCH))

	var parts := st().parts
	var items := st().items.size()
	var ledger := float(st().ledger.get("parts_from_salvage", 0.0))
	# a rock sample is not a machine part
	_at(SITES[1])
	var s := String(_req(&"take_sample", StringName(SITES[1])).changes.get("item", ""))
	_at(String(BENCH))
	var rock := _req(&"refurbish", BENCH, {"item": s})
	_check("refurbish: a rock sample cannot be turned into a part (no electronics from rock)", not rock.ok and rock.reason == &"wrong_target"
		and rock.message.contains("rock") and st().items.has(s) and st().parts == parts, rock.message)
	_req(&"drop", StringName(s))
	items = st().items.size()
	var r := _req(&"refurbish", BENCH, {"item": item})
	var job := String(r.changes.get("job", ""))
	var j: Dictionary = ScienceActions.read(st(), "bench").get(job, {})
	_check("refurbish: consumes exactly the carried salvaged part and adds nothing yet (it waits for its bench test)", r.ok and not st().items.has(item)
		and not me().cargo.has(StringName(item)) and st().items.size() == items - 1 and st().parts == parts and job != ""
		and is_equal_approx(float(j.ready_at_hours) - float(j.started_at_hours), ScienceBalance.get_current().refurbish_hours), str(r.changes))
	var early := _req(&"bench_test", BENCH, {"job": job})
	_check("bench_test: refused until the part is ready, with the time left in words", not early.ok and early.message.contains("ready in"), early.message)
	_run_hours(ScienceBalance.get_current().refurbish_hours + 0.05)
	_at(String(BENCH))
	r = _req(&"bench_test", BENCH, {"job": job})
	_check("bench_test: the test passes and adds exactly one spare part (ledger parts_from_salvage)", r.ok and st().parts == parts + 1
		and is_equal_approx(float(st().ledger.parts_from_salvage), ledger + 1.0) and st().evidence.has("res_assembly_test")
		and int(ScienceActions.read(st(), "components").get("fan_motor", 0)) == 1, "%s parts %d -> %d" % [r.reason, parts, st().parts])
	var twice := _req(&"bench_test", BENCH, {"job": job})
	_check("bench_test: a finished part cannot be tested (and counted) twice", not twice.ok and st().parts == parts + 1, String(twice.reason))
	_check("refurbish: the colony stores obey the ledger: no matter made (items -1, parts +1)", st().items.size() == items - 1 and st().invariants_ok().is_empty(),
		", ".join(st().invariants_ok()))


func _test_upgrades() -> void:
	# the second relay of the same kind still needs a bench test without res_repeat_assembly
	var relay1 := _salvage(DONORS[1], "relay")
	_at(String(BENCH))
	var r1 := _req(&"refurbish", BENCH, {"item": relay1})
	_run_hours(ScienceActions.refurbish_hours(st()) + 0.05)
	_at(String(BENCH))
	_req(&"bench_test", BENCH, {"job": String(r1.changes.get("job", ""))})
	var relay2 := _salvage(DONORS[2], "relay")
	_at(String(BENCH))
	var parts := st().parts
	var r2 := _req(&"refurbish", BENCH, {"item": relay2})
	_check("bench test required: a kind made before still waits for its test without the repeat assembly upgrade", r1.ok and r2.ok
		and String(r2.changes.get("job", "")) != "" and st().parts == parts and ScienceActions.assembled_before(st(), "relay"), "%s / %s" % [r1.changes, r2.changes])
	_run_hours(ScienceActions.refurbish_hours(st()) + 0.05)
	_at(String(BENCH))
	_req(&"bench_test", BENCH, {"job": String(r2.changes.get("job", ""))})

	# res_component_refurbishment: one more part per donor and less time on the bench
	_upgrade("res_component_refurbishment")
	var bus := _salvage(DONORS[1], "bus_bar")
	_at(String(BENCH))
	var r3 := _req(&"refurbish", BENCH, {"item": bus})
	var j3: Dictionary = ScienceActions.read(st(), "bench").get(String(r3.changes.get("job", "")), {})
	_check("upgrades: component refurbishment recovers one more part from a donor and takes less time", bus != "" and r3.ok
		and ScienceActions.recovered_count(st(), DONORS[1]) == 2 and is_equal_approx(float(j3.ready_at_hours) - float(j3.started_at_hours), ScienceBalance.get_current().refurbish_hours_upgraded)
		and ScienceBalance.get_current().refurbish_hours_upgraded < ScienceBalance.get_current().refurbish_hours, "%s %s" % [bus, j3])

	# res_repeat_assembly: a kind made before (fan motor) needs no bench test; a new kind (blower wheel) still does
	_upgrade("res_repeat_assembly")
	var fan2 := _salvage(DONORS[4], "fan_motor")
	var wheel := _salvage(DONORS[0], "blower_wheel")
	_at(String(BENCH))
	parts = st().parts
	var items := st().items.size()
	var bench := ScienceActions.read(st(), "bench").size()
	var ledger := float(st().ledger.parts_from_salvage)
	var rw := _req(&"refurbish", BENCH, {"item": wheel})
	_check("upgrades: with repeat assembly a new kind (blower wheel) still goes to the bench test", wheel != "" and rw.ok and String(rw.changes.get("job", "")) != "", str(rw.changes))
	var rp := _req(&"refurbish", BENCH, {"item": fan2})
	_check("upgrades: repeat assembly skips the bench test for a kind made before (one part at once, input used up)", fan2 != "" and rp.ok and not bool(rp.changes.tested)
		and String(rp.changes.get("job", "")) == "" and st().parts == parts + 1 and is_equal_approx(float(st().ledger.parts_from_salvage), ledger + 1.0)
		and not st().items.has(fan2) and st().items.size() == items - 2 and ScienceActions.read(st(), "bench").size() == bench + 1, str(rp.changes))
	_upgrade("res_repeat_assembly", false)
	_upgrade("res_component_refurbishment", false)
	# res_salvage_inspection: looking it over shows every part that fits at once
	_upgrade("res_salvage_inspection")
	_become(&"crew_2")
	_at(DONORS[2])
	var ri := _req(&"inspect_donor", StringName(DONORS[2]))
	var fits := PackedStringArray()
	for p: Dictionary in ri.changes.parts:
		if bool(p.fits):
			fits.append(String(p.id))
	_check("upgrades: salvage inspection shows every compatible part at once", ri.ok and fits == PackedStringArray(["relay", "cable_lug"])
		and ScienceActions.is_identified(st(), DONORS[2], "cable_lug") and not ScienceActions.is_identified(st(), DONORS[2], "breaker"), str(fits))
	_upgrade("res_salvage_inspection", false)
	_check("upgrades: without salvage inspection a part must be chosen first", not ScienceActions.is_identified(st(), DONORS[2], "cable_lug"))


func _test_evidence_once() -> void:
	var stamps := {}
	for id in EVIDENCE:
		stamps[id] = float((st().evidence.get(id, {}) as Dictionary).get("at_hours", -1.0))
	# repeat every task once more
	var s := _sample_at(SITES[2])
	_req(&"analyze_sample", LAB, {"sample": s})
	_req(&"interpret_sample", LAB, {"sample": s, "choice": _right_choice(s)})
	_become(&"crew_3")
	_at(String(GREENHOUSE))
	var ids: Array = ScienceActions.read(st(), "results").keys()
	for rid: String in ids:
		if not bool((ScienceActions.read(st(), "results")[rid] as Dictionary).applied):
			_req(&"apply_result", GREENHOUSE, {"result_id": rid})
			break
	_at(DONORS[3])
	_req(&"inspect_donor", StringName(DONORS[3]), {"choice": "pressure_gauge"})
	var same := true
	var counts := PackedStringArray()
	for id in EVIDENCE:
		same = same and st().evidence.has(id) and float((st().evidence[id] as Dictionary).at_hours) == float(stamps[id]) and int(_eligibility.get(id, 0)) == 1
		counts.append("%s x%d" % [id, int(_eligibility.get(id, 0))])
	_check("evidence: each of the 5 science and resources ids is recorded once, however often the task is repeated", same, ", ".join(counts))
	var order := ["sci_record_context", "sci_compare_controls", "sci_apply_result"]
	var in_order := true
	for i in order.size() - 1:
		in_order = in_order and float((st().evidence[order[i]] as Dictionary).at_hours) <= float((st().evidence[order[i + 1]] as Dictionary).at_hours)
	_check("evidence: the science evidence came in the order of the activity (context, comparison, applied)", in_order
		and String((st().evidence.sci_record_context as Dictionary).sector) == "science" and String((st().evidence.res_assembly_test as Dictionary).sector) == "resources")


# ---------------------------------------------------------------- panels

func _open(id: String) -> StationPanel:
	_at(id)
	var panel := _make_panel(id)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	panel.refresh()
	return panel


func _close(panel: Control) -> void:
	panel.queue_free()
	await process_frame


func _test_panels() -> void:
	# sample site: refused reason for others, a working button for the field specialist
	_become(&"crew_1")
	var site: SampleSiteStationPanel = await _open(SITES[1])
	var before := JSON.stringify(st().to_dict())
	for i in 3:
		site.refresh()
	var untouched := JSON.stringify(st().to_dict()) == before
	_check("panel sample site: disabled for a non-specialist with the reason in words", site.take_button.disabled
		and site.take_reason_text().contains("field engineering and geology specialist") and site.reading_text(&"taken").contains(" of "), site.take_reason_text())
	_check("panels only read state (refresh changes nothing)", untouched)
	await _close(site)
	_become(&"crew_4")
	_empty_pack()
	site = await _open(SITES[1])
	site.take_button.pressed.emit()
	site.refresh()
	_check("panel sample site: the field specialist takes a sample and the label is shown", not site.take_button.disabled
		and site.cause_text().contains("Sample taken") and site.label_text().contains("Time: Sol") and site.label_text().contains("Conditions:"),
		site.cause_text() + " | " + site.label_text())
	await _close(site)

	# lab: compare, wrong, right
	var lab: LabStationPanel = await _open(String(LAB))
	var sample := ""
	for c in me().cargo:
		if String((st().items.get(String(c), {}) as Dictionary).get("kind", "")) == "sample":
			sample = String(c)
	var compare := lab.compare_buttons.get("%s|ref_basaltic_sand" % sample) as Button
	var second := lab.compare_buttons.get("%s|ref_clay_mudstone" % sample) as Button
	if compare != null:
		compare.pressed.emit()
	lab.refresh()
	var text := lab.comparison_text()
	_check("panel lab: the comparison table shows control, reference and sample with the reference's provenance and its 'illustrative' label",
		compare != null and second != null and second.disabled and lab.shown_sample() == sample and text.contains("Control (empty)") and text.contains("Your sample")
		and text.contains("Gale crater") and text.contains("CheMin") and text.contains("illustrative, not from the archive") and lab.choice_buttons.size() == 3, text)
	var wrong := _wrong_choice(sample)
	lab.choice_buttons[wrong].pressed.emit()
	lab.refresh()
	var fb := lab.feedback_text()
	var right := _right_choice(sample)
	lab.choice_buttons[right].pressed.emit()
	lab.refresh()
	_check("panel lab: a wrong choice shows feedback, a right one gives a result with its uncertainty", fb.begins_with("! Not quite.")
		and lab.feedback_text().begins_with("✓ Right") and lab.results_text().contains("nutrient setting") and lab.results_text().contains("±"),
		fb + " | " + lab.feedback_text())
	var apply := lab.apply_buttons.values()
	_check("panel lab: without the upgrade 'Use for every bed' is disabled and says where to use the result", not apply.is_empty() and (apply[0] as Button).disabled
		and lab.results_text().contains("garden bed or the greenhouse console"), lab.results_text())
	await _close(lab)

	# salvage: wrong choice, then a right one, then take it out
	_become(&"crew_2")
	var donor: SalvageStationPanel = await _open(DONORS[3])
	(donor.fit_buttons["strap"] as Button).pressed.emit()
	donor.refresh()
	var wrong_status := donor.part_status_text("strap")
	_check("panel salvage: a wrong choice is marked 'does not fit' with the reason", wrong_status.contains("Does not fit") and donor.cause_text().contains("Not this one"),
		wrong_status + " | " + donor.cause_text())
	_check("panel salvage: 'Take it out' for a fitting part is disabled for a non-specialist, with the reason",
		donor.take_buttons.has("pressure_gauge") and donor.take_reason_text("pressure_gauge").contains("field engineering"), donor.take_reason_text("pressure_gauge"))
	await _close(donor)
	_become(&"crew_4")
	_empty_pack()
	_upgrade("res_component_refurbishment")
	donor = await _open(DONORS[2])
	(donor.fit_buttons["cable_lug"] as Button).pressed.emit()
	donor.refresh()
	(donor.take_buttons["cable_lug"] as Button).pressed.emit()
	donor.refresh()
	_check("panel salvage: the field specialist takes out the part chosen as fitting", donor.part_status_text("cable_lug").contains("Taken out")
		and _cargo_kinds(me()).has("salvaged_cable_lug"), donor.part_status_text("cable_lug") + " " + str(_cargo_kinds(me())))
	await _close(donor)
	_upgrade("res_component_refurbishment", false)

	# workbench: refurbish, wait, test
	var bench: WorkbenchStationPanel = await _open(String(BENCH))
	var item := ""
	for c in me().cargo:
		if String((st().items.get(String(c), {}) as Dictionary).get("kind", "")) == "salvaged_cable_lug":
			item = String(c)
	var parts := st().parts
	(bench.refurbish_buttons[item] as Button).pressed.emit()
	bench.refresh()
	var job := ""
	for id: String in bench.test_buttons:
		if String((ScienceActions.read(st(), "bench")[id] as Dictionary).part) == "cable_lug":
			job = id
	var waiting := job != "" and (bench.test_buttons[job] as Button).disabled and bench.job_status_text(job).contains("ready in")
	_run_hours(ScienceActions.refurbish_hours(st()) + 0.05)
	_at(String(BENCH))
	bench.refresh()
	var ready := job != "" and not (bench.test_buttons[job] as Button).disabled and bench.job_status_text(job).contains("Ready for its bench test")
	if job != "":
		(bench.test_buttons[job] as Button).pressed.emit()
	bench.refresh()
	_check("panel workbench: refurbish, wait (button off with the time left), then the bench test adds one part", waiting and ready
		and st().parts == parts + 1 and bench.cause_text().contains("Bench test passed"), "%s %s %s" % [waiting, ready, bench.cause_text()])
	await _close(bench)


# ---------------------------------------------------------------- layout

func _test_layouts() -> void:
	_become(&"crew_4")
	_empty_pack()
	# fill the panels: a sample measured at the lab, a part on the bench, a donor half used
	var s := _sample_at(SITES[2])
	_req(&"analyze_sample", LAB, {"sample": s})
	var stretch := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for id: String in [SITES[0], String(LAB), DONORS[1], DONORS[3], String(BENCH)]:
		_at(id)
		var panel := _make_panel(id)
		root.add_child(panel)
		await _check_layout(panel, "%s (%s)" % [(panel as UiPanel).panel_title(), id])
		panel.queue_free()
		await process_frame
	root.content_scale_mode = stretch


func _check_layout(ctl: Control, label: String) -> void:
	var layout := PackedStringArray()
	var focus := PackedStringArray()
	for size: Array in SIZES:
		root.size = size[0]
		UiTheme.apply_text_scale(float(size[1]))
		ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _frames(2)
		(ctl as UiPanel).refresh()
		await _frames(2)
		for line in UiLayoutCheck.problems(ctl, Vector2(size[0])):
			layout.append("%s text %s: %s" % [size[0], size[1], line])
		var min_size := ctl.get_combined_minimum_size()
		if min_size.x > float(size[0].x) or min_size.y > float(size[0].y):
			layout.append("%s text %s: minimum size %s is bigger than the screen" % [size[0], size[1], min_size])
		for line in UiLayoutCheck.focus_problems(ctl):
			focus.append("%s text %s: %s" % [size[0], size[1], line])
	UiTheme.apply_text_scale(1.0)
	root.size = Vector2i(1280, 720)
	_check("layout %s at 1280x720, 1920x1080 and 1280x720 text 1.5" % label, layout.is_empty(), "\n  ".join(layout))
	_check("focus %s" % label, focus.is_empty() and not UiLayoutCheck.focusable(ctl).is_empty(), "\n  ".join(focus))
