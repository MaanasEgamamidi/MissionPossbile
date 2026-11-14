extends Control
## Two full-resolution textures, with aspect-fill framing and overlapping motion.
## The next shot loads on a worker thread while the current shot is on screen.
const SHOT_FOLDER := "res://assets/menu/beauty_shots/"
const HERO := SHOT_FOLDER + "00_colony_4k.png"
const SHOT_SECONDS := 18.0
const FADE_SECONDS := 3.0
const ADVANCE_SECONDS := SHOT_SECONDS - FADE_SECONDS

var _paths: PackedStringArray = []
var _current: Texture2D
var _next: Texture2D
var _index := 0
var _age := 0.0
var _single_age := 0.0
var _pending := ""
var _screen_size := Vector2.ZERO
var motion_enabled := true:
	set(value):
		if motion_enabled != value:
			motion_enabled = value
			queue_redraw()


func _ready() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	process_mode = Node.PROCESS_MODE_ALWAYS
	_paths.append(HERO)
	var folder := DirAccess.open(SHOT_FOLDER)
	if folder != null:
		var extras: PackedStringArray = []
		for file in folder.get_files():
			var original := file.trim_suffix(".remap")
			if original.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
				var path := SHOT_FOLDER + original
				if path != HERO and not extras.has(path) and ResourceLoader.exists(path):
					extras.append(path)
		extras.sort()
		_paths.append_array(extras)
	if ResourceLoader.exists(HERO):
		_current = load(HERO) as Texture2D
	_request_next()
	_fit_screen()
	get_viewport().size_changed.connect(_fit_screen)


func _fit_screen() -> void:
	_screen_size = get_viewport_rect().size
	queue_redraw()


func _request_next() -> void:
	if _paths.size() < 2:
		return
	_pending = _paths[(_index + 1) % _paths.size()]
	var error := ResourceLoader.load_threaded_request(_pending, "Texture2D")
	if error != OK:
		_skip_failed_next()


func _skip_failed_next() -> void:
	push_warning("Menu beauty shot could not load: " + _pending)
	_paths.remove_at((_index + 1) % _paths.size())
	_index = _paths.find(HERO) if _current == null else clampi(_index, 0, _paths.size() - 1)
	_pending = ""
	_request_next()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not motion_enabled:
		return
	if not _pending.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_pending)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_next = ResourceLoader.load_threaded_get(_pending) as Texture2D
			_pending = ""
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_skip_failed_next()
	_single_age += delta
	if _paths.size() > 1:
		_age += delta
		# Never fade to an unloaded image. Keep the opaque current image underneath.
		if _next == null:
			_age = minf(_age, ADVANCE_SECONDS)
		elif _age >= SHOT_SECONDS:
			_age -= ADVANCE_SECONDS
			_index = (_index + 1) % _paths.size()
			_current = _next
			_next = null
			_request_next()
	queue_redraw()


func _draw() -> void:
	draw_set_transform(-global_position)
	draw_rect(Rect2(Vector2.ZERO, _screen_size), Color("100d10"))
	if _current != null:
		# A single image moves on a closed curve: no reset or jump while awaiting more shots.
		var phase := _age / SHOT_SECONDS if _paths.size() > 1 else (1.0 - cos(_single_age * TAU / 48.0)) * 0.5
		_draw_shot(_current, phase if motion_enabled else 0.5, _index, 1.0)
	if motion_enabled and _next != null and _age > ADVANCE_SECONDS:
		var fade := smoothstep(0.0, FADE_SECONDS, _age - ADVANCE_SECONDS)
		_draw_shot(_next, (_age - ADVANCE_SECONDS) / SHOT_SECONDS, (_index + 1) % _paths.size(), fade)
	# Fixed scrim keeps labels readable while the imagery continues moving beneath it.
	var shade := Color(0.018, 0.022, 0.033)
	var edge := _screen_size.x * 0.24
	var end := _screen_size.x * 0.64
	draw_rect(Rect2(0, 0, edge, _screen_size.y), Color(shade, 0.88))
	draw_polygon(PackedVector2Array([Vector2(edge, 0), Vector2(end, 0), Vector2(end, _screen_size.y), Vector2(edge, _screen_size.y)]), PackedColorArray([Color(shade, 0.88), Color(shade, 0.02), Color(shade, 0.02), Color(shade, 0.88)]))


func _draw_shot(image: Texture2D, phase: float, shot: int, opacity: float) -> void:
	var t := smoothstep(0.0, 1.0, clampf(phase, 0.0, 1.0))
	var dimensions := image.get_size()
	var cover := maxf(_screen_size.x / dimensions.x, _screen_size.y / dimensions.y)
	var zoom := lerpf(1.025, 1.075, t)
	var drawn := dimensions * cover * zoom
	var slack := (drawn - _screen_size) * 0.5
	var direction := 1.0 if shot % 2 == 0 else -1.0
	var drift := Vector2(slack.x * (t * 2.0 - 1.0) * 0.45 * direction, slack.y * (1.0 - t * 2.0) * 0.3)
	draw_texture_rect(image, Rect2((_screen_size - drawn) * 0.5 + drift, drawn), false, Color(1, 1, 1, opacity))

