class_name WorkbenchStationPanel
extends StationPanel
## The workbench in the Hangar (Prompt 08, Part S). A carried salvaged part goes on the bench ("Refurbish",
## `refurbish`; the part is used up), and when it is ready its bench test ("Run the bench test", `bench_test`) turns it
## into exactly one working spare part. With the repeat assembly upgrade a kind of component made before needs no
## test. Only salvaged parts can be refurbished: nothing is made from rock or soil.

## "Refurbish" buttons by carried item id.
var refurbish_buttons: Dictionary = {}
## "Run the bench test" buttons by bench job id.
var test_buttons: Dictionary = {}

var _carried_box: VBoxContainer
var _bench_box: VBoxContainer
var _done_label: Label
var _job_status: Dictionary = {}
var _sig := ""


## The status words of a bench job as shown ("Ready for its bench test", "Ready in about 2 game hours").
func job_status_text(job_id: String) -> String:
	var l := _job_status.get(job_id) as Label
	return l.text if l != null else ""


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Put a salvaged part on the bench to clean and fit it (anyone).",
		"Run its bench test when it is ready: a part that passes becomes one working spare part.",
		"Only salvaged parts can be refurbished. Nothing is made from rock or soil."])


func _build_body() -> void:
	_add_reading(&"parts", "⚙", "Spare parts", "parts")
	_add_reading(&"from_salvage", "♻", "Spare parts made from salvage", "parts")
	_add_reading(&"time", "⧗", "Time on the bench", "sol_clock")
	_add_heading_with_help(_body, "Salvaged parts in your pack", "cargo")
	_carried_box = VBoxContainer.new()
	_carried_box.name = "Carried"
	_body.add_child(_carried_box)
	_add_heading_with_help(_body, "On the bench", "parts")
	_bench_box = VBoxContainer.new()
	_bench_box.name = "Bench"
	_body.add_child(_bench_box)
	_done_label = _add_text(_body, "", UiTheme.MUTED)
	_done_label.name = "Finished"


func _refresh_body(st: ColonyState) -> void:
	_show_reading(&"parts", "%d parts" % st.parts, &"ok" if st.parts > 0 else &"warn")
	_show_reading(&"from_salvage", "%d parts" % roundi(float(st.ledger.get(ScienceActions.LEDGER_PARTS, 0.0))), &"ok")
	_show_reading(&"time", ScienceActions.hours_text(ScienceActions.refurbish_hours(st)) + (" · quicker (upgrade)" if st.has_upgrade("res_component_refurbishment") else ""), &"ok")
	var me := services.local_character()
	var carried := ScienceActions.carried(st, me, ScienceActions.SALVAGED_PREFIX)
	var samples := ScienceActions.carried(st, me, ScienceActions.SAMPLE_KIND)
	var bench := ScienceActions.read(st, "bench")
	var sig := "%s|%s|%s|%s" % [",".join(PackedStringArray(carried)), samples.size(), JSON.stringify(bench), st.has_upgrade("res_repeat_assembly")]
	if sig != _sig:
		_sig = sig
		_build_lists(st, carried, samples, bench)
	for job: String in _job_status:
		var j: Dictionary = bench.get(job, {})
		var left := float(j.get("ready_at_hours", 0.0)) - st.sim_hours
		var l := _job_status[job] as Label
		var b := test_buttons.get(job) as Button
		if left > 1e-6:
			l.text = "! Being refurbished: ready in %s" % ScienceActions.hours_text(left)
			l.theme_type_variation = UiTheme.WARN
		else:
			l.text = "✓ Ready for its bench test"
			l.theme_type_variation = UiTheme.GOOD
		if b != null:
			b.disabled = left > 1e-6 or me == null
			b.tooltip_text = "Not ready yet." if left > 1e-6 else "Test the refurbished part."
	var comps := ScienceActions.read(st, "components")
	var names := PackedStringArray()
	for pid: String in comps:
		names.append("%s × %d" % [pid.replace("_", " "), int(comps[pid])])
	_done_label.text = "Components made so far: %s." % (", ".join(names) if not names.is_empty() else "none yet")


func _build_lists(st: ColonyState, carried: Array[String], samples: Array[String], bench: Dictionary) -> void:
	for box: VBoxContainer in [_carried_box, _bench_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	refurbish_buttons.clear()
	test_buttons.clear()
	_job_status.clear()
	if carried.is_empty():
		_add_text(_carried_box, "You carry no salvaged part. Take one out of a damaged object first (salvage donors).", UiTheme.MUTED)
	for id in carried:
		var item: Dictionary = st.items.get(id, {})
		var part := ScienceActions.part_info(String(item.get("donor", "")), String(item.get("part", "")))
		var row := HBoxContainer.new()
		_carried_box.add_child(row)
		var name := String(part.get("name", String(item.get("kind", id))))
		var known := st.has_upgrade("res_repeat_assembly") and ScienceActions.assembled_before(st, String(item.get("part", "")))
		var l := _add_text(row, "%s from the %s%s" % [name, String(ScienceActions.donor_info(String(item.get("donor", ""))).get("name", "?")).to_lower(),
			" · made before: no bench test needed" if known else ""])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.name = "Refurbish_%s" % id
		b.text = "Refurbish"
		b.theme_type_variation = UiTheme.PRIMARY_BUTTON
		b.pressed.connect(_on_refurbish.bind(id))
		row.add_child(b)
		refurbish_buttons[id] = b
	if not samples.is_empty():
		_add_text(_carried_box, "You also carry a rock sample: samples go to the lab, they cannot become machine parts.", UiTheme.MUTED)
	var open := 0
	var ids: Array = bench.keys()
	ids.sort()
	for job: String in ids:
		var j: Dictionary = bench[job]
		if bool(j.get("done", false)):
			continue
		open += 1
		var card := PanelContainer.new()
		card.theme_type_variation = UiTheme.CARD
		_bench_box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		_add_text(col, String(j.get("name", job)), UiTheme.HEADING)
		_job_status[job] = _add_text(col, "")
		var b := Button.new()
		b.name = "Test_%s" % job
		b.text = "Run the bench test"
		b.pressed.connect(_on_test.bind(job))
		col.add_child(b)
		test_buttons[job] = b
	if open == 0:
		_add_text(_bench_box, "The bench is empty.", UiTheme.MUTED)


func _on_refurbish(item_id: String) -> void:
	_ask(&"refurbish", {"item": item_id}, _on_answer)


func _on_test(job_id: String) -> void:
	_ask(&"bench_test", {"job": job_id}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	refresh()
