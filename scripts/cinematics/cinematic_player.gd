extends Node
## Plays one cinematic sequence (the new-game intro or the "base operational" tour) on THIS machine only (Prompt Pack
## V01). It never changes colony state: the host simulation, hazards and every other player carry on. While it plays:
##   * its own Camera3D is current; the player's camera, HUD and controls come back on every exit (done, skip, danger,
##     disconnect, the presenter leaving the tree);
##   * the local player body takes no keys or mouse (it stands still where it is; nothing protects it, so the
##     presenter only starts when the player is safe and this node stops at once if they come into danger);
##   * the rooms on the camera's path are woken through the perf ZoneManager's own API (the way ShaderWarmup tours the
##     map): the manager and the ExteriorController are paused, the zones the segment needs are set WARM (seen-through
##     rooms VIEW_ONLY) and the rest COLD, and the manager clears hidden zone layers from this camera as from any
##     current camera. On exit both are resumed and ZoneManager.snap() puts every room back for the player;
##   * E, Space or Esc skips (that key is then held away from the player until it is let go).
##   * Narrator (owner 2026-11-15: "add a narrator speaking during the first cutscene before the player gets a chance
##     to actually move"): in the new-game intro only (NARRATED_SEQUENCES), each Mission Control caption is read aloud
##     by the computer's own text-to-speech voice (scripts/voice/narration.gd, no audio files) the moment it appears.
##     When a line is longer than its caption window, the caption WAITS for the voice: the camera slows and then holds
##     just before the caption's "until" (never inside the fade to black), for at most NARRATION_HOLD_MAX_S per line,
##     so the story is never cut mid-sentence. Skipping (or any other stop) stops the voice at once. With the voice off
##     or unavailable, timing is exactly as authored in data/cinematics.json.

signal finished(reason: StringName)

const Rail := preload("res://scripts/cinematics/cinematic_rail.gd")
const Narration := preload("res://scripts/voice/narration.gd")
## Sequences whose captions the narrator reads (the tour's room labels are not story lines).
const NARRATED_SEQUENCES: Array[String] = ["intro"]
const NARRATION_KIND := &"narrator"
## The camera slows to this share of normal speed in the last NARRATION_SLOW_S before a caption would end while its
## line is still being read, then holds; a line holds the timeline for at most NARRATION_HOLD_MAX_S (design balance).
const NARRATION_SLOW_RATE := 0.35
const NARRATION_SLOW_S := 1.0
const NARRATION_HOLD_MAX_S := 12.0
## Between GameHud (10) and UiRoot (20): menus and the critical alert banner stay on top.
const OVERLAY_LAYER := 15
## Every render layer (1..20): zones, the first-person-hidden layer (so the player's own head shows) and the sun layer.
const ALL_LAYERS := (1 << 20) - 1
const SKIP_ACTIONS: Array[StringName] = [&"interact", &"jump", &"back"]
## Health below this, or a suit tank below this while outside, counts as danger (design balance; GameHud's urgent levels).
const DANGER_HEALTH := 30.0
const DANGER_SUIT_CHARGE := 10.0
## Letterbox bars, share of the screen height each.
const BAR_SHARE := 0.11

var game: Node
var services: GameServices
var settings: GameSettings
var seq: Dictionary = {}
var playing := false
## Why the last run ended: &"done", &"skipped" or a danger reason (&"danger", &"disconnected", &"recovered"...).
var result: StringName = &""
var seg_index := 0
var seg_time := 0.0
var in_end_card := false
var end_card_left := 0.0
var camera: Camera3D
## What is on screen now (tests read these).
var caption_text := ""
var caption_speaker := ""
## Zone names woken for the current segment.
var woken: PackedStringArray = []
## Reduced motion (settings): each segment is a still frame at its last key.
var still := false

var _zm: Node                    # ZoneManager (perf), or null
var _paused: Array[Node] = []
var _hold_keys := false          # a skip key is still down after the end: keep it away from the player
var _overlay: CanvasLayer
var _fade: ColorRect
var _bars: Array[ColorRect] = []
var _caption: Label
var _speaker: Label
var _hint: Label
var _card: Label
var _card_sub: Label
var _fade_out_left := 0.0
## The narrator reads this run's captions; the caption index it is reading (-1: none yet in this segment).
var _narrate := false
var _spoken_caption := -1
var _hold_spent := 0.0


func _ready() -> void:
	process_priority = 100          # after GameMain._process, which sets player.input_enabled every frame
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts `p_seq`. Returns false (and plays nothing) when it has no segments.
func play(p_seq: Dictionary, p_game: Node, p_services: GameServices, p_settings: GameSettings = null) -> bool:
	if playing or Rail.segments(p_seq).is_empty():
		return false
	seq = p_seq
	game = p_game
	services = p_services
	settings = p_settings
	still = settings != null and settings.reduce_motion
	result = &""
	playing = true
	in_end_card = false
	_hold_keys = false
	_narrate = NARRATED_SEQUENCES.has(String(seq.get("id", ""))) and _narration().can_speak()
	_spoken_caption = -1
	_hold_spent = 0.0
	camera = Camera3D.new()
	camera.name = "CinematicCamera"
	camera.near = 0.05
	camera.far = 4000.0
	camera.cull_mask = ALL_LAYERS
	add_child(camera)
	var pc := _player_camera()
	if pc != null:
		camera.environment = pc.environment
		camera.attributes = pc.attributes
	camera.current = true
	_build_overlay()
	_pause_perf()
	var hud := game.get("hud") as GameHud if game != null else null
	if hud != null:
		hud.set_visible_hud(false)
	if services != null and not services.events.character_recovered.is_connected(_on_recovered):
		services.events.character_recovered.connect(_on_recovered)
	_enter_segment(0)
	_block_player()
	return true


func is_playing() -> bool:
	return playing


## The segment on screen now ({} during the end card).
func segment() -> Dictionary:
	var segs := Rail.segments(seq)
	return segs[seg_index] if not in_end_card and seg_index < segs.size() else {}


## Skip (E, Space, Esc). The tour still says "Base operational" as a subtitle.
func skip() -> void:
	if not playing:
		return
	var card: Dictionary = seq.get("end_card", {})
	var ui := game.get("ui") as UiRoot if game != null else null
	if not card.is_empty() and ui != null:
		ui.show_subtitle("%s. %s" % [String(card.get("text", "")), String(card.get("sub", ""))], 5.0, "", true)
	stop(&"skipped")


## Ends playback and gives everything back. Safe to call more than once.
func stop(reason: StringName) -> void:
	if not playing:
		return
	playing = false
	result = reason
	if _narrate:
		_narration().stop(NARRATION_KIND)
	_narrate = false
	_spoken_caption = -1
	if camera != null:
		camera.current = false
	var p := _player()
	if p != null:
		p.set_first_person(p.is_first_person())      # gives the player's own camera back (as the drone does)
	_resume_perf()
	var hud := game.get("hud") as GameHud if game != null and is_instance_valid(game) else null
	var ui := game.get("ui") as UiRoot if game != null and is_instance_valid(game) else null
	if hud != null:
		hud.set_visible_hud(ui == null or not ui.is_open())
	if services != null and services.events.character_recovered.is_connected(_on_recovered):
		services.events.character_recovered.disconnect(_on_recovered)
	_hold_keys = _skip_key_down()
	if p != null:
		p.input_enabled = not _hold_keys and (ui == null or ui.gameplay_has_focus())
	if camera != null:
		camera.queue_free()
		camera = null
	caption_text = ""
	caption_speaker = ""
	# a short fade from black on the player's own view, then the overlay goes
	_fade_out_left = 0.0 if reason != &"done" and reason != &"skipped" else _fade_seconds()
	if _overlay != null:
		var parts: Array = [_caption, _speaker, _hint, _card, _card_sub]
		parts.append_array(_bars)
		for n: Variant in parts:
			if n is Control:
				(n as Control).visible = false
		if _fade_out_left <= 0.0:
			_overlay.queue_free()
			_overlay = null
	finished.emit(reason)


func _exit_tree() -> void:
	if playing:
		stop(&"removed")


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if not playing:
		if _hold_keys:
			if _skip_key_down():
				_block_player()
			else:
				_hold_keys = false
		if _overlay != null and _fade_out_left > 0.0:
			_fade_out_left -= delta
			_fade.color.a = clampf(_fade_out_left / _fade_seconds(), 0.0, 1.0)
			if _fade_out_left <= 0.0:
				_overlay.queue_free()
				_overlay = null
		return
	var why := danger_reason()
	if why != &"":
		stop(why)
		return
	_block_player()
	advance(delta)


## Moves playback on by `delta` seconds (tests call this directly).
func advance(delta: float) -> void:
	if not playing:
		return
	var segs := Rail.segments(seq)
	if in_end_card:
		end_card_left -= delta
		_fade.color.a = 0.45       # dim the last view so the card reads
		if end_card_left <= 0.0:
			stop(&"done")
		return
	var seg: Dictionary = segs[seg_index]
	var length := Rail.seg_seconds(seg)
	seg_time += _narration_step(seg, length, delta)
	if seg_time >= length:
		if seg_index + 1 < segs.size():
			_enter_segment(seg_index + 1)
			seg = segs[seg_index]
			length = Rail.seg_seconds(seg)
		elif not (seq.get("end_card", {}) as Dictionary).is_empty():
			_enter_end_card()
			return
		else:
			stop(&"done")
			return
	camera.global_transform = Rail.pose(seg, seg_time, still)
	_update_caption(seg)
	# fade through black at every cut (and in from black at the very start)
	var fade := _fade_seconds()
	var a := 0.0
	if seg_time < fade:
		a = 1.0 - seg_time / fade
	if length - seg_time < fade:
		a = maxf(a, 1.0 - (length - seg_time) / fade)
	_fade.color.a = clampf(a, 0.0, 1.0)


func _enter_segment(i: int) -> void:
	seg_index = i
	seg_time = 0.0
	_spoken_caption = -1
	_hold_spent = 0.0
	var seg: Dictionary = Rail.segments(seq)[i]
	camera.fov = float(seg.get("fov", float((Rail.data().get("camera", {}) as Dictionary).get("fov", 62.0))))
	camera.global_transform = Rail.pose(seg, 0.0, still)
	_wake_for(seg)
	_update_caption(seg)


func _enter_end_card() -> void:
	in_end_card = true
	var card: Dictionary = seq.get("end_card", {})
	end_card_left = float(card.get("seconds", 3.0))
	caption_text = String(card.get("text", ""))
	caption_speaker = ""
	if _card != null:
		_card.text = caption_text
		_card_sub.text = String(card.get("sub", ""))
		_card.visible = true
		_card_sub.visible = true
		_caption.visible = false
		_speaker.visible = false


func _update_caption(seg: Dictionary) -> void:
	var text := String(seg.get("caption", ""))
	var speaker := ""
	var index := 0 if text != "" else -1
	if seg.has("captions"):
		text = ""
		index = -1
		var caps: Array = seg.captions
		for ci in caps.size():
			var c: Dictionary = caps[ci]
			if seg_time >= float(c.get("t", 0.0)) and seg_time < float(c.get("until", 1e9)):
				text = String(c.get("text", ""))
				speaker = String(c.get("speaker", ""))
				index = ci
	caption_text = text
	caption_speaker = speaker
	# The narrator starts each line the moment its caption appears.
	if _narrate and index >= 0 and index != _spoken_caption and text != "":
		_spoken_caption = index
		_hold_spent = 0.0
		_narration().say(text, NARRATION_KIND)
	if _caption != null:
		_caption.text = text
		_caption.visible = text != ""
		_speaker.text = speaker.to_upper()
		_speaker.visible = speaker != "" and text != ""


# ---------------------------------------------------------------- narrator

func _narration() -> Narration:
	return Narration.shared() as Narration


## How far the timeline moves this frame: `delta`, unless the narrator is still reading a line whose caption is about
## to end. Then the camera slows and holds just before the caption's "until" (and before the cut's fade to black) until
## the voice finishes, or NARRATION_HOLD_MAX_S has passed for this line.
func _narration_step(seg: Dictionary, length: float, delta: float) -> float:
	if not _narrate or _spoken_caption < 0 or _hold_spent >= NARRATION_HOLD_MAX_S:
		return delta
	if not _narration().is_speaking(NARRATION_KIND):
		return delta
	var until := length
	var caps: Array = seg.get("captions", [])
	if _spoken_caption < caps.size():
		until = float((caps[_spoken_caption] as Dictionary).get("until", length))
	var hold_at := minf(until, length - _fade_seconds()) - 0.02
	if seg_time + delta < hold_at - NARRATION_SLOW_S:
		return delta
	_hold_spent += delta
	return clampf(minf(delta * NARRATION_SLOW_RATE, hold_at - seg_time), 0.0, delta)


# ---------------------------------------------------------------- safety

## Why playback must stop now, or &"" while it is safe to go on.
func danger_reason() -> StringName:
	if services == null or not services.has_game():
		return &"disconnected"
	var p := _player()
	if p == null:
		return &"no_player"
	return vitals_danger(services.local_character())


## &"danger" when this astronaut is hurt, exposed or nearly out of suit air; &"no_player" without one; else &"".
static func vitals_danger(me: CharacterState) -> StringName:
	if me == null:
		return &"no_player"
	if me.health < DANGER_HEALTH or me.exposure_active or me.lethal_exposure_seconds > 0.0:
		return &"danger"
	if me.outside and me.suit_on and me.suit_charge < DANGER_SUIT_CHARGE:
		return &"danger"
	return &""


func _on_recovered(character_id: StringName, _info: Dictionary) -> void:
	var me := services.local_character() if services != null else null
	if me != null and me.id == character_id:
		stop(&"recovered")


func _block_player() -> void:
	var p := _player()
	if p != null:
		p.input_enabled = false


func _skip_key_down() -> bool:
	for a: StringName in SKIP_ACTIONS:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventMouseMotion:
		if event.is_pressed() and not event.is_echo():
			for a: StringName in SKIP_ACTIONS:
				if InputMap.has_action(a) and event.is_action_pressed(a):
					get_viewport().set_input_as_handled()
					skip()
					return
		# nothing else reaches the game (no pause menu, map or panels) while the camera is away
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- rooms: the perf ZoneManager's API

func _pause_perf() -> void:
	_paused.clear()
	_zm = get_tree().get_first_node_in_group(&"zone_manager") if is_inside_tree() else null
	if _zm != null and not bool(_zm.get("is_graph_ready")):
		_zm = null
	if _zm == null:
		return
	_paused.append(_zm)
	var ec := get_tree().get_first_node_in_group(&"exterior_controller")
	if ec != null:
		_paused.append(ec)
	for n in _paused:
		n.set_process(false)


func _resume_perf() -> void:
	for n in _paused:
		if is_instance_valid(n):
			n.set_process(true)
	_paused.clear()
	if _zm != null and is_instance_valid(_zm):
		_zm.call(&"snap")        # every room back to what the player's own position needs, at once
	_zm = null
	woken = PackedStringArray()


## Wakes what a segment shows and puts the rest to sleep, through Zone.apply_immediately (as ShaderWarmup does).
func _wake_for(seg: Dictionary) -> void:
	var zones := services.zones if services != null else null
	if zones == null:
		woken = PackedStringArray()
		return
	woken = Rail.wake_zones(seg, zones)
	if _zm == null:
		return
	var want := {}
	var hops := 2
	var perf_cfg: Variant = Perf.cfg() if get_node_or_null("/root/PerfSettings") != null else null
	if perf_cfg != null:
		hops = int(perf_cfg.get("glass_view_hops"))
	for zname in woken:
		var z: Node = _zm.call(&"zone", zname)
		if z == null:
			continue
		want[z] = Zone.State.WARM
		for seen: Node in _zm.call(&"zones_visible_through_open_doors", z, hops):
			if not want.has(seen):
				want[seen] = Zone.State.VIEW_ONLY
	for z: Zone in _zm.get("zones"):
		z.apply_immediately(int(want.get(z, Zone.State.COLD)))
	# Mars itself (terrain, rocks, the sun's layer for outdoor shots): show it if a segment looks outside.
	var outdoors := bool(seg.get("exterior", false)) or woken.has(ColonyZones.EXTERIOR) or woken.has(ColonyZones.GARDEN) or woken.has(ColonyZones.PLAZA)
	var ec: Node = _paused[1] if _paused.size() > 1 else null
	if outdoors and ec != null and not bool(ec.get("shown")) and ec.has_method(&"_set_shown"):
		ec.call(&"_set_shown", true)


## Render-layer bits the zones of the current segment need (tests compare them with camera.cull_mask).
func needed_bits() -> int:
	var bits := 0
	if services != null and services.zones != null:
		for zname in woken:
			bits |= services.zones.bit_of(zname)
	return bits


# ---------------------------------------------------------------- helpers

func _player() -> PlayerController:
	if game == null or not is_instance_valid(game):
		return null
	var p: Variant = game.get("player")
	return p as PlayerController if p is PlayerController and is_instance_valid(p) else null


func _player_camera() -> Camera3D:
	var p := _player()
	return p.camera_rig().camera() if p != null and p.camera_rig() != null else null


func _fade_seconds() -> float:
	return maxf(0.05, float((Rail.data().get("camera", {}) as Dictionary).get("fade_s", 0.45)))


func _text_scale() -> float:
	return settings.text_scale if settings != null else 1.0


func _build_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = CanvasLayer.new()
	_overlay.name = "CinematicOverlay"
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)
	_bars.clear()
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BAR_SHARE
		bar.anchor_bottom = BAR_SHARE if top else 1.0
		root.add_child(bar)
		_bars.append(bar)
	var s := _text_scale()
	_speaker = _label(root, 22 * s, Color(1.0, 0.72, 0.35))
	_speaker.anchor_top = 1.0 - BAR_SHARE - 0.12
	_speaker.anchor_bottom = 1.0 - BAR_SHARE - 0.085
	_caption = _label(root, 34 * s, Color(1, 1, 1))
	_caption.anchor_top = 1.0 - BAR_SHARE - 0.085
	_caption.anchor_bottom = 1.0 - BAR_SHARE + 0.06
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(root, 20 * s, Color(0.85, 0.85, 0.85))
	_hint.anchor_top = 1.0 - BAR_SHARE * 0.55
	_hint.anchor_bottom = 1.0
	_hint.text = String(seq.get("skip_hint", "E, Space or Esc: skip"))
	_card = _label(root, 64 * s, Color(1.0, 0.8, 0.45))
	_card.anchor_top = 0.38
	_card.anchor_bottom = 0.5
	_card.visible = false
	_card_sub = _label(root, 30 * s, Color(1, 1, 1))
	_card_sub.anchor_top = 0.5
	_card_sub.anchor_bottom = 0.58
	_card_sub.visible = false
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)
	# the end card sits above the fade so "Base operational" is readable over black
	_card.move_to_front()
	_card_sub.move_to_front()


func _label(parent: Control, size: float, color: Color) -> Label:
	var l := Label.new()
	l.anchor_left = 0.08
	l.anchor_right = 0.92
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
