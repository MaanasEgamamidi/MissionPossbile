class_name MotionBlur
extends MeshInstance3D
## Camera motion blur (Settings > Graphics > Motion blur, 0 = off; always off with Less motion). One full-screen quad
## with materials/motion_blur.gdshader, kept on the active camera; it hands the shader the camera of the previous frame.
## It exists only while the setting is above 0, so at 0 it costs nothing. A teleport or a camera cut (a big jump in one
## frame) is not blurred.

const NODE_NAME := "GqMotionBlur"
const SHADER := preload("res://materials/motion_blur.gdshader")
## A jump bigger than this in one frame is a cut, not motion.
const CUT_METRES := 2.0
const CUT_DEGREES := 45.0

var strength := 0.0
var _mat: ShaderMaterial
var _prev := Transform3D()
var _has_prev := false


## Shows the blur at `level` (0..10) on `tree`, or removes it at 0.
static func set_strength(tree: SceneTree, level: int) -> void:
	if tree == null or tree.root == null:
		return
	var node := tree.root.get_node_or_null(NODE_NAME) as MotionBlur
	if level <= 0 or DisplayServer.get_name() == "headless":
		if node != null:
			node.queue_free()
		return
	if node == null:
		node = MotionBlur.new()
		node.name = NODE_NAME
		tree.root.add_child.call_deferred(node)
	node.strength = clampf(float(level) / 10.0, 0.0, 1.0)


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = -127
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# drawn by every camera whatever rooms its cull mask leaves out, never culled
	layers = (1 << 20) - 1
	custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))
	extra_cull_margin = 16384.0
	process_priority = 1000


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		visible = false
		_has_prev = false
		return
	var now := cam.global_transform
	global_transform = now.translated_local(Vector3(0.0, 0.0, -1.0))
	var cut := not _has_prev or now.origin.distance_to(_prev.origin) > CUT_METRES \
		or rad_to_deg(now.basis.get_rotation_quaternion().angle_to(_prev.basis.get_rotation_quaternion())) > CUT_DEGREES
	_mat.set_shader_parameter("prev_view", Projection(_prev.affine_inverse() if not cut else now.affine_inverse()))
	_mat.set_shader_parameter("strength", strength)
	visible = not cut
	_prev = now
	_has_prev = true
