class_name VoiceService
extends Node
## Private voice for the colony (Prompt 11): open-mic capture, Opus encoding, sending over the game's own ENet
## session (NetSession.send_voice, channel 2), receiving, the timed buffer (VoiceScheduler), routing (VoiceRouter),
## decoding and playing. A presenter: GameMain adds it in _begin_play() and calls setup(world, services, game).
##
## Built on TwoVoIP 6.1 (MIT, addons/twovoip): the microphone and speaker logic is adapted from its helper scripts
## two_voip_mic.gd and two_voip_speaker.gd (Julian Todd and contributors), without their MQTT backend. The helper's
## catch-up (playing faster or slower with pitch_scale to steer the buffer) is NOT used: pitch_scale stays 1.0, so
## speech speed never changes and a radio delay is never shortened.
##
## Open mic (2026-11-15): voice chat is always on. While a game is running and the microphone is not muted, Opus
## frames go continuously to the other players of this session; no key needs to be held. Nothing is recorded or
## written to disk; buffers live in memory and are cleared on mute,
## on a player's disconnect and when the session ends. Without a microphone (none, blocked, or a headless run) the
## game plays on and listening still works. Voice keeps working while the game is paused.
## The extension's classes are looked up at run time (ClassDB) and every method is checked first, so a missing or
## different library leaves the game playable with voice off and a plain message.

const GROUP := &"voice_service"
## Tutorial (2026-11-14): crew voice is off until the T01 radio is fixed (scripts/voice/comms_gate.gd).
const CommsGate := preload("res://scripts/voice/comms_gate.gd")
## Suit radio (2026-11-15, UPGRADE_PATHS_PLAN.md §7.1): which route, no signal / delay / garble by the Communication
## level (suit_radio.gd), and how the garbled radio sounds (radio_fx.gd). Face to face inside is unchanged.
const SuitRadio := preload("res://scripts/voice/suit_radio.gd")
const RadioFx := preload("res://scripts/voice/radio_fx.gd")
## The speaker's "No signal" line stays this long after the press that triggered it, seconds.
const NO_SIGNAL_HOLD_S := 3.0
## Opus encoder settings (engineering): 64 kbit/s, complexity 10 (best quality), tuned for voice.
const OPUS_BITRATE := 64000
const OPUS_COMPLEXITY := 10
## The microphone stays open this long after the talk key is let go, so quick presses do not keep reopening it.
const MIC_HANG_S := 3.0
## An open microphone that gives no samples for this long is reported as "no signal".
const MIC_SIGNAL_TIMEOUT_S := 3.0
## Digital silence (including a Windows/hardware mute) is not proof that a microphone works.
const MIC_SILENCE_PEAK := 0.000001
## Retry unavailable/stalled capture and watch device/sample-rate changes at this interval, in seconds.
const MIC_RETRY_S := 5.0
## Height of a speaker's voice above their feet, metres (engineering).
const MOUTH_HEIGHT_M := 1.6
## A "heard" line stays this long after the last frame, seconds.
const HEARD_HOLD_S := 0.5
## The indoor/outdoor change note stays this long, seconds.
const TRANSITION_NOTE_S := 6.0
## Highest per-player and overall volume (linear; 5 = 500 %).
const VOLUME_MAX := 5.0
## Nearby voices play through AudioStreamPlayer3D, whose output Godot caps at max_db (+6 dB at most). To reach 500 %
## they play on this bus, which amplifies by BOOST_LINEAR, with their own volume divided by the same amount.
const BOOST_BUS := &"VoiceBoost"
const BOOST_LINEAR := 5.0

const ENCODER_CLASS := "TwovoipOpusEncoder"
const STREAM_CLASS := "AudioStreamOpus"
const PLAYBACK_CLASS := "AudioStreamPlaybackOpus"
const ENCODER_METHODS: PackedStringArray = ["create_sampler", "create_opus_encoder", "reset_opus_encoder",
	"calc_audio_chunk_size", "process_pre_encoded_chunk", "encode_chunk"]
const PLAYBACK_METHODS: PackedStringArray = ["push_opus_packet", "mark_end_opus_stream", "queue_length_frames",
	"available_space_frames"]

signal mic_state_changed(state: StringName)
signal transmitting_changed(on: bool)

var services: GameServices
var game: Node
var world: Node3D
## The player's settings (voice_input_device, voice_mic_muted, voice_volume). A private copy when none is given.
var settings: GameSettings
var scheduler := VoiceScheduler.new()
## Door portals (VoiceRouter) and the door controllers by id.
var portals: Array[Dictionary] = []
var doors: Dictionary = {}
## Counters for the HUD, the tests and the notes (in-process numbers only).
var counters := {"sent_frames": 0, "sent_packets": 0, "received_packets": 0, "bad_packets": 0, "decoded_frames": 0,
	"fec_frames": 0, "lost_frames": 0, "overflow_frames": 0, "utterances_sent": 0}
## Scheduler latency samples: seconds from a frame's arrival to its release (stage-4 style, no intentional delay).
var release_latency_s: Array[float] = []
## Tests: feed synthetic capture instead of a microphone (labelled synthetic; no microphone is used).
var synthetic_input := false
## Tests with every machine in ONE process (one clock): milliseconds from the speaker's send time (in the packet) to
## the frame's release into the player here. Meaningless between two computers, so it is off by default.
var measure_same_clock := false
var same_clock_latency_ms: Array[float] = []

var _library := false
var _library_problem := ""
var _encoder: Object
var _audio_chunk := 882
var _mic_state: StringName = &""
var _mic_active := false
var _mic_frames_seen := false
var _mic_last_frames := 0.0
var _mic_last_sound := 0.0
var _mic_device := ""
var _encoder_input_rate := 0
var _want_input_until := -1.0
var _meter_requests := 0
var _level := 0.0
var _ptt_override := -1
var _synthetic: Array[PackedVector2Array] = []
var _transmitting := false
var _stream_id := 0
var _seq := 0
var _utt_start_ms := 0
var _frame_index := 0
var _outs := {}                    # "peer|lane" -> VoiceOut
var _heard := {}                   # peer -> {"lane", "until", "delay_s", "start_local"}
var _unheard := {}                 # peer -> {"reason", "until", "seq"}
var _player_volume := {}           # peer -> 0..VOLUME_MAX (this session only)
var _player_muted := {}            # peer -> true (this session only)
var _arrived := {}                 # "peer|seq|index" -> arrival seconds, for release_latency_s (bounded)
var _was_online := false
var _last_outside := -1
var _transition_text := ""
var _transition_until := 0.0
var _peer_check_left := 0.0
var _fx: RadioFx                   # radio_fx.gd: the SuitRadio bus, clicks, hiss, dropouts, the no-signal beep
var _no_signal_until := -1.0       # the speaker's "No signal" line shows until then (once per press)
var _mic_retry_left := MIC_RETRY_S


## One speaker's player on one route. Proximity: AudioStreamPlayer3D at the speaker (no engine attenuation: the
## router's gain is the level). Radio: a plain AudioStreamPlayer.
class VoiceOut extends RefCounted:
	var peer := 0
	var lane: StringName = &""
	var player: Node
	var stream: AudioStream
	var playback: Object
	var waiting := true
	var pushed := 0
	var fec := 0
	var overflow := 0
	var seq := -1
	## Suit radio garble of the utterance playing now (0 = clear; proximity is always 0).
	var garble := 0.0

	func ensure_playing() -> void:
		var p := player
		if playback != null and p.get(&"playing"):
			return
		p.call(&"play")
		playback = p.call(&"get_stream_playback")
		waiting = true

	func begin(p_seq: int) -> void:
		seq = p_seq
		ensure_playing()
		waiting = true

	## Queues one frame. Returns false when the player's buffer is full (the frame is dropped).
	func push(packet: PackedByteArray, prefix: int, use_fec: bool) -> bool:
		ensure_playing()
		if playback == null:
			return false
		if int(playback.call(&"available_space_frames")) < VoiceScheduler.FRAME_SAMPLES:
			overflow += 1
			return false
		playback.call(&"push_opus_packet", packet, prefix, 1 if use_fec else 0)
		pushed += 1
		if use_fec:
			fec += 1
		_unpause_if_ready()
		return true

	func _unpause_if_ready() -> void:
		if waiting and playback != null and int(playback.call(&"queue_length_frames")) >= roundi(VoiceScheduler.PLAYBACK_TARGET_S * VoiceScheduler.SAMPLE_RATE):
			playback.call(&"mark_end_opus_stream", true)
			waiting = false

	## The utterance is over: play what is queued, then pause at its end.
	func finish() -> void:
		if playback == null:
			return
		if waiting and int(playback.call(&"queue_length_frames")) > 0:
			playback.call(&"mark_end_opus_stream", true)
		playback.call(&"mark_end_opus_stream", false)
		waiting = true

	## Drops everything queued at once (mute, disconnect, leaving).
	func stop() -> void:
		if player != null and is_instance_valid(player):
			player.call(&"stop")
		playback = null
		waiting = true

	func queued_frames() -> int:
		return int(playback.call(&"queue_length_frames")) if playback != null else 0


## The voice service of a scene tree, or null.
static func find(tree: SceneTree) -> VoiceService:
	return tree.get_first_node_in_group(GROUP) as VoiceService if tree != null else null


## The TwoVoIP GDExtension. Godot normally loads it from .godot/extension_list.cfg, but .godot/ is not in git, so a
## fresh clone or pull (and a run before the editor has rescanned) starts without it. ensure_library() loads it then.
const EXTENSION_PATH := "res://addons/twovoip/twovoip.gdextension"


## Loads the TwoVoIP extension at run time when Godot did not load it at startup. Safe to call more than once.
static func ensure_library() -> void:
	if ClassDB.class_exists(ENCODER_CLASS) or not FileAccess.file_exists(EXTENSION_PATH):
		return
	if GDExtensionManager.is_extension_loaded(EXTENSION_PATH):
		return
	var status := GDExtensionManager.load_extension(EXTENSION_PATH)
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		push_warning("Voice: could not load %s (status %d)." % [EXTENSION_PATH, status])


## Problems with the TwoVoIP library in this build ("" when every class and method needed is there).
static func library_problem() -> String:
	ensure_library()
	for cls: String in [ENCODER_CLASS, STREAM_CLASS, PLAYBACK_CLASS]:
		if not ClassDB.class_exists(cls):
			return "the class %s is missing" % cls
	for m: String in ENCODER_METHODS:
		if not ClassDB.class_has_method(ENCODER_CLASS, m):
			return "%s.%s is missing" % [ENCODER_CLASS, m]
	for m: String in PLAYBACK_METHODS:
		if not ClassDB.class_has_method(PLAYBACK_CLASS, m):
			return "%s.%s is missing" % [PLAYBACK_CLASS, m]
	for m: String in ["set_input_device_active", "get_input_frames", "get_input_frames_available"]:
		if not ClassDB.class_has_method("AudioServer", m):
			return "AudioServer.%s is missing" % m
	return ""


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS          # voice keeps working while the game is paused
	process_priority = -100                       # drain voice before ordinary gameplay work


## Presenter entry point. `world` may be null (tests); `game` is GameMain or null.
func setup(p_world: Node3D, p_services: GameServices, p_game: Node) -> void:
	world = p_world
	services = p_services
	game = p_game
	name = "VoiceService"
	if settings == null:
		var s: Variant = p_game.get(&"settings") if p_game != null else null
		settings = s as GameSettings if s is GameSettings else GameSettings.new()
	_stream_id = randi() & 0xffff
	# voice chat is always on: a mute left over from an earlier session does not carry into this one
	if settings.voice_mic_muted:
		settings.voice_mic_muted = false
	_library_problem = library_problem()
	_library = _library_problem == ""
	if _library:
		_make_encoder()
	_probe_mic()
	_build_portals()
	if _fx == null:
		_fx = RadioFx.new()
		_fx.name = "RadioFx"
		add_child(_fx)
	if services != null and services.net != null:
		var net := services.net
		if not net.voice_packet_received.is_connected(_on_voice_packet):
			net.voice_packet_received.connect(_on_voice_packet)
			net.peer_disconnected.connect(_on_peer_disconnected)
			net.host_lost.connect(func(_reason: String) -> void: _end_session("the host left"))
	if p_game != null and p_game.get(&"hud") is Node and is_instance_valid(p_game.get(&"hud")):
		var hud_widget := VoiceHud.new()
		hud_widget.name = "VoiceHud"
		(p_game.get(&"hud") as Node).add_child(hud_widget)
		hud_widget.setup(self)


func _exit_tree() -> void:
	_end_session("the game closed")
	_stop_mic()


func _make_encoder() -> void:
	_encoder = ClassDB.instantiate(ENCODER_CLASS)
	if _encoder == null:
		_library = false
		_library_problem = "the encoder could not be created"
		return
	var in_rate := int(AudioServer.get_input_mix_rate())
	_encoder_input_rate = in_rate
	# create_sampler(input mix rate, Opus sample rate, channels, noise suppression), as the TwoVoIP helper calls it
	var ok_sampler := bool(_encoder.call(&"create_sampler", in_rate, VoiceScheduler.SAMPLE_RATE, VoiceScheduler.CHANNELS, false))
	var ok_encoder := bool(_encoder.call(&"create_opus_encoder", OPUS_BITRATE, OPUS_COMPLEXITY, true))
	_audio_chunk = int(_encoder.call(&"calc_audio_chunk_size", VoiceScheduler.FRAME_SAMPLES))
	if not ok_sampler or not ok_encoder or _audio_chunk <= 0:
		_library = false
		_library_problem = "the Opus encoder did not start"
		_encoder = null


## Input frames per 20 ms Opus frame at this computer's input mix rate (882 at 44.1 kHz).
func audio_chunk_frames() -> int:
	return _audio_chunk


# ================================================================ microphone

func _probe_mic() -> void:
	if synthetic_input:
		_set_mic_state(&"synthetic")
	elif not _library:
		_set_mic_state(&"no_library")
	elif DisplayServer.get_name() == "headless":
		_set_mic_state(&"headless")
	elif not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		_set_mic_state(&"input_off")
	elif built_in_device(AudioServer.get_input_device_list()).is_empty():
		_set_mic_state(&"no_device")
	else:
		_set_mic_state(&"available")


## available/opening, ready (sound received), quiet (silent PCM), or a concrete capture failure.
func mic_state() -> StringName:
	return _mic_state


## True when this computer can send voice (a working or synthetic microphone, not muted).
func can_capture() -> bool:
	return _mic_state in [&"ready", &"quiet", &"synthetic"] and not mic_muted()


func mic_muted() -> bool:
	return settings != null and settings.voice_mic_muted


func set_mic_muted(on: bool) -> void:
	if settings != null:
		settings.voice_mic_muted = on
	if on:
		_stop_transmit()
		_stop_mic()
	else:
		retry_microphone()


## The microphone's state in words for the HUD and the voice settings.
func mic_state_text() -> String:
	if mic_muted():
		return "✖ Your microphone is muted. Others cannot hear you; you can still hear them."
	match _mic_state:
		&"available", &"opening":
			return "Opening the built-in microphone. Speak to check the input level."
		&"ready":
			return "✓ Built-in microphone receiving audio. Voice chat is on: just talk."
		&"quiet":
			return "✖ No sound detected. Speak, then check the microphone mute key and system input volume."
		&"synthetic":
			return "✓ Test sound instead of a microphone (synthetic input)."
		&"headless":
			return "✖ No microphone (the game is running without a screen). You can still listen."
		&"no_library":
			return "✖ Voice is off: the voice library did not load (%s). The game works without it." % _library_problem
		&"input_off":
			return "✖ No microphone: microphone input is switched off in this build. You can still listen."
		&"no_device":
			return "✖ Built-in microphone not found. Enable it in system sound settings. You can still listen."
		&"failed":
			return "✖ Microphone could not open. Check microphone permission in Windows settings. Retrying automatically."
		&"no_signal":
			return "✖ Microphone stopped delivering audio. Check system microphone access. Retrying automatically."
	return "✖ No microphone. You can still listen."


## Short form for the HUD.
func mic_short_text() -> String:
	if mic_muted():
		return "✖ Microphone muted"
	if _mic_state == &"quiet":
		return "✖ Microphone silent — check the system mute key"
	if _mic_state in [&"available", &"opening"]:
		return "Opening built-in microphone…"
	if can_capture():
		return ""
	return "✖ No microphone — you can still listen"


## Godot exposes endpoint names, not hardware form factors. Recognize the built-in endpoint names used by
## Windows laptop drivers; never fall back to Default, USB, Bluetooth or a virtual input.
static func built_in_device(devices: PackedStringArray) -> String:
	for device: String in devices:
		var label := device.to_lower().replace("_", " ").replace("-", " ")
		var external := false
		for word: String in ["usb", "bluetooth", "airpods", "headset", "iphone", "virtual", "webcam", "brio", "voicemeeter", "cable"]:
			if label.contains(word):
				external = true
				break
		if external:
			continue
		if label.contains("microphone array") or label.contains("internal mic") or label.contains("built in mic"):
			return device
	return ""


## Only the built-in microphone is offered, even if the system default changes to a headset.
func input_devices() -> PackedStringArray:
	var device := built_in_device(AudioServer.get_input_device_list())
	return PackedStringArray([device]) if device != "" else PackedStringArray()


## Older settings/callers cannot select an external microphone. Resolve the built-in input on this computer.
func set_input_device(_device: String) -> void:
	retry_microphone()


func retry_microphone() -> void:
	_stop_transmit()
	_stop_mic()
	if settings != null:
		settings.voice_input_device = built_in_device(AudioServer.get_input_device_list())
	_probe_mic()
	_mic_retry_left = MIC_RETRY_S
	if not mic_muted():
		_start_mic(_now())


## The voice settings ask for the level meter while they are open (the microphone opens; nothing is sent).
func request_meter(on: bool) -> void:
	_meter_requests = maxi(0, _meter_requests + (1 if on else -1))


## Peak level of the microphone over the last moment, 0..1.
func input_level() -> float:
	return _level


## Tests: holds (1) or releases (0) the talk key; -1 = read the real key.
func set_ptt_override(state: int) -> void:
	_ptt_override = state


## Tests: queues synthetic capture chunks of audio_chunk_frames() frames each (no microphone is used).
func inject_capture(chunk: PackedVector2Array) -> void:
	if synthetic_input:
		_synthetic.append(chunk)


func _set_mic_state(s: StringName) -> void:
	if s != _mic_state:
		_mic_state = s
		mic_state_changed.emit(s)


func _start_mic(now: float) -> void:
	if _mic_active or synthetic_input or _mic_state not in [&"available", &"ready", &"quiet", &"no_signal"] or mic_muted():
		return
	var device := built_in_device(AudioServer.get_input_device_list())
	if device.is_empty():
		_set_mic_state(&"no_device")
		return
	AudioServer.input_device = device
	if settings != null:
		settings.voice_input_device = device
	var err := AudioServer.set_input_device_active(true)
	if err != OK:
		_set_mic_state(&"failed")
		return
	_mic_active = true
	_mic_device = device
	_mic_frames_seen = false
	_mic_last_frames = now
	_mic_last_sound = now
	# Some drivers only report their actual input rate after opening the endpoint.
	if _encoder_input_rate != int(AudioServer.get_input_mix_rate()):
		_make_encoder()
	if not _library:
		_stop_mic()
		_set_mic_state(&"no_library")
		return
	_set_mic_state(&"opening")


## Looks for the microphone again every MIC_RETRY_S while it is missing or failed, so voice starts by itself once a
## microphone is plugged in or allowed.
func _retry_mic(delta: float) -> void:
	_mic_retry_left -= delta
	if _mic_retry_left > 0.0:
		return
	_mic_retry_left = MIC_RETRY_S
	if synthetic_input or not _library or mic_muted():
		return
	var device := built_in_device(AudioServer.get_input_device_list())
	if _mic_state in [&"failed", &"no_device", &"no_signal"] \
			or (_mic_active and (_mic_device != device or AudioServer.input_device != device \
			or _encoder_input_rate != int(AudioServer.get_input_mix_rate()))):
		retry_microphone()


func _stop_mic() -> void:
	_stop_transmit()
	if _mic_active:
		AudioServer.set_input_device_active(false)
	_mic_active = false
	_level = 0.0
	if _mic_state in [&"opening", &"ready", &"quiet", &"no_signal"]:
		_set_mic_state(&"available")


func _observe_input(chunk: PackedVector2Array, now: float) -> void:
	_mic_frames_seen = true
	_mic_last_frames = now
	var peak := 0.0
	for sample: Vector2 in chunk:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	_level = maxf(_level * 0.85, minf(peak, 1.0))
	if peak > MIC_SILENCE_PEAK:
		_mic_last_sound = now
		if not synthetic_input:
			_set_mic_state(&"ready")


func _check_mic_health(now: float) -> void:
	if not _mic_active or synthetic_input:
		return
	if now - _mic_last_frames > MIC_SIGNAL_TIMEOUT_S:
		_set_mic_state(&"no_signal")
		_stop_transmit()
	elif _mic_frames_seen and now - _mic_last_sound > MIC_SIGNAL_TIMEOUT_S:
		_set_mic_state(&"quiet")


## Open mic: voice chat is always on, so the microphone always wants to send (tests may override it).
func _ptt_held() -> bool:
	if _ptt_override >= 0:
		return _ptt_override == 1
	return true


func _next_chunk() -> PackedVector2Array:
	if synthetic_input:
		return _synthetic.pop_front() if not _synthetic.is_empty() else PackedVector2Array()
	# A driver may switch to Default when an endpoint disappears. Never consume that replacement input.
	if _mic_active and AudioServer.input_device != _mic_device:
		_stop_mic()
		_set_mic_state(&"no_device")
		return PackedVector2Array()
	if not _mic_active or AudioServer.get_input_frames_available() < _audio_chunk:
		return PackedVector2Array()
	return AudioServer.get_input_frames(_audio_chunk)


# ================================================================ sending

func is_transmitting() -> bool:
	return _transmitting


func _capture(now: float) -> void:
	if not _library or _encoder == null:
		return
	var held := _ptt_held()
	if (held or _meter_requests > 0) and not mic_muted():
		_want_input_until = now + MIC_HANG_S
	if now < _want_input_until and not mic_muted():
		_start_mic(now)
	elif _mic_active:
		_stop_mic()
	var talk := held and can_capture() and services != null and services.has_game() and services.local_character() != null and not comms_down()
	if talk and not _transmitting:
		_start_transmit()
		_on_press(now)
	var got_audio := false
	while true:
		var chunk := _next_chunk()
		if chunk.is_empty():
			break
		got_audio = true
		_observe_input(chunk, now)
		_encoder.call(&"process_pre_encoded_chunk", chunk, VoiceScheduler.FRAME_SAMPLES, false, false)
		if _transmitting:
			_send_frame()
	if not got_audio:
		_level *= 0.9
	_check_mic_health(now)
	if _transmitting and not talk:
		_stop_transmit()


## A new press of the talk key (not the restart of a very long hold): once per press, tell the speaker when the suit
## radio has no signal (line + beep), or key the suit radio with a click when it carries the voice.
func _on_press(now: float) -> void:
	var st := speaker_radio_status()
	var vol := settings.voice_volume if settings != null else 1.0
	if bool(st.no_signal):
		_no_signal_until = now + NO_SIGNAL_HOLD_S
		if _fx != null:
			_fx.no_signal_beep(vol)
	else:
		_no_signal_until = -1.0
		if bool(st.radio) and _fx != null:
			_fx.click(vol)


## What the local player's voice does now over the suit radio (SuitRadio.speaker_status), {} pieces filled with
## defaults when there is no game.
func speaker_radio_status() -> Dictionary:
	if services == null or not services.has_game() or services.local_character() == null:
		return {"radio": false, "no_signal": false, "delay_s": 0.0, "garble": 0.0, "nearby": 0}
	var st := services.state()
	var mine := services.local_peer()
	var others: Array = []
	for c: CharacterState in st.active_characters():
		if c.owner_peer != mine:
			others.append(SuitRadio.participant(st, c, services.zones))
	return SuitRadio.speaker_status(st, _listener(), others, services.zones, portals, door_openings())


func _character_id() -> String:
	var me := services.local_character() if services != null and services.has_game() else null
	return String(me.id) if me != null else ""


func _start_transmit() -> void:
	_seq = (_seq + 1) & 0xffff
	_utt_start_ms = Time.get_ticks_msec()
	_frame_index = 0
	_encoder.call(&"reset_opus_encoder")
	_send(VoiceScheduler.make_start(_stream_id, _seq, _utt_start_ms, _utt_start_ms, _character_id()), true)
	_transmitting = true
	counters.utterances_sent += 1
	transmitting_changed.emit(true)


func _send_frame() -> void:
	var prefix := VoiceScheduler.make_header(VoiceScheduler.KIND_FRAME, _stream_id, _seq, _frame_index, _utt_start_ms,
		Time.get_ticks_msec(), _character_id())
	var packet: PackedByteArray = _encoder.call(&"encode_chunk", prefix, 1.0)
	if packet.size() > prefix.size():
		_send(packet, false)
		counters.sent_frames += 1
	_frame_index += 1
	if _frame_index >= VoiceScheduler.MAX_UTTERANCE_FRAMES:
		# a very long hold becomes several utterances, so every buffer stays bounded
		_stop_transmit()
		_start_transmit()


func _stop_transmit() -> void:
	if not _transmitting:
		return
	var now_ms := Time.get_ticks_msec()
	_send(VoiceScheduler.make_end(_stream_id, _seq, _frame_index, _utt_start_ms, now_ms, _character_id()), true)
	_transmitting = false
	transmitting_changed.emit(false)


func _send(packet: PackedByteArray, reliable: bool) -> void:
	if services != null and services.net != null:
		services.net.send_voice(packet, reliable)
		counters.sent_packets += 1


# ================================================================ receiving

func _now() -> float:
	return float(Time.get_ticks_usec()) / 1e6


func _on_voice_packet(from_peer: int, packet: PackedByteArray) -> void:
	counters.received_packets += 1
	if services == null or not services.has_game() or from_peer == services.local_peer():
		return
	var h := VoiceScheduler.parse(packet)
	if h.is_empty():
		counters.bad_packets += 1
		return
	if is_player_muted(from_peer) or comms_down():
		return
	var now := _now()
	var stream := int(h.stream)
	var seq := int(h.seq)
	var kind := int(h.kind)
	match scheduler.classify(from_peer, stream, seq):
		&"old":
			var u: Dictionary = _unheard.get(from_peer, {})
			if not u.is_empty() and int(u.seq) == seq:
				u.until = now + HEARD_HOLD_S if kind != VoiceScheduler.KIND_END else now
			return
		&"new":
			var route := route_for(from_peer)
			var lane: StringName = route.route if route.route != VoiceRouter.ROUTE_NONE else &""
			# the suit radio's delay (real seconds) is applied here on the listener's side by the scheduler; its
			# garble rides in the utterance info to the player (radio_fx.gd)
			scheduler.open(from_peer, stream, seq, lane, now - VoiceScheduler.elapsed_s(h), float(route.delay_s),
				{"reason": route.reason, "character": h.character, "garble": float(route.get("garble", 0.0))}, now)
			if lane == &"":
				_unheard[from_peer] = {"reason": String(route.reason), "until": now + HEARD_HOLD_S, "seq": seq}
				return
	match kind:
		VoiceScheduler.KIND_FRAME:
			if scheduler.push_frame(from_peer, stream, seq, int(h.index), packet, int(h.header_len), now) == &"queued" and _arrived.size() < 4096:
				_arrived["%d|%d|%d" % [from_peer, seq, int(h.index)]] = now
		VoiceScheduler.KIND_END:
			scheduler.end(from_peer, stream, seq, int(h.index), now)


## The route from `peer`'s character to this machine's player now: face to face inside (VoiceRouter's proximity rule,
## unchanged) or the suit radio with its delay and garble (SuitRadio.decide, by the Communication level).
func route_for(peer: int) -> Dictionary:
	var st := services.state() if services != null and services.has_game() else null
	var speaker := st.character_of_peer(peer) if st != null else null
	if speaker == null:
		return {"route": VoiceRouter.ROUTE_NONE, "gain": 0.0, "delay_s": 0.0, "garble": 0.0, "reason": "unknown_speaker", "via_door": -1}
	var zones := services.zones
	return SuitRadio.decide(st, SuitRadio.participant(st, speaker, zones), _listener(), zones, portals, door_openings())


func _listener() -> Dictionary:
	var me := services.local_character() if services != null and services.has_game() else null
	if me == null:
		return {"id": &"", "position": Vector3(1e6, 0.0, 1e6), "outside": false, "zone": "(nobody)", "seated": false, "suit": false}
	return SuitRadio.participant(services.state(), me, services.zones)


## How far each known door is open now, by door id (0..1).
func door_openings() -> Dictionary:
	var out := {}
	for id: int in doors:
		var d: Variant = doors[id]
		if d is DoorController and is_instance_valid(d):
			out[id] = (d as DoorController).open_amount
	return out


func _build_portals() -> void:
	portals.clear()
	doors.clear()
	var zones := services.zones if services != null else null
	if zones == null:
		return
	if FileAccess.file_exists(GameServices.MANIFEST_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameServices.MANIFEST_PATH))
		if data is Dictionary:
			portals = VoiceRouter.portals_from_manifest(data, zones)
	var known := {}
	for p: Dictionary in portals:
		known[int(p.door_id)] = true
	for d: DoorController in _door_controllers():
		doors[d.door_id] = d
		if known.has(d.door_id):
			continue
		# a door the manifest does not list (the airlock doors): measure it from its leaves
		var centre := Vector3.ZERO
		var through := Vector3.ZERO
		var n := 0
		for leaf: Node in d.get_children():
			if leaf is AnimatableBody3D:
				centre += (leaf as Node3D).global_position if (leaf as Node3D).is_inside_tree() else d.transform * (leaf as Node3D).position
				through = (leaf as Node3D).global_basis.z if (leaf as Node3D).is_inside_tree() else (leaf as Node3D).basis.z
				n += 1
		if n == 0:
			continue
		var p := VoiceRouter.portal_from_door(d.door_id, centre / float(n), through, zones)
		if not p.is_empty():
			portals.append(p)
			known[d.door_id] = true


func _door_controllers() -> Array[DoorController]:
	var out: Array[DoorController] = []
	if game == null:
		return out
	var collision: Variant = game.get(&"collision")
	if collision is Node and (collision as Node).has_node("Doors"):
		for d: Node in (collision as Node).get_node("Doors").get_children():
			if d is DoorController:
				out.append(d)
	for key: StringName in [&"airlock_doors", &"garden_airlock_doors"]:
		var list: Variant = game.get(key)
		if list is Array:
			for d: Variant in list:
				if d is DoorController and is_instance_valid(d) and not out.has(d):
					out.append(d)
	return out


# ================================================================ playing

func _process(delta: float) -> void:
	var now := _now()
	_retry_mic(delta)
	_capture(now)
	_watch_session(delta)
	_play(now)
	_watch_transition(now)


func _play(now: float) -> void:
	for e: Dictionary in scheduler.pop_due(now):
		var peer := int(e.peer)
		var makes: bool = e.type == &"start" or e.type == &"frame"
		var out: VoiceOut = _out_for(peer, e.lane) if makes else _outs.get("%d|%s" % [peer, e.lane]) as VoiceOut
		if out == null:
			continue
		match e.type:
			&"start":
				out.begin(int(e.seq))
				if out.lane == VoiceRouter.ROUTE_RADIO:
					_radio_begin(out, e)
			&"frame":
				var key := "%d|%d|%d" % [peer, int(e.seq), int(e.index)]
				if _arrived.has(key):
					if float(e.delay_s) <= 0.0 and not bool(e.fec) and release_latency_s.size() < 2000:
						release_latency_s.append(now - float(_arrived[key]))
					_arrived.erase(key)
				if measure_same_clock and not bool(e.fec) and same_clock_latency_ms.size() < 4000:
					var sent := (e.packet as PackedByteArray).decode_u32(14)
					same_clock_latency_ms.append(float((Time.get_ticks_msec() - sent) & 0xffffffff))
				if out.push(e.packet, int(e.prefix), bool(e.fec)):
					counters.decoded_frames += 1
					if bool(e.fec):
						counters.fec_frames += 1
				else:
					counters.overflow_frames += 1
				_heard[peer] = {"lane": e.lane, "until": now + HEARD_HOLD_S, "delay_s": float(e.delay_s), "start_local": float(e.start_local),
					"garble": out.garble}
			&"lost":
				counters.lost_frames += 1
			&"end":
				match StringName(e.reason):
					&"footer", &"timeout":
						out.finish()
					_:
						out.stop()
				if out.lane == VoiceRouter.ROUTE_RADIO:
					_radio_end(out)
	_apply_levels()


## A suit radio utterance starts playing here: its bus (garbled -> SuitRadio, clear -> Master), the bus tuning and the
## squelch click.
func _radio_begin(out: VoiceOut, e: Dictionary) -> void:
	var info: Dictionary = e.get("info", {})
	out.garble = clampf(float(info.get("garble", 0.0)), 0.0, 1.0)
	out.player.set(&"bus", RadioFx.bus_for(out.garble))
	if _fx != null:
		if out.garble > 0.0:
			_fx.tune(out.garble)
		_fx.click(settings.voice_volume if settings != null else 1.0)


## A suit radio utterance ended (or was cleared): the closing click; its hiss and dropouts stop.
func _radio_end(out: VoiceOut) -> void:
	out.garble = 0.0
	if _fx != null:
		_fx.forget("%d|%s" % [out.peer, out.lane])
		_fx.click(settings.voice_volume if settings != null else 1.0)


## Sets each player's level and position: the router's gain for proximity (re-read every frame), and the volumes.
func _apply_levels() -> void:
	var master := settings.voice_volume if settings != null else 1.0
	var now := _now()
	var hiss := 0.0
	for key: String in _outs:
		var out: VoiceOut = _outs[key]
		var vol := master * player_volume(out.peer)
		var gain := 1.0
		if out.lane == VoiceRouter.ROUTE_RADIO and out.garble > 0.0 and _fx != null:
			# suit radio garble: short random dropouts, and the hiss while it plays
			gain = _fx.gate(key, out.garble, now)
			if bool(out.player.get(&"playing")):
				hiss = maxf(hiss, out.garble)
		if out.lane == VoiceRouter.ROUTE_PROXIMITY:
			var r := route_for(out.peer)
			# the utterance keeps its proximity route; if the pair is no longer both inside, it simply fades out
			gain = float(r.gain) if r.route == VoiceRouter.ROUTE_PROXIMITY else 0.0
			var st := services.state()
			var c := st.character_of_peer(out.peer) if st != null else null
			if c != null and out.player is Node3D and (out.player as Node3D).is_inside_tree():
				var pos: Vector3 = VoiceRouter.participant(st, c, services.zones).position
				(out.player as Node3D).global_position = pos + Vector3(0.0, MOUTH_HEIGHT_M, 0.0)
		var level := gain * vol
		if out.player is AudioStreamPlayer3D:
			level /= BOOST_LINEAR  # the VoiceBoost bus multiplies it back
		out.player.set(&"volume_db", linear_to_db(maxf(level, 1e-5)))
	if _fx != null:
		_fx.set_hiss(hiss, master)


## The VoiceBoost bus (made on first use): one Amplify effect of BOOST_LINEAR, sending to Master.
static func _ensure_boost_bus() -> StringName:
	if AudioServer.get_bus_index(BOOST_BUS) >= 0:
		return BOOST_BUS
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BOOST_BUS)
	AudioServer.set_bus_send(idx, &"Master")
	var amp := AudioEffectAmplify.new()
	amp.volume_db = linear_to_db(BOOST_LINEAR)
	AudioServer.add_bus_effect(idx, amp)
	return BOOST_BUS


func _out_for(peer: int, lane: StringName) -> VoiceOut:
	var key := "%d|%s" % [peer, lane]
	if _outs.has(key):
		return _outs[key]
	if not _library:
		return null
	var stream := ClassDB.instantiate(STREAM_CLASS) as AudioStream
	if stream == null:
		return null
	stream.set(&"opus_sample_rate", VoiceScheduler.SAMPLE_RATE)
	stream.set(&"opus_channels", VoiceScheduler.CHANNELS)
	var out := VoiceOut.new()
	out.peer = peer
	out.lane = lane
	out.stream = stream
	if lane == VoiceRouter.ROUTE_PROXIMITY:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p3.max_distance = 0.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.max_db = 6.0
		p3.bus = _ensure_boost_bus()
		p3.stream = stream
		out.player = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		out.player = p2
	out.player.name = "Voice_%d_%s" % [peer, lane]
	out.player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(out.player)
	_outs[key] = out
	return out


## Players currently playing a lane of `peer` (tests and the HUD).
func outs_of(peer: int) -> Array:
	var out := []
	for key: String in _outs:
		if (_outs[key] as VoiceOut).peer == peer:
			out.append(_outs[key])
	return out


# ================================================================ players: volume, mute, leaving

## Other players in this session: [{"peer", "name", "volume", "muted"}].
func player_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if services == null or not services.has_game():
		return rows
	var mine := services.local_peer()
	for peer: int in services.session.peers:
		if peer == mine:
			continue
		var c := services.state().character_of_peer(peer)
		rows.append({"peer": peer, "name": c.display_name if c != null else "Player %d" % peer,
			"volume": player_volume(peer), "muted": is_player_muted(peer)})
	return rows


func player_volume(peer: int) -> float:
	return float(_player_volume.get(peer, 1.0))


func set_player_volume(peer: int, v: float) -> void:
	_player_volume[peer] = clampf(v, 0.0, VOLUME_MAX)


func is_player_muted(peer: int) -> bool:
	return bool(_player_muted.get(peer, false))


## Mutes or unmutes one player for this session. Muting clears everything of theirs that is waiting or playing.
func set_player_muted(peer: int, on: bool) -> void:
	if on:
		_player_muted[peer] = true
		_clear_peer(peer, "muted", false)
	else:
		_player_muted.erase(peer)


func _clear_peer(peer: int, reason: String, forget: bool) -> void:
	if forget:
		scheduler.forget_speaker(peer, reason)
		_player_volume.erase(peer)
		_player_muted.erase(peer)
	else:
		scheduler.clear_speaker(peer, reason)
	for out: VoiceOut in outs_of(peer):
		out.stop()
	_heard.erase(peer)
	_unheard.erase(peer)
	for key: String in _arrived.keys():
		if key.begins_with("%d|" % peer):
			_arrived.erase(key)


func _on_peer_disconnected(peer: int) -> void:
	_clear_peer(peer, "left the colony", true)


## Clears every buffer and player (leaving the session or closing the game).
func _end_session(reason: String) -> void:
	_stop_transmit()
	scheduler.clear_all(reason)
	scheduler.pop_due(_now())       # the end events of what was cleared; the players stop below
	for key: String in _outs:
		(_outs[key] as VoiceOut).stop()
	_heard.clear()
	_unheard.clear()
	_arrived.clear()
	_player_volume.clear()
	_player_muted.clear()


## Clients do not get a disconnect signal for other clients: compare with the session's player list.
func _watch_session(delta: float) -> void:
	var online := services != null and services.net != null and services.net.is_online()
	if _was_online and not online:
		_end_session("the session ended")
	_was_online = online
	_peer_check_left -= delta
	if _peer_check_left > 0.0 or services == null or not services.has_game():
		return
	_peer_check_left = 0.5
	var peers: Array[int] = services.session.peers
	for p: int in scheduler.speakers():
		if not peers.has(p):
			_clear_peer(p, "left the colony", true)


# ================================================================ words for the HUD

## Old radio card stage (0..4, CommsStage). The voice path no longer uses it: the suit radio follows the
## Communication level (suit_radio_level()).
func stage() -> int:
	return CommsStage.stage(services.state()) if services != null and services.has_game() else 0


## Communication level that drives the suit radio (AreaLevels "command"), 1 without a game.
func suit_radio_level() -> int:
	return SuitRadio.level(services.state()) if services != null and services.has_game() else 1


## Number of other players outside right now.
func crew_outside() -> int:
	if services == null or not services.has_game():
		return 0
	var n := 0
	var mine := services.local_peer()
	for c: CharacterState in services.state().active_characters():
		if c.owner_peer != mine and bool(VoiceRouter.participant(services.state(), c, services.zones).outside):
			n += 1
	return n


func _me_outside() -> bool:
	return bool(_listener().outside)


## Demo build: crew voice is never cut off (the tutorial radio gate is ignored); see own_line for the label.
func comms_down() -> bool:
	return false


## Voice chat is always on (open mic); the corner never reads "off".
func voice_label_off() -> bool:
	return false


## The local player's own line: what their voice does now (talking) or would do (idle).
func own_line() -> String:
	var short := mic_short_text()
	if short != "":
		return short
	if _transmitting or _now() < _no_signal_until:
		var status := speaker_radio_status()
		# the "No signal" line of this press stays for NO_SIGNAL_HOLD_S even after a quick press
		if _now() < _no_signal_until:
			status.no_signal = true
		var text := SuitRadio.speaking_text(status)
		if _transmitting and services != null and services.net != null and not services.net.is_online():
			text += " (playing alone: nobody else is here)"
		return text
	if services == null or not services.has_game():
		return "Voice chat is on: people near you hear you."
	return SuitRadio.idle_text(services.state(), _listener(), services.zones)


## Lines about other players: heard now, waiting in the radio, or talking with no route to this player.
func heard_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var now := _now()
	var st := services.state() if services != null and services.has_game() else null
	if st == null:
		return out
	for peer: int in _heard.keys():
		var h: Dictionary = _heard[peer]
		if now > float(h.until):
			_heard.erase(peer)
			continue
		out.append(SuitRadio.heard_text(_name_of(peer), h.lane, now - float(h.start_local) if float(h.delay_s) >= 1.0 else 0.0,
			float(h.get("garble", 0.0))))
	for u: Dictionary in scheduler.utterances():
		if not bool(u.started) and String(u.lane) == String(VoiceRouter.ROUTE_RADIO) and float(u.due0) - now >= 1.0:
			out.append(SuitRadio.pending_text(_name_of(int(u.peer)), float(u.due0) - now))
	for peer: int in _unheard.keys():
		var u: Dictionary = _unheard[peer]
		if now > float(u.until):
			_unheard.erase(peer)
			continue
		var line := SuitRadio.unheard_text(_name_of(peer), String(u.reason))
		if line != "":
			out.append(line)
	return out


## The note shown for a few seconds after going outside or coming in ("" when none).
func transition_line() -> String:
	return _transition_text if _now() < _transition_until else ""


func _watch_transition(now: float) -> void:
	if services == null or not services.has_game() or services.local_character() == null:
		_last_outside = -1
		return
	var outside := 1 if _me_outside() else 0
	if _last_outside >= 0 and outside != _last_outside:
		_transition_text = SuitRadio.transition_text(services.state(), outside == 1)
		_transition_until = now + TRANSITION_NOTE_S
	_last_outside = outside


func _name_of(peer: int) -> String:
	var c := services.state().character_of_peer(peer) if services != null and services.has_game() else null
	return c.display_name if c != null else "Player %d" % peer
