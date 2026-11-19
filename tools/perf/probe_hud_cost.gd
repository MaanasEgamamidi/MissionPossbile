extends "res://tools/perf/perf_bench.gd"
## Times the pieces of the MissionHud's 4 Hz refresh (diagnostic only). WINDOWED.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_hud_cost.gd -- --views=room_command_room

func _process(delta: float) -> bool:
	if _phase != "next":
		return super(delta)
	_enter_view(_views[0])
	var mh: Node = _game.get_node("Hud/MissionHud")
	var calls := {
		"mission_refresh": func() -> void: mh.call("refresh"),
		"vitals": func() -> void: mh.get("vitals").call("refresh"),
		"energy": func() -> void: mh.get("energy").call("refresh"),
		"balance_chip": func() -> void: mh.get("balance_chip").call("refresh"),
		"goals": func() -> void: mh.get("goals").call("refresh"),
		"tracker_near": func() -> void: mh.call("_tracker_near"),
		"check_low": func() -> void: mh.call("_check_low"),
		"layout": func() -> void: mh.call("_layout"),
	}
	# PowerModel.solar_kw_with must give exactly solar_kw (bit for bit) over a whole sol, tracking on and off.
	var services: GameServices = _game.get("services")
	var st := services.state()
	var mismatches := 0
	for tracking: bool in [true, false]:
		var inputs := PowerModel.solar_inputs(st, services.balance, tracking)
		for i in 2000:
			var ph := float(i) / 2000.0
			if PowerModel.solar_kw(st, services.balance, ph, tracking) != PowerModel.solar_kw_with(inputs, ph):
				mismatches += 1
	print("SOLAR_EQUAL mismatches=", mismatches, " of 4000")
	for k: String in calls:
		var best := INF
		var total := 0.0
		for i in 5:
			var t0 := Time.get_ticks_usec()
			(calls[k] as Callable).call()
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			best = minf(best, ms)
			total += ms
		print("HUDCOST %-22s mean %8.2f ms  best %8.2f ms" % [k, total / 5.0, best])
	quit(0)
	return true
