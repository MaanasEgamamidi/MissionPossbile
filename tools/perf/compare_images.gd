extends SceneTree
## Compares stills of the same view (diagnostic only, headless is fine).
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/perf/compare_images.gd -- \
##       --dir=G:/nasa app/_perf/ultra/shots --base=base --cases=cur_zone_lights_only,fsr2_067_nomsaa [--diff]
## For every <view>__<base>.png in --dir and each case: mean absolute difference (0-255, luminance), share of pixels
## off by more than 8/255, and the worst 1 % of pixels. --diff writes <view>__<case>__diff.png (difference x 8).

func _initialize() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var dir: String = args.get("dir", "")
	var base: String = args.get("base", "base")
	var cases := String(args.get("cases", "")).split(",", false)
	var da := DirAccess.open(dir)
	if da == null:
		print("no dir ", dir)
		quit(1)
		return
	for f: String in da.get_files():
		if not f.ends_with("__%s.png" % base):
			continue
		var view := f.trim_suffix("__%s.png" % base)
		var a := Image.load_from_file(dir.path_join(f))
		for c: String in cases:
			var path := dir.path_join("%s__%s.png" % [view, c])
			if not FileAccess.file_exists(path):
				continue
			var b := Image.load_from_file(path)
			if b.get_size() != a.get_size():
				b.resize(a.get_width(), a.get_height())
			var w := a.get_width()
			var h := a.get_height()
			var diff: Image = Image.create(w, h, false, Image.FORMAT_RGB8) if args.has("diff") else null
			var total := 0.0
			var changed := 0
			var hist := PackedInt32Array()
			hist.resize(256)
			for y in range(0, h, 2):
				for x in range(0, w, 2):
					var ca := a.get_pixel(x, y)
					var cb := b.get_pixel(x, y)
					var d := absf(ca.get_luminance() - cb.get_luminance()) * 255.0
					total += d
					if d > 8.0:
						changed += 1
					hist[mini(255, int(d))] += 1
					if diff != null:
						var v := clampf(d * 8.0 / 255.0, 0.0, 1.0)
						diff.set_pixel(x, y, Color(v, v, v))
						diff.set_pixel(mini(x + 1, w - 1), y, Color(v, v, v))
						diff.set_pixel(x, mini(y + 1, h - 1), Color(v, v, v))
						diff.set_pixel(mini(x + 1, w - 1), mini(y + 1, h - 1), Color(v, v, v))
			var n := float((w / 2) * (h / 2))
			var acc := 0
			var p99 := 0
			for i in 256:
				acc += hist[i]
				if acc >= n * 0.99:
					p99 = i
					break
			print("CMP %-22s %-26s mean_abs %6.2f  changed>8 %6.2f %%  p99 %3d" % [view, c, total / n, 100.0 * changed / n, p99])
			if diff != null:
				diff.save_png(dir.path_join("%s__%s__diff.png" % [view, c]))
	quit(0)
