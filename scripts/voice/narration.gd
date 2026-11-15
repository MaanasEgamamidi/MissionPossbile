extends RefCounted
## Voice-over for the game's own words (owner request 2026-11-15): "Throughout the game we pick up cassettes; currently
## the cassette is being played and the info is good; we just need a reader / voice-over on this." and "Also add a
## narrator speaking during the first cutscene before the player gets a chance to actually move."
##
## The voice is the computer's own text-to-speech voice (Godot's DisplayServer.tts_*; Windows SAPI/OneCore, macOS
## AVSpeech, Linux speech-dispatcher). There are NO audio files in the repo: the text on screen is read aloud as it is.
## It needs the project setting audio/general/text_to_speech=true. Where speech is not possible (a headless run, the
## setting off, or a computer with no voice installed) every call quietly does nothing and the words still show.
##
## Used by the cassette player panel (each tape page is read aloud) and the new-game intro cinematic (Mission Control's
## captions). Crew voice chat (voice_service.gd, comms_gate.gd) is a different thing and is not touched.
##
## One shared reader for the whole game (no class_name; preload by path):
##   const Narration := preload("res://scripts/voice/narration.gd")
##   var n := Narration.shared() as Narration
##   n.say("It is the 2060s.", &"narrator")   # stops whatever was being read, then reads this
##   n.is_speaking(&"narrator") / n.stop(&"cassette") / n.line_finished.connect(...)
## Only one line plays at a time: a new say() cuts the old one off. The player's GameSettings (bound by UiRoot.setup)
## give on/off (narrator_voice) and loudness (narrator_volume, 0..1, read as TTS volume 0..100).

## A line ended: `completed` is false when it was cut off (stop(), a new line, or the OS cancelled it).
signal line_finished(kind: StringName, completed: bool)

const SETTING := "audio/general/text_to_speech"
## Voices tried first, in order (Windows names; any part of the voice name). Then any en-US / en-GB voice, then any
## English voice, then the first voice the computer has.
const PREFERRED_VOICES: Array[String] = ["Zira", "Aria", "Jenny", "David", "Guy"]
## A little slower than normal speech, for players aged 9 to 12 (design choice).
const RATE := 0.95
const PITCH := 1.0
## Loudness when no settings are bound (0..100).
const DEFAULT_VOLUME := 90
## A line that the OS still reports as not speaking this long after say() is treated as finished (seconds).
const START_GRACE_S := 1.0

static var _shared: RefCounted

## The player's settings (UiRoot.setup binds the game's own). Null: voice on, DEFAULT_VOLUME.
var settings: GameSettings:
	set(v):
		if settings != null and settings.changed.is_connected(_on_settings_changed):
			settings.changed.disconnect(_on_settings_changed)
		settings = v
		if settings != null and not settings.changed.is_connected(_on_settings_changed):
			settings.changed.connect(_on_settings_changed)

var _checked := false
var _available := false
var _voice_id := ""
var _voice_name := ""
var _next_id := 1
var _current_id := 0
var _current_kind: StringName = &""
var _started_msec := 0
var _fallback_on := true


## The one reader every caller shares.
static func shared() -> RefCounted:
	if _shared == null:
		var script := load("res://scripts/voice/narration.gd") as GDScript
		_shared = script.new() as RefCounted
	return _shared


## Speech is possible on this computer (a window, the project setting on, at least one voice).
func available() -> bool:
	if not _checked:
		_checked = true
		_available = _detect()
	return _available


## The player wants the voice (settings.narrator_voice; on by default).
func voice_on() -> bool:
	return settings.narrator_voice if settings != null else _fallback_on


## Switches the voice on or off (the cassette panel's button). Off stops the line being read.
func set_voice_on(on: bool) -> void:
	if settings != null:
		settings.narrator_voice = on
	else:
		_fallback_on = on
	if not on:
		stop()


## The voice would be heard if say() were called now.
func can_speak() -> bool:
	return voice_on() and available()


## The name of the chosen OS voice ("" when there is none).
func voice_name() -> String:
	return _voice_name if available() else ""


## Reads `text` aloud as `kind` (&"narrator", &"cassette"...), cutting off any line still playing.
## Returns true when a line was started; false when the voice is off, unavailable or there is nothing to say.
func say(text: String, kind: StringName = &"narrator") -> bool:
	var spoken := clean(text)
	if spoken.is_empty() or not can_speak():
		stop()
		return false
	_cut_current()
	var id := _next_id
	_next_id += 1
	_current_id = id
	_current_kind = kind
	_started_msec = Time.get_ticks_msec()
	DisplayServer.tts_speak(spoken, _voice_id, _volume(), PITCH, RATE, id, true)
	return true


## Stops the line being read. With a `kind`, only a line of that kind is stopped (so one screen cannot silence another).
func stop(kind: StringName = &"") -> void:
	if _current_id == 0:
		return
	if kind != &"" and kind != _current_kind:
		return
	_cut_current()
	if available():
		DisplayServer.tts_stop()


## A line (of `kind`, or any) is still being read.
func is_speaking(kind: StringName = &"") -> bool:
	if _current_id == 0:
		return false
	if kind != &"" and kind != _current_kind:
		return false
	# Safety net in case the OS never sends "ended": once the OS says nothing is playing, the line is over.
	if available() and not DisplayServer.tts_is_speaking() and Time.get_ticks_msec() - _started_msec > int(START_GRACE_S * 1000.0):
		_finish(_current_id, true)
		return false
	return true


## The kind of the line being read, or &"".
func speaking_kind() -> StringName:
	return _current_kind if is_speaking() else &""


# ---------------------------------------------------------------- text the voice reads

## The words as a person would say them: no markup, no brackets, symbols and chemical formulas spelled out.
static func clean(text: String) -> String:
	var t := text
	t = _re(t, "\\[[^\\]]*\\]", " ")              # BBCode tags and [bracketed] notes
	t = _re(t, "<[^>]*>", " ")                     # HTML-style tags
	t = t.replace("{", " ").replace("}", " ")
	t = t.replace("°C", " degrees Celsius").replace("° C", " degrees Celsius")
	t = t.replace("°F", " degrees Fahrenheit").replace("°", " degrees")
	t = t.replace("CO₂", "carbon dioxide").replace("O₂", "oxygen").replace("H₂O", "water").replace("N₂", "nitrogen")
	t = _re(t, "\\bCO2\\b", "carbon dioxide")
	t = _re(t, "\\bO2\\b", "oxygen")
	t = _re(t, "\\bH2O\\b", "water")
	t = t.replace("₂", "2").replace("₃", "3")
	t = t.replace("%", " percent").replace("&", " and ").replace("×", " times ").replace("→", " to ")
	t = t.replace("≈", " about ").replace("±", " plus or minus ").replace("+", " plus ")
	t = t.replace("—", ", ").replace("–", ", ").replace(" - ", ", ").replace("…", ". ").replace("•", ", ")
	t = t.replace("e.g.", "for example").replace("i.e.", "that is").replace(" vs. ", " versus ").replace(" vs ", " versus ")
	t = _re(t, "(\\d)\\s*kg\\b", "$1 kilograms")
	t = _re(t, "(\\d)\\s*kPa\\b", "$1 kilopascals")
	t = _re(t, "(\\d)\\s*km\\b", "$1 kilometres")
	t = _re(t, "(\\d)\\s*kW\\b", "$1 kilowatts")
	t = _re(t, "(\\d)\\s*kWh\\b", "$1 kilowatt hours")
	t = _re(t, "\\bEsc\\b", "Escape")
	t = t.replace("(", ", ").replace(")", ", ").replace("\"", "").replace("*", " ").replace("_", " ").replace("#", " ")
	t = t.replace("\n", ". ").replace("\t", " ")
	t = _re(t, "\\s+", " ")
	t = _re(t, "\\s+([,.!?;:])", "$1")
	t = _re(t, ",\\s*([,.!?;:])", "$1")
	t = _re(t, "\\.(\\s*\\.)+", ".")
	t = t.strip_edges()
	while t.begins_with(",") or t.begins_with("."):
		t = t.substr(1).strip_edges()
	return t


static func _re(text: String, pattern: String, replacement: String) -> String:
	var rx := RegEx.create_from_string(pattern)
	return rx.sub(text, replacement, true) if rx != null and rx.is_valid() else text


# ---------------------------------------------------------------- the OS voice

func _detect() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not bool(ProjectSettings.get_setting(SETTING, false)):
		return false
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	var voices: Array[Dictionary] = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return false
	var english_ids := DisplayServer.tts_get_voices_for_language("en")
	var english: Array[Dictionary] = []
	for v: Dictionary in voices:
		if english_ids.has(String(v.get("id", ""))) or String(v.get("language", "")).to_lower().begins_with("en"):
			english.append(v)
	var pick := {}
	for token: String in PREFERRED_VOICES:
		for v: Dictionary in english:
			if String(v.get("name", "")).containsn(token):
				pick = v
				break
		if not pick.is_empty():
			break
	if pick.is_empty():
		for v: Dictionary in english:
			var lang := String(v.get("language", "")).to_lower().replace("-", "_")
			if lang.begins_with("en_us") or lang.begins_with("en_gb"):
				pick = v
				break
	if pick.is_empty():
		pick = english[0] if not english.is_empty() else voices[0]
	_voice_id = String(pick.get("id", ""))
	_voice_name = String(pick.get("name", _voice_id))
	if _voice_id.is_empty():
		return false
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_canceled)
	return true


func _volume() -> int:
	if settings == null:
		return DEFAULT_VOLUME
	return clampi(roundi(settings.narrator_volume * 100.0), 0, 100)


func _cut_current() -> void:
	if _current_id != 0:
		_finish(_current_id, false)


func _finish(id: int, completed: bool) -> void:
	if id == 0 or id != _current_id:
		return
	var kind := _current_kind
	_current_id = 0
	_current_kind = &""
	line_finished.emit(kind, completed)


func _on_utterance_ended(id: int) -> void:
	_finish(id, true)


func _on_utterance_canceled(id: int) -> void:
	_finish(id, false)


func _on_settings_changed() -> void:
	if not voice_on():
		stop()
