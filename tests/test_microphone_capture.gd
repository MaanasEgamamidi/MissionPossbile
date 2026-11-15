extends SceneTree
## Focused windowed check; no colony, network peers, playback or audio files.
## Run with --script res://tests/test_microphone_capture.gd; add -- --live for an 8-second hardware check.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	root.size = Vector2i(600, 180)
	root.title = "Built-in microphone check (no audio saved)"
	check("Windows built-in wins over headset and default", VoiceService.built_in_device([
		"Default", "Headset Microphone (USB)", "Microphone Array (Realtek(R) Audio)"])
		== "Microphone Array (Realtek(R) Audio)")
	check("internal input wins over Bluetooth", VoiceService.built_in_device([
		"Default", "Bluetooth Headset", "Internal Microphone (Realtek Audio)"])
		== "Internal Microphone (Realtek Audio)")
	check("built-in endpoint name", VoiceService.built_in_device(["Built-in Microphone"]) == "Built-in Microphone")
	check("no external fallback", VoiceService.built_in_device(["Default", "USB Microphone Array", "Virtual Internal Microphone"]).is_empty())
	check("no device stays unavailable", VoiceService.built_in_device([]).is_empty())
	var v := VoiceService.new()
	v.settings = GameSettings.new()
	v._mic_active = true # simulated state; never opens the hardware
	v._set_mic_state(&"opening")
	check("opening does not claim capture is ready", not v.can_capture())
	v._observe_input(PackedVector2Array([Vector2.ZERO]), 4.0)
	v._check_mic_health(4.0)
	check("silent PCM reports quiet rather than ready", v.mic_state() == &"quiet" and v.input_level() == 0.0)
	v._observe_input(PackedVector2Array([Vector2(0.03, -0.05)]), 4.1)
	check("sound recovers without reopening", v.mic_state() == &"ready" and v.can_capture() and is_equal_approx(v.input_level(), 0.05))
	v._check_mic_health(7.2)
	check("capture stalls detected even after earlier frames", v.mic_state() == &"no_signal" and not v.can_capture())
	v._observe_input(PackedVector2Array([Vector2(0.1, 0.1)]), 7.3)
	check("new sound clears stalled state", v.mic_state() == &"ready")
	v.settings.voice_mic_muted = true
	check("user mute always blocks transmission", not v.can_capture())
	v._mic_active = false
	v.free()
	var presets := ConfigFile.new()
	check("Windows export preset parses", presets.load("res://export_presets.cfg") == OK)
	check("only Windows export supported", presets.get_value("preset.0", "platform", "") == "Windows Desktop" and not presets.has_section("preset.1"))
	check("Windows voice libraries exist", FileAccess.file_exists("res://addons/twovoip/libs/libtwovoip.windows.template_debug.x86_64.dll")
		and FileAccess.file_exists("res://addons/twovoip/libs/libtwovoip.windows.template_release.x86_64.dll"))
	if OS.get_cmdline_user_args().has("--live"):
		await _live_check()
	print("RESULT %d/%d" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func _live_check() -> void:
	var v := VoiceService.new()
	root.add_child(v)
	v.setup(null, null, null)
	v.set_input_device("Headset Microphone (USB)")
	check("legacy external device selection is ignored", v.settings.voice_input_device == VoiceService.built_in_device(AudioServer.get_input_device_list()))
	var panel := VoiceSettingsPanel.new()
	panel.settings = v.settings
	panel.settings_path = ""
	panel.voice = v
	panel.setup(null)
	root.add_child(panel)
	panel.size = Vector2(600, 180)
	var peak := 0.0
	for i in 80:
		await create_timer(0.1).timeout
		peak = maxf(peak, v.input_level())
		panel.refresh()
	check("live built-in device selected", AudioServer.input_device == VoiceService.built_in_device(AudioServer.get_input_device_list()))
	check("live microphone delivers nonzero audio", peak > VoiceService.MIC_SILENCE_PEAK)
	check("live meter responds", panel.meter_value() > 0.0)
	check("device selector locked to built-in", panel.device_button().disabled and panel.device_button().item_count == 1)
	print("LIVE device=%s state=%s peak=%f rate=%d" % [AudioServer.input_device, v.mic_state(), peak, v._encoder_input_rate])
	v.set_mic_muted(true)
	check("muting closes capture and clears meter", not v._mic_active and is_zero_approx(v.input_level()))
	panel.free()
	v.free()
