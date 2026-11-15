class_name SurvivalHud
extends CanvasLayer
## Fatal-exposure presentation only. The host decides danger, safety and recovery.
## A stale countdown can reach zero visually, but can never kill, recover or clear an astronaut.

signal warning_changed(active: bool)
signal alarm_started

const OVERLAY_LAYER := 60
const STATIC_BACKGROUND := Color("851b0f")
const STATIC_BORDER := Color("ffb047")

var services: GameServices
var settings: GameSettings
var ui: UiRoot
var active := false
var remaining_seconds := 0.0
var authoritative_status: Dictionary = {}
var alarm_count := 0
var screen: Control
var banner: PanelContainer
var cause_label: Label
var countdown_label: Label
var protection_label: Label
var action_label: Label
var border: Control
var alarm: AudioStreamPlayer

var _edge_style: StyleBoxFlat
var _banner_style: StyleBoxFlat
var _actor_id: StringName = &""
var _sample_remaining := -1.0
var _sample_age := 0.0
var _pulse_seconds := 0.0
var _host_sample_frame := -1


func _init() -> void:
	name = "SurvivalHud"
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen = Control.new()
	screen.name = "ExposureOverlay"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = UiTheme.get_theme()
	add_child(screen)
	border = Panel.new()
	border.name = "DangerBorder"
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge_style = StyleBoxFlat.new()
	_edge_style.bg_color = Color.TRANSPARENT
	_edge_style.set_border_width_all(4)
	(border as Panel).add_theme_stylebox_override(&"panel", _edge_style)
	screen.add_child(border)
	banner = PanelContainer.new()
	banner.name = "FatalExposureWarning"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_style = StyleBoxFlat.new()
	_banner_style.set_border_width_all(3)
	_banner_style.content_margin_left = 10.0
	_banner_style.content_margin_right = 10.0
	_banner_style.content_margin_top = 6.0
	_banner_style.content_margin_bottom = 6.0
	banner.add_theme_stylebox_override(&"panel", _banner_style)
	screen.add_child(banner)
	var body := VBoxContainer.new()
	body.name = "Message"
	body.add_theme_constant_override(&"separation", 2)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(body)
	var first := HBoxContainer.new()
	first.name = "CauseAndCountdown"
	first.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(first)
	cause_label = _label("Cause")
	cause_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.add_child(cause_label)
	countdown_label = _label("Countdown")
	countdown_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	first.add_child(countdown_label)
	protection_label = _label("ProtectionAndArea")
	body.add_child(protection_label)
	action_label = _label("EscapeAction")
	body.add_child(action_label)
	alarm = AudioStreamPlayer.new()
	alarm.name = "ExposureAlarm"
	alarm.bus = &"Master"
	alarm.stream = _alarm_stream()
	add_child(alarm)
	screen.visible = false
	_apply_palette()


func setup(p_services: GameServices, p_settings: GameSettings, p_ui: UiRoot = null) -> void:
	services = p_services
	settings = p_settings if p_settings != null else GameSettings.new()
	ui = p_ui
	if not services.events.state_changed.is_connected(_on_authoritative_change):
		services.events.state_changed.connect(_on_authoritative_change)
		services.events.character_recovered.connect(_on_recovered)
	if not settings.changed.is_connected(_on_settings_changed):
		settings.changed.connect(_on_settings_changed)
	refresh_from_host()


## Read only the local peer's host-owned status. Other astronauts' danger never changes this overlay.
func refresh_from_host() -> void:
	if services == null or not services.has_game():
		_set_inactive()
		return
	var actor := services.local_character()
	if actor == null:
		_set_inactive()
		return
	var status: Dictionary = services.session.survival.status(actor.id)
	var changed_actor := _actor_id != actor.id
	_actor_id = actor.id
	authoritative_status = status.duplicate(true)
	if not bool(status.get("active", false)):
		_set_inactive()
		return
	var host_remaining := maxf(0.0, float(status.get("remaining_seconds", 0.0)))
	if changed_actor or not is_equal_approx(host_remaining, _sample_remaining):
		_sample_remaining = host_remaining
		_sample_age = 0.0
		_host_sample_frame = Engine.get_process_frames()
	var just_started := not active or changed_actor
	active = true
	screen.visible = true
	_update_words()
	if just_started:
		_pulse_seconds = 0.0
		if ui != null:
			ui.interrupt_critical_panels(cause_label.text)
		_play_alarm()
		warning_changed.emit(true)
	_draw_countdown()
	_layout_banner()


func _process(delta: float) -> void:
	refresh_from_host()
	if not active:
		return
	if not services.session.paused and Engine.get_process_frames() > _host_sample_frame:
		_sample_age += delta
		_pulse_seconds += delta
	_draw_countdown()
	var static_mode := settings == null or settings.reduce_flashes or settings.reduce_motion
	border.modulate.a = 1.0 if static_mode else 0.88 + 0.12 * sin(_pulse_seconds * TAU * 0.6)
	_layout_banner()


func _draw_countdown() -> void:
	remaining_seconds = maxf(0.0, _sample_remaining - _sample_age)
	countdown_label.text = "RECOVERY %.1f s" % remaining_seconds


func _update_words() -> void:
	var cause := String(authoritative_status.get("cause", "No breathable air"))
	var area := String(authoritative_status.get("area", "Affected area"))
	var low_cause := cause.to_lower()
	var airlock := "airlock" in area.to_lower() or "airlock" in low_cause
	var empty_suit := "reserve" in low_cause or "tank" in low_cause or ("suit" in low_cause and "empty" in low_cause)
	var failed_suit := "suit" in low_cause and "seal" in low_cause
	if empty_suit:
		cause_label.text = "! SUIT OXYGEN EMPTY"
	elif failed_suit:
		cause_label.text = "! SUIT SEAL FAILED"
	elif "pressure" in low_cause or airlock:
		cause_label.text = "! PRESSURE FAILURE"
	elif "cabin" in low_cause:
		cause_label.text = "! CABIN AIR UNSAFE"
	else:
		cause_label.text = "! NO BREATHABLE AIR"
	protection_label.text = ("REACH SAFE PRESSURE - " if empty_suit or failed_suit else "SUIT REQUIRED - ") + area
	if airlock:
		action_label.text = "Retreat through inner door. Field engineer repairs from safety."
	else:
		action_label.text = "Reach safe air or equip a charged suit."


func _layout_banner() -> void:
	if not is_inside_tree():
		return
	var canvas := get_viewport().get_visible_rect().size
	banner.position = Vector2(8.0, 8.0)
	banner.size = Vector2(maxf(100.0, canvas.x - 16.0), banner.get_combined_minimum_size().y)


func _set_inactive() -> void:
	var was_active := active
	active = false
	screen.visible = false
	remaining_seconds = 0.0
	_sample_remaining = -1.0
	_sample_age = 0.0
	alarm.stop()
	if was_active:
		warning_changed.emit(false)


func _play_alarm() -> void:
	if settings == null or settings.warning_sound_muted or settings.warning_sound_volume <= 0.0:
		return
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0 and AudioServer.is_bus_mute(master):
		return
	alarm.volume_db = linear_to_db(settings.warning_sound_volume)
	alarm.play()
	alarm_count += 1
	alarm_started.emit()


func _on_settings_changed() -> void:
	_apply_palette()
	if settings.warning_sound_muted or settings.warning_sound_volume <= 0.0:
		alarm.stop()
	else:
		alarm.volume_db = linear_to_db(settings.warning_sound_volume)


func _apply_palette() -> void:
	var contrast := settings != null and settings.high_contrast
	_banner_style.bg_color = Color.BLACK if contrast else STATIC_BACKGROUND
	_banner_style.border_color = Color.YELLOW if contrast else STATIC_BORDER
	_edge_style.border_color = _banner_style.border_color
	for label: Label in [cause_label, countdown_label, protection_label, action_label]:
		label.add_theme_color_override(&"font_color", Color.WHITE if contrast else UiTheme.palette().text)


func _on_authoritative_change(_reason: StringName) -> void:
	refresh_from_host()


func _on_recovered(id: StringName, _info: Dictionary) -> void:
	if id == _actor_id:
		# Recovery is an authoritative event. The next snapshot may show a new hazard, which reopens normally.
		_set_inactive()


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _alarm_stream() -> AudioStreamWAV:
	# Original 0.34-second two-tone chime, generated locally. It contains no speech or external asset.
	const RATE := 22050
	const SECONDS := 0.34
	var samples := int(RATE * SECONDS)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var seconds := float(i) / RATE
		var tone := 740.0 if seconds < 0.17 else 980.0
		var envelope := minf(seconds * 80.0, 1.0) * minf((SECONDS - seconds) * 35.0, 1.0)
		data.encode_s16(i * 2, int(sin(seconds * tone * TAU) * envelope * 11000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
