class_name GameServices
extends Node
## The running game's services in one place: settings, events, the host session and saving.
## It is a plain node (the game scene adds it; it is not an autoload), so tools and tests can make their own.
##
## Who does what:
##   SessionService  the host's authority: clock, simulation ticks, validated actions, crew ownership, pause
##   SaveService     files on disk: versioned JSON, safe replacement, backups, migrations
##   GameServices    glue: new game / continue, what goes into a save, when to save
## Presentation (player body, cameras, lights, HUD) only listens to `events` and sends requests.

const GROUP := &"game_services"
const CONFIG_PATH := "res://config/game_config.tres"
const BALANCE_PATH := "res://config/game_balance.tres"
const MANIFEST_PATH := "res://data/colony_manifest.json"

var config: GameConfig
var balance: GameBalance
var events: GameEvents
var session: SessionService
var saves: SaveService
var zones: ColonyZones
## Result of the last continue_game(), for the menu to explain what happened.
var last_load: SaveLoadResult
## LAN session, or null while playing alone. See NetSession.
var net: NetSession
## &"offline" (solo), &"host" (owns the colony and the save) or &"client" (shows the host's colony).
var mode: StringName = &"offline"

var _autosave_left := 0.0
var _pending_save: StringName = &""


## The services node of a scene tree, or null.
static func find(tree: SceneTree) -> GameServices:
	return tree.get_first_node_in_group(GROUP) as GameServices


func _init() -> void:
	config = _load_resource(CONFIG_PATH, GameConfig.new()) as GameConfig
	balance = _load_resource(BALANCE_PATH, GameBalance.new()) as GameBalance
	events = GameEvents.new()
	events.name = "Events"
	add_child(events)
	session = SessionService.new(config, balance, events)
	saves = SaveService.new(config.save_dir, config.save_name, config.backup_count)
	if FileAccess.file_exists(MANIFEST_PATH):
		zones = ColonyZones.from_manifest(MANIFEST_PATH)
	events.state_changed.connect(_on_state_changed)
	events.character_recovered.connect(func(_id: StringName, _info: Dictionary) -> void: _pending_save = &"recovery")


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS          # the game has its own pause rule; the tree pause is not used for it
	get_tree().auto_accept_quit = false               # closing the window saves first (see _notification)


func state() -> ColonyState:
	return session.state


func clock() -> SolClock:
	return session.clock


func has_game() -> bool:
	return session.state != null


## Network peer id of this machine: 1 when solo or hosting.
func local_peer() -> int:
	if mode == &"client" and net != null:
		return net.local_peer()
	return SessionService.HOST_PEER


## True when this machine owns the colony: it ticks the simulation, validates actions and writes the save.
func is_authority() -> bool:
	return mode != &"client"


## The character this machine's player controls, or null.
func local_character() -> CharacterState:
	return session.state.character_of_peer(local_peer()) if has_game() else null


## Every request from this machine's player goes through here. On a client it is sent to the host and a
## pending answer comes back at once; the host's real answer arrives as events.action_resolved.
func request(action: StringName, target: StringName = &"", params := {}) -> ActionResult:
	if mode == &"client":
		if net == null:
			return ActionResult.failure("", &"offline")
		return net.send_request(action, target, params)
	return session.request(action, target, params, local_peer())


## Reports where this machine's player body is. The host checks ownership before storing it.
func report_position(character_id: StringName, position: Vector3, yaw: float) -> void:
	if mode == &"client":
		if net != null:
			net.send_position(character_id, position, yaw)
		return
	session.report_position(local_peer(), character_id, position, yaw)


## Starts a fresh colony. The host takes `host_character`. `seed_value` < 0 picks a seed from the system clock.
func start_new_game(seed_value := -1, host_character: StringName = &"crew_1") -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0) & 0x7fffffff
	var zone_names := zones.names if zones != null else PackedStringArray()
	var st := ColonyState.new_game(balance, seed_value, zone_names)
	if zones != null:
		st.stations = StationCatalog.from_manifest(MANIFEST_PATH, zones)
	_place_crew_at_hub(st, true)
	# REHEARSAL PROPS: three crates by the hub so carrying can be played before real cargo exists.
	for i in 3:
		var p := config.hub_position + Vector3(2.2 + 0.7 * float(i), 0.0, 1.5)
		st.items["crate_%d" % (i + 1)] = {"kind": "supply_crate", "position": [p.x, p.y, p.z], "holder": ""}
	var c := SolClock.new()
	c.sol_minutes = config.clamp_sol_minutes(config.sol_minutes_default)
	c.phase = config.start_phase
	session.begin(st, c)
	session.request(&"claim_character", host_character)
	_autosave_left = config.autosave_seconds
	_pending_save = &""
	events.game_loaded.emit("new")
	save_now(&"new_game")


## Loads the newest usable save. Returns what happened; on anything but a usable result the current game is untouched.
func continue_game() -> SaveLoadResult:
	last_load = saves.read()
	if last_load.is_usable():
		restore(last_load.payload)
		events.game_loaded.emit(last_load.source_path)
	return last_load


## Everything a save holds. Voice and anything on screen are not part of it.
func snapshot() -> Dictionary:
	session.sync_rng_to_state()
	var colony := session.state.to_dict()
	# Network peers belong to one play session, not to the colony: the save only remembers who the host was playing.
	var host_character := ""
	var chars: Dictionary = colony["characters"]
	for id: String in chars:
		var c: Dictionary = chars[id]
		if int(c["owner_peer"]) == SessionService.HOST_PEER:
			host_character = id
		c["owner_peer"] = 0
	return {"clock": session.clock.to_dict(), "colony": colony, "session": {"host_character": host_character}}


## Puts a saved game back. No real time is added for the time the game was closed.
func restore(payload: Dictionary) -> void:
	var st := ColonyState.from_dict(payload.get("colony", {}))
	var c := SolClock.from_dict(payload.get("clock", {}))
	var host_character := StringName(String((payload.get("session", {}) as Dictionary).get("host_character", "")))
	_place_crew_at_hub(st, false, host_character)
	session.begin(st, c)
	if st.characters.has(host_character):
		session.request(&"claim_character", host_character)
	_autosave_left = config.autosave_seconds
	_pending_save = &""


func save_now(reason: StringName = &"manual") -> Error:
	if not has_game() or not is_authority():
		return ERR_UNCONFIGURED
	var err := saves.write(snapshot(), reason)
	_pending_save = &""
	_autosave_left = config.autosave_seconds
	if err == OK:
		events.game_saved.emit(saves.main_path(), reason)
	else:
		push_warning("Save failed (%s): %s. The previous save is still in place." % [reason, error_string(err)])
	return err


## Saves, then leaves. Use this for "Quit" in the menu; closing the window does the same.
func quit_game() -> void:
	save_now(&"quit")
	get_tree().quit()


func _process(delta: float) -> void:
	if not has_game() or not is_authority():
		return
	session.advance(delta)
	if _pending_save != &"":
		save_now(_pending_save)
	elif not session.paused:
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			save_now(&"autosave")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func _on_state_changed(reason: StringName) -> void:
	if reason == &"tick" or not is_authority():
		return
	var def := session.actions.definition(reason)
	if def != null and def.important:
		_pending_save = reason


## Parked crew wait at the hub. On a new game everyone starts there; on load only crew nobody will control are moved.
func _place_crew_at_hub(st: ColonyState, everyone: bool, keep: StringName = &"") -> void:
	var ids := st.characters.keys()
	ids.sort()
	for i in ids.size():
		var c := st.characters[ids[i]] as CharacterState
		if everyone:
			var angle := TAU * float(i) / float(maxi(1, ids.size()))
			c.hub_spot = config.hub_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.2
			c.position = c.hub_spot
			c.yaw = angle
		elif c.id != keep:
			c.position = c.hub_spot


static func _load_resource(path: String, fallback: Resource) -> Resource:
	if ResourceLoader.exists(path):
		var r := load(path)
		if r != null:
			return r
	return fallback
