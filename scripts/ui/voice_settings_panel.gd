class_name VoiceSettingsPanel
extends UiPanel
## Voice and microphone settings (Prompt 11), opened from Settings > Controls > "Voice and microphone…".
## Microphone state in words, the input device list, an input level meter (the microphone opens while this panel is
## open; voice chat is always on, so in a game it is sent all the time), mute my microphone, the volume of everyone's
## voices, and for each other
## player a volume slider and a mute switch (for this session). Then how voice works: nearby inside, radio outside,
## the radio's stage and why it is slow. The microphone, mute and volume are saved with the other settings; per-player
## volume and mute last for the session only (there are no player accounts).

## The settings being edited (SettingsPanel passes its own).
var settings: GameSettings
var settings_path := GameSettings.DEFAULT_PATH
## The running voice service; found in the tree when not set. Without one (main menu) only the saved settings change.
var voice: VoiceService

var _status: Label
var _device: OptionButton
var _meter: ProgressBar
var _meter_label: Label
var _mute_mic: CheckButton
var _volume: HSlider
var _volume_label: Label
var _players_box: VBoxContainer
var _players_note: Label
var _player_rows := {}             # peer -> {"label", "slider", "mute"}
var _players_sig := ""
var _stage_label: Label
var _metering: VoiceService
var _device_name := ""
var _device_refresh_at := 0


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	if settings == null:
		settings = GameSettings.new()
	name = "VoiceSettingsPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_type_variation = UiTheme.PANEL
	_build()
	_read_settings()


func panel_title() -> String:
	return "Voice and microphone"


## The microphone list (tests).
func device_button() -> OptionButton:
	return _device


## The mute-my-microphone switch (tests).
func mute_button() -> CheckButton:
	return _mute_mic


## The row of controls for one other player: {"label", "slider", "mute"} or {} (tests).
func player_row(peer: int) -> Dictionary:
	return _player_rows.get(peer, {})


func status_text() -> String:
	return _status.text if _status != null else ""


func meter_value() -> float:
	return _meter.value if _meter != null else 0.0


func _voice() -> VoiceService:
	if voice != null and is_instance_valid(voice):
		return voice
	return VoiceService.find(get_tree()) if is_inside_tree() else null


func _enter_tree() -> void:
	_set_metering(true)


func _exit_tree() -> void:
	_set_metering(false)
	if settings != null and settings_path != "":
		settings.save(settings_path)


func _set_metering(on: bool) -> void:
	if on and _metering == null:
		var v := _voice()
		if v != null:
			v.request_meter(true)
			_metering = v
	elif not on and _metering != null:
		if is_instance_valid(_metering):
			_metering.request_meter(false)
		_metering = null


func _process(_delta: float) -> void:
	if _meter == null:
		return
	if _metering == null:
		_set_metering(true)
	var v := _voice()
	# A perceptual scale makes ordinary speech visible without changing the transmitted audio gain.
	_meter.value = (sqrt(v.input_level()) * 100.0) if v != null else 0.0


func refresh() -> void:
	if _status == null:
		return
	var v := _voice()
	_refresh_device()
	if v != null:
		_status.text = v.mic_state_text()
	elif settings.voice_mic_muted:
		_status.text = "✖ Your microphone is muted. Others cannot hear you; you can still hear them."
	else:
		_status.text = "Voice uses the built-in microphone automatically when you enter a colony."
	_status.theme_type_variation = UiTheme.WARN if _status.text.begins_with("✖") or _status.text.begins_with("⚠") else UiTheme.GOOD
	var st := services.state() if services != null and services.has_game() else null
	# Suit radio (2026-11-15): the comms level decides no signal / delay / garble (scripts/voice/suit_radio.gd).
	var suit_radio: Variant = load("res://scripts/voice/suit_radio.gd")
	_stage_label.text = String(suit_radio.status_text(st)) if st != null else CommsStage.stage_text(0) + " (in a colony, this shows its radio.)"
	_refresh_players(v)


func _refresh_players(v: VoiceService) -> void:
	var rows: Array[Dictionary] = []
	if v != null:
		rows = v.player_rows()
	var sig := ""
	for r: Dictionary in rows:
		sig += "%d:%s;" % [int(r.peer), String(r.name)]
	if sig != _players_sig:
		_players_sig = sig
		for child in _players_box.get_children():
			_players_box.remove_child(child)
			child.queue_free()
		_player_rows.clear()
		for r: Dictionary in rows:
			_add_player_row(int(r.peer), String(r.name))
	_players_note.visible = rows.is_empty()
	for r: Dictionary in rows:
		var row: Dictionary = _player_rows.get(int(r.peer), {})
		if row.is_empty():
			continue
		(row.slider as HSlider).set_value_no_signal(float(r.volume))
		(row.mute as CheckButton).set_pressed_no_signal(bool(r.muted))
		(row.label as Label).text = "%s · %d %%%s" % [String(r.name), roundi(float(r.volume) * 100.0), " · muted" if bool(r.muted) else ""]


func _add_player_row(peer: int, player_name: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Player_%d" % peer
	_players_box.add_child(row)
	var label := Label.new()
	label.text = player_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = VoiceService.VOLUME_MAX
	slider.step = 0.05
	slider.custom_minimum_size.x = 160.0
	slider.tooltip_text = "How loud %s is for you." % player_name
	slider.value_changed.connect(func(value: float) -> void:
		var v := _voice()
		if v != null:
			v.set_player_volume(peer, value)
		refresh())
	row.add_child(slider)
	var mute := CheckButton.new()
	mute.text = "Mute"
	mute.tooltip_text = "Stop hearing %s (for this session)." % player_name
	mute.toggled.connect(func(on: bool) -> void:
		var v := _voice()
		if v != null:
			v.set_player_muted(peer, on)
		refresh())
	row.add_child(mute)
	_player_rows[peer] = {"label": label, "slider": slider, "mute": mute}


func _build() -> void:
	var outer := VBoxContainer.new()
	outer.name = "Outer"
	add_child(outer)
	var title := Label.new()
	title.text = "Voice and microphone"
	title.theme_type_variation = UiTheme.TITLE
	outer.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_status = _label(body, "")
	_label(body, "Built-in microphone (always used)")
	_device = OptionButton.new()
	_device.name = "Device"
	_device.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_device.tooltip_text = "Voice stays on this computer's built-in microphone, even when a headset is connected."
	_device.disabled = true
	body.add_child(_device)
	_meter_label = _label(body, "Input level: speak to see the bar move. Voice chat is always on: no key to hold.")
	_meter_label.theme_type_variation = UiTheme.MUTED
	_meter = ProgressBar.new()
	_meter.name = "Meter"
	_meter.min_value = 0.0
	_meter.max_value = 100.0
	_meter.show_percentage = false
	_meter.custom_minimum_size = Vector2(240.0, 14.0)
	_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_meter)
	var retry := Button.new()
	retry.text = "Retry built-in microphone"
	retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	retry.pressed.connect(func() -> void:
		var v := _voice()
		if v != null:
			v.retry_microphone()
		refresh())
	body.add_child(retry)
	_mute_mic = CheckButton.new()
	_mute_mic.name = "MuteMic"
	_mute_mic.text = "Mute my microphone"
	_mute_mic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_mute_mic.toggled.connect(func(on: bool) -> void:
		var v := _voice()
		if v != null:
			v.set_mic_muted(on)
		else:
			settings.voice_mic_muted = on
		refresh())
	body.add_child(_mute_mic)
	_volume_label = _label(body, "")
	_volume = HSlider.new()
	_volume.name = "Volume"
	_volume.min_value = 0.0
	_volume.max_value = VoiceService.VOLUME_MAX
	_volume.step = 0.05
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.value_changed.connect(func(value: float) -> void:
		settings.voice_volume = value
		_update_volume_label())
	body.add_child(_volume)

	var heading := _label(body, "Players")
	heading.theme_type_variation = UiTheme.HEADING
	_players_note = _label(body, "No other players are here. Their volume and mute switches appear when they join.")
	_players_note.theme_type_variation = UiTheme.MUTED
	_players_box = VBoxContainer.new()
	_players_box.name = "Players"
	body.add_child(_players_box)

	var how := _label(body, "How voice works")
	how.theme_type_variation = UiTheme.HEADING
	_label(body, "Voice chat is always on: just talk. Inside the base, people near you hear you at once: clearly up to 5 m, fading out by 25 m. "
		+ "Walls stop your voice; an open door lets some of it through.")
	_label(body, "If you or the listener is outside, your voice goes over the colony radio instead, to everyone on the map, "
		+ "inside too. Outside there is almost no air to carry sound, so suits use the radio.")
	_stage_label = _label(body, "")
	_stage_label.theme_type_variation = UiTheme.HEADING
	var why := _label(body, CommsStage.explanation())
	why.theme_type_variation = UiTheme.MUTED
	var privacy := _label(body, "Your voice only goes to the other players in this colony (mute your microphone above to stop it). "
		+ "It is never recorded or saved.")
	privacy.theme_type_variation = UiTheme.MUTED

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Done"
	close.theme_type_variation = UiTheme.PRIMARY_BUTTON
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: close_requested.emit())
	outer.add_child(close)


func _read_settings() -> void:
	_refresh_device()
	_mute_mic.set_pressed_no_signal(settings.voice_mic_muted)
	_volume.set_value_no_signal(settings.voice_volume)
	_update_volume_label()
	refresh()


func _refresh_device() -> void:
	var now := Time.get_ticks_msec()
	if _device_name != "" and now < _device_refresh_at:
		return
	_device_refresh_at = now + 5000
	var device := VoiceService.built_in_device(AudioServer.get_input_device_list())
	var label := device if device != "" else "Built-in microphone unavailable"
	if label == _device_name:
		return
	_device_name = label
	_device.clear()
	_device.add_item(label)
	_device.select(0)
	settings.voice_input_device = device


func _update_volume_label() -> void:
	_volume_label.text = "Voices volume (everyone): %d %%" % roundi(settings.voice_volume * 100.0)


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l
