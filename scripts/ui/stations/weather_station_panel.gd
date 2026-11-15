extends StationPanel
## The weather screen (stations of kind "weather"): which archive data the game runs on, the dust in the sky now and
## what it does to solar power, and the dust warning. It always says what the data is: archive observations from
## Jezero, played faster, and not a forecast for this colony. It only reads state; the one button asks the host
## (`acknowledge_weather_warning`).

const ARCHIVE_LABEL := "Archive observations from Jezero, played faster"
const NOT_FORECAST_LABEL := "Not a forecast for this colony"

var _labels_card: VBoxContainer
var _warning_text: Label
var _ack_text: Label
var _ack_button: Button
var _history_box: VBoxContainer
var _newer_text: Label


func panel_title() -> String:
	return "Weather screen"


func _title_text() -> String:
	return "Weather screen"


func _shows_later_note() -> bool:
	return false


func _what_you_can_do() -> PackedStringArray:
	return PackedStringArray(["See how dusty the sky is and how much power the panels lose.",
		"Read the dust warning and tell your team you heard it.",
		"See which archive data the game uses and when it was last checked."])


## The two labels that always stand on this screen.
func label_texts() -> PackedStringArray:
	return StationPanel._box_lines(_labels_card)


func warning_text() -> String:
	return _warning_text.text if _warning_text != null else ""


func acknowledge_button() -> Button:
	return _ack_button


func _build_body() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.CARD
	_body.add_child(card)
	_labels_card = VBoxContainer.new()
	_labels_card.name = "Labels"
	card.add_child(_labels_card)
	_add_text(_labels_card, "! " + ARCHIVE_LABEL + ".", UiTheme.WARN)
	_add_text(_labels_card, "! " + NOT_FORECAST_LABEL + ".", UiTheme.WARN)
	# UI overhaul: the two labels stand; why (the archive replay, the game's own timing) is behind the "?" switch.
	var why := "The dust events replay dust measured at Jezero crater on Mars. The time between events is a game choice (much faster than on Mars), not how often NASA saw dust storms."
	_add_note(_labels_card, why)
	card.tooltip_text = why

	_add_heading_with_help(_body, "Dust warning", "panel_dust")
	_warning_text = _add_text(_body, "")
	_warning_text.name = "WarningText"
	_warning_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_ack_text = _add_text(_body, "", UiTheme.MUTED)
	var row := HBoxContainer.new()
	_body.add_child(row)
	_ack_button = Button.new()
	_ack_button.name = "AcknowledgeButton"
	_ack_button.text = "I heard the warning"
	_ack_button.theme_type_variation = UiTheme.PRIMARY_BUTTON
	_ack_button.pressed.connect(_on_acknowledge)
	row.add_child(_ack_button)

	# The sky in words and bars; wind and season are details behind the "?" switch.
	_add_heading_with_help(_body, "The sky now", "solar_power")
	_add_reading(&"opacity", "τ", "Dust in the air", "solar_power", _body)
	_add_reading(&"sunlight", "☀", "Sunlight on panels", "solar_power", _body)
	_add_reading(&"panels", "▦", "Dust on panels", "panel_dust", _body)
	_add_reading(&"phase", "•", "Dust event", "panel_dust", _body)
	_help_only(_add_reading(&"wind", "≈", "Wind", "sources", _body))
	_help_only(_add_reading(&"season", "◷", "Season in the game (Ls)", "sol_clock", _body))

	# Which archive data the game runs on: all of it behind the "?" switch.
	var archive := VBoxContainer.new()
	archive.name = "Archive"
	_body.add_child(archive)
	_help_only(archive)
	_add_heading_with_help(archive, "Archive data in use", "sources")
	_add_reading(&"site", "⌖", "Place", "sources", archive)
	_add_reading(&"dates", "▤", "Observed (archive dates)", "sources", archive)
	_add_reading(&"status", "✓", "Data check", "sources", archive)
	_add_reading(&"snapshot", "#", "Data used by this game", "sources", archive)
	_add_reading(&"last_check", "⧗", "Last check for new data", "sources", archive)
	_newer_text = _add_text(archive, "", UiTheme.MUTED)
	_newer_text.name = "NewerData"

	_add_heading(_body, "Past dust events")
	_history_box = VBoxContainer.new()
	_history_box.name = "History"
	_body.add_child(_history_box)

	# Long archive values (dates, the data id, the last check's result) wrap inside their row instead of widening the
	# panel past a 1280-pixel screen.
	for id: StringName in readings:
		var r := readings[id] as Reading
		r.value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _refresh_body(st: ColonyState) -> void:
	var bal := services.balance
	var w: Dictionary = st.weather
	var tau := st.dust_tau
	# states, not numbers: the sky in words (its opacity τ is the tooltip), sunlight and panel dust as bars
	var sky := WeatherSystem.opacity_words(tau)
	_show_reading(&"opacity", sky.left(1).to_upper() + sky.substr(1),&"ok" if tau < 0.9 else (&"warn" if tau < 2.0 else &"urgent"))
	(readings[&"opacity"] as Reading).tooltip_text = "Opacity τ %s: how much dust is in the air." % num(tau, 2)
	var share := WeatherSystem.sunlight_share(st, bal)
	_show_reading(&"sunlight", "%d %% of usual" % roundi(share * 100.0), &"ok" if share >= 0.8 else (&"warn" if share >= 0.5 else &"urgent"), share)
	(readings[&"sunlight"] as Reading).tooltip_text = WeatherSystem.solar_words(st, bal)
	var dust := PowerModel.average_dust(st)
	_show_reading(&"panels", "Clean them" if dust >= 0.2 else "Clean", &"ok" if dust < 0.2 else &"warn")
	(readings[&"panels"] as Reading).tooltip_text = "%d %% of the panels is covered with dust." % roundi(dust * 100.0)
	var wind := float(w.get("wind_ms", -1.0))
	if wind < 0.0:
		_show_reading(&"wind", "not measured in the archive", &"ok")
	else:
		_show_reading(&"wind", "about %s m/s (%s)" % [num(wind, 1), String(w.get("wind_source", "archive"))], &"ok")
	_show_reading(&"season", "Ls %d° (game time, sol %d)" % [roundi(float(w.get("ls", 0.0))), int(st.sim_hours / GameConfig.SOL_HOURS)], &"ok")
	_show_reading(&"phase", _phase_words(w), &"ok" if String(w.get("phase", "calm")) == "calm" else &"warn")

	var warning: Dictionary = w.get("warning", {})
	if warning.is_empty():
		var active: Dictionary = w.get("active", {})
		if active.is_empty():
			_warning_text.text = "✓ No dust warning right now."
			_warning_text.theme_type_variation = UiTheme.GOOD
		else:
			_warning_text.text = "! Dust now. Stay near the airlock."
			_warning_text.theme_type_variation = UiTheme.WARN
		_warning_text.tooltip_text = "Clean the panels when the dust has passed." if not active.is_empty() else ""
		_ack_text.visible = false
		_ack_button.visible = false
	else:
		# short on screen (when, and what to do); the whole warning is the tooltip
		var left := maxf(0.0, float(warning.get("starts_at_hours", 0.0)) - st.sim_hours)
		var minutes := maxi(1, roundi(left / maxf(services.clock().hours_per_real_second(), 1e-9) / 60.0))
		_warning_text.text = "! Dust warning: in about %d minute%s.\nWalk back to the airlock." % [minutes, "" if minutes == 1 else "s"]
		_warning_text.tooltip_text = "%s (Starts in about %d game hours.)" % [StationPanel.words(String(warning.get("text", ""))), roundi(left)]
		_warning_text.theme_type_variation = UiTheme.WARN
		var by: Array = warning.get("acknowledged_by", [])
		var names := PackedStringArray()
		for id: Variant in by:
			var c := st.character(StringName(String(id)))
			names.append(c.display_name if c != null else String(id))
		_ack_text.visible = true
		_ack_text.text = "Heard by: %s" % (", ".join(names) if not names.is_empty() else "nobody yet")
		var me := services.local_character()
		_ack_button.visible = me != null and not by.has(String(me.id))

	var data: Dictionary = w.get("data", {})
	var builtin := String(data.get("source", "builtin")) == "builtin"
	_show_reading(&"site", String(data.get("site", "")) if not builtin else "none (built-in default sky)", &"ok" if not builtin else &"warn")
	if builtin:
		_show_reading(&"dates", "no archive data", &"warn")
	else:
		var sols := ""
		if not WeatherArchive.is_missing(float(data.get("sol_start", -999.0))) and not WeatherArchive.is_missing(float(data.get("sol_end", -999.0))):
			sols = " (sols %d to %d)" % [int(data.sol_start), int(data.sol_end)]
		_show_reading(&"dates", "%s to %s%s" % [String(data.get("observation_start", "?")).left(10), String(data.get("observation_end", "?")).left(10), sols], &"ok")
	_show_reading(&"status", String(data.get("validation", "unknown")), &"ok" if not builtin else &"warn")
	_show_reading(&"snapshot", String(st.data_snapshot_id) if st.data_snapshot_id != "" else "not chosen yet", &"ok")
	var status := _refresh_status()
	if status.is_empty():
		_show_reading(&"last_check", "not checked yet", &"ok")
	else:
		var ok := bool(status.get("last_ok", true))
		_show_reading(&"last_check", "%s · %s" % [String(status.get("last_check_utc", "?")).replace("T", " ").left(16), String(status.get("last_result", ""))],
			&"ok" if ok else &"warn")
	var published: Dictionary = status.get("published_updates", {})
	var newer := String(status.get("cache_snapshot", ""))
	if newer != "" and st.data_snapshot_id != "" and newer != st.data_snapshot_id:
		_newer_text.text = "Newer data is ready (%s). This game keeps its data so its dust events stay the same; the new data is used from the next new game or load." % newer
		_newer_text.visible = true
	elif not published.is_empty():
		_newer_text.text = "The Mars weather archive has newer data (%s). This game keeps the data it started with." % ", ".join(PackedStringArray(published.keys()))
		_newer_text.visible = true
	else:
		_newer_text.visible = false

	var lines: Array = []
	var details := PackedStringArray()
	var history: Array = w.get("history", [])
	for i in range(history.size() - 1, maxi(-1, history.size() - 4), -1):
		var h: Dictionary = history[i]
		lines.append({"text": "Sol %d: dust for about %d hours" % [int(float(h.get("at_hours", 0.0)) / GameConfig.SOL_HOURS), roundi(float(h.get("duration_hours", 0.0)))],
			"level": "info"})
		details.append("Sol %d: darkest sky τ %s, severity %s of the archive episode %s (game time)." % [int(float(h.get("at_hours", 0.0)) / GameConfig.SOL_HOURS),
			num(float(h.get("peak_tau", 0.0)), 2), num(float(h.get("severity", 0.0)), 2), String(h.get("episode_id", ""))])
	_fill_alerts(_history_box, lines, "No dust events yet.")
	_history_box.tooltip_text = "\n".join(details)


static func _phase_words(w: Dictionary) -> String:
	match String(w.get("phase", "calm")):
		"warned": return "warning given, dust coming"
		"rising": return "dust is rising"
		"peak": return "the darkest part"
		"falling": return "dust is settling"
	return "calm"


func _refresh_status() -> Dictionary:
	var node := WeatherRefresh.find(get_tree()) if is_inside_tree() else null
	return node.status() if node != null else WeatherRefresh.read_status()


func _on_acknowledge() -> void:
	_ask(&"acknowledge_weather_warning", {}, func(result: ActionResult) -> void:
		if result.ok:
			_show_message(answer_text(result), UiTheme.GOOD)
		else:
			_show_refusal(result)
		refresh())
