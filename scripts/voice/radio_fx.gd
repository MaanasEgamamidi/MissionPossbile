extends Node
## Suit radio sound (owner 2026-11-15, UPGRADE_PATHS_PLAN.md §7.1): how a garbled, delayed radio voice sounds on the
## listener's computer, plus the clicks and the "no signal" beep. VoiceService makes one as its child.
## Loaded by path (no class_name): const RadioFx := preload("res://scripts/voice/radio_fx.gd")
##
## The Opus decoder (TwoVoIP's AudioStreamPlaybackOpus) turns packets into sound inside the engine, so the PCM is not
## touched in script. Instead, cheap engine effects on one dedicated bus, BUS ("SuitRadio", made at run time, sends to
## Master):
##   * radio EQ: high-pass 320 Hz and a low-pass that closes from 3400 Hz (clear) to 1600 Hz (garble 1);
##   * bit-crush: AudioEffectDistortion in LOFI mode, drive = garble * BITCRUSH_MAX;
##   * hiss: a looping half-second of white noise on the same bus while a garbled radio voice plays, louder with
##     garble;
##   * dropouts: VoiceService multiplies the voice's level by gate(), which mutes short random stretches (60-200 ms,
##     longer with garble) at a rate proportional to garble, each with a tiny crackle;
##   * a short squelch click at the start and the end of every radio utterance (clear ones too).
## A voice with garble 0 plays on Master exactly as before. All sounds are made in memory once; nothing is recorded.
## The bus is tuned to the garble of the newest radio utterance (each level has one garble value, so this is exact
## except for an utterance still in the radio across an upgrade).

const BUS := &"SuitRadio"
const MASTER := &"Master"
## Strongest bit-crush (AudioEffectDistortion.drive in LOFI mode: 0 = 16 bit, 1 = 2 bit).
const BITCRUSH_MAX := 0.75
const LOWPASS_CLEAR_HZ := 3400.0
const LOWPASS_GARBLED_HZ := 1600.0
const HIGHPASS_HZ := 320.0
## Hiss level (linear) at garble 0 and 1.
const HISS_MIN := 0.03
const HISS_MAX := 0.16
## Click level (linear).
const CLICK_LEVEL := 0.35
## Dropout check period, seconds; chance per check = garble * DROPOUT_CHANCE.
const DROPOUT_CHECK_S := 0.2
const DROPOUT_CHANCE := 0.3
const SYNTH_RATE := 22050

var _noise: AudioStreamPlayer
var _click: AudioStreamPlayer
var _crackle: AudioStreamPlayer
var _beep: AudioStreamPlayer
var _gates := {}             # out key -> {"until": seconds, "next": seconds}
var _hiss_garble := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	ensure_bus()
	_noise = _player("RadioHiss", _make_noise(0.5), BUS)
	_click = _player("RadioClick", _make_click(), MASTER)
	_crackle = _player("RadioCrackle", _make_click(), BUS)
	_beep = _player("RadioNoSignal", _make_beep(), MASTER)


func _player(n: String, stream: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.stream = stream
	p.bus = bus
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## The SuitRadio bus index (made on first use with its three effects).
static func ensure_bus() -> int:
	var idx := AudioServer.get_bus_index(BUS)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, MASTER)
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = HIGHPASS_HZ
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = LOWPASS_CLEAR_HZ
	var crush := AudioEffectDistortion.new()
	crush.mode = AudioEffectDistortion.MODE_LOFI
	crush.drive = 0.0
	crush.post_gain = -2.0
	AudioServer.add_bus_effect(idx, hp)
	AudioServer.add_bus_effect(idx, lp)
	AudioServer.add_bus_effect(idx, crush)
	return idx


## Tunes the bus for a garble amount (0..1).
func tune(garble: float) -> void:
	var g := clampf(garble, 0.0, 1.0)
	var idx := ensure_bus()
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectLowPassFilter:
			(fx as AudioEffectLowPassFilter).cutoff_hz = lerpf(LOWPASS_CLEAR_HZ, LOWPASS_GARBLED_HZ, g)
		elif fx is AudioEffectDistortion:
			(fx as AudioEffectDistortion).drive = g * BITCRUSH_MAX


## The bus a radio voice with this garble plays on.
static func bus_for(garble: float) -> StringName:
	return BUS if garble > 0.0 else MASTER


## Squelch click (start or end of a radio utterance, or keying the suit radio). `volume` = the voice volume (linear).
func click(volume := 1.0) -> void:
	if _click == null:
		return
	_click.volume_db = linear_to_db(maxf(CLICK_LEVEL * volume, 1e-5))
	_click.play()


## "No signal" double beep, played once per press on the speaker's own computer.
func no_signal_beep(volume := 1.0) -> void:
	if _beep == null:
		return
	_beep.volume_db = linear_to_db(maxf(0.4 * volume, 1e-5))
	_beep.play()


## Hiss while garbled radio voices play: `garble` = the strongest one playing now (0 = none, hiss off).
func set_hiss(garble: float, volume := 1.0) -> void:
	if _noise == null:
		return
	_hiss_garble = clampf(garble, 0.0, 1.0)
	if _hiss_garble <= 0.0:
		if _noise.playing:
			_noise.stop()
		return
	_noise.volume_db = linear_to_db(maxf(lerpf(HISS_MIN, HISS_MAX, _hiss_garble) * volume, 1e-5))
	if not _noise.playing:
		_noise.play()


## Level multiplier (0 or 1) for the radio voice `key` now: random short dropouts proportional to garble.
func gate(key: String, garble: float, now: float) -> float:
	if garble <= 0.0:
		_gates.erase(key)
		return 1.0
	var g: Dictionary = _gates.get(key, {})
	if g.is_empty():
		g = {"until": 0.0, "next": now + DROPOUT_CHECK_S}
		_gates[key] = g
	if now < float(g.until):
		return 0.0
	if now >= float(g.next):
		g.next = now + DROPOUT_CHECK_S
		if _rng.randf() < garble * DROPOUT_CHANCE:
			g.until = now + _rng.randf_range(0.06, 0.2) * (0.6 + garble)
			if _crackle != null:
				_crackle.volume_db = linear_to_db(CLICK_LEVEL * 0.5 * garble)
				_crackle.play()
			return 0.0
	return 1.0


## Forgets a voice's dropout timer (its utterance ended).
func forget(key: String) -> void:
	_gates.erase(key)


# ---------------------------------------------------------------- sounds made in memory

static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SYNTH_RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_noise(seconds: float) -> AudioStreamWAV:
	var n := roundi(seconds * SYNTH_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = _rng.randf_range(-1.0, 1.0) * 0.8
	return _wav(s, true)


## 40 ms squelch: a decaying noise burst over a short 1.2 kHz square tone.
func _make_click() -> AudioStreamWAV:
	var n := roundi(0.04 * SYNTH_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SYNTH_RATE
		var sq := 1.0 if sin(TAU * 1200.0 * t) >= 0.0 else -1.0
		s[i] = _rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.6 + sq * exp(-t * 60.0) * 0.25
	return _wav(s, false)


## Two falling tones (480 Hz, then 380 Hz), 120 ms each with a 60 ms gap: "no signal".
func _make_beep() -> AudioStreamWAV:
	var tone := 0.12
	var gap := 0.06
	var n := roundi((tone * 2.0 + gap) * SYNTH_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SYNTH_RATE
		var f := 0.0
		var local := 0.0
		if t < tone:
			f = 480.0
			local = t
		elif t >= tone + gap:
			f = 380.0
			local = t - tone - gap
		if f <= 0.0:
			continue
		# soft edges so the beep itself does not click
		var env := minf(1.0, minf(local, tone - local) / 0.01)
		s[i] = sin(TAU * f * t) * 0.6 * maxf(env, 0.0)
	return _wav(s, false)
