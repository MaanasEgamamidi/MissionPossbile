extends SceneTree
## Perf overhaul, Phase 2 inventory (headless). Boots the real game (no menu, temporary save folder) and prints what the
## zone system needs to know: rooms, doors and the zones on each side of them, fixture lights per zone, reflection
## probes, glazed meshes per zone, mesh counts per render layer and the top of the world tree.
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/perf/probe_inventory.gd

var _game: Node = null
var _frames := 0


func _initialize() -> void:
	var save_dir := OS.get_user_data_dir().path_join("perf_probe_saves")
	DirAccess.make_dir_recursive_absolute(save_dir)
	_game = Node3D.new()
	_game.set_script(load("res://scripts/game/game_main.gd"))
	_game.set("show_menu", false)
	_game.set("check_weather_updates", false)
	_game.set("save_directory", save_dir)
	_game.name = "Game"
	root.add_child(_game)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 20:
		_dump()
		return true
	return false


func _dump() -> void:
	var services: GameServices = _game.get("services")
	var zones: ColonyZones = services.zones
	var world: Node3D = _game.get("world")
	var collision: Node3D = _game.get("collision")
	print("== ZONES ", zones.names)
	for r: Dictionary in zones.rooms:
		print("ROOM %s x[%.2f,%.2f] y[%.2f,%.2f] ceil=%s layer=%d" % [r.name, float(r.x0), float(r.x1), float(r.y0), float(r.y1), str(r.get("ceiling", "?")), zones.layer_of(String(r.name))])
	print("DOME ", zones.dome)
	print("== WORLD TOP")
	for c in world.get_children():
		print("  %s (%s) children=%d descendants=%d" % [c.name, c.get_class(), c.get_child_count(), c.find_children("*", "", true, false).size()])
	for top: String in ["Environment", "Terrain"]:
		var n := world.get_node_or_null(top)
		if n == null:
			continue
		for c in n.get_children():
			print("  %s/%s (%s) descendants=%d" % [top, c.name, c.get_class(), c.find_children("*", "", true, false).size()])
			for cc in c.get_children().slice(0, 12):
				print("     %s (%s) d=%d" % [cc.name, cc.get_class(), cc.find_children("*", "", true, false).size()])
	print("== DOORS")
	var doors: Array = collision.get_node("Doors").get_children()
	for extra in ["EnvironmentDoors"]:
		var n := collision.get_node_or_null(extra)
		if n != null:
			doors += n.get_children()
	for d in collision.find_children("*", "DoorController", true, false):
		if not doors.has(d):
			doors.append(d)
	for d: DoorController in doors:
		var sense := d.get_node_or_null("Sense") as Node3D
		var p: Vector3 = sense.global_position if sense != null else d.global_position
		var leaves := d.get_children().filter(func(n: Node) -> bool: return n is AnimatableBody3D)
		var axis := Vector3.ZERO
		if not leaves.is_empty():
			axis = (leaves[0] as Node3D).global_basis.x.normalized()
		var nrm := axis.cross(Vector3.UP).normalized()
		var a := zones.zone_at_world(p + nrm * 1.2)
		var b := zones.zone_at_world(p - nrm * 1.2)
		print("DOOR %d %s path=%s at=(%.2f,%.2f,%.2f) slide=(%.2f,%.2f,%.2f) side+=%s side-=%s partner=%s leaves=%d" % [d.door_id, d.name, collision.get_path_to(d), p.x, p.y, p.z, axis.x, axis.y, axis.z, a, b, str(d.partner.door_id) if d.partner != null else "-", leaves.size()])
	print("== LIGHTS")
	for n in world.get_node("Lights").get_children():
		var cnt := {}
		for l in n.get_children():
			var k := "%s%s" % [l.get_class(), "+sh" if (l as Light3D).shadow_enabled else ""]
			cnt[k] = int(cnt.get(k, 0)) + 1
		print("LIGHTS zone=%s %s" % [n.get_meta("zone", "?"), cnt])
	var others := {}
	for l in world.find_children("*", "Light3D", true, false):
		if l.get_parent().get_parent() != world.get_node("Lights"):
			others[String(world.get_path_to(l))] = l.get_class()
	print("OTHER LIGHTS ", others)
	print("== PROBES")
	var probes := world.get_node_or_null("ReflectionProbes")
	if probes != null:
		for p in probes.get_children():
			print("PROBE %s zone=%s mode=%d" % [p.name, p.get_meta("zone", "?"), (p as ReflectionProbe).update_mode])
	print("== MESHES PER LAYER (visual instances under world)")
	var per_layer := {}
	var total := 0
	for gi in world.find_children("*", "GeometryInstance3D", true, false):
		var layers := (gi as VisualInstance3D).layers
		total += 1
		for bit in 20:
			if layers & (1 << bit):
				per_layer[bit + 1] = int(per_layer.get(bit + 1, 0)) + 1
	print("GEOMETRY total=%d per_layer=%s" % [total, per_layer])
	var sub := {}
	for top in world.get_children():
		var c := 0
		var layer_union := 0
		for gi in top.find_children("*", "GeometryInstance3D", true, false):
			c += 1
			layer_union |= (gi as VisualInstance3D).layers
		sub[String(top.name)] = [c, layer_union]
	print("GEOMETRY per top node [count, layer union] ", sub)
	print("== GLAZING per zone")
	var glaze := {}
	for mi in world.get_node("Colony").find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for i in m3.mesh.get_surface_count():
			var m := m3.mesh.surface_get_material(i) as ShaderMaterial
			if m != null and m.shader != null and m.shader.resource_path.ends_with("colony_glass.gdshader"):
				var box: AABB = m3.global_transform * m3.mesh.get_aabb()
				var key := "%s|layers=%d" % [m3.get_meta("area", "?"), m3.layers]
				glaze[key] = int(glaze.get(key, 0)) + 1
				break
	for k in glaze:
		print("GLAZE ", k, " x", glaze[k])
	print("== CAMERA")
	var player: PlayerController = _game.get("player")
	var cam := root.get_viewport().get_camera_3d()
	print("camera=%s cull_mask=%d far=%.1f fov=%.1f" % [cam.get_path() if cam else "none", cam.cull_mask if cam else 0, cam.far if cam else 0.0, cam.fov if cam else 0.0])
	print("player at ", player.global_position if player else "none")
	print("nodes=%d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	var sun := world.get_node_or_null("GC_MarsSun") as DirectionalLight3D
	if sun:
		print("SUN max_dist=%.1f mode=%d fade=%.2f cull=%d" % [sun.directional_shadow_max_distance, sun.directional_shadow_mode, sun.directional_shadow_fade_start, sun.light_cull_mask])
	var we := world.get_node("WorldEnvironment") as WorldEnvironment
	var e := we.environment
	print("ENV fog=%s depth=%s ssao=%s ssil=%s ssr=%s sdfgi=%s vol=%s glow=%s" % [e.fog_enabled, e.fog_mode, e.ssao_enabled, e.ssil_enabled, e.ssr_enabled, e.sdfgi_enabled, e.volumetric_fog_enabled, e.glow_enabled])
