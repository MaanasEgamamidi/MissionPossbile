class_name PlayerInput
extends RefCounted
## Runtime input defaults and portable remaps; no project settings edits.

## Default physical keys; negative values encode mouse buttons.
const ACTIONS: Dictionary = {
	&"move_forward": [KEY_W], &"move_back": [KEY_S],
	&"move_left": [KEY_A], &"move_right": [KEY_D], &"sprint": [KEY_SHIFT],
	&"jump": [KEY_SPACE], &"interact": [KEY_E], &"grab": [KEY_G, -MOUSE_BUTTON_LEFT],
	&"toggle_view": [KEY_TAB], &"map": [KEY_M], &"push_to_talk": [KEY_V],
	&"back": [KEY_ESCAPE], &"source_register": [KEY_BACKSPACE | KEY_MASK_SHIFT],
	# Added in Prompt 05 (not in the pack's list, remappable): cargo and crew screens.
	&"inventory": [KEY_I], &"crew": [KEY_C],
	# Scout update (mission-control HUD, remappable): power drawer, build drawer at the solar field, fold the supplies,
	# fold the goals, close a Mission Control message, the science behind the numbers.
	# Owner 2026-11-15 (upgrade plan §1.6): folding the supplies moved from H to U; H is the help key below.
	&"power_view": [KEY_O], &"build": [KEY_B], &"hud_details": [KEY_U], &"goals": [KEY_J], &"advisor_ok": [KEY_K],
	&"vitals_help": [KEY_F1],
	# Added in Prompt 12 (remappable): a tutorial hint on request (N) and the colony journal / story log (L). U and J are the mission HUD's folds.
	&"tutorial_hint": [KEY_N], &"journal": [KEY_L],
	# Owner 2026-11-15: "H should make the sparkle lines pop up" (scripts/guide/help_key.gd).
	&"help": [KEY_H],
}
## Plain names for the settings screen, in display order.
const ACTION_NAMES: Dictionary = {
	&"move_forward": "Move forward", &"move_back": "Move back", &"move_left": "Move left", &"move_right": "Move right",
	&"sprint": "Sprint", &"jump": "Jump", &"interact": "Use (interact)", &"grab": "Grab, drop, throw",
	&"toggle_view": "First / third person", &"map": "Blueprint map (off for now)", &"inventory": "Cargo", &"crew": "Crew",
	&"push_to_talk": "Toggle voice chat", &"back": "Close / pause", &"source_register": "Source register",
	&"power_view": "Power and life support", &"build": "Build (at the solar field)", &"hud_details": "Fold the supplies bar",
	&"goals": "Goals (list / map / compact)", &"advisor_ok": "Close a Mission Control message", &"vitals_help": "Science behind the numbers",
	&"tutorial_hint": "Tutorial hint", &"journal": "Colony journal", &"help": "Help: show the way (gold sparkles)",
}
static var _remapped: Dictionary = {}

## Adds defaults without removing existing user bindings.
static func ensure_actions() -> void:
	# Godot ships F5 on its file-dialog refresh action. Reserve it for the app;
	# remove only this engine default, never a player's gameplay remap.
	if InputMap.has_action(&"ui_filedialog_refresh"):
		for event: InputEvent in InputMap.action_get_events(&"ui_filedialog_refresh"):
			if event is InputEventKey and (event.keycode == KEY_F5 or event.physical_keycode == KEY_F5):
				InputMap.action_erase_event(&"ui_filedialog_refresh", event)
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if _remapped.has(action):
			continue
		for code: int in ACTIONS[action]:
			var event: InputEvent = _default_event(code)
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

## Replaces an action's bindings with one chosen event.
static func rebind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	_remapped[action] = true

## Restores the defaults for one action.
static func reset(action: StringName) -> void:
	if not ACTIONS.has(action):
		return
	_remapped.erase(action)
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for code: int in ACTIONS[action]:
		InputMap.action_add_event(action, _default_event(code))

## Saves remapped InputEvents as Godot's textual variants inside JSON.
static func save(path: String) -> Error:
	var data: Dictionary = {}
	for action: StringName in _remapped:
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(var_to_str(event))
		data[String(action)] = events
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return file.get_error()

## Loads saved remaps after validating all event records.
static func load(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return ERR_PARSE_ERROR
	var decoded: Dictionary = {}
	for action: String in data:
		if not ACTIONS.has(StringName(action)) or not data[action] is Array:
			return ERR_INVALID_DATA
		var events: Array[InputEvent] = []
		for record: Variant in data[action]:
			if not record is String:
				return ERR_INVALID_DATA
			var event: Variant = str_to_var(record)
			if not event is InputEvent:
				return ERR_INVALID_DATA
			events.append(event)
		decoded[StringName(action)] = events
	# Owner 2026-11-15: H is the help key now. A saved fold-the-supplies binding on H (from before the move) goes back
	# to its new default U, so H shows the way instead of folding the bar. Kept when the player also saved their own help key.
	if decoded.has(&"hud_details") and not decoded.has(&"help") and _has_key(decoded[&"hud_details"], KEY_H):
		decoded.erase(&"hud_details")
		_remapped.erase(&"hud_details")
		if InputMap.has_action(&"hud_details"):
			InputMap.action_erase_events(&"hud_details")
	ensure_actions()
	for action: StringName in decoded:
		InputMap.action_erase_events(action)
		for event: InputEvent in decoded[action]:
			InputMap.action_add_event(action, event)
		_remapped[action] = true
	return OK

## Human-readable bindings for help and settings screens.
static func describe(action: StringName) -> String:
	var names := PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			names.append("Left mouse")
		elif event is InputEventKey:
			var key: int = event.physical_keycode if event.physical_keycode else event.keycode
			names.append(("Shift+" if event.shift_pressed else "") + OS.get_keycode_string(key))
		else:
			names.append(event.as_text())
	return " / ".join(names)

## True when one of `events` is the plain key `key` (physical or logical code, no Shift).
static func _has_key(events: Array[InputEvent], key: Key) -> bool:
	for event: InputEvent in events:
		var k := event as InputEventKey
		if k != null and not k.shift_pressed and (k.physical_keycode == key or k.keycode == key):
			return true
	return false


static func _default_event(code: int) -> InputEvent:
	if code < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code
		return mouse
	var key := InputEventKey.new()
	key.physical_keycode = code & KEY_CODE_MASK
	key.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	return key
