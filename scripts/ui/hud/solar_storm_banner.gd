extends PanelContainer
## Solar storm banner (upgrade paths plan §5.2 and §10): hidden while calm. After Mission Control's warning it says
## "☢ SOLAR STORM in 0:42 · Go to the shelter (Med Bay)" with a real-time countdown; during the storm "☢ Solar storm ·
## 1.3 sols left · Stay in the shelter (Med Bay)", and whether YOUR crewmate is sheltered now (and how much of the
## storm gets through where they stand). Read only: state.radiation (scripts/survival/radiation_system.gd).
## Never takes the mouse. Loaded by path:
##     var banner := preload("res://scripts/ui/hud/solar_storm_banner.gd").new()
##     banner.services = services
##     add_child(banner)        # it centres itself near the top (auto_place) unless the HUD lays it out

const RadiationSystem := preload("res://scripts/survival/radiation_system.gd")
const REFRESH_SECONDS := 0.2
const C_RADIATION := Color(0.98, 0.84, 0.25)

var services: GameServices
## True: the banner centres itself at the top of the screen, TOP_SHARE of the height down.
var auto_place := true
const TOP_SHARE := 0.11

var _title: Label
var _where: Label
var _you: Label
var _left := 0.0


func _init() -> void:
	name = "SolarStormBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	add_theme_stylebox_override(&"panel", AstraStyle.glass(AstraStyle.RADIUS, 18, 10, true))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(AstraStyle.label("☢", 24, C_RADIATION, "Symbol", true))
	_title = AstraStyle.label("", 20, AstraStyle.TEXT, "Title")
	row.add_child(_title)
	_where = AstraStyle.label("", 16, C_RADIATION, "Where")
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_where)
	_you = AstraStyle.label("", 13, AstraStyle.TEXT_2, "You")
	_you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_you)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_SECONDS
		refresh()
	if visible and auto_place:
		var screen := get_viewport_rect().size
		size = get_combined_minimum_size()
		position = Vector2(roundf((screen.x - size.x) * 0.5), roundf(screen.y * TOP_SHARE))


func refresh() -> void:
	if services == null or not services.has_game():
		visible = false
		return
	var st := services.state()
	var now := RadiationSystem.storm_now(st)
	var phase := String(now.phase)
	visible = phase != "calm"
	if not visible:
		return
	var hours := float(now.hours)
	var shelter := RadiationSystem.shelter_words(st)
	if phase == "warned":
		var hps := services.clock().hours_per_real_second() if services.clock() != null else 1.0
		var seconds := hours / maxf(hps, 1e-9)
		_title.text = "SOLAR STORM in %s" % _clock(seconds)
		AstraStyle.set_color(_title, AstraStyle.DANGER)
		_where.text = shelter
	else:
		var left := "%.1f sols left" % (hours / GameConfig.SOL_HOURS) if hours >= GameConfig.SOL_HOURS else "%d h left" % maxi(1, ceili(hours))
		_title.text = "Solar storm · %s" % left
		AstraStyle.set_color(_title, AstraStyle.WARN if bool(now.faded) else AstraStyle.DANGER)
		if bool(now.faded):
			_where.text = "The worst is over. Short trips are OK; stay in for the rest if you can."
		else:
			_where.text = shelter.replace("Go to", "Stay in") if RadiationSystem.has_shelter(st) else shelter
	_you.text = _you_words(st)
	_you.visible = _you.text != ""


## Where your crewmate is and how much of the storm reaches them there.
func _you_words(st: ColonyState) -> String:
	var me := services.local_character()
	if me == null:
		return ""
	var crew: Dictionary = st.radiation.get("crew", {}) if st.radiation.get("crew") is Dictionary else {}
	var place := String((crew.get(String(me.id), {}) as Dictionary).get("place", "inside"))
	var through := roundi(RadiationSystem.storm_factor(st, place) * 100.0)
	match place:
		"outside":
			return "You are OUTSIDE: the whole storm reaches you. Come in now!"
		"rover":
			return "You are in the sealed rover cabin: about %d %% of the storm gets through." % through
		"shelter":
			if RadiationSystem.has_shelter(st):
				return "You are in the shelter: about %d %% of the storm gets through." % through
	return "You are inside, not in the shelter: about %d %% of the storm gets through." % through


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [floori(s / 60.0), s % 60]
