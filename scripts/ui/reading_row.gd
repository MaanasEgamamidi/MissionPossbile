class_name ReadingRow
extends HBoxContainer
## One reading on one line: symbol, name, value with its unit, a status mark in words and a "?" button.
## Used by the colony summary and by the station panels. Colour is never the only cue: the status always
## shows a symbol (✓ ! ✖) and a word as well as its theme colour.

## Symbol and default word for each level.
const LEVELS := {
	&"ok": {"symbol": "✓", "word": "OK"},
	&"warn": {"symbol": "!", "word": "Watch"},
	&"urgent": {"symbol": "✖", "word": "Act now"},
}

## The symbol at the start of the row (a Unicode glyph).
var symbol_label: Label
## What the reading is, in words ("Battery").
var name_label: Label
## The value with its unit ("180 kWh of 400 kWh").
var value_label: Label
## The status mark and word ("✓ OK").
var status_label: Label
## The "?" button at the end, or null when the row has no explanation.
var explain_button: ExplainButton
## The level last given to set_value(): &"ok", &"warn" or &"urgent".
var level: StringName = &"ok"


## Builds a row. `explanation_id` is an id from data/explanations.json; empty means no "?" button.
static func make(symbol: String, label: String, explanation_id: String) -> ReadingRow:
	var row := ReadingRow.new()
	row.name = "Reading_" + label.validate_node_name().replace(" ", "_")
	row.symbol_label = Label.new()
	row.symbol_label.name = "Symbol"
	row.symbol_label.text = symbol
	row.add_child(row.symbol_label)
	row.name_label = Label.new()
	row.name_label.name = "Name"
	row.name_label.text = label
	row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(row.name_label)
	row.value_label = Label.new()
	row.value_label.name = "Value"
	row.value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(row.value_label)
	row.status_label = Label.new()
	row.status_label.name = "Status"
	row.add_child(row.status_label)
	if explanation_id != "":
		row.explain_button = ExplainButton.make(explanation_id)
		row.explain_button.name = "Explain"
		row.add_child(row.explain_button)
	row.set_value("—", &"ok")
	return row


## Shows a value (with its unit) and a level: &"ok", &"warn" or &"urgent".
## `word` replaces the default status word ("OK", "Watch", "Act now"), for example "Low" or "On".
func set_value(text: String, p_level: StringName, word := "") -> void:
	level = p_level if LEVELS.has(p_level) else &"ok"
	var info: Dictionary = LEVELS[level]
	value_label.text = text
	status_label.text = "%s %s" % [info.symbol, word if word != "" else String(info.word)]
	var variation := variation_of(level)
	value_label.theme_type_variation = variation
	status_label.theme_type_variation = variation


## The UiTheme label variation for a level.
static func variation_of(p_level: StringName) -> StringName:
	match p_level:
		&"warn":
			return UiTheme.WARN
		&"urgent":
			return UiTheme.URGENT
	return UiTheme.GOOD
