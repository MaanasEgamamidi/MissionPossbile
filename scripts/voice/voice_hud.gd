class_name VoiceHud
extends PanelContainer
## The voice corner of the HUD (Prompt 11), bottom right, clear of the colony corner (top left), your crew card (top
## right), the messages and hints (bottom centre), the session status (bottom left) and the crosshair (centre).
## Shown as a small microphone icon, one look per state:
##   white mic            voice chat on, nobody hears you right now (idle)
##   green mic + waves    you are speaking (being sent)
##   grey mic, slashed    voice chat off (V not pressed yet, or the microphone muted in the voice settings)
##   mic + amber "!"      on, but something is wrong (silent microphone, no radio link, no signal)
##   mic + red "×"        no microphone on this computer — you can still listen
## A speaker icon with a number appears beside it while you hear other players (or radio messages are on the way).
## A one-line caption shows for a few seconds whenever the state changes (and while an outside/inside note is
## active), so the state is readable while the mouse is captured; hovering the corner shows the full description
## (what your voice does, who you hear, the V key).
## VoiceService adds it under GameHud, so it hides with the HUD while a panel is open.

## Distance from the screen edges, pixels (the HUD's own margin).
const EDGE := 24
## Icon size, pixels at UI scale 1.
const ICON := 30.0
## Widest the caption gets before it wraps, pixels at UI scale 1.
const CAPTION_WIDTH := 220.0
## Seconds the caption stays after a state change.
const CAPTION_S := 4.0
## Most "heard" lines listed in the hover description.
const MAX_LINES := 4

const STATE_ON := &"on"
const STATE_SPEAKING := &"speaking"
const STATE_OFF := &"off"
const STATE_WARN := &"warn"
const STATE_NO_MIC := &"no_mic"

var voice: VoiceService

var _row: HBoxContainer
var _mic: _MicIcon
var _caption: Label
var _heard_icon: _SpeakerIcon
var _heard_count: Label
var _own_text := ""
var _note_text := ""
var _heard_text := ""
var _state := STATE_OFF
var _caption_key := ""
var _caption_until := 0.0
var _clock := 0.0
var _timer := 0.0
var _last := ""
var _place_left := 0


func setup(p_voice: VoiceService) -> void:
	voice = p_voice
	name = "VoiceHud"
	theme = UiTheme.get_theme()
	theme_type_variation = UiTheme.HUD_PANEL
	# PASS (not STOP): hovering shows the description, clicks still reach the game.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", 8)
	add_child(_row)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.visible = false
	_row.add_child(_caption)
	_heard_icon = _SpeakerIcon.new()
	_heard_icon.name = "HeardIcon"
	_heard_icon.visible = false
	_row.add_child(_heard_icon)
	_heard_count = Label.new()
	_heard_count.name = "HeardCount"
	_heard_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heard_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heard_count.theme_type_variation = UiTheme.GOOD
	_heard_count.visible = false
	_row.add_child(_heard_count)
	_mic = _MicIcon.new()
	_mic.name = "MicIcon"
	_row.add_child(_mic)
	_place()
	refresh()


## The lines behind the icon (tests read them; the hover description shows them).
func own_text() -> String:
	return _own_text


func note_text() -> String:
	return _note_text


func heard_text() -> String:
	return _heard_text


## The icon's state now: on, speaking, off, warn or no_mic.
func state() -> StringName:
	return _state


## The caption under the mouse-free view ("" when hidden).
func caption_text() -> String:
	return _caption.text if _caption != null and _caption.visible else ""


func _process(delta: float) -> void:
	_clock += delta
	if _mic != null:
		_mic.clock = _clock
		if _state == STATE_SPEAKING:
			_mic.queue_redraw()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	refresh()


func refresh() -> void:
	if voice == null or not is_instance_valid(voice) or _mic == null:
		return
	var key := _key_label()
	_own_text = voice.own_line()
	_note_text = voice.transition_line()
	var lines := voice.heard_lines()
	var heard_n := lines.size()
	if lines.size() > MAX_LINES:
		lines = lines.slice(0, MAX_LINES)
	_heard_text = "\n".join(lines)

	_state = _state_now()
	_mic.state = _state
	_mic.scale_ui = UiTheme.text_scale()
	_mic.update_minimum_size()
	_mic.queue_redraw()

	# Caption: a short name for the state, for a few seconds after it changes (speaking and idle count as one, so
	# talking does not flash it); an outside/inside note shows for as long as the note lasts.
	var key_state := String(STATE_ON if _state == STATE_SPEAKING else _state)
	if key_state != _caption_key:
		_caption_key = key_state
		_caption_until = _clock + CAPTION_S
	var caption := _note_text if _note_text != "" else (_short_label(_state, key) if _clock < _caption_until else "")
	_caption.text = caption
	_caption.visible = caption != ""
	_caption.theme_type_variation = _caption_variation(_state)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if caption.length() > 28 else TextServer.AUTOWRAP_OFF
	_caption.custom_minimum_size.x = CAPTION_WIDTH * UiTheme.text_scale() if caption.length() > 28 else 0.0

	_heard_icon.visible = heard_n > 0
	_heard_icon.scale_ui = UiTheme.text_scale()
	_heard_icon.update_minimum_size()
	_heard_count.visible = heard_n > 1
	_heard_count.text = str(heard_n)

	tooltip_text = _describe(_state, key)

	var sig := "%s|%s|%s|%s|%s" % [_state, caption, heard_n, UiTheme.text_scale(), get_viewport_rect().size if is_inside_tree() else Vector2.ZERO]
	_place_left -= 1
	if sig != _last or _place_left <= 0:
		_last = sig
		_place_left = 10         # once a second anyway: the hint strip below can change size
		_place()


func _state_now() -> StringName:
	if voice.mic_muted():
		return STATE_OFF
	if not voice.can_capture():
		return STATE_NO_MIC
	if not voice.is_voice_on():
		return STATE_OFF
	if _own_text.begins_with("✖"):
		return STATE_WARN
	if voice.is_transmitting():
		return STATE_SPEAKING
	return STATE_ON


func _short_label(s: StringName, key: String) -> String:
	match s:
		STATE_OFF:
			return "Mic muted" if voice.mic_muted() else "Mic off · %s" % key
		STATE_NO_MIC:
			return "No microphone"
		STATE_WARN:
			return _own_text.trim_prefix("✖").strip_edges()
		_:
			return "Mic on · %s" % key


func _caption_variation(s: StringName) -> StringName:
	match s:
		STATE_OFF:
			return UiTheme.MUTED
		STATE_WARN, STATE_NO_MIC:
			return UiTheme.WARN
		_:
			return UiTheme.GOOD


func _describe(s: StringName, key: String) -> String:
	var title := ""
	match s:
		STATE_OFF:
			if voice.mic_muted():
				title = "Microphone muted (voice settings) — others cannot hear you; you can still hear them."
			else:
				title = "Voice chat OFF — others cannot hear you; you can still hear them."
		STATE_NO_MIC:
			title = "No microphone — you can still listen."
		STATE_WARN:
			title = "Voice chat ON — but there is a problem:"
		STATE_SPEAKING:
			title = "Voice chat ON — you are speaking."
		_:
			title = "Voice chat ON — people near you hear you when you talk."
	var parts := PackedStringArray([title])
	if s != STATE_NO_MIC and not voice.mic_muted() and _own_text != "":
		parts.append(_own_text)
	if _note_text != "":
		parts.append(_note_text)
	if _heard_text != "":
		parts.append("Hearing:\n" + _heard_text)
	if not voice.mic_muted() and s != STATE_NO_MIC:
		parts.append("Press %s to turn voice chat %s." % [key, "on" if s == STATE_OFF else "off"])
	return "\n".join(parts)


## The key that turns voice chat on and off (V by default).
func _key_label() -> String:
	var label := PlayerInput.describe(&"push_to_talk") if InputMap.has_action(&"push_to_talk") else ""
	return label if label != "" else "V"


## Keeps the box in the bottom-right corner at its content's size, above the HUD's bottom strip (hints, status)
## wherever that strip reaches across.
func _place() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, EDGE)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	if not is_inside_tree():
		return
	var mine := get_global_rect()
	var limit := mine.end.y
	for strip: Control in _bottom_strip():
		if strip.is_visible_in_tree():
			var r := strip.get_global_rect()
			if r.position.x < mine.end.x and r.end.x > mine.position.x and r.end.y > mine.position.y:
				limit = minf(limit, r.position.y - 8.0)
	var shift := limit - mine.end.y
	if shift < 0.0:
		offset_top += shift
		offset_bottom += shift


var _strip: Array[Control] = []


## The HUD's bottom-edge boxes (GameHud names them "Hints" and "Status").
func _bottom_strip() -> Array[Control]:
	if _strip.is_empty() and get_parent() != null:
		for n: String in ["Hints", "Status"]:
			var c := get_parent().find_child(n, true, false) as Control
			if c != null and c != self:
				_strip.append(c)
	return _strip


## The microphone glyph, drawn (no font or emoji needed), one look per state.
class _MicIcon extends Control:
	var state := &"off"
	var scale_ui := 1.0
	var clock := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(ICON, ICON) * scale_ui

	func _draw() -> void:
		var p := UiTheme.palette()
		var s := ICON * scale_ui
		var c := Vector2(s * 0.5, s * 0.5)
		var col: Color = p.text
		match state:
			&"speaking":
				col = p.good
			&"off":
				col = Color(p.muted, 0.6)
			&"no_mic":
				col = Color(p.muted, 0.8)
		var w := maxf(1.5, s * 0.075)
		# capsule
		var cap_w := s * 0.30
		var cap_top := s * 0.10
		var cap_bot := s * 0.52
		var r := cap_w * 0.5
		draw_circle(Vector2(c.x, cap_top + r), r, col)
		draw_circle(Vector2(c.x, cap_bot - r), r, col)
		draw_rect(Rect2(c.x - r, cap_top + r, cap_w, cap_bot - cap_top - cap_w), col)
		# holder, stem, base
		var hold_c := Vector2(c.x, s * 0.42)
		draw_arc(hold_c, s * 0.25, 0.0, PI, 20, col, w, true)
		draw_line(Vector2(c.x, hold_c.y + s * 0.25), Vector2(c.x, s * 0.82), col, w, true)
		draw_line(Vector2(c.x - s * 0.16, s * 0.84), Vector2(c.x + s * 0.16, s * 0.84), col, w, true)
		match state:
			&"speaking":
				var pulse := 0.55 + 0.45 * sin(clock * 6.0)
				for i in 2:
					var rad := s * (0.40 + 0.12 * i)
					var a := Color(col, (1.0 - 0.35 * i) * pulse)
					draw_arc(Vector2(c.x, s * 0.31), rad, -PI * 0.22, PI * 0.22, 10, a, w, true)
					draw_arc(Vector2(c.x, s * 0.31), rad, PI - PI * 0.22, PI + PI * 0.22, 10, a, w, true)
			&"off":
				var bg: Color = p.hud
				var a := Vector2(s * 0.12, s * 0.10)
				var b := Vector2(s * 0.88, s * 0.90)
				draw_line(a, b, Color(bg, 1.0), w * 2.6, true)
				draw_line(a, b, p.urgent, w * 1.2, true)
			&"warn":
				_badge(p.warn, s, w, true)
			&"no_mic":
				_badge(p.urgent, s, w, false)

	## Small round badge, bottom right: "!" (warning) or "×" (no microphone).
	func _badge(fill: Color, s: float, w: float, bang: bool) -> void:
		var bc := Vector2(s * 0.80, s * 0.78)
		var br := s * 0.20
		draw_circle(bc, br + w * 0.7, Color(UiTheme.palette().hud, 1.0))
		draw_circle(bc, br, fill)
		var ink := Color(0.06, 0.06, 0.06)
		if bang:
			draw_line(bc + Vector2(0, -br * 0.55), bc + Vector2(0, br * 0.15), ink, w, true)
			draw_circle(bc + Vector2(0, br * 0.50), w * 0.6, ink)
		else:
			var d := br * 0.45
			draw_line(bc + Vector2(-d, -d), bc + Vector2(d, d), ink, w, true)
			draw_line(bc + Vector2(-d, d), bc + Vector2(d, -d), ink, w, true)


## Speaker glyph shown while you hear someone.
class _SpeakerIcon extends Control:
	var scale_ui := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(ICON * 0.8, ICON) * scale_ui

	func _draw() -> void:
		var p := UiTheme.palette()
		var s := ICON * scale_ui
		var col: Color = p.good
		var w := maxf(1.5, s * 0.07)
		var y := s * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(s * 0.05, y - s * 0.10), Vector2(s * 0.20, y - s * 0.10), Vector2(s * 0.40, y - s * 0.26),
			Vector2(s * 0.40, y + s * 0.26), Vector2(s * 0.20, y + s * 0.10), Vector2(s * 0.05, y + s * 0.10)]), col)
		draw_arc(Vector2(s * 0.40, y), s * 0.14, -PI * 0.3, PI * 0.3, 8, col, w, true)
		draw_arc(Vector2(s * 0.40, y), s * 0.28, -PI * 0.3, PI * 0.3, 10, col, w, true)
