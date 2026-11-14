extends SceneTree

var passed := 0
var total := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	await process_frame
	var services := GameServices.new()
	root.add_child(services)
	services.start_new_game(41)
	services.set_process(false)
	await process_frame
	services.set_process(false)
	var st := services.state()
	var b := services.balance
	for id: String in ColonyState.EQUIPMENT_IDS:
		st.equipment[id]["condition"] = 1.0
		st.equipment[id]["on"] = true
	PowerModel.allocate(st, b, 0.5, 0.01, {"electrolyser": 0.0, "co2_unit": 0.0})
	check("normal fixed machine is not a problem", PowerLifePanel.equipment_problem(st, b, "scrubber") == "")
	st.equipment.scrubber.kw = b.scrubber_kw * 2.0
	check("high draw gives a specific explanation", "Unusually high" in PowerLifePanel.equipment_problem(st, b, "scrubber"))
	st.equipment.scrubber.kw = b.scrubber_kw * 0.2
	check("low draw gives a specific explanation", "Unusually low" in PowerLifePanel.equipment_problem(st, b, "scrubber"))
	st.equipment.scrubber.kw = b.scrubber_kw * 1.1
	check("small variation is ignored", PowerLifePanel.equipment_problem(st, b, "scrubber") == "")
	st.equipment.scrubber.condition = 0.1
	check("broken machine identifies repair", "broken" in PowerLifePanel.equipment_problem(st, b, "scrubber"))
	st.equipment.scrubber.condition = 1.0
	st.equipment.scrubber.powered = false
	check("lost supply identifies shortage", "insufficient supply" in PowerLifePanel.equipment_problem(st, b, "scrubber"))
	st.equipment.scrubber.on = false
	check("deliberately off is not a fault", PowerLifePanel.equipment_problem(st, b, "scrubber") == "")
	check("idle oxygen production is not a fault", PowerLifePanel.equipment_problem(st, b, "electrolyser") == "")
	st.panel_dust.fill(0.5)
	check("dirty solar array explains low output", "dust" in PowerLifePanel.solar_problem_text(st, b, true))
	check("night is not a solar fault", PowerLifePanel.solar_problem_text(st, b, false) == "")
	st.panel_dust.fill(0.0)
	check("clean solar array has no fault", PowerLifePanel.solar_problem_text(st, b, true) == "")
	var panel := PowerLifePanel.new()
	panel.setup(services)
	root.add_child(panel)
	panel.refresh()
	var loads := panel.get("_loads") as VBoxContainer
	check("five collapsed power categories", loads.get_child_count() == 5)
	var button := loads.get_child(0) as Button
	check("normal category is neutral", button.get_theme_color("font_color").is_equal_approx(AstraStyle.TEXT_2))
	button.pressed.emit()
	check("category expands to individual readings", loads.get_child_count() > 5)
	st.equipment.scrubber.on = true
	panel.refresh()
	var problems := panel.get("_problems") as VBoxContainer
	check("faults pop up in problem list", problems.visible and problems.get_child_count() > 1)
	st.equipment.scrubber.powered = true
	st.equipment.scrubber.kw = b.scrubber_kw
	panel.refresh()
	check("resolved faults disappear", not problems.visible)
	panel.queue_free()
	services.queue_free()
	await process_frame
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)
