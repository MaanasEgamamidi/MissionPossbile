class_name GameMain
extends Node3D
## Root of the playable game: puts the map, its collision, the services, the local player and the HUD together.
## Presentation only. It never changes colony state itself; it sends requests and listens to GameEvents.

const WORLD_SCENE := "res://scenes/world/colony_world.tscn"
const MANIFEST_PATH := "res://data/colony_manifest.json"
const COLLIDERS_PATH := "res://data/colliders.json"
const TERRAIN_HEIGHT_PATH := "res://data/terrain_height.res"
const INPUT_PATH := "user://input.json"

## Tests switch this off to run without the 300 MB map.
@export var load_world := true
## Start at the main menu (true) or go straight into the newest save or a new colony (tests and capture tools).
@export var show_menu := true
## Tests point saves at a folder inside the project instead of user://.
@export var save_directory := ""

var services: GameServices
var world: Node3D
var collision: Node3D
var lighting: ZoneLighting
var player: PlayerController
var hud: GameHud
## Menus, panels, pause menu and subtitles (Prompt 05).
var ui: UiRoot
## The player's own settings: text size, FOV, mouse, subtitles... (user://settings.json).
var settings: GameSettings
var notice := ""
## Door leaves whose visible mesh was found in the map and now moves with its collider (52 when the map is loaded).
var door_visuals_attached := 0
## The exit tunnel's inner and outer doors, paired as an airlock (empty when the map is not loaded).
var airlock_doors: Array[DoorController] = []
## True if the rigged astronaut was found and is used instead of the capsule stand-in.
var rigged_bodies := false
## What PropCollision built at load (hulls, trimeshes, skipped, ms); empty when the map is not loaded.
var prop_collision_stats := {}

var _crew_visuals := {}          # character id -> PlayerVisual (crew the local player does not control)
var _item_nodes := {}            # item id -> CarryItem
var _cache_nodes := {}           # cache id -> Node3D marker
var _sun_timer := 0.0
var _layer_timer := 0.0
var _zone_now := ""
var _playing := false
var _main_menu: MainMenu
var _confirm_new := false


func _ready() -> void:
	PlayerInput.ensure_actions()
	PlayerInput.load(INPUT_PATH)
	settings = GameSettings.load_or_default()
	settings.apply(get_tree())
	settings.changed.connect(_apply_player_settings)

	services = GameServices.new()
	services.name = "Services"
	if save_directory != "":
		services.saves = SaveService.new(save_directory, services.config.save_name, services.config.backup_count)
	add_child(services)

	if load_world and ResourceLoader.exists(WORLD_SCENE):
		world = (load(WORLD_SCENE) as PackedScene).instantiate() as Node3D
		add_child(world)
		lighting = ZoneLighting.new()
		lighting.name = "ZoneLighting"
		add_child(lighting)
		lighting.setup(world)
		for cam in world.find_children("*", "Camera3D", true, false):
			(cam as Camera3D).current = false

	collision = WorldCollision.build(MANIFEST_PATH, COLLIDERS_PATH)
	add_child(collision)
	if world != null:
		for door in collision.get_node("Doors").get_children():
			door_visuals_attached += (door as DoorController).attach_visuals(world)
		# The glass hall and its exit tunnel are environment scenery outside the manifest: give them collision and working doors.
		airlock_doors = EnvironmentCollision.build(world, collision)
		# The 996 outdoor rocks are scenery too: one convex hull each so nobody walks into them.
		RockCollision.build(world, collision)
		# Racks and stands show the crew's own suit, not the old white one modelled into the map.
		SuitDisplays.build(world)
	_add_ground()
	if world != null:
		# Everything else solid that is drawn (rovers, tanks, machines, hall frames and curb, dome shell...) gets its own
		# collision, so no rigid object can be walked into.
		var height := load(TERRAIN_HEIGHT_PATH) as TerrainHeight if ResourceLoader.exists(TERRAIN_HEIGHT_PATH) else null
		prop_collision_stats = PropCollision.build(world, collision, MANIFEST_PATH, COLLIDERS_PATH, height, PropCollision.CACHE_PATH)


	ui = UiRoot.new()
	ui.name = "Ui"
	add_child(ui)
	ui.setup(services, settings)
	ui.quit_to_menu_requested.connect(_on_quit_to_menu)

	if show_menu:
		_open_main_menu()
	else:
		_start_or_continue()
		_begin_play()


## Everything that needs a running colony: HUD, crew bodies, items, lights. Called once, after the menu.
func _begin_play() -> void:
	_playing = true
	hud = GameHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(services)
	# One thing at a time on screen: the HUD steps aside while a panel or menu is open.
	if not ui.menu_mode_changed.is_connected(_on_menu_mode_changed):
		ui.menu_mode_changed.connect(_on_menu_mode_changed)
	for door: DoorController in airlock_doors:
		# Each time the outer door opens, the airlock has let some cabin air out (Prompt 07: pressure boundary).
		if door.door_id == 902:
			door.opened_changed.connect(func(_id: int, open: bool) -> void:
				if open and services.is_authority():
					services.session.note_airlock_cycle())
		door.cycle_started.connect(func(_id: int, seconds: float) -> void:
			ui.show_subtitle("Airlock cycling: the other door must stay shut. Wait %.0f s." % ceilf(seconds), seconds + 0.5, "Airlock", true))
	if notice != "":
		ui.show_subtitle(notice, 8.0, "", true)

	var ev := services.events
	ev.state_changed.connect(_on_state_changed)
	ev.zone_power_changed.connect(_on_zone_power_changed)
	ev.crew_ownership_changed.connect(func(_id: StringName, _peer: int) -> void: _rebuild_crew())
	ev.suit_check_finished.connect(_on_suit_check_finished)
	ev.suit_check_started.connect(_on_suit_check_started)
	ev.character_recovered.connect(_on_character_recovered)

	_rebuild_crew()
	_sync_items()
	_apply_all_zone_power()
	_update_sun(true)
	_apply_player_settings()
	ui.close_all()        # leaves menu mode: the mouse is captured for play


func _on_menu_mode_changed(open: bool) -> void:
	if hud != null:
		hud.set_visible_hud(not open)


# ---------------------------------------------------------------- menu

func _open_main_menu() -> void:
	_main_menu = MainMenu.new()
	_main_menu.continue_pressed.connect(_on_menu_continue)
	_main_menu.new_game_pressed.connect(_on_menu_new)
	_main_menu.host_pressed.connect(func(_port: int, _continue_save: bool) -> void: _main_menu.show_notice(NETWORK_LATER))
	_main_menu.join_pressed.connect(func(_address: String, _port: int) -> void: _main_menu.show_notice(NETWORK_LATER))
	_main_menu.quit_pressed.connect(func() -> void: get_tree().quit())
	ui.open(_main_menu)


## Playing together over a network is Prompt 06, skipped for now at the owner's request.
const NETWORK_LATER := "Playing together on a network is not built yet. You can play the colony on your own for now: choose Continue or New colony."


func _on_menu_continue() -> void:
	var loaded := services.continue_game()
	if not loaded.is_usable():
		_main_menu.show_notice("The saved colony could not be opened (%s). Choose New colony to start again; the old files are kept." % loaded.status)
		return
	if loaded.status == &"recovered_from_backup":
		notice = "The newest save was damaged. An earlier save was loaded instead."
	_begin_play()


func _on_menu_new() -> void:
	if services.saves.has_save() and not _confirm_new:
		_confirm_new = true
		_main_menu.show_notice("A new colony replaces your saved one (the old save is kept as a backup). Press New colony again to start.")
		return
	services.start_new_game()
	_begin_play()


func _on_quit_to_menu() -> void:
	if services.is_authority() and services.has_game():
		services.save_now(&"quit")
	get_tree().reload_current_scene()

func _start_or_continue() -> void:
	var loaded := services.continue_game()
	if loaded.is_usable():
		if loaded.status == &"recovered_from_backup":
			notice = "The newest save was damaged. An earlier save was loaded instead."
		return
	if loaded.status != &"no_save":
		# Do not overwrite saves this version cannot read: play under another name and say so.
		services.saves.save_name += "_new"
		notice = "The saved game could not be opened (%s). A new game was started beside it." % loaded.status
	services.start_new_game()


## Outdoor ground: the sampled height grid if it has been built, else a flat plane at y = 0 so nobody falls for ever.
func _add_ground() -> void:
	if ResourceLoader.exists(TERRAIN_HEIGHT_PATH):
		var height := load(TERRAIN_HEIGHT_PATH) as TerrainHeight
		if height != null:
			collision.add_child(height.make_body())
			return
	var body := StaticBody3D.new()
	body.name = "FlatGroundFallback"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	shape.position.y = -0.2
	body.add_child(shape)
	collision.add_child(body)


# ---------------------------------------------------------------- crew

func _local_character() -> CharacterState:
	return services.local_character()


func _rebuild_crew() -> void:
	var st := services.state()
	var mine := _local_character()
	if player != null and (mine == null or player.character != mine):
		player.queue_free()
		player = null
	if mine != null and player == null:
		player = PlayerController.new()
		player.name = "Player"
		add_child(player)
		player.setup(services.config, PlayerTuning.new(), mine, _submit,
			func(pos: Vector3, yaw: float) -> void: services.report_position(mine.id, pos, yaw))
		player.teleport(mine.position + Vector3(0.0, 0.05, 0.0), mine.yaw)
		rigged_bodies = player.visual().use_rig_if_available()
		player.visual().set_crew_identity(_identity_of(mine))
		player.visual().set_suit(mine.suit_on)
		player.action_answered.connect(_on_action_answered)
		_apply_player_settings()
	for id: StringName in st.characters:
		var c := st.characters[id] as CharacterState
		var is_mine := mine != null and c.id == mine.id
		if is_mine and _crew_visuals.has(id):
			(_crew_visuals[id] as Node).queue_free()
			_crew_visuals.erase(id)
		elif not is_mine:
			var v := _crew_visuals.get(id) as PlayerVisual
			if v == null:
				v = PlayerVisual.new()
				v.name = "Crew_" + String(id)
				add_child(v)
				_crew_visuals[id] = v
				v.use_rig_if_available()
				v.set_first_person(false)   # other crew are always seen from outside: keep their heads visible
				v.set_crew_identity(_identity_of(c))
			v.global_position = c.position
			v.rotation.y = c.yaw
			v.set_suit(c.suit_on)
			v.play(&"idle")
			if services.zones != null:
				v.set_zone_layers(_layers_for(services.zones.zone_at_world(c.position)))


## Everything the local player asks for goes to the host through here.
func _submit(action: StringName, target: StringName, params: Dictionary) -> ActionResult:
	if action == &"use_station":
		# Opening a station's surface changes nothing; every control on it is its own validated request.
		var panel := StationPanels.for_station(target, services)
		if panel != null:
			ui.open(panel)
			return ActionResult.success("", {})
		return LegacyStations.interact(services.session, services.local_peer(), target, params)
	return services.request(action, target, params)


## Settings that reach into the player body: field of view, mouse, sprint toggle.
func _apply_player_settings() -> void:
	if player == null or settings == null:
		return
	player.tuning.mouse_sensitivity = settings.mouse_sensitivity
	player.invert_y = settings.invert_y
	player.toggle_sprint = settings.toggle_sprint
	player.camera_rig().set_fov(settings.fov_degrees)


func _identity_of(c: CharacterState) -> int:
	return maxi(0, CharacterState.SPECIALTIES.find(c.specialty))


func _layers_for(zone: String) -> int:
	var z := services.zones
	var mask := z.bit_of(zone)
	if zone == ColonyZones.PLAZA or zone == ColonyZones.GARDEN or zone == ColonyZones.EXTERIOR:
		mask |= z.sun_bit()
	return mask if mask != 0 else 1


# ---------------------------------------------------------------- items

func _sync_items() -> void:
	var st := services.state()
	for id: String in st.items:
		var rec: Dictionary = st.items[id]
		var holder := String(rec.get("holder", ""))
		var node := _item_nodes.get(id) as CarryItem
		if node == null:
			node = CarryItem.make_crate(StringName(id))
			add_child(node)
			_item_nodes[id] = node
			node.release(_v3(rec.get("position", [0, 0, 0])) + Vector3(0.0, 0.3, 0.0))
		var mine := _local_character()
		if holder == "":
			node.visible = true
			if node.is_held() and (player == null or player.held_item() != node):
				node.release(_v3(rec.get("position", [0, 0, 0])) + Vector3(0.0, 0.6, 0.0))
		elif holder.begins_with("cache:"):
			if node.is_held():
				node.release(_v3(rec.get("position", [0, 0, 0])))
			node.visible = false
			node.freeze = true
		elif mine != null and holder == String(mine.id):
			node.visible = true
			if player != null and not node.is_held():
				node.attach_to(player.visual().hand_anchor(true))
		else:
			var v := _crew_visuals.get(StringName(holder)) as PlayerVisual
			node.visible = v != null
			if v != null and not node.is_held():
				node.attach_to(v.hand_anchor(true))
	# cache markers
	var wanted := {}
	for cache: Dictionary in st.caches:
		var cid := String(cache.get("id", ""))
		wanted[cid] = true
		if not _cache_nodes.has(cid):
			var marker := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 0.35, 0.45)
			marker.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.95, 0.55, 0.1)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.4, 0.05)
			marker.material_override = mat
			marker.position = _v3(cache.get("position", [0, 0, 0])) + Vector3(0.0, 0.2, 0.0)
			marker.set_meta("cache_id", cid)
			add_child(marker)
			_cache_nodes[cid] = marker
	for cid: String in _cache_nodes.keys():
		if not wanted.has(cid):
			(_cache_nodes[cid] as Node).queue_free()
			_cache_nodes.erase(cid)


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


# ---------------------------------------------------------------- light and time

func _apply_all_zone_power() -> void:
	if lighting == null:
		return
	for zone: String in services.state().zones:
		lighting.set_zone_powered(zone, services.state().is_zone_powered(zone))


func _update_sun(force := false) -> void:
	if lighting == null:
		return
	_sun_timer -= get_process_delta_time()
	if force or _sun_timer <= 0.0:
		_sun_timer = 0.5
		lighting.set_sun_phase(services.clock().phase)


func _process(_delta: float) -> void:
	if not _playing or not services.has_game():
		return
	if player != null:
		player.input_enabled = ui.gameplay_has_focus()
		hud.set_held(player.held_item().item_id if player.held_item() != null else &"")
	_update_sun()
	if player != null and services.zones != null:
		var zone := services.zones.zone_at_world(player.global_position)
		if zone != _zone_now:
			_zone_now = zone
			player.visual().set_zone_layers(_layers_for(zone))
	if hud != null and player != null:
		hud.set_target(player.aimed_target())
	_layer_timer -= _delta
	if _layer_timer <= 0.0 and services.zones != null:
		_layer_timer = 0.5
		for id: String in _item_nodes:
			var node := _item_nodes[id] as CarryItem
			var mask := _layers_for(services.zones.zone_at_world(node.global_position))
			for mesh in node.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).layers = mask


# ---------------------------------------------------------------- input that belongs to the whole game

## Esc, panels, the pause menu and the M / I / C / Shift+Backspace screens belong to UiRoot.
## Here only: a click takes the mouse back for play after the window lost it (alt-tab) while no panel is open.
func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not ui.is_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- events

func _on_state_changed(reason: StringName) -> void:
	if reason == &"tick":
		return
	_sync_items()
	if reason == &"release_character" or reason == &"claim_character":
		_rebuild_crew()


func _on_zone_power_changed(zone: String, powered: bool) -> void:
	if lighting != null:
		lighting.set_zone_powered(zone, powered)


func _on_suit_check_started(character_id: StringName, seconds: float) -> void:
	var mine := _local_character()
	if mine != null and mine.id == character_id and player != null:
		player.visual().play_once(&"suit", seconds)
	elif _crew_visuals.has(character_id):
		(_crew_visuals[character_id] as PlayerVisual).play_once(&"suit", seconds)


func _on_suit_check_finished(character_id: StringName, suit_on: bool, completed: bool) -> void:
	var mine := _local_character()
	if mine != null and mine.id == character_id:
		player.visual().set_suit(suit_on)
		hud.show_message("Suit check complete. Suit %s." % ("on" if suit_on else "off") if completed else "Suit check cancelled.", 3.0)
	elif _crew_visuals.has(character_id):
		(_crew_visuals[character_id] as PlayerVisual).set_suit(suit_on)


func _on_character_recovered(character_id: StringName, info: Dictionary) -> void:
	var mine := _local_character()
	if mine != null and mine.id == character_id and player != null:
		player.teleport(mine.position + Vector3(0.0, 0.05, 0.0), mine.yaw)
	var text := "%s was brought back to the hub. Cost: %.1f meals and %.1f L of water." % [
		services.state().character(character_id).display_name, float(info.get("meals", 0.0)), float(info.get("water_l", 0.0))]
	if String(info.get("cache_id", "")) != "":
		var p := _v3(info.get("cache_position", []))
		var where := services.zones.zone_at_world(p) if services.zones != null else ""
		text += " Their cargo is waiting in a cache: %s (%.0f, %.0f)." % [where, p.x, p.z]
	ui.show_subtitle(text, 12.0, "Colony computer", true)
	_rebuild_crew()
	_sync_items()


func _on_action_answered(result: ActionResult) -> void:
	if result != null and not result.ok and not result.pending:
		hud.show_message(result.message, 3.0)
