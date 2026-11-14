class_name SolarBuildPanel
extends UiPanel
## "Build" at the solar field: the drawer that opens with B while you stand by a sun tracker outside. One card per
## energy upgrade (sun tracking, battery bank, panel cleaner): what it does, its catch, what it costs in spare parts
## and what it needs first. A card that is ready has a Build button; the electrical and comms specialist installs it
## right here (install_upgrade at this tracker, the same rules as at the power panel). Locked cards say why.

const CATCHES := {
	"energy_solar_tracking": "Catch: it only helps while the Sun is up, and dusty panels still lose power.",
	"energy_battery_reserve": "Catch: a battery stores power but never makes any. When only the reserve is left, the lights go off first.",
	"energy_cleaner_automation": "Catch: a broken cleaner still needs a sol to fix itself, and a big dust storm covers panels faster than it wipes.",
}
const ICONS := {"energy_solar_tracking": "☀", "energy_battery_reserve": "▮", "energy_cleaner_automation": "✧"}
const NAMES := {"energy_solar_tracking": "Solar array tracking", "energy_battery_reserve": "Battery bank", "energy_cleaner_automation": "Panel cleaner robot"}

var tracker_id: StringName = &""
var build_buttons: Dictionary = {}

var _parts: Label
var _tracker: Label
var _list: VBoxContainer
var _message: Label
var _sig := ""


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "SolarBuildPanel"
	align_right = true
	max_width = 470
	accent_line = false
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 18, 16, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := AstraStyle.label("Build · solar field", 20, AstraStyle.TEXT, "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := AstraStyle.flat_button("×", 20, AstraStyle.TEXT_2)
	close.name = "Close"
	close.focus_mode = Control.FOCUS_ALL
	close.tooltip_text = "Close (Esc or B)"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	var stock := HBoxContainer.new()
	stock.add_theme_constant_override(&"separation", 6)
	box.add_child(stock)
	stock.add_child(AstraStyle.label("⚙", 16, AstraStyle.C_PARTS, "", true))
	_parts = AstraStyle.label("", 15, AstraStyle.TEXT, "Parts")
	stock.add_child(_parts)
	var more := AstraStyle.label("Need more? Take parts from the broken-down rover, or turn hematite into parts at the workbench.", 12, AstraStyle.TEXT_3)
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(more)
	_tracker = AstraStyle.label("", 12, AstraStyle.TEXT_2, "Tracker")
	_tracker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tracker)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_list)
	_message = AstraStyle.label("", 13, AstraStyle.TEXT_2, "Message")
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)


func panel_title() -> String:
	return "Build · solar field"


func first_focus() -> Control:
	for id: String in build_buttons:
		var b := build_buttons[id] as Button
		if not b.disabled:
			return b
	return find_child("Close", true, false) as Control


func message_text() -> String:
	return _message.text


func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	_parts.text = "%d spare parts" % st.parts
	var rec: Dictionary = st.stations.get(String(tracker_id), {})
	var idx := int(rec.get("tracker", -1))
	if idx >= 0 and idx < st.panel_dust.size():
		_tracker.text = "This sun tracker: dust on its panels %d %%. Press E at it to clean it." % roundi(float(st.panel_dust[idx]) * 100.0)
	else:
		_tracker.text = ""
	var me := services.local_character()
	var sig := "%d|%s|%s|%s|%s" % [st.parts, JSON.stringify(st.upgrades), JSON.stringify(st.knowledge), JSON.stringify(st.evidence), me.id if me != null else ""]
	if sig == _sig:
		return
	_sig = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	build_buttons.clear()
	for c: UpgradeDefinition in ProgressionSystem.cards_of("energy"):
		# Only the cards that can be built at a sun tracker (the radio cards are energy-sector too, but are installed
		# at the comms console: Prompt 11).
		if c.also_install_kinds.has("solar"):
			_list.add_child(_card(st, c, me))


func _card(st: ColonyState, c: UpgradeDefinition, me: CharacterState) -> Control:
	var id := String(c.id)
	var installed := ProgressionSystem.is_installed(st, c.id)
	var missing := ProgressionSystem.missing(st, c)
	var card := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.045), AstraStyle.RADIUS_SM + 4, 14, 12, AstraStyle.LINE), id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	card.add_child(row)
	var icon := AstraStyle.panel(AstraStyle.pill(Color(AstraStyle.C_POWER, 0.14), 10, 10, 6), "Icon")
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.add_child(AstraStyle.label(String(ICONS.get(id, "⚡")), 20, AstraStyle.C_POWER, "", true))
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(AstraStyle.label(String(NAMES.get(id, c.title)), 16, AstraStyle.TEXT, "Name"))
	var what := AstraStyle.label(c.effect, 13, AstraStyle.TEXT_2, "Effect")
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(what)
	var catch := AstraStyle.label(String(CATCHES.get(id, "")), 13, AstraStyle.ACCENT, "Catch")
	catch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catch.visible = catch.text != ""
	col.add_child(catch)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", 6)
	col.add_child(chips)
	chips.add_child(_chip("⚙ %d" % c.cost_parts, AstraStyle.C_PARTS))
	chips.add_child(_chip("Energy level %d" % c.tier, AstraStyle.TEXT_2))
	chips.add_child(_chip(String(StationPanels.SPECIALTY_SYMBOLS.get(c.specialty, "●")) + " installs", AstraStyle.C_POWER))
	if installed:
		col.add_child(AstraStyle.label("✓ Built and working", 14, AstraStyle.GOOD, "Status"))
		return card
	for r: Dictionary in missing:
		var l := AstraStyle.label("✖ " + String(r.text), 12, AstraStyle.TEXT_3, "Missing")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 10)
	col.add_child(actions)
	var b := AstraStyle.primary_button("⚒ Build")
	b.name = "Build_%s" % id
	var right_person := me != null and (c.specialty == &"" or me.specialty == c.specialty)
	b.disabled = not missing.is_empty() or not right_person
	b.pressed.connect(_on_build.bind(id))
	actions.add_child(b)
	build_buttons[id] = b
	var why := ""
	if not missing.is_empty():
		why = "Locked: %d thing%s still needed" % [missing.size(), "" if missing.size() == 1 else "s"]
	elif not right_person:
		why = "Needs the %s" % ProgressionSystem.installer_words(c)
	else:
		why = "Ready to build here"
	actions.add_child(AstraStyle.label(why, 12, AstraStyle.GOOD if why == "Ready to build here" else AstraStyle.TEXT_3, "Why"))
	return card


func _chip(text: String, color: Color) -> Control:
	var p := AstraStyle.panel(AstraStyle.pill(Color(1, 1, 1, 0.06), 999, 8, 2, AstraStyle.LINE), "Chip")
	p.add_child(AstraStyle.label(text, 11, color, "", true))
	return p


func _on_build(upgrade_id: String) -> void:
	var r := services.request(&"install_upgrade", tracker_id, {"upgrade_id": upgrade_id})
	if r.pending:
		_message.text = "Asking the host…"
		services.events.action_resolved.connect(_on_answer, CONNECT_ONE_SHOT)
		return
	_on_answer(r)


func _on_answer(r: ActionResult) -> void:
	if r.ok:
		_message.text = String(r.changes.get("text", "Built."))
		AstraStyle.set_color(_message, AstraStyle.GOOD)
	else:
		_message.text = r.message
		AstraStyle.set_color(_message, AstraStyle.WARN)
	_sig = ""
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"build"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
