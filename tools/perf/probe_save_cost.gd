extends "res://tools/perf/perf_bench.gd"
## Times the parts of a save (diagnostic only). WINDOWED (a running game).
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/perf/probe_save_cost.gd -- --views=room_command_room

func _process(delta: float) -> bool:
	if _phase != "next":
		return super(delta)
	var services: GameServices = _game.get("services")
	for i in 3:
		var t0 := Time.get_ticks_usec()
		var snap := services.snapshot()
		var t1 := Time.get_ticks_usec()
		var sum := services.saves.checksum(snap)
		var t2 := Time.get_ticks_usec()
		var text := JSON.stringify({"payload": snap, "checksum": sum}, "\t", true, true)
		var t3 := Time.get_ticks_usec()
		var err := services.saves.write(snap, &"probe")
		var t4 := Time.get_ticks_usec()
		var t5 := Time.get_ticks_usec()
		services.save_now(&"probe")
		var t6 := Time.get_ticks_usec()
		print("SAVECOST snapshot %.1f ms  checksum %.1f ms  stringify %.1f ms (%d KB)  write() %.1f ms (err %d)  save_now %.1f ms" % [
			(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, text.length() / 1024, (t4 - t3) / 1000.0, err, (t6 - t5) / 1000.0])
	quit(0)
	return true
