extends SceneTree
## C01/C02 host behavior, durable shared collection and local world presentation.

class RecordingHud extends GameHud:
	var heard: Array[String] = []
	func show_message(text: String, _seconds := 3.0) -> void:
		heard.append(text)

var _passed := 0
var _total := 0
var _sessions: Array[SessionService] = []
var _zones: ColonyZones
var _stations: Dictionary

func _initialize() -> void:
	_zones = ColonyZones.from_manifest("res://data/colony_manifest.json")
	_stations = StationCatalog.from_manifest("res://data/colony_manifest.json", _zones)
	_collection()
	_playback_authority()
	_reader_lifecycle()
	_persistence_and_props()
	_pickup_feedback()
	for session: SessionService in _sessions:
		session.events.free()
	print("RESULT %d/%d" % [_passed, _total])
	quit(0 if _passed == _total else 1)

func _check(label: String, okay: bool) -> void:
	_total += 1
	if okay:
		_passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label)

func _session() -> SessionService:
	var session := SessionService.new(GameConfig.new(), GameBalance.new(), GameEvents.new())
	var state := ColonyState.new_game(session.balance, 731)
	state.stations = _stations.duplicate(true)
	session.zone_at_position = func(position: Vector3) -> String: return _zones.zone_at_world(position)
	for actor: CharacterState in state.characters.values():
		actor.position = session.config.hub_position
		actor.hub_spot = actor.position
	session.begin(state, SolClock.new())
	state.character(&"crew_1").owner_peer = 1
	session.peer_joined(2)
	state.character(&"crew_2").owner_peer = 2
	_sessions.append(session)
	return session

func _at(session: SessionService, station_id: String, peer := 1) -> void:
	var actor := session.state.character_of_peer(peer)
	session.report_position(peer, actor.id, CharacterState._v3(session.state.stations[station_id].position), 0.0)

func _collect_all(session: SessionService) -> void:
	for id: String in CassetteCatalog.TAPES:
		_at(session, id)
		session.request(&"cassette_collect", StringName(id))

func _collection() -> void:
	var s := _session()
	_check("six distinct room cassette identities", CassetteCatalog.TAPES.size() == 6 and CassetteCatalog.TAPES.cassette_greenhouse.room_id != CassetteCatalog.TAPES.cassette_green_dome.room_id)
	var actor := s.state.character_of_peer(1)
	actor.cargo = [&"full_1", &"full_2", &"full_3", &"full_4", &"full_5", &"full_6"]
	var original_cargo := actor.cargo.duplicate()
	var original_stores := s.state.stores.duplicate()
	for id: String in CassetteCatalog.TAPES:
		_at(s, id)
		_at(s, id, 2)
		var req := ActionRequest.make("collect_" + id, 1, actor.id, &"cassette_collect", StringName(id))
		var result := s.submit(req)
		_check("collect %s once with full cargo" % id, result.ok and result.changes.cassette_id == id and result.changes.collected and CassetteCatalog.collected(s.state, id))
		_check("simultaneous other peer cannot duplicate %s" % id, s.request(&"cassette_collect", StringName(id), {}, 2).reason == &"already_collected")
		_check("network replay is idempotent %s" % id, s.submit(req).duplicate and (s.state.repair.collected_cassettes as Array).count(id) == 1)
		_check("pickup exposes metadata only %s" % id, not result.changes.has("pages") and not result.changes.has("image_path") and not result.changes.has("caption"))
	_check("collection independent of cargo and resources", actor.cargo == original_cargo and s.state.stores == original_stores and s.state.repair.collected_cassettes.size() == 6)
	_at(s, "cassette_med_bay")
	_check("another peer cannot act as owned crew", s.submit(ActionRequest.make("forged_actor", 2, actor.id, &"cassette_collect", &"cassette_med_bay")).reason == &"not_owner")
	actor.health = 0.0
	_check("dead crew cannot collect", not s.request(&"cassette_collect", &"cassette_med_bay").ok)
	actor.health = 100.0
	s.state.repair.collected_cassettes.clear()
	s.state.stations.cassette_med_bay.room_id = "greenhouse"
	_check("pickup rejects mismatched canonical room metadata", s.request(&"cassette_collect", &"cassette_med_bay").reason == &"wrong_target")
	s.state.stations.cassette_med_bay.room_id = "med_bay"
	s.zone_at_position = func(_position: Vector3) -> String: return "Command Room"
	_check("pickup validates actual actor room", s.request(&"cassette_collect", &"cassette_med_bay").reason == &"wrong_room")

func _playback_authority() -> void:
	var s := _session()
	_collect_all(s)
	var player_id := StringName(CassetteCatalog.PLAYER_ID)
	_at(s, "cassette_med_bay")
	for id: String in CassetteCatalog.TAPES:
		_check("direct open/read away rejected %s" % id, not s.request(&"cassette_open", player_id).ok and not s.request(&"cassette_select", player_id, {"cassette_id": id}).ok and not s.request(&"cassette_read", player_id, {"cassette_id": id, "page": 0}).ok)
	_at(s, CassetteCatalog.PLAYER_ID)
	_check("read requires station opening first", s.request(&"cassette_select", player_id, {"cassette_id": "cassette_med_bay"}).reason == &"play_at_command")
	var opened := s.request(&"cassette_open", player_id)
	_check("initial damaged room player opens without repair prerequisite", opened.ok and opened.changes.authorized and s.cassette_runtime.is_authorized(1) and not s.state.repair.rooms.command_center.first_completed)
	for id: String in CassetteCatalog.TAPES:
		var count := CassetteCatalog.page_count(id)
		_check("packaged local photograph and briefing %s" % id, count > 0)
		var selected := s.request(&"cassette_select", player_id, {"cassette_id": id})
		_check("each collected tape selectable only at player %s" % id, selected.ok and selected.changes.cassette_id == id and int(selected.changes.page) == 0)
		var read := s.request(&"cassette_read", player_id, {"cassette_id": id, "page": maxi(0, count - 1)})
		_check("host authorizes real page %s" % id, read.ok and read.changes.authorized and not read.changes.has("pages") and not read.changes.has("image_path"))
		_check("page beyond packaged record rejected %s" % id, not s.request(&"cassette_read", player_id, {"cassette_id": id, "page": count}).ok)
	_check("negative page rejected", s.request(&"cassette_read", player_id, {"cassette_id": "cassette_hangar", "page": -1}).reason == &"bad_request")
	s.state.repair.collected_cassettes.erase("cassette_med_bay")
	_check("missing tape remains locked", s.request(&"cassette_select", player_id, {"cassette_id": "cassette_med_bay"}).reason == &"cassette_missing")
	s.state.stations.fake_player = s.state.stations[CassetteCatalog.PLAYER_ID].duplicate(true)
	_check("fake playback anchor rejected", not s.request(&"cassette_open", &"fake_player").ok)
	s.state.stations[CassetteCatalog.PLAYER_ID].room_id = "med_bay"
	_check("player room metadata must be canonical", not s.request(&"cassette_open", player_id).ok)
	s.state.stations[CassetteCatalog.PLAYER_ID].room_id = "command_center"
	s.zone_at_position = func(_position: Vector3) -> String: return "Med Bay"
	_check("player checks actual actor room", not s.request(&"cassette_open", player_id).ok)

func _reader_lifecycle() -> void:
	var s := _session()
	_collect_all(s)
	var player_id := StringName(CassetteCatalog.PLAYER_ID)
	_at(s, CassetteCatalog.PLAYER_ID)
	_at(s, CassetteCatalog.PLAYER_ID, 2)
	var actor := s.state.character_of_peer(1)
	var req := ActionRequest.make("open_once", 1, actor.id, &"cassette_open", player_id)
	s.submit(req)
	s.request(&"cassette_open", player_id, {}, 2)
	_check("playback library is not exclusive between peers", s.cassette_runtime.is_authorized(1) and s.cassette_runtime.is_authorized(2) and s.cassette_runtime.readers.size() == 2)
	_at(s, "cassette_med_bay")
	_check("walking away revokes reader immediately", not s.cassette_runtime.is_authorized(1) and not s.cassette_runtime.readers.has("1"))
	var replay := s.submit(req)
	_check("cached old open cannot restore revoked permission", replay.duplicate and not s.cassette_runtime.is_authorized(1))
	_at(s, CassetteCatalog.PLAYER_ID)
	s.request(&"cassette_open", player_id)
	actor.health = 0.0
	s.cassette_runtime.prune(s)
	_check("death revokes playback", not s.cassette_runtime.is_authorized(1))
	actor.health = 100.0
	s.request(&"cassette_open", player_id)
	s.recover_character(actor.id)
	_check("recovery releases playback", not s.cassette_runtime.readers.has("1"))
	s.peer_left(2)
	_check("disconnect releases playback", not s.cassette_runtime.readers.has("2"))
	_at(s, CassetteCatalog.PLAYER_ID)
	s.request(&"cassette_open", player_id)
	s.state.stations.erase(CassetteCatalog.PLAYER_ID)
	s.cassette_runtime.prune(s)
	_check("station invalidation revokes playback", not s.cassette_runtime.is_authorized(1))
	_check("close always releases even away from station", s.request(&"cassette_close", player_id).ok)
	var clock_before := s.clock.real_seconds
	s.advance(0.25)
	_check("cassette UI never pauses simulation", not s.paused and s.clock.real_seconds > clock_before)

func _persistence_and_props() -> void:
	var s := _session()
	_collect_all(s)
	_at(s, CassetteCatalog.PLAYER_ID)
	s.request(&"cassette_open", StringName(CassetteCatalog.PLAYER_ID))
	var services := GameServices.new()
	services.session.begin(s.state, s.clock)
	services.saves = SaveService.new(ProjectSettings.globalize_path("res://tests/tmp/cassettes"), "fixture")
	services.saves.delete_all()
	_check("shared collection writes real save fixture", services.save_now(&"cassette_fixture") == OK)
	var saved := services.saves.read()
	_check("cassette reader permission never persists", saved.is_usable() and not saved.payload.session.has("cassettes") and not saved.payload.colony.repair.has("readers"))
	services.restore(saved.payload)
	_check("all six remain collected after disk restore", services.state().repair.collected_cassettes.size() == 6 and services.session.cassette_runtime.readers.is_empty())
	var late := _session()
	late.state.assign_from(s.state.to_dict())
	late.apply_replica(s.replica_dict())
	_check("late snapshot has shared collection and live reader", late.state.repair.collected_cassettes.size() == 6 and late.cassette_runtime.is_authorized(1))
	var collision := Node3D.new()
	var stations := Node3D.new()
	stations.name = "Stations"
	collision.add_child(stations)
	for id: String in CassetteCatalog.TAPES:
		var area := Area3D.new()
		area.name = id
		area.collision_layer = Layers.STATION
		stations.add_child(area)
	var player := Area3D.new()
	player.name = CassetteCatalog.PLAYER_ID
	stations.add_child(player)
	var presenter := CassettePresenter.new()
	presenter.setup(services, collision)
	_check("six locally distinct original cassette models", presenter.cassette_nodes.size() == 6 and (stations.get_node("cassette_med_bay/CassetteModel/RoomLabel") as Label3D).text != (stations.get_node("cassette_greenhouse/CassetteModel/RoomLabel") as Label3D).text)
	var hidden := true
	for area: Area3D in presenter.cassette_nodes.values():
		hidden = hidden and not area.visible and area.collision_layer == 0
	_check("collected props disappear and cannot be targeted after late load", hidden)
	services.state().repair.collected_cassettes.clear()
	presenter.refresh()
	var visible := true
	for area: Area3D in presenter.cassette_nodes.values():
		visible = visible and area.visible and area.collision_layer == Layers.STATION
	_check("new colony props are visible and interactable", visible)
	_check("cassette models create no solid collision traps", collision.find_children("*", "PhysicsBody3D", true, false).is_empty() and player.has_node("CassettePlayerModel"))
	presenter.free()
	collision.free()
	services.saves.delete_all()
	services.free()

func _pickup_feedback() -> void:
	var s := _session()
	var services := GameServices.new()
	services.session.begin(s.state, s.clock)
	services.session.peer_joined(2)
	var hud := RecordingHud.new()
	hud.services = services
	services.events.action_resolved.connect(hud._on_action_resolved)
	_at(services.session, "cassette_med_bay")
	var req := ActionRequest.make("feedback_pickup", 1, services.local_character().id, &"cassette_collect", &"cassette_med_bay")
	var result := services.session.submit(req)
	var expected := "Collected: Med Bay. " + CassetteCatalog.PLAY_INSTRUCTION
	_check("successful pickup HUD shows only title and collection guidance", result.ok and hud.heard == [expected] and not hud.heard[0].contains(String(CassetteCatalog.metadata("cassette_med_bay").pages[0])))
	services.session.submit(req)
	_check("duplicate pickup success does not repeat HUD completion", hud.heard == [expected])
	var failure := services.session.request(&"cassette_collect", &"cassette_med_bay")
	_check("fresh duplicate pickup failure does not claim another completion", not failure.ok and hud.heard.size() == 2 and not hud.heard[1].begins_with("Collected:"))
	_at(services.session, "cassette_greenhouse", 2)
	var before := hud.heard.size()
	services.session.request(&"cassette_collect", &"cassette_greenhouse", {}, 2)
	_check("another peer's pickup does not emit local completion toast", hud.heard.size() == before)
	hud.free()
	services.free()
