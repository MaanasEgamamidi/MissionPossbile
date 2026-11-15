extends Node
## Decides WHEN this machine plays a cinematic (2026-11-14 owner whiteboard: "start outside broken base from video
## clip" and "after all fixes, a beauty shot of everything fixed"). Presentation only: it reads the replicated colony
## state and never sends a request, so the host simulation and the other players never wait for it.
##
## Intro: once per new colony per player (this machine remembers the colony seeds it has shown, in user://), when the
##   game starts in tutorial mode (GameConfig.tutorial_start_outside) and the tutorial is not done. A 23 s fly-in over
##   the colony that ends behind the crew at the exit tunnel's outer door, with Mission Control telling the story.
## Tour: when state.campaign.base_operational (written by the host's TutorialSystem) turns from false to true while
##   this machine is watching. Every client sees it from the replicated flag; a late joiner or a loaded save that is
##   already operational sees nothing (the flag was never false here). Waits while the player is unsafe, in a panel,
##   in a vehicle or flying the drone.
## Both are skippable (E, Space, Esc). Headless runs (tests, servers) and games started without the main menu
## (GameMain.show_menu = false: tests and capture tools) never play them unless `force` is set.

const Rail := preload("res://scripts/cinematics/cinematic_rail.gd")
const PlayerScript := preload("res://scripts/cinematics/cinematic_player.gd")
const NODE_NAME := "CinematicsPresenter"
const SEEN_PATH := "user://cinematics_seen.json"
const OPERATIONAL_KEY := "base_operational"
const SEEN_KEPT := 64

var game: Node
var world: Node3D
var services: GameServices
var player_node: Node            # cinematic_player.gd
## Tests: play even headless or without the main menu.
var force := false
## Where the seen intros are remembered (tests point it into _test_saves).
var seen_path := SEEN_PATH
## What happened (tests and the integrator read these).
var intro_played := false
var tour_played := false
var tour_pending := false
var intro_pending := false
var last_started: StringName = &""

var _intro_decided := false
## The base_operational value last seen here; null until the first look (a late join or a load starts "already true").
var _last_operational: Variant = null


## GameMain hook: `load(<this>).call(&"attach", game, world, services, game)` after the other presenters.
static func attach(p_game: Node, p_world: Node3D, p_services: GameServices, _host: Node = null) -> Node:
	var existing := p_game.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var me: Node = load("res://scripts/cinematics/cinematics_presenter.gd").new()
	me.name = NODE_NAME
	p_game.add_child(me)
	me.call(&"setup", p_game, p_world, p_services)
	return me


func setup(p_game: Node, p_world: Node3D, p_services: GameServices) -> void:
	game = p_game
	world = p_world
	services = p_services
	player_node = PlayerScript.new()
	player_node.name = "CinematicPlayer"
	add_child(player_node)


func is_playing() -> bool:
	return player_node != null and bool(player_node.call(&"is_playing"))


## Cinematics run here at all: a real window and a game started from the main menu (or `force`).
func enabled() -> bool:
	if force:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	return game == null or bool(game.get("show_menu"))


## state.campaign.base_operational as TutorialSystem writes it: {} until the base works, then {"done": true, "at_hours"}.
static func is_operational(st: ColonyState) -> bool:
	if st == null:
		return false
	var v: Variant = st.campaign.get(OPERATIONAL_KEY, null)
	if v is Dictionary:
		return bool((v as Dictionary).get("done", false))
	return v is bool and bool(v)


## The intro belongs to this colony and player: tutorial mode on, tutorial not done, base not yet operational, and
## this machine has not shown it for this colony.
func wants_intro() -> bool:
	if services == null or not services.has_game() or services.local_character() == null:
		return false
	var st := services.state()
	if not services.config.tutorial_start_outside or TutorialSystem.is_tutorial_done(st) or is_operational(st):
		return false
	return not has_seen_intro(_colony_key(st))


func _process(_delta: float) -> void:
	if services == null or not services.has_game():
		return
	var st := services.state()
	# ---- the tour: an edge of the replicated flag, seen on this machine
	var now := is_operational(st)
	if _last_operational == null:
		_last_operational = now
	elif now and not bool(_last_operational):
		_last_operational = true
		tour_pending = enabled()
	elif not now:
		_last_operational = false
	# ---- the intro: decided once, when the player body exists
	if not _intro_decided and _player() != null:
		_intro_decided = true
		intro_pending = enabled() and wants_intro()
	if intro_pending and not is_playing() and safe_to_start():
		intro_pending = false
		start(&"intro")
	elif tour_pending and not is_playing() and safe_to_start():
		tour_pending = false
		start(&"tour")


## Plays a sequence now ("intro" or "tour"). Returns false if it could not start.
func start(id: StringName) -> bool:
	if is_playing():
		return false
	var seq := Rail.sequence(String(id))
	var settings: GameSettings = game.get("settings") if game != null else null
	if not bool(player_node.call(&"play", seq, game, services, settings)):
		return false
	last_started = id
	if id == &"intro":
		intro_played = true
		mark_intro_seen(_colony_key(services.state()))
	elif id == &"tour":
		tour_played = true
	return true


## The local player can hand the camera over: alive, not in danger, no panel open, on foot, not flying the drone.
func safe_to_start() -> bool:
	var p := _player()
	if p == null or services.local_character() == null:
		return false
	var ui := game.get("ui") as UiRoot if game != null else null
	if ui != null and not ui.gameplay_has_focus():
		return false
	if p.is_seated():
		return false
	var drone: Variant = game.get("drone") if game != null else null
	if drone is Node and is_instance_valid(drone) and (drone as Node).has_method(&"blocks_player_input") and bool((drone as Node).call(&"blocks_player_input")):
		return false
	return PlayerScript.vitals_danger(services.local_character()) == &""


# ---------------------------------------------------------------- seen intros (this machine only)

func _colony_key(st: ColonyState) -> String:
	return str(st.rng_seed) if st != null else ""


func _read_seen() -> Dictionary:
	if not FileAccess.file_exists(seen_path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(seen_path))
	return v if v is Dictionary else {}


func has_seen_intro(key: String) -> bool:
	var list: Variant = _read_seen().get("intro", [])
	return list is Array and (list as Array).has(key)


func mark_intro_seen(key: String) -> void:
	var d := _read_seen()
	var list: Array = d.get("intro", []) if d.get("intro", []) is Array else []
	if not list.has(key):
		list.append(key)
	while list.size() > SEEN_KEPT:
		list.pop_front()
	d["intro"] = list
	var f := FileAccess.open(seen_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, " "))


func _player() -> PlayerController:
	var p: Variant = game.get("player") if game != null else null
	return p as PlayerController if p is PlayerController and is_instance_valid(p) else null
