class_name LabStationPanel
extends StationPanel
## The lab glovebox in the Med Bay (Prompt 08, Part S). A carried field sample is measured next to a reference and a
## blank control (`analyze_sample`); the table shows the mineral shares of all three with their plus-or-minus, and
## where the reference comes from (mission, instrument, site, archive; its numbers are illustrative). The player then
## picks one of three interpretations (`interpret_sample`): right gives a lab result, wrong gives feedback and a fresh
## measurement to try again. A result is a nutrient setting that is used once at a garden bed or the greenhouse
## console (`apply_result`), or straight from here with the evidence-based settings upgrade.

## Compare buttons by "sample_id|reference_id".
var compare_buttons: Dictionary = {}
## The three interpretation buttons of the comparison shown (index 0..2).
var choice_buttons: Array[Button] = []
## "Use for every bed" buttons by result id.
var apply_buttons: Dictionary = {}

var _samples_box: VBoxContainer
var _compare_box: VBoxContainer
var _results_box: VBoxContainer
var _feedback: Label
var _shown_sample := ""
var _samples_sig := ""
var _compare_sig := ""
var _results_sig := ""


## The sample whose comparison is shown ("" if none).
func shown_sample() -> String:
	return _shown_sample


## Every line of the comparison section (table, provenance, choices), joined by new lines.
func comparison_text() -> String:
	return "\n".join(_texts(_compare_box))


## The last interpretation answer ("" if none).
func feedback_text() -> String:
	return _feedback.text if _feedback != null else ""


## Every line of the lab results section.
func results_text() -> String:
	return "\n".join(_texts(_results_box))


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["Measure a field sample next to a reference sample and an empty holder (the control).",
		"Choose what the sample is from three ideas. A wrong choice gives a hint and a fresh measurement.",
		"Use a lab result for a real colony setting: the nutrient setting of the garden beds."])


func _build_body() -> void:
	_add_reading(&"carried", "◈", "Samples in your pack", "cargo")
	_add_reading(&"references", "≡", "Reference samples", "sources")
	_add_reading(&"uncertainty", "±", "Measurement uncertainty", "sources")
	_add_reading(&"results", "✓", "Lab results", "food")

	_add_heading_with_help(_body, "Your samples", "cargo")
	_samples_box = VBoxContainer.new()
	_samples_box.name = "Samples"
	_body.add_child(_samples_box)

	_add_heading_with_help(_body, "Comparison", "sources")
	_compare_box = VBoxContainer.new()
	_compare_box.name = "Comparison"
	_body.add_child(_compare_box)
	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback.visible = false
	_body.add_child(_feedback)

	_add_heading_with_help(_body, "Lab results", "food")
	_results_box = VBoxContainer.new()
	_results_box.name = "Results"
	_body.add_child(_results_box)
	_add_text(_body, String(ScienceActions.samples_data().get("use_note", "")), UiTheme.MUTED)


func _refresh_body(st: ColonyState) -> void:
	var me := services.local_character()
	var carried := ScienceActions.carried(st, me, ScienceActions.SAMPLE_KIND)
	var refs := ScienceActions.references_available(st)
	var results := ScienceActions.read(st, "results")
	var used := 0
	for id: String in results:
		if bool((results[id] as Dictionary).get("applied", false)):
			used += 1
	_show_reading(&"carried", "%d" % carried.size(), &"ok" if not carried.is_empty() else &"warn")
	_show_reading(&"references", "%d of %d available" % [refs.size(), (ScienceActions.samples_data().get("references", []) as Array).size()], &"ok")
	_show_reading(&"uncertainty", "± %s percentage points%s" % [num(ScienceActions.mineral_uncertainty(st), 0),
		" · calibrated" if st.has_upgrade("sci_instrument_calibration") else ""], &"ok")
	_show_reading(&"results", "%d · %d used" % [results.size(), used], &"ok")

	if _shown_sample == "" or not carried.has(_shown_sample) or not ScienceActions.read(st, "lab").has(_shown_sample):
		_shown_sample = ""
		for id in carried:
			if ScienceActions.read(st, "lab").has(id):
				_shown_sample = id
				break
	_refresh_samples(st, carried, refs)
	_refresh_comparison(st)
	_refresh_results(st, results)


# ---------------------------------------------------------------- samples

func _refresh_samples(st: ColonyState, carried: Array[String], refs: PackedStringArray) -> void:
	var sig := "%s|%s" % [",".join(PackedStringArray(carried)), ",".join(refs)]
	if sig == _samples_sig:
		return
	_samples_sig = sig
	_clear(_samples_box)
	compare_buttons.clear()
	if carried.is_empty():
		_add_text(_samples_box, "You carry no sample. The field engineering and geology specialist ⛏ takes them at the sample sites outside.", UiTheme.MUTED)
		return
	var samples := ScienceActions.read(st, "samples")
	for id in carried:
		var s: Dictionary = samples.get(id, {})
		var card := PanelContainer.new()
		card.theme_type_variation = UiTheme.CARD
		_samples_box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		_add_text(col, "%s from the %s" % [id.replace("_", " ").capitalize(), String(s.get("site_name", "?"))], UiTheme.HEADING)
		var cond: Dictionary = s.get("conditions", {})
		_add_text(col, "Label: %s, %s, dust in the air %s." % [String(s.get("time_text", "")), String(cond.get("sky", "")), num(float(cond.get("dust_tau", 0.0)), 2)], UiTheme.MUTED)
		var row := HFlowContainer.new()
		col.add_child(row)
		for ref: Dictionary in ScienceActions.samples_data().get("references", []):
			var ref_id := String(ref.id)
			var b := Button.new()
			b.name = "Compare_%s_%s" % [id, ref_id]
			b.text = "Compare with reference %d" % (1 + (ScienceActions.samples_data().references as Array).find(ref))
			b.disabled = not refs.has(ref_id)
			b.tooltip_text = "Needs the sample comparison upgrade." if b.disabled else "Measure the sample next to %s and the empty holder." % String(ref.name).to_lower()
			b.pressed.connect(_on_compare.bind(id, ref_id))
			row.add_child(b)
			compare_buttons["%s|%s" % [id, ref_id]] = b
		if refs.size() < (ScienceActions.samples_data().get("references", []) as Array).size():
			_add_text(col, "Reference 2 becomes available with the sample comparison upgrade.", UiTheme.MUTED)


# ---------------------------------------------------------------- comparison

func _refresh_comparison(st: ColonyState) -> void:
	var lab: Dictionary = ScienceActions.read(st, "lab").get(_shown_sample, {})
	var sig := "%s|%s|%s|%s" % [_shown_sample, String(lab.get("reference", "")), int(lab.get("variant", 0)), ScienceActions.mineral_uncertainty(st)]
	if sig == _compare_sig:
		return
	_compare_sig = sig
	_clear(_compare_box)
	choice_buttons.clear()
	if _shown_sample == "" or lab.is_empty():
		_add_text(_compare_box, "Press \"Compare\" next to a sample to measure it.", UiTheme.MUTED)
		return
	var sample: Dictionary = ScienceActions.read(st, "samples").get(_shown_sample, {})
	var variant := int(lab.get("variant", 0))
	var ref := ScienceActions.reference_info(String(lab.get("reference", ScienceActions.default_reference())))
	var control := ScienceActions.control_info()
	var readout := ScienceActions.sample_readout(String(sample.get("site", "")), variant)
	var unc := num(ScienceActions.mineral_uncertainty(st), 0)
	_add_text(_compare_box, "%s, measurement %d. Shares of the powder, in %% (each ± %s points):" % [_shown_sample.replace("_", " ").capitalize(), variant + 1, unc])
	var grid := GridContainer.new()
	grid.name = "Table"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compare_box.add_child(grid)
	for head in ["Mineral group", "Control (empty)", "Reference", "Your sample"]:
		var h := _add_text(grid, head, UiTheme.HEADING)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ref_values: Dictionary = ref.get("readout", {})
	var control_values: Dictionary = control.get("readout", {})
	for g: Dictionary in ScienceActions.samples_data().get("groups", []):
		var gid := String(g.id)
		_add_text(grid, String(g.name))
		_add_text(grid, "%d %%" % int(control_values.get(gid, 0)))
		_add_text(grid, "%d %%" % int(ref_values.get(gid, 0)))
		_add_text(grid, "%d %%" % int(readout.get(gid, 0)))
	_add_text(_compare_box, "Control: %s" % String(control.get("why", "")), UiTheme.MUTED)
	var where := _add_text(_compare_box, "%s. Mission: %s. Instrument: %s. Site: %s. Archive: %s (source %s). %s" % [
		String(ref.get("name", "")), String(ref.get("mission", "")), String(ref.get("instrument", "")), String(ref.get("site", "")),
		String(ref.get("archive", "")), String(ref.get("source_id", "")), String(ref.get("values_label", ""))], UiTheme.MUTED)
	where.name = "Provenance"
	_add_text(_compare_box, "What is this sample?", UiTheme.HEADING)
	var options := ScienceActions.interpretation_options(variant)
	for i in options.size():
		var b := Button.new()
		b.name = "Choice_%d" % i
		b.text = "%d. %s" % [i + 1, String((options[i] as Dictionary).get("text", ""))]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_choice.bind(_shown_sample, i))
		_compare_box.add_child(b)
		choice_buttons.append(b)


# ---------------------------------------------------------------- results

func _refresh_results(st: ColonyState, results: Dictionary) -> void:
	var sig := "%s|%s" % [JSON.stringify(results), st.has_upgrade("sci_evidence_settings")]
	if sig == _results_sig:
		return
	_results_sig = sig
	_clear(_results_box)
	apply_buttons.clear()
	if results.is_empty():
		_add_text(_results_box, "No lab results yet.", UiTheme.MUTED)
		return
	var direct := st.has_upgrade("sci_evidence_settings")
	var rock_types: Dictionary = ScienceActions.samples_data().get("rock_types", {})
	var ids: Array = results.keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = results[id]
		var row := HBoxContainer.new()
		_results_box.add_child(row)
		var applied := bool(r.get("applied", false))
		var mark := "✓ Used" if applied else "• Not used yet"
		var text := "%s %s: nutrient setting %s ± %s (%s, %s)." % [mark, id.replace("_", " ").capitalize(), num(float(r.get("value", 0.0)), 2),
			num(float(r.get("uncertainty", 0.0)), 2), String((rock_types.get(String(r.get("rock_type", "")), {}) as Dictionary).get("name", "")),
			String(ScienceActions.site_info(String(r.get("site", ""))).get("name", ""))]
		if applied:
			var to := String(r.get("applied_to", ""))
			text += " Used for %s." % ("every garden bed" if to == "all_beds" else to)
		elif not direct:
			text += " Use it at a garden bed or the greenhouse console."
		var l := _add_text(row, text, UiTheme.GOOD if applied else &"")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not applied:
			var b := Button.new()
			b.name = "Apply_%s" % id
			b.text = "Use for every bed"
			b.disabled = not direct
			b.tooltip_text = "Sets every garden bed to this nutrient setting." if direct else "Needs the evidence-based settings upgrade. Without it, use the result at a bed."
			b.pressed.connect(_on_apply.bind(id))
			row.add_child(b)
			apply_buttons[id] = b


# ---------------------------------------------------------------- answers

func _on_compare(sample: String, ref_id: String) -> void:
	_shown_sample = sample
	_ask(&"analyze_sample", {"sample": sample, "reference": ref_id}, _on_answer)


func _on_choice(sample: String, index: int) -> void:
	_ask(&"interpret_sample", {"sample": sample, "choice": index}, _on_choice_answer)


func _on_apply(result_id: String) -> void:
	_ask(&"apply_result", {"result_id": result_id}, _on_answer)


func _on_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		_show_cause(answer_text(result))
	else:
		_show_refusal(result)
	_compare_sig = ""
	refresh()


func _on_choice_answer(result: ActionResult) -> void:
	if result.ok:
		_show_message("")
		var right := bool(result.changes.get("correct", false))
		_feedback.text = ("✓ " if right else "! ") + answer_text(result)
		_feedback.theme_type_variation = UiTheme.GOOD if right else UiTheme.WARN
		_feedback.visible = true
		_show_cause("")
	else:
		_show_refusal(result)
	_compare_sig = ""
	refresh()


# ---------------------------------------------------------------- helpers

static func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## Visible label and button texts under `node`, in tree order.
static func _texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		out.append_array(_texts(child))
	return out
