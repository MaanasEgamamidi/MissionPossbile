class_name CassettePresenter
extends Node3D
## Six room cassettes and the Command Room tape deck as real models (assets/props/*.glb, built by
## tools/blender/props/build_props.py). Each rests ON a real surface (a desk, crate, bench or table top): the spot is
## "prop_position" / "prop_yaw_deg" of its entry in data/stations_repairs.json, measured in the intact map so the visual
## top and the collision top agree within 2 cm. Nothing floats and no sign hangs in the air (owner 2026-11-14): the HUD
## prompt "[E] ..." says what to do. Presentation follows shared authoritative collection state.
## Tapes first (owner 2026-11-14): each tape not yet found twinkles with a small cloud of gold sparkles (one
## GPUParticles3D per tape, the shared sparkle look of tape_trail_presenter.gd) over a faint gold rim glow, lines of gold
## sparkles lead to them from just inside the base (tape_trail_presenter.gd, made here) until every tape is found, and
## a tape that is picked up while the game runs (the replicated state, on every machine) stops twinkling and shrinks
## away under a gold sparkle burst (scripts/tasks/sparkle_burst.gd). No lights: the sparkles are the gold look.
## The station's sensing Area3D stays the only interaction shape: its sphere, plus a small reach box around the prop so
## that aiming at the prop itself works. The props add no solid collision.

const TAPE_SCENE := "res://assets/props/cassette_tape.glb"
const PLAYER_SCENE := "res://assets/props/cassette_player.glb"
## Top of the tape's room colour band, in the tape model (glb) frame: the room name is printed flat on it.
const TAPE_STRIP_TOP := Vector3(0.0, 0.0198, -0.032)
## Reach boxes (designer balance): a little larger than the props, so E aims easily at a small tape.
const TAPE_REACH := Vector3(0.5, 0.3, 0.44)
const TAPE_GLOW_SHADER := preload("res://materials/specialist_gold.gdshader")
## Rich gold, the same as the gold guide lines (tape_trail_presenter.gd), strong enough to read from across a room.
const TAPE_GLOW := Color(1.0, 0.75, 0.2)
const TapeTrails := preload("res://scripts/cassettes/tape_trail_presenter.gd")
const SparkleBurst := preload("res://scripts/tasks/sparkle_burst.gd")
## Owner 2026-11-15: the first-week gold sparkle guide line (gold + sparkles always mean "this works / go this way"),
## made here next to the tape trails; group &"guide_sparkles" (the coming H key finds it there).
const GuideSparkles := preload("res://scripts/guide/guide_sparkles.gd")
## Seconds a picked-up tape takes to shrink away under its sparkles.
const VANISH_SECONDS := 0.35
## Idle gold sparkles around a tape not yet found: count (half on Low), half size of the box they twinkle in (centred
## IDLE_LIFT above the tape's resting spot, so they sit just over the surface), seconds each lives.
const IDLE_SPARKLES := 20
const IDLE_EXTENTS := Vector3(0.28, 0.09, 0.28)
const IDLE_LIFT := 0.12
const IDLE_LIFETIME := 1.6
const PLAYER_REACH := Vector3(0.62, 0.34, 0.42)

var services: GameServices
var cassette_nodes: Dictionary = {}
var _refresh_left := 0.0
## The gold guide lines to the tapes (tape_trail_presenter.gd), made in setup.
var trails: Node3D
## The gold sparkle guide line of the first week (scripts/guide/guide_sparkles.gd), made in setup.
var guide: Node3D
## Sparkle bursts played since setup, and the last one (checks).
var bursts_started := 0
var last_burst: Node3D
## Instance id of the colony state the tapes were last shown for (another one = loaded or joined: no sparkles).
var _state_id := 0
## cassette id -> collected when last shown.
var _seen := {}
## cassette id -> seconds into its shrink after pickup.
var _vanish := {}
## cassette id -> world pose of the tape (sparkles).
var _tape_pose := {}
## cassette id -> the tape's idle gold sparkles (GPUParticles3D, a child of its station).
var _idle := {}

func setup(p_services: GameServices, collision: Node3D) -> void:
	services = p_services
	var stations := collision.get_node_or_null("Stations")
	if stations == null:
		return
	var entries := {}
	for entry: Dictionary in StationCatalog.extra_entries():
		if entry.has("id"):
			entries[String(entry.id)] = entry
	for cassette_id: String in CassetteCatalog.TAPES:
		var station := stations.get_node_or_null(NodePath(cassette_id)) as Area3D
		if station == null:
			continue
		var model := _cassette(cassette_id)
		_place(station, model, entries.get(cassette_id, {}), TAPE_REACH, 0.06)
		_tape_pose[cassette_id] = prop_pose(entries.get(cassette_id, {}), station.position)
		cassette_nodes[cassette_id] = station
	var player := stations.get_node_or_null(NodePath(CassetteCatalog.PLAYER_ID)) as Area3D
	if player != null:
		_place(player, _player_model(), entries.get(CassetteCatalog.PLAYER_ID, {}), PLAYER_REACH, 0.16)
	trails = TapeTrails.new()
	add_child(trails)
	trails.call(&"setup", services)
	guide = GuideSparkles.new()
	add_child(guide)
	guide.call(&"setup", services)
	var mask := int(trails.call(&"_layers"))
	# Low graphics preset: still GPU particles (cheap), half as many.
	var idle_amount := int(IDLE_SPARKLES * 0.5) if _use_cpu() else IDLE_SPARKLES
	for cassette_id: String in cassette_nodes:
		var station := cassette_nodes[cassette_id] as Area3D
		var pose: Transform3D = _tape_pose[cassette_id]
		var sparkles := TapeTrails.idle_sparkles(idle_amount, IDLE_EXTENTS, IDLE_LIFETIME)
		sparkles.name = "TapeSparkles"
		sparkles.layers = mask
		sparkles.emitting = false
		# Stations sit under the identity "Stations" node, so local = world offsets.
		sparkles.position = pose.origin - station.position + Vector3(0, IDLE_LIFT, 0)
		station.add_child(sparkles)
		_idle[cassette_id] = sparkles
	services.events.state_changed.connect(func(_reason: StringName) -> void: refresh())
	services.events.game_loaded.connect(_on_game_loaded)
	refresh()

## A loaded colony is shown as it is: no sparkles, no fades.
func _on_game_loaded(_source: String) -> void:
	_state_id = 0
	refresh()

func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		refresh()
	step_vanish(delta)

## Shows each tape as the shared collection state says. A tape that becomes collected while the game runs (on the host
## by the pickup, on clients by the replicated state) plays a sparkle burst and shrinks away; a loaded or joined colony
## is shown as it is, without sparkles. The gold lines follow on the same refresh.
func refresh() -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	var fresh := st.get_instance_id() != _state_id
	_state_id = st.get_instance_id()
	var newly: Array[String] = []
	for cassette_id: String in cassette_nodes:
		var collected := CassetteCatalog.collected(st, cassette_id)
		if not fresh and collected and _seen.has(cassette_id) and not bool(_seen[cassette_id]):
			newly.append(cassette_id)
		_seen[cassette_id] = collected
		if fresh:
			_end_vanish(cassette_id)
	# More than two at once is a state sync (a late join), not pickups: no sparkles.
	if newly.size() <= 2:
		for cassette_id: String in newly:
			_sparkle(cassette_id)
	for cassette_id: String in cassette_nodes:
		var station := cassette_nodes[cassette_id] as Area3D
		var available := not CassetteCatalog.collected(st, cassette_id)
		station.visible = available or _vanish.has(cassette_id)
		station.collision_layer = Layers.STATION if available else 0
		station.set_meta("cassette_collected", not available)
		# Twinkles while it waits to be found; a picked-up tape's last sparkles fade out under its burst.
		var sparkles := _idle.get(cassette_id) as GPUParticles3D
		if sparkles != null and sparkles.emitting != available:
			if available:
				sparkles.restart() # starts already twinkling (preprocess)
			else:
				sparkles.emitting = false
	if trails != null:
		trails.call(&"refresh", fresh)


## Sparkles over a tape that was just picked up, and its shrink.
func _sparkle(cassette_id: String) -> void:
	if not is_inside_tree():
		return
	var pose: Transform3D = _tape_pose.get(cassette_id, Transform3D())
	var centre := pose.origin + Vector3(0, 0.08, 0)
	var bounds := AABB(centre - Vector3(0.22, 0.1, 0.22), Vector3(0.44, 0.3, 0.44))
	var mask := (1 << 20) - 1
	if trails != null:
		mask = int(trails.call(&"_layers"))
	last_burst = SparkleBurst.spawn(self, bounds, mask, _use_cpu(), TAPE_GLOW)
	bursts_started += 1
	_vanish[cassette_id] = 0.0


## Shrinks picked-up tapes away under their sparkles (tests call it directly).
func step_vanish(delta: float) -> void:
	for cassette_id: String in _vanish.keys():
		var t := float(_vanish[cassette_id]) + delta
		_vanish[cassette_id] = t
		var model := (cassette_nodes[cassette_id] as Node3D).get_node_or_null("CassetteModel") as Node3D
		if model != null:
			model.scale = Vector3.ONE * maxf(0.001, 1.0 - smoothstep(0.0, VANISH_SECONDS, t))
		if t >= VANISH_SECONDS:
			_end_vanish(cassette_id)
			var gone := services != null and services.has_game() and CassetteCatalog.collected(services.state(), cassette_id)
			(cassette_nodes[cassette_id] as Node3D).visible = not gone


func _end_vanish(cassette_id: String) -> void:
	_vanish.erase(cassette_id)
	var station := cassette_nodes.get(cassette_id) as Node3D
	var model := station.get_node_or_null("CassetteModel") as Node3D if station != null else null
	if model != null:
		model.scale = Vector3.ONE


func _use_cpu() -> bool:
	var level := GraphicsQuality.applied_level(get_tree()) if is_inside_tree() else -1
	return level == GraphicsQuality.Level.LOW

## World position (on its support surface) and yaw of a prop, from its station entry. Without "prop_position" the prop
## sits on the floor under the station.
static func prop_pose(entry: Dictionary, station_position: Vector3) -> Transform3D:
	var at := station_position - Vector3(0, 1.0, 0)
	if entry.has("position"):
		var q: Array = entry.position
		at = Vector3(float(q[0]), float(q[1]), float(q[2]))
	if entry.has("prop_position"):
		var p: Array = entry.prop_position
		at = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(entry.get("prop_yaw_deg", 0.0)))), at)

## Puts the model at its surface spot (stations sit under the identity "Stations" node, so local = world offsets) and
## adds the reach box, `lift` metres high, around it.
static func _place(station: Area3D, model: Node3D, entry: Dictionary, reach: Vector3, lift: float) -> void:
	var pose := prop_pose(entry, station.position)
	model.transform = Transform3D(pose.basis, pose.origin - station.position)
	station.add_child(model)
	var shape := CollisionShape3D.new()
	shape.name = "PropReach"
	var box := BoxShape3D.new()
	box.size = reach
	shape.shape = box
	shape.transform = Transform3D(pose.basis, pose.origin - station.position + Vector3(0, lift, 0))
	station.add_child(shape)

static func _instance(path: String, label: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("CassettePresenter: missing model " + path)
		var empty := Node3D.new()
		empty.name = label
		return empty
	var node := scene.instantiate() as Node3D
	node.name = label
	return node

static func _cassette(cassette_id: String) -> Node3D:
	var info: Dictionary = CassetteCatalog.TAPES[cassette_id]
	var model := Node3D.new()
	model.name = "CassetteModel"
	var tape := _instance(TAPE_SCENE, "Tape")
	model.add_child(tape)
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(String(info.color))
	strip.roughness = 0.55
	for part: String in ["RoomStrip", "LabelLine"]:
		var mesh := tape.find_child(part, true, false) as MeshInstance3D
		if mesh != null:
			mesh.material_override = strip
	# The room name printed flat on the colour band (not a floating sign): it lies on the tape and reads from +Z.
	var label := Label3D.new()
	label.name = "RoomLabel"
	label.text = "%s  %s" % [info.code, info.title]
	label.position = TAPE_STRIP_TOP + Vector3(0, 0.0004, 0)
	label.rotation.x = -PI * 0.5
	label.font_size = 40
	label.pixel_size = 0.00025
	label.outline_size = 0
	label.modulate = Color("1b1d20")
	label.double_sided = false
	label.no_depth_test = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(label)
	_add_glow(model)
	return model

## Owner 2026-11-14: tapes are easy to find. The gold look is the idle sparkles (made in setup); under them a faint,
## gently pulsing rich-gold rim on the tape (the same rim shader as the broken parts, in a colour of its own: green and
## red mean "you can / cannot fix this"). No light (it was one extra light per tape). Gone with the tape once picked up.
static func _add_glow(model: Node3D) -> void:
	var glow := ShaderMaterial.new()
	glow.shader = TAPE_GLOW_SHADER
	glow.set_shader_parameter(&"gold", TAPE_GLOW)
	glow.set_shader_parameter(&"base_glow", 0.4)
	glow.set_shader_parameter(&"strength", 2.2)
	glow.set_shader_parameter(&"pulse_depth", 0.3)
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D:
			(g as MeshInstance3D).material_overlay = glow
	# Owner 2026-11-14: replaced by sparkle particles
	# var light := OmniLight3D.new()
	# light.name = "TapeGlowLight"
	# light.light_color = TAPE_GLOW
	# light.light_energy = 2.0
	# light.omni_range = 1.6
	# light.omni_attenuation = 1.6
	# light.shadow_enabled = false
	# light.position = Vector3(0, 0.12, 0)
	# model.add_child(light)

static func _player_model() -> Node3D:
	var model := Node3D.new()
	model.name = "CassettePlayerModel"
	model.add_child(_instance(PLAYER_SCENE, "Deck"))
	return model
