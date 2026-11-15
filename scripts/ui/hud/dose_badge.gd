extends VBoxContainer
## Radiation dose badge for the crew box (upgrade paths plan §5.2): "☢ 123 mSv" with a small bar to NASA's 600 mSv
## limit, coloured by band (green < 400, amber 400-500, orange 500-600, red at the limit), and one line when the
## crewmate is in isolation ("In isolation · 31 h left · swap crewmate (C)") or indoor-only. Your own crewmate by
## default; set `character_id` to show someone else. Read only: it reads CharacterState.dose_msv / isolation and
## state.radiation.crew (scripts/survival/radiation_system.gd) and never changes state. Loaded by path:
##     var badge := preload("res://scripts/ui/hud/dose_badge.gd").new()
##     badge.services = services
##     _crew_box.add_child(badge)

const RadiationSystem := preload("res://scripts/survival/radiation_system.gd")
const REFRESH_SECONDS := 0.25
const C_RADIATION := Color(0.98, 0.84, 0.25)

var services: GameServices
## Crewmate to show; &"" = the one this machine plays.
var character_id: StringName = &""

var _value: Label
var _rate: Label
var _bar: AstraStyle.Meter
var _note: Label
var _left := 0.0


func _init() -> void:
	name = "DoseBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(AstraStyle.label("☢", 14, C_RADIATION, "Symbol", true))
	row.add_child(AstraStyle.label("Dose", 12, AstraStyle.TEXT_3, "Word"))
	_value = AstraStyle.label("0 mSv", 13, AstraStyle.TEXT, "Value")
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_value)
	_rate = AstraStyle.label("", 11, AstraStyle.TEXT_3, "Rate")
	row.add_child(_rate)
	_bar = AstraStyle.Meter.new(AstraStyle.GOOD, 4.0)
	_bar.name = "Bar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_bar)
	_note = AstraStyle.label("", 12, AstraStyle.WARN, "Note")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	add_child(_note)


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH_SECONDS
	refresh()


func refresh() -> void:
	var c := _actor()
	visible = c != null
	if c == null:
		return
	var dose := c.dose_msv
	_value.text = "%d mSv of %d" % [roundi(dose), roundi(RadiationSystem.LIMIT_MSV)]
	var color := band_color(RadiationSystem.band(dose))
	AstraStyle.set_color(_value, color if dose >= RadiationSystem.WARN_MSV[0] else AstraStyle.TEXT)
	_bar.color = color
	_bar.share = dose / RadiationSystem.LIMIT_MSV
	var st := services.state()
	var rec: Dictionary = (st.radiation.get("crew", {}) as Dictionary).get(String(c.id), {}) if st.radiation.get("crew") is Dictionary else {}
	var rate := float(rec.get("rate_msv_h", 0.0))
	_rate.text = "+%.1f/h" % rate if rate > 0.0 else ""
	AstraStyle.set_color(_rate, AstraStyle.DANGER if rate > 3.0 * RadiationSystem.background_rate(st, "outside") else AstraStyle.TEXT_3)
	var note := ""
	if RadiationSystem.is_isolated(c):
		note = "✚ In isolation · %d h left · swap crewmate (C)" % ceili(RadiationSystem.isolation_hours_left(st, c))
		AstraStyle.set_color(_note, AstraStyle.DANGER)
	elif RadiationSystem.indoor_only(c):
		note = "Indoor work only (dose limit reached)"
		AstraStyle.set_color(_note, AstraStyle.WARN)
	elif dose >= RadiationSystem.WARN_MSV[0]:
		note = "High dose: stay inside when you can"
		AstraStyle.set_color(_note, AstraStyle.WARN)
	_note.text = note
	_note.visible = note != ""


## Colour of a dose band (RadiationSystem.band): always shown with the number, never alone.
static func band_color(b: String) -> Color:
	match b:
		"warn":
			return AstraStyle.WARN
		"high":
			return AstraStyle.ACCENT
		"limit":
			return AstraStyle.DANGER
	return AstraStyle.GOOD


func _actor() -> CharacterState:
	if services == null or not services.has_game():
		return null
	if character_id != &"":
		return services.state().character(character_id)
	return services.local_character()
