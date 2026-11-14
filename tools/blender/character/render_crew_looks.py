"""Renders the four crew looks (hair, Feminine shape key, skin / hair / accent colours) from crew_v2.blend after
crew_variants.py. Workbench, flat colours; never saves the blend.

  blender -b --factory-startup --disable-autoexec crew_v2.blend --python run_logged.py -- <log> render_crew_looks.py <out_dir> [--poses]

Writes <out_dir>/raw/*.png; tools/blender/character/crew_looks_sheets.py assembles the contact sheets.
The CREW table is the design the game uses per identity (0-3); colours are sRGB hex.
"""
import bpy, math, os, sys, json
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.join(argv[0], "raw")
POSES = "--poses" in argv
os.makedirs(OUT, exist_ok=True)

CREW = [
    {"id": 0, "name": "electrical", "hair": "Ponytail", "beard": False, "feminine": 1.0, "height": 0.93,
     "skin": "a8714f", "hair_col": "3b2417", "accent": "ffc400", "symbol": "Triangle", "band": "Solid"},
    {"id": 1, "name": "medical", "hair": "Curly", "beard": False, "feminine": 0.0, "height": 1.05,
     "skin": "6e452e", "hair_col": "151210", "accent": "2a7bff", "symbol": "Plus", "band": "Double"},
    {"id": 2, "name": "biology", "hair": "Bob", "beard": False, "feminine": 1.0, "height": 0.90,
     "skin": "f1c9a5", "hair_col": "a4502a", "accent": "1e9e48", "symbol": "Circle", "band": "Dots"},
    {"id": 3, "name": "geology", "hair": "Buzz", "beard": True, "feminine": 0.0, "height": 1.00,
     "skin": "c39a6e", "hair_col": "6b4a2b", "accent": "d2379b", "symbol": "Diamond", "band": "Chevron"},
]

def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def set_col(mat_name, hexcol):
    m = bpy.data.materials[mat_name]
    c = lin(hexcol)
    m.diffuse_color = (*c, 1)
    if m.use_nodes and "Principled BSDF" in m.node_tree.nodes:
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*c, 1)

sc = bpy.context.scene
ARM = bpy.data.objects["Armature"]
for t in ARM.animation_data.nla_tracks: t.mute = True
ARM.animation_data.action = None
for pb in ARM.pose.bones: pb.matrix_basis = Matrix.Identity(4)
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_shadows = False
sh.show_cavity = True; sh.cavity_type = 'WORLD'; sh.cavity_ridge_factor = 0.6; sh.cavity_valley_factor = 0.8
sh.show_object_outline = True; sh.object_outline_color = (0.02, 0.02, 0.02)
sc.view_settings.view_transform = 'Standard'
if sc.world is None:
    sc.world = bpy.data.worlds.new("w")
sc.world.color = (0.045, 0.05, 0.06)
sc.render.film_transparent = False
cam = bpy.data.objects.new("_looks_cam", bpy.data.cameras.new("_looks_cam")); sc.collection.objects.link(cam); sc.camera = cam
me = bpy.data.meshes.new("_looks_floor")
me.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
floor = bpy.data.objects.new("_looks_floor", me); sc.collection.objects.link(floor)
fm = bpy.data.materials.new("_looks_floor"); fm.diffuse_color = (0.30, 0.17, 0.10, 1); me.materials.append(fm)

MESHES = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == ARM]

def apply(crew, suited):
    want = {"Body_Head"}
    if suited:
        want |= {o.name for o in MESHES if o.name.startswith("Suit")}
        want |= {"HairIn_" + crew["hair"], "Ident_Symbol_" + crew["symbol"], "Ident_Band_" + crew["band"]}
    else:
        want |= {"Body_Torso", "Body_Arms", "Body_Legs", "Hair_" + crew["hair"]}
    if crew["beard"]:
        want.add("Hair_Beard")
    for o in MESHES:
        o.hide_render = o.name not in want
        if o.data.shape_keys and "Feminine" in o.data.shape_keys.key_blocks:
            o.data.shape_keys.key_blocks["Feminine"].value = crew["feminine"]
    ARM.scale = (crew["height"],) * 3
    set_col("Mat_Skin", crew["skin"]); set_col("Mat_Hair", crew["hair_col"]); set_col("Mat_Ident", crew["accent"])

def shoot(path, ang, cz, scale, rx, ry, dist=6.0, ortho=True, el=0.0):
    a = math.radians(ang); e = math.radians(el)
    cam.data.type = 'ORTHO' if ortho else 'PERSP'
    if ortho:
        cam.data.ortho_scale = scale
    else:
        cam.data.lens = scale
    cam.location = Vector((math.sin(a) * dist * math.cos(e), -math.cos(a) * dist * math.cos(e), cz + dist * math.sin(e)))
    cam.rotation_euler = (math.pi / 2 - e, 0, a)
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    sc.render.filepath = os.path.join(OUT, path)
    bpy.ops.render.render(write_still=True)

for crew in CREW:
    i = crew["id"]
    apply(crew, False)
    for ang, tag in ((0, "front"), (-35, "3q"), (90, "side"), (180, "back")):
        shoot(f"c{i}_body_{tag}.png", ang, 0.93, 2.05, 330, 460)
    for ang, tag in ((0, "front"), (-35, "3q"), (90, "side"), (180, "back"), (150, "back3q")):
        shoot(f"c{i}_head_{tag}.png", ang, 1.665 * crew["height"], 0.44, 330, 330)
    apply(crew, True)
    for ang, tag in ((0, "front"), (180, "back"), (-35, "3q")):
        shoot(f"c{i}_suit_{tag}.png", ang, 0.95, 2.1, 330, 460)
    for ang, tag in ((0, "front"), (-35, "3q"), (180, "back")):
        shoot(f"c{i}_helmet_{tag}.png", ang, 1.67 * crew["height"], 0.52, 330, 330)
    # third-person game view: behind and above, ~10 m away, narrow lens
    shoot(f"c{i}_far_back.png", 180, 1.0, 50, 160, 160, dist=10.0, ortho=False, el=12)

if POSES:
    def set_action(name):
        act = bpy.data.actions[name]
        ARM.animation_data.action = act
        if hasattr(ARM.animation_data, "action_slot") and act.slots:
            ARM.animation_data.action_slot = act.slots[0]
        return act
    tracks = {t.name: t.strips[0].action.name for t in ARM.animation_data.nla_tracks if t.strips}
    for crew in (CREW[0], CREW[2], CREW[1]):
        apply(crew, False)
        for clip in ("idle", "walk", "sprint", "jump_start", "jump", "land"):
            act = set_action(tracks[clip])
            last = int(round(act.frame_range[1]))
            for k in range(4):
                f = round(last * k / 3)
                sc.frame_set(f)
                shoot(f"pose_c{crew['id']}_{clip}_{k}.png", 90, 1.0, 2.2, 260, 300)
    ARM.animation_data.action = None
    for pb in ARM.pose.bones: pb.matrix_basis = Matrix.Identity(4)
json.dump(CREW, open(os.path.join(argv[0], "crew_design.json"), "w"), indent=1)
