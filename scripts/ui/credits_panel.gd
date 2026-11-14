class_name CreditsPanel
extends UiPanel
## Credits: the engine, tools, assets and science sources behind the game, read from res://data/credits.json,
## grouped by kind, each with its licence in plain words. A licence nobody found is shown as unknown.

## Kind in credits.json -> group heading, in the order shown.
const GROUPS: Array[Array] = [
	["engine", "Engine"],
	["tool", "Tools"],
	["asset", "Assets"],
	["science", "Science sources"],
]

## Prompt 11: the voice libraries, listed with the tools (addons/twovoip/VERSION.txt and LICENSE.txt).
const VOICE_CREDITS: Array[Dictionary] = [
	{"id": "twovoip", "kind": "tool", "name": "TwoVoIP 6.1 (Godot voice extension)",
		"by": "Julian Todd, K. S. Ernest (iFire) Lee, Gordon MacPherson and Marc Weber",
		"licence_words": "MIT licence: free to use, change and share, as long as the copyright notice and licence text are kept (addons/twovoip/LICENSE.txt).",
		"used_for": "Voice chat between players: squeezes microphone sound into small Opus packets and plays them back on the other computers. The game's own voice code is adapted from its helper scripts.",
		"url": "https://github.com/goatchurchprime/two-voip-godot-4"},
	{"id": "opus", "kind": "tool", "name": "Opus audio codec (libopus, inside TwoVoIP)", "by": "Xiph.Org Foundation and contributors",
		"licence_words": "BSD-style licence: free to use and share, as long as the copyright notice is kept. Its full text is in the library's own source files (it is not copied into this build).",
		"used_for": "Compresses speech so it is small enough to send many times a second."},
	{"id": "speexdsp", "kind": "tool", "name": "SpeexDSP resampler (inside TwoVoIP)", "by": "Xiph.Org Foundation and contributors",
		"licence_words": "BSD-style licence: free to use and share, as long as the copyright notice is kept. Its full text is in the library's own source files (it is not copied into this build).",
		"used_for": "Changes the microphone's sample rate to the one the codec uses."},
	{"id": "rnnoise", "kind": "tool", "name": "RNNoise noise suppression (inside TwoVoIP)", "by": "Jean-Marc Valin, Mozilla, Xiph.Org Foundation and contributors",
		"licence_words": "BSD-style licence: free to use and share, as long as the copyright notice is kept. Its full text is in the library's own source files (it is not copied into this build).",
		"used_for": "Part of the voice library. The game does not switch noise suppression on."},
]

var _list: VBoxContainer
var _scroll: ScrollContainer


func setup(p_services: GameServices) -> void:
	super.setup(p_services)
	name = "CreditsPanel"
	theme_type_variation = UiTheme.PANEL
	_build()


func panel_title() -> String:
	return "Credits"


## The group headings shown, in order (for checks).
func group_titles() -> PackedStringArray:
	var out := PackedStringArray()
	if _list == null:
		return out
	for child in _list.get_children():
		if child is Label and (child as Label).theme_type_variation == UiTheme.HEADING:
			out.append((child as Label).text)
	return out


## The scrolling list of credits.
func credit_list() -> ScrollContainer:
	return _scroll


func _build() -> void:
	var box := VBoxContainer.new()
	box.name = "Box"
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Credits"
	title.theme_type_variation = UiTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Close"
	close.tooltip_text = "Close the credits (Esc)."
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	var intro := Label.new()
	intro.text = "The engine, tools, models and science pages this game was made with, and the licence of each one. A licence is a set of rules for using someone's work."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(intro)

	_scroll = ScrollContainer.new()
	_scroll.name = "Credits"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	for group: Array in GROUPS:
		var entries: Array[Dictionary] = []
		for c: Dictionary in SourceLibrary.credits() + VOICE_CREDITS:
			if String(c.get("kind", "")) == String(group[0]):
				entries.append(c)
		if entries.is_empty():
			continue
		var heading := _label(String(group[1]), UiTheme.HEADING)
		_list.add_child(heading)
		for c: Dictionary in entries:
			_list.add_child(_card(c))


func _card(c: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Credit_" + String(c.get("id", ""))
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	card.add_child(box)
	box.add_child(_label(String(c.get("name", "")), UiTheme.HEADING))
	_add_row(box, "Made by", String(c.get("by", "")))
	var licence := String(c.get("licence_words", ""))
	if licence == "":
		licence = String(c.get("licence", ""))
	if licence == "":
		licence = "Unknown."
	_add_row(box, "Licence", licence)
	_add_row(box, "Used for", String(c.get("used_for", "")))
	if String(c.get("note", "")) != "":
		box.add_child(_label(String(c.get("note", "")), UiTheme.MUTED))
	if String(c.get("url", "")) != "":
		var url := _label("Web address: " + String(c.get("url", "")), UiTheme.MUTED)
		url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		box.add_child(url)
	if String(c.get("kind", "")) == "science":
		var open := Button.new()
		open.name = "OpenRegister"
		open.text = "Open the source register"
		open.tooltip_text = "See every page, what was read from it and how well it was checked."
		open.pressed.connect(_open_register)
		box.add_child(open)
	return card


func _add_row(box: VBoxContainer, heading: String, value: String) -> void:
	if value.strip_edges() == "":
		return
	box.add_child(_label("%s: %s" % [heading, value], &""))


func _label(words: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		label.theme_type_variation = variation
	return label


func _open_register() -> void:
	var register := SourceRegisterPanel.new()
	register.show_entry("")
	open_requested.emit(register)
