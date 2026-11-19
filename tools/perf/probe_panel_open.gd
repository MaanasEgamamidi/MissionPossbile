extends "res://tools/perf/perf_bench.gd"
## Cost of opening a station panel, first and later times (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_panel_open.gd -- \
##       --quality=3 --cap=60 --window=2560x1369 --views=room_command_room [--station=cm_colony_computer] [--opens=4]
## Opens the station's panel the way GameMain._submit does (StationPanels.for_station + ui.open), keeps it open for
## 1 s, closes it, waits 1 s, and repeats. Prints the slowest frame within 10 frames after each open, and how long the
## open call itself took on the main thread.

var _po_n := 0
var _po_t := 0.0
var _po_state := "wait"
var _po_frames: Array = []
var _po_panel: Node = null
var _po_call_ms := 0.0


func _process(delta: float) -> bool:
	if _phase == "next":
		_enter_view(_views[0])
		_phase = "panel"
		return false
	if _phase != "panel":
		return super(delta)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_po_t += delta
	match _po_state:
		"wait":
			if _po_t >= 1.5:
				var services: GameServices = _game.get("services")
				var station := StringName(_args.get("station", "cm_colony_computer"))
				var ta := Time.get_ticks_usec()
				var st := services.state()
				var tb := Time.get_ticks_usec()
				var mapped := RepairCatalog.interaction_station_id(st, String(station))
				var tc := Time.get_ticks_usec()
				print("PANELPARTS state() %.2f ms, interaction_station_id %.2f ms -> %s, has record %s" % [(tb - ta) / 1000.0,
					(tc - tb) / 1000.0, mapped, st.stations.has(mapped)])
				var t0 := Time.get_ticks_usec()
				_po_panel = StationPanels.for_station(station, services)
				var t1 := Time.get_ticks_usec()
				if _po_panel != null:
					_game.get("ui").call("open", _po_panel)
				_po_call_ms = float(Time.get_ticks_usec() - t0) / 1000.0
				print("PANELBUILT %s kind=%s build %.1f ms, ui.open %.1f ms" % [_po_panel.get_class() if _po_panel != null else "null",
					st.stations.get(mapped, {}).get("kind", "?"), (t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0])
				_po_frames = []
				_po_state = "open"
				_po_t = 0.0
		"open":
			if _po_frames.size() < 10:
				_po_frames.append(frame_ms)
			if _po_t >= 1.0:
				_po_n += 1
				var worst: float = _po_frames.max() if not _po_frames.is_empty() else 0.0
				print("PANELOPEN %d %s: open call %.1f ms, slowest of the next 10 frames %.1f ms" % [_po_n,
					"panel" if is_instance_valid(_po_panel) else "panel gone", _po_call_ms, worst])
				var ui: Node = _game.get("ui")
				if ui.has_method("close"):
					ui.call("close")
				elif ui.has_method("close_all"):
					ui.call("close_all")
				elif is_instance_valid(_po_panel):
					_po_panel.queue_free()
				_po_state = "wait"
				_po_t = 0.0
				if _po_n >= int(_args.get("opens", "4")):
					quit(0)
					return true
	return false
