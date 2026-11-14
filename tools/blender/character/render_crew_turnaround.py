"""Renders turnaround stills of the crew character (with and without suit) into OUT_DIR, optionally posed by a clip.
Run inside Blender: ns = {...}; exec(open(path).read(), ns); ns["render"](out_dir, clip=None, frame=0)
"""
import bpy, math, os
from mathutils import Vector

def render(out_dir, clip=None, frame=0, views=(0, 45, 90, 180, 270), size=(420, 640), tag=""):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    arm = bpy.data.objects["Armature"]
    if clip:
        arm.animation_data.action = bpy.data.actions[clip]
        if hasattr(arm.animation_data, "action_slot") and arm.animation_data.action.slots:
            arm.animation_data.action_slot = arm.animation_data.action.slots[0]
    else:
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.matrix_basis.identity()
    sc.frame_set(frame)
    sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_WORKBENCH'
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.film_transparent = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.56, 0.58, 1); bg.inputs[1].default_value = 0.9
    sun = bpy.data.objects.get("_sun")
    if sun is None:
        sun = bpy.data.objects.new("_sun", bpy.data.lights.new("_sun", 'SUN')); sc.collection.objects.link(sun)
        sun.data.energy = 3.0; sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    cam = bpy.data.objects.get("_cam")
    if cam is None:
        cam = bpy.data.objects.new("_cam", bpy.data.cameras.new("_cam")); sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.05
    files = []
    for suited in (False, True):
        for o in bpy.data.objects:
            if o.type == 'MESH':
                if o.name.startswith("Suit"):
                    o.hide_render = not suited
                elif o.name in ("Body_Torso", "Body_Arms", "Body_Legs"):
                    o.hide_render = suited
        for ang in views:
            a = math.radians(ang)
            cam.location = Vector((math.sin(a) * 6, -math.cos(a) * 6, 0.93))
            cam.rotation_euler = (math.pi / 2, 0, a)
            f = os.path.join(out_dir, f"{tag}{'suit' if suited else 'body'}_{ang:03d}.png")
            sc.render.filepath = f
            bpy.ops.render.render(write_still=True)
            files.append(f)
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = False
    return files
