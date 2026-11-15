extends SceneTree
## Regression checks for the reported suit lifecycle, map corrections, camera obstruction and real ladder motion.
var passed := 0
var total := 0

func _initialize() -> void:
	await process_frame
	var session := _test_suits()
	await _test_ladder()
	await _test_map(session)
	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)

func _test_suits() -> SessionService:
	var session := SessionService.new(GameConfig.new(), GameBalance.new(), GameEvents.new())
	var state := ColonyState.new_game(session.balance, 42, PackedStringArray(["Airlock"]))
	state.stations = StationCatalog.from_manifest("res://data/colony_manifest.json", ColonyZones.from_manifest("res://data/colony_manifest.json"))
	session.begin(state, SolClock.new())
	var rack: StringName = &"al_suit_rack"
	for i in 4:
		var c := state.character(StringName("crew_%d" % (i + 1)))
		c.owner_peer = i + 1
		c.position = CharacterState._v3(state.stations[String(rack)].position)
		c.suit_charge = 37.0
		if i > 0:
			session.peer_joined(i + 1)
		_check("crew %d reserves a separate suit" % i, session.request(&"begin_suit_check", rack, {"on": true}, i + 1).ok)
	_check("four concurrent checks reserve all slots", session.available_suit_slot(rack) == -1)
	var fourth := state.character(&"crew_4")
	var at := fourth.position
	fourth.position += Vector3(10, 0, 0)
	session.advance(0.1)
	_check("walking away releases reservation", session.available_suit_slot(rack) == 3 and not fourth.suit_on)
	fourth.position = at
	_check("cancelled suit can be reserved again", session.request(&"begin_suit_check", rack, {"on": true}, 4).ok)
	session.advance(session.config.suit_check_seconds + 0.1)
	var slots := {}
	for c: CharacterState in state.characters.values():
		slots[c.suit_slot] = true
		_check("worn suit remembers rack and preserves charge", c.suit_on and c.suit_rack == rack and is_equal_approx(c.suit_charge, 37.0))
	_check("four distinct worn suits", slots.size() == 4 and session.available_suit_slot(rack) == -1)
	var restored := ColonyState.from_dict(state.to_dict())
	for id in state.characters:
		_check("saved/replicated suit identity survives", restored.character(id).suit_slot == state.character(id).suit_slot and restored.character(id).suit_rack == rack)
	for c: CharacterState in restored.characters.values():
		c.suit_slot = -1
		c.suit_rack = &""
	var old := SessionService.new(session.config, session.balance, GameEvents.new())
	old.begin(restored, SolClock.new())
	slots.clear()
	for c: CharacterState in restored.characters.values():
		slots[c.suit_slot] = true
	_check("old saves get four unique slots", slots.size() == 4 and not slots.has(-1))
	return session

func _test_ladder() -> void:
	var collision := WorldCollision.build("res://data/colony_manifest.json", "res://data/colliders.json")
	root.add_child(collision)
	var ladder := collision.get_node("hgw_ladder") as ClimbableLadder
	_check("authored ladder has a climb volume", ladder != null)
	var c := CharacterState.new()
	var player := PlayerController.new()
	player.setup(GameConfig.new(), PlayerTuning.new(), c, Callable(), Callable())
	root.add_child(player)
	player.teleport(Vector3(27.66, 0.04, -0.33), -PI / 2)
	await _frames(5)
	_check("ladder can be aimed at from its foot", player.aimed_target().kind == "ladder")
	player._interact()
	Input.action_press("move_forward")
	await _frames(135)
	Input.action_release("move_forward")
	await _frames(5)
	_check("climb exits onto the real mezzanine", player.global_position.y > 2.65 and player.global_position.x > 28.2)
	player._ladder = ladder
	Input.action_press("move_back")
	await _frames(160)
	Input.action_release("move_back")
	await _frames(5)
	_check("descend reaches hangar floor", player.global_position.y < 0.2)
	player._ladder = ladder
	player.input_enabled = false
	var before := player.position
	Input.action_press("move_forward")
	await _frames(10)
	Input.action_release("move_forward")
	_check("menus pause ladder input", player.position.is_equal_approx(before))
	player.visual().set_first_person(false)
	player.visual().set_camera_obstructed(true)
	var hidden := true
	for mi in player.visual().find_children("*", "MeshInstance3D", true, false):
		hidden = hidden and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check("retracted camera never draws inside own body", hidden)
	player.queue_free()
	collision.queue_free()
	await process_frame

func _test_map(session: SessionService) -> void:
	var world := (load("res://assets/colony/colony.glb") as PackedScene).instantiate()
	root.add_child(world)
	var stats := HabitatFinish.new().apply(world)
	_check("interior surfaces corrected", int(stats.cleaned) > 500)
	_check("both planters show soil", int(stats.soil) == 2)
	_check("one chess set corrected", int(stats.chess) == 1)
	var white := 0
	var black := 0
	for n in world.find_children("*", "Node3D", true, false):
		if n.has_meta("chess_side"):
			if int(n.get_meta("chess_side")) == 0: white += 1
			else: black += 1
	_check("chess has 16 pieces per side", white == 16 and black == 16)
	var removed := 0
	var outside_unchanged := true
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var asset := String(mi.get_meta("gc_asset", ""))
		if asset in HabitatFinish.REMOVE:
			removed += 1
			_check("reported unwanted object hidden: " + String(mi.name), not mi.visible)
		if String(mi.get_meta("area", "")) == "Exterior":
			for surface in mi.mesh.get_surface_count():
				outside_unchanged = outside_unchanged and mi.get_surface_override_material(surface) == null
	_check("outside finishes preserved", outside_unchanged)
	_check("drain grates, wire and footprints located", removed >= 5)
	# 2026-11-14: drain tiles keep a whole floor (hiding them left holes to the sand)
	var drain_tiles := 0
	var drain_floors_whole := true
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		if String(mi.get_meta("gc_asset", "")) == "gr_floor_drain":
			drain_tiles += 1
			var plain := world.find_child("gr_floor", true, false) as MeshInstance3D
			drain_floors_whole = drain_floors_whole and mi.visible and plain != null and mi.mesh == plain.mesh
	_check("greenhouse drain tiles drawn as whole floor tiles", drain_tiles == 3 and drain_floors_whole and int(stats.floors) == 3)
	var deck := DomeDeck.build(world, "res://data/colony_manifest.json")
	var deck_aabb := deck.get_aabb()
	_check("dome plaza has a deck floor over the hall footprint", deck.mesh.get_surface_count() == 1 and deck_aabb.size.x > 50.0
		and deck_aabb.size.z > 30.0 and absf(deck_aabb.position.y - DomeDeck.Y) < 0.001 and deck.layers != 0)
	_check("greenhouse has cleaning equipment", world.find_child("GreenhouseCleaningTools", true, false) != null)
	SuitDisplays.build(world)
	var visual := PlayerVisual.new()
	world.add_child(visual)
	visual.use_rig_if_available()
	visual.set_suit(true)
	visual.set_first_person(true)
	var bands_hidden := true
	for part in visual.find_children("Ident_*", "MeshInstance3D", true, false):
		bands_hidden = bands_hidden and part.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check("helmet identity bands cannot enter first-person jump view", bands_hidden)
	var displays := get_nodes_in_group(&"rack_suit_display")
	_check("rack displays four suits", displays.size() == 4)
	SuitDisplays.sync(self, session.state)
	var visible := 0
	for d in displays: if d.visible: visible += 1
	_check("four worn suits disappear from rack", visible == 0)
	var c := session.state.character(&"crew_2")
	var slot := c.suit_slot
	_check("return check starts", session.request(&"begin_suit_check", c.suit_rack, {"on": false}, c.owner_peer).ok)
	session.advance(session.config.suit_check_seconds + 0.1)
	SuitDisplays.sync(self, session.state)
	visible = 0
	var original_slot := false
	for d in displays:
		if d.visible:
			visible += 1
			original_slot = int(d.get_meta("suit_slot")) == slot
	_check("returned suit reappears in exact original slot", visible == 1 and original_slot)
	world.queue_free()
	await process_frame

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _check(label: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
		print("PASS " + label)
	else:
		print("FAIL " + label)
