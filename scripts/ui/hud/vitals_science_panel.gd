class_name VitalsSciencePanel
extends UiPanel
## The "?" of the vitals bar: the science behind every number on it, on a need-to-know basis. One card per idea
## (electricity, solar power, what uses power, oxygen, water, food, cabin air, dust on the panels...), each with its
## plain-language explanation and a "?" that opens its sources. Texts come from data/explanations.json, so the
## science stays in one place for every screen.

const TOPICS := ["battery", "solar_power", "load", "battery_forecast", "oxygen", "electrolysis", "co2_oxygen_unit",
	"cabin_air", "water", "water_quality", "food", "panel_dust", "stock_vs_flow", "sol_length"]


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "VitalsSciencePanel"
	align_right = true
	max_width = 560
	accent_line = false
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 18, 16, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := AstraStyle.label("The science behind the numbers", 20, AstraStyle.TEXT, "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := AstraStyle.flat_button("×", 20, AstraStyle.TEXT_2)
	close.name = "Close"
	close.focus_mode = Control.FOCUS_ALL
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 10)
	scroll.add_child(content)
	for id: String in TOPICS:
		var e := Explanations.get_entry(id)
		if e.is_empty():
			continue
		var card := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.04), AstraStyle.RADIUS_SM + 2, 14, 10, AstraStyle.LINE), id)
		content.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override(&"separation", 4)
		card.add_child(col)
		var row := HBoxContainer.new()
		col.add_child(row)
		var t := AstraStyle.label(String(e.title), 15, AstraStyle.TEXT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(ExplainButton.make(id))
		var l := AstraStyle.label(String(e.long), 13, AstraStyle.TEXT_2)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)


func panel_title() -> String:
	return "The science behind the numbers"


func first_focus() -> Control:
	return find_child("Close", true, false) as Control
