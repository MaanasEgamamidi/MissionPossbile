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
## Check the NASA weather data for published updates in the background (Prompt 09). Never in headless runs (tests).
@export var check_weather_updates := true
## Tests point saves at a folder inside the project instead of user://.
@export var save_directory := ""

var services: GameServices
var world: Node3D
var collision: Node3D
var lighting: ZoneLighting
## Sky, sun and fog follow the dust in the air (Prompt 09).
var weather_presenter: WeatherPresenter
## Scout update: the scout rover, the broken-down rover and the ore deposits in the world, and the mast camera.
var scout_presenter: ScoutPresenter
## Scout update: the mission-control HUD (vitals bar, goals, map, pop-ups, dock) laid around GameHud.
var mission_hud: MissionHud
## Prompt 11: private proximity voice and the colony radio (VoiceService adds its HUD corner itself).
var voice: VoiceService
## Prompt 10: the shared four-seat rover (body, seats, driving, HUD widget, network pose).
var rover: RoverPresenter
## Prompt 12: tutorial tracker, hints, specialist cues and the colony journal.
var tutorial: TutorialPresenter
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
## The garden dome (greenhouse) airlock's inner and outer sliding doors, paired the same way (empty without the map).
var garden_airlock_doors: Array[DoorController] = []
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
		GraphicsQuality.apply(get_tree(), settings.graphics_quality)   # after setup: it swaps in its own environment copy
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
		HabitatFinish.new().apply(world)
	_add_ground()
	if world != null:
		# Everything else solid that is drawn (rovers, tanks, machines, hall frames and curb, dome shell...) gets its own
		# collision, so no rigid object can be walked into.
		var height := load(TERRAIN_HEIGHT_PATH) as TerrainHeight if ResourceLoader.exists(TERRAIN_HEIGHT_PATH) else null
		prop_collision_stats = PropCollision.build(world, collision, MANIFEST_PATH, COLLIDERS_PATH, height, PropCollision.CACHE_PATH)
		# The garden dome's airlock vestibule is modelled open: give it sliding doors that cycle like the exit tunnel.
		# Built after PropCollision so the vestibule's own collision (and the baked cache) is unchanged.
		garden_airlock_doors = GardenDomeDoors.build(world, collision)


	ui = UiRoot.new()
	ui.name = "Ui"
	add_child(ui)
	ui.setup(services, settings)
	ui.quit_to_menu_requested.connect(_on_quit_to_menu)

	# Development shortcuts for trying co-op on one computer, after "--" on the command line:
	#   --host[=PORT]          continue the save (or start one) and host at once
	#   --join=ADDRESS[:PORT]  join at once
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--host" or arg.begins_with("--host="):
			_open_main_menu()
			_on_menu_host(int(arg.get_slice("=", 1)) if arg.contains("=") else NetSession.DEFAULT_PORT, services.saves.has_save())
			return
		if arg.begins_with("--join="):
			var target := arg.get_slice("=", 1)
			_open_main_menu()
			_on_menu_join(target.get_slice(":", 0), int(target.get_slice(":", 1)) if target.contains(":") else NetSession.DEFAULT_PORT)
			return

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
	# Prompt 12: tutorial tracker, hints, specialist cues and the colony journal (J).
	tutorial = TutorialPresenter.new()
	tutorial.name = "TutorialPresenter"
	add_child(tutorial)
	tutorial.setup(world, services, self)
	# One thing at a time on screen: the HUD steps aside while a panel or menu is open.
	if not ui.menu_mode_changed.is_connected(_on_menu_mode_changed):
		ui.menu_mode_changed.connect(_on_menu_mode_changed)
	for door: DoorController in airlock_doors + garden_airlock_doors:
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
	# Prompt 09: the sky follows the dust in the air (after ZoneLighting, which owns the environment it adjusts), and
	# the weather data is checked for published updates in the background. The running game keeps its pinned data.
	weather_presenter = WeatherPresenter.new()
	weather_presenter.name = "WeatherPresenter"
	add_child(weather_presenter)
	weather_presenter.setup(world, services)
	scout_presenter = ScoutPresenter.new()
	add_child(scout_presenter)
	scout_presenter.setup(world, services, self)
	mission_hud = MissionHud.new()
	mission_hud.setup(world, services, self)
	# Prompt 11: voice. After the HUD (its corner goes under GameHud) and the doors (it reads them for sound).
	voice = VoiceService.new()
	voice.name = "Voice"
	add_child(voice)
	voice.setup(world, services, self)
	# Prompt 10: the rover. After the crew and the props: it hides the static map copy and drives its own body.
	rover = RoverPresenter.new()
	rover.name = "RoverPresenter"
	add_child(rover)
	rover.setup(world, services, self)
	if check_weather_updates and DisplayServer.get_name() != "headless":
		var refresh := WeatherRefresh.new()
		refresh.name = "WeatherRefresh"
		add_child(refresh)
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
	_main_menu.host_pressed.connect(_on_menu_host)
	_main_menu.join_pressed.connect(_on_menu_join)
	_main_menu.quit_pressed.connect(func() -> void: get_tree().quit())
	ui.open(_main_menu)
	if menu_notice != "":
		_main_menu.show_notice(menu_notice)
		menu_notice = ""


## A message for the next main menu, kept across the scene reload (for example "the host closed the colony").
static var menu_notice := ""


## Host: open the colony (saved or new), then listen on `port` for up to three other players.
func _on_menu_host(port: int, continue_save: bool) -> void:
	if continue_save:
		var loaded := services.continue_game()
		if not loaded.is_usable():
			_main_menu.show_notice("The saved colony could not be opened (%s). Untick \"Continue my saved colony\" to host a new one." % loaded.status)
			return
	else:
		if services.saves.has_save() and not _confirm_new:
			_confirm_new = true
			_main_menu.show_notice("Hosting a new colony replaces your saved one (the old save is kept as a backup). Press Start hosting again to go ahead, or tick \"Continue my saved colony\".")
			return
		services.start_new_game()
	var err := services.net.host(port)
	if err != OK:
		_main_menu.show_notice("Could not host on port %d (%s). Another program may be using it: try another port." % [port, error_string(err)])
		return
	_hook_net()
	_begin_play()
	_announce_hosting()


## Join: connect, wait for the host's colony, then play. The menu stays up until the colony arrives.
func _on_menu_join(address: String, port: int) -> void:
	if services.net.is_joining():
		return
	_hook_net()
	var err := services.net.join(address, port)
	if err != OK:
		_main_menu.show_notice("Could not start connecting (%s). Check the address." % error_string(err))
		return
	_main_menu.show_notice("Connecting to %s:%d…" % [address, port])


func _hook_net() -> void:
	var net := services.net
	if net.joined.is_connected(_on_net_joined):
		return
	net.joined.connect(_on_net_joined)
	net.join_failed.connect(func(reason: String) -> void:
		if _main_menu != null and is_instance_valid(_main_menu):
			_main_menu.show_notice(reason))
	net.host_lost.connect(func(reason: String) -> void:
		menu_notice = reason
		get_tree().reload_current_scene())
	net.peer_connected.connect(func(peer: int) -> void: _say_crew_change(peer, true))
	net.peer_disconnected.connect(func(peer: int) -> void: _say_crew_change(peer, false))


func _on_net_joined(_peer: int) -> void:
	if not _playing:
		_begin_play()
		var me := _local_character()
		ui.show_subtitle("Joined the colony%s." % (" as %s" % me.display_name if me != null else ""), 6.0, "", true)


func _announce_hosting() -> void:
	var addrs := NetSession.lan_addresses()
	var where := " or ".join(Array(addrs.slice(0, 3))) if not addrs.is_empty() else "this computer's address"
	ui.show_subtitle("Hosting. Other players choose Join a colony and type %s, port %d. The pause menu shows this again." % [where, services.net.port], 14.0, "Network", true)


func _say_crew_change(peer: int, joined_now: bool) -> void:
	if hud == null:
		return
	var c := services.state().character_of_peer(peer) if joined_now and services.has_game() else null
	if c != null:
		hud.show_message("A new player joined the colony as %s." % c.display_name, 4.0)
	else:
		hud.show_message("A player %s the colony." % ("joined" if joined_now else "left"), 4.0)


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
	# The network peer lives on the SceneTree, not in this scene: close it, or the next Host finds the port taken.
	services.net.leave()
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
		services.events.action_resolved.connect(player.resolve_answer)
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
				v.add_child(_presence_body())
			if not c.is_active():
				# Parked crew stand still at the hub; crew other players control are moved smoothly by _move_crew.
				v.global_position = c.position
				v.rotation.y = c.yaw
				v.play(&"idle")
			v.set_suit(c.suit_on)
			v.set_name_tag(CrewLooks.tag_text(c.display_name, _identity_of(c)))   # other crew only, never your own body
			# Only crew someone is playing are "there" for doors: parked crew on the hub ring must not hold a door open.
			(v.get_node("Presence") as CollisionObject3D).collision_layer = Layers.CREW_SOLID | (Layers.PLAYER if c.is_active() else 0)
			if services.zones != null:
				v.set_zone_layers(_layers_for(services.zones.zone_at_world(c.position)))


## Other crew are drawn, not simulated, but doors sense bodies on the PLAYER layer: give each one a capsule there so a
## door opens for every player on every screen. CREW_SOLID also stops local players walking through active or parked crew.
func _presence_body() -> AnimatableBody3D:
	var tuning := PlayerTuning.new()
	var body := AnimatableBody3D.new()
	body.name = "Presence"
	body.sync_to_physics = false
	body.collision_layer = Layers.CREW_SOLID  # _rebuild_crew adds door sensing for active crew
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = tuning.body_radius_m
	capsule.height = tuning.body_height_m
	shape.shape = capsule
	shape.position.y = tuning.body_height_m / 2.0
	body.add_child(shape)
	return body


## Moves the bodies of crew other players control toward their last reported pose (positions arrive about 20 times a
## second) and picks idle, walk or sprint from how fast they actually move.
func _move_crew(delta: float) -> void:
	var st := services.state()
	var follow := 1.0 - exp(-delta * 14.0)
	for id: StringName in _crew_visuals:
		var c := st.character(id)
		var v := _crew_visuals[id] as PlayerVisual
		if c == null or v == null or not c.is_active():
			continue
		var before := v.global_position
		var gap := c.position - before
		v.global_position = c.position if gap.length() > 6.0 else before + gap * follow      # snap after a teleport
		v.rotation.y = lerp_angle(v.rotation.y, c.yaw, follow)
		var moved := v.global_position - before
		var speed := Vector2(moved.x, moved.z).length() / maxf(delta, 1e-4)
		var smoothed := lerpf(float(v.get_meta(&"speed", 0.0)), speed, 1.0 - exp(-delta * 8.0))
		v.set_meta(&"speed", smoothed)
		var holding := false
		for item_id: String in st.items:
			if String((st.items[item_id] as Dictionary).get("holder", "")) == String(id):
				holding = true
				break
		if holding:
			v.play(&"carry")
		elif smoothed < 0.15:
			v.play(&"idle")
		elif smoothed < 2.6:
			v.play(&"walk", clampf(smoothed / PlayerVisual.WALK_CLIP_SPEED, PlayerVisual.MIN_CLIP_SCALE, PlayerVisual.MAX_CLIP_SCALE))
		else:
			v.play(&"sprint", clampf(smoothed / PlayerVisual.SPRINT_CLIP_SPEED, PlayerVisual.MIN_CLIP_SCALE, PlayerVisual.MAX_CLIP_SCALE))


## Everything the local player asks for goes to the host through here.
func _submit(action: StringName, target: StringName, params: Dictionary) -> ActionResult:
	if action == &"use_station":
		# Opening a station's surface changes nothing; every control on it is its own validated request.
		var panel := StationPanels.for_station(target, services)
		if panel != null:
			ui.open(panel)
			return ActionResult.success("", {})
		if not services.is_authority():
			# A client never runs the session itself: ask the host for the station's action instead.
			var st := services.state()
			var kind := String((st.stations.get(target, {}) as Dictionary).get("kind", "")) if st.stations.has(target) else ""
			if not LegacyStations.KIND_ACTION.has(kind):
				return ActionResult.failure("", &"not_available_yet" if kind != "" else &"unknown_target")
			return services.request(LegacyStations.KIND_ACTION[kind], target, params)
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
	_move_crew(_delta)
	SuitDisplays.sync(get_tree(), services.state())
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
		for id: StringName in _crew_visuals:
			var v := _crew_visuals[id] as PlayerVisual
			v.set_zone_layers(_layers_for(services.zones.zone_at_world(v.global_position)))


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
