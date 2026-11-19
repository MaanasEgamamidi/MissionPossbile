extends SceneTree
## Headless checks of "Fit to this computer" (scripts/ui/hardware_profile.gd, GameSettings.graphics_auto): graphics
## cards are rated into the right tier by name, a headless run changes nothing, and the settings file keeps a preset
## that was picked by hand before the setting existed.
## Written 2026-11-15 and NOT run by its author (owner rule: the owner runs the suites).

var _passed := 0
var _total := 0


func _initialize() -> void:
	await process_frame
	const DISCRETE := 2
	const INTEGRATED := 1

	# the laptop this was written for
	var p := HardwareProfile.classify("NVIDIA GeForce RTX 5050 Laptop GPU", DISCRETE)
	_check(int(p["tier"]) == HardwareProfile.Tier.MID and absf(float(p["score"]) - 0.70) < 0.02 and bool(p["laptop"]),
		"RTX 5050 Laptop GPU is Mid-range, score about 0.70 (%.2f)" % float(p["score"]))
	_check(int(p["level"]) == GraphicsQuality.Level.MEDIUM and bool(p["dynamic"]) and int(p["max_pixels"]) == 1920 * 1200,
		"it gets Medium, adaptive resolution and at most 1920x1200 pixels of 3D")

	# the card the colony was tuned on keeps the authored picture
	p = HardwareProfile.classify("NVIDIA GeForce RTX 4060 Ti", DISCRETE)
	_check(int(p["tier"]) == HardwareProfile.Tier.STRONG and int(p["level"]) == GraphicsQuality.Level.ULTRA
		and not bool(p["dynamic"]) and int(p["max_pixels"]) == 0, "RTX 4060 Ti is Strong: Ultra (its own adaptive FSR 2), no profile resolution cap")

	_check(_tier("NVIDIA GeForce RTX 4060", DISCRETE) == HardwareProfile.Tier.MID, "RTX 4060 is Mid-range")
	_check(_tier("NVIDIA GeForce RTX 5070", DISCRETE) == HardwareProfile.Tier.STRONG, "RTX 5070 is Strong")
	_check(_tier("NVIDIA GeForce GTX 1650", DISCRETE) == HardwareProfile.Tier.BASIC, "GTX 1650 is Basic")
	_check(_tier("AMD Radeon RX 7600", DISCRETE) == HardwareProfile.Tier.MID, "RX 7600 is Mid-range")
	_check(_tier("AMD Radeon RX 9070 XT", DISCRETE) == HardwareProfile.Tier.STRONG, "RX 9070 XT is Strong")
	_check(_tier("Intel(R) Arc(TM) B580 Graphics", DISCRETE) == HardwareProfile.Tier.MID, "Arc B580 is Mid-range")

	# chips built into the processor (a hybrid laptop that started the game on the wrong chip)
	p = HardwareProfile.classify("AMD Radeon(TM) 610M", INTEGRATED)
	_check(int(p["tier"]) == HardwareProfile.Tier.BASIC and int(p["level"]) == GraphicsQuality.Level.LOW and bool(p["dynamic"]),
		"Radeon 610M (integrated) is Basic: Low with adaptive resolution")
	_check(is_equal_approx(float(p["target_fps"]), HardwareProfile.INTEGRATED_TARGET_FPS), "an integrated chip aims for 30 FPS")
	_check(is_equal_approx(float(HardwareProfile.classify("NVIDIA GeForce RTX 3050", DISCRETE)["target_fps"]), HardwareProfile.TARGET_FPS),
		"a discrete Basic card (RTX 3050) still aims for 60 FPS")
	_check(_tier("Intel(R) UHD Graphics 770", INTEGRATED) == HardwareProfile.Tier.BASIC, "Intel UHD is Basic")
	_check(_tier("Apple M1", INTEGRATED) == HardwareProfile.Tier.BASIC, "Apple M1 is Basic")
	_check(_tier("Apple M3 Max", INTEGRATED) != HardwareProfile.Tier.BASIC, "Apple M3 Max is not Basic")

	# not recognised: nothing is changed
	p = HardwareProfile.classify("", -1)
	_check(int(p["tier"]) == HardwareProfile.Tier.UNKNOWN and int(p["level"]) == -1 and not bool(p["dynamic"]),
		"no name: Unknown, no preset, no adaptive resolution")
	_check(_tier("Some Future Card 9000", DISCRETE) == HardwareProfile.Tier.UNKNOWN, "an unrecognised name is Unknown")
	_check(HardwareProfile.recommended_level() == -1 and HardwareProfile.summary() == "",
		"this headless run has no graphics card: nothing is recommended")

	# settings
	var s := GameSettings.new()
	_check(s.graphics_auto and s.graphics_quality == GraphicsQuality.default_level(), "defaults: fit to this computer on, High")
	s.fit_to_hardware()
	_check(s.graphics_quality == GraphicsQuality.default_level(), "headless: fitting leaves the preset alone")
	var dir := ProjectSettings.globalize_path("res://_test_saves/diag")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("hardware_settings.json")
	_write(path, {"graphics_quality": GraphicsQuality.Level.LOW})
	var old_file := GameSettings.load_or_default(path)
	_check(old_file.graphics_quality == GraphicsQuality.Level.LOW and not old_file.graphics_auto,
		"an older file with a preset picked by hand keeps it and turns fitting off")
	_write(path, {"graphics_quality": GraphicsQuality.default_level()})
	_check(GameSettings.load_or_default(path).graphics_auto, "an older file on the default preset gets fitting on")
	s.graphics_auto = false
	s.graphics_quality = GraphicsQuality.Level.ULTRA
	s.save(path)
	var back := GameSettings.load_or_default(path)
	_check(not back.graphics_auto and back.graphics_quality == GraphicsQuality.Level.ULTRA, "the choice survives save and load")
	DirAccess.remove_absolute(path)

	# the adaptive resolution node stays off in a headless run
	var node := DynamicResolution.attach(root, s)
	await process_frame
	await process_frame
	_check(node != null and not node.active and is_equal_approx(root.scaling_3d_scale, 1.0),
		"adaptive resolution is off and the render scale untouched in a headless run")
	_check(DynamicResolution.attach(root, s) == node, "attaching twice gives the same node")
	node.queue_free()
	await process_frame

	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)


func _tier(adapter: String, device_type: int) -> int:
	return int(HardwareProfile.classify(adapter, device_type)["tier"])


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _check(ok: bool, what: String) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("PASS ", what)
	else:
		print("FAIL ", what)
