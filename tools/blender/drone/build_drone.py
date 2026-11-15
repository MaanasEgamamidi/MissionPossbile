# Scout drone kit (2026-11-14 upgrade paths): builds the four upgrade stages of the flying scout drone and its landing
# pad / dock in Blender from real mesh detail (bevels, lofted twisted rotor blades, splayed legs) and simple run-time
# materials (no texture baking), then exports one glb per stage and renders a preview of the four stages side by side.
#
# Run headless (Blender 5.x):
#   blender-launcher.exe -b --factory-startup --disable-autoexec --python tools/blender/drone/build_drone.py -- <project dir>
#
# Writes:
#   assets/drone/drone_v1.glb .. drone_v4.glb   Y-up, metres, origin at the landing-gear base centre, faces -Z (Godot)
#   assets/drone/drone_pad.glb                  landing pad and charger, origin at the ground centre
#   assets_src/drone/drone_kit.blend            the source scene (assets_src has a .gdignore)
#   docs/revisions/evidence/drone/drone_stages_preview.png and drone_pad_preview.png
#   docs/revisions/evidence/drone/build_log.txt  object and triangle counts
#
# The drone is an original design that takes cues from NASA's Ingenuity helicopter (a small box body with gold foil
# insulation, a solar deck on top, thin splayed landing legs, a downward camera), but it is a quad-rotor, not a coaxial
# helicopter. Rotor hubs are separate objects named RotorHub_FL / FR / BL / BR with their origin on the spin axis, so
# the game can spin them around their local up axis. Blender +Y is the drone's front (glTF/Godot -Z after export).
#
# Stages (data/area_levels.json, track scout_drone):
#   V1  basic frame, 4 short rotors, a small fixed camera under the nose
#   V2  longer rotors and a bigger battery pod under the body
#   V3  + gimbal survey camera (replaces the small camera), a whip antenna and the autopilot nav puck
#   V4  + rear sensor pod, landing lights under the motors, a long-range dish antenna (replaces the whip)

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PROJECT = os.path.abspath(ARGS[0]) if ARGS else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_GLB = os.path.join(PROJECT, "assets", "drone")
OUT_SRC = os.path.join(PROJECT, "assets_src", "drone")
OUT_EVID = os.path.join(PROJECT, "docs", "revisions", "evidence", "drone")
for d in (OUT_GLB, OUT_SRC, OUT_EVID):
    os.makedirs(d, exist_ok=True)
LOG = []


def log(msg):
    LOG.append(str(msg))
    print(msg)


# ------------------------------------------------------------------ scene and materials

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


MATS = {}


def material(name, color, metallic=0.0, rough=0.6, emit=0.0, emit_color=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = rough
    if emit > 0.0:
        key = "Emission Color" if "Emission Color" in p.inputs else "Emission"
        p.inputs[key].default_value = (*(emit_color or color), 1.0)
        p.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*color, 1.0)
    MATS[name] = m
    return m


def mats():
    return {
        "white": material("drone_white_paint", (0.86, 0.86, 0.84), 0.0, 0.45),
        "foil": material("drone_gold_foil", (0.83, 0.62, 0.24), 1.0, 0.32),
        "carbon": material("drone_carbon", (0.07, 0.07, 0.08), 0.2, 0.5),
        "blade": material("drone_blade", (0.12, 0.12, 0.13), 0.1, 0.4),
        "alu": material("drone_aluminium", (0.66, 0.67, 0.69), 1.0, 0.35),
        "dark": material("drone_dark_grey", (0.18, 0.19, 0.21), 0.3, 0.55),
        "solar": material("drone_solar_cells", (0.05, 0.09, 0.22), 0.6, 0.25),
        "glass": material("drone_lens_glass", (0.02, 0.03, 0.05), 0.0, 0.05),
        "orange": material("drone_orange", (0.95, 0.42, 0.10), 0.0, 0.5),
        "light": material("drone_landing_light", (1.0, 0.97, 0.88), 0.0, 0.2, 6.0),
        "nav_red": material("drone_nav_red", (1.0, 0.1, 0.06), 0.0, 0.3, 4.0),
        "nav_green": material("drone_nav_green", (0.1, 1.0, 0.25), 0.0, 0.3, 4.0),
        "pad": material("pad_concrete", (0.36, 0.34, 0.33), 0.0, 0.85),
        "pad_paint": material("pad_paint_orange", (0.92, 0.45, 0.12), 0.0, 0.6),
        "pad_white": material("pad_paint_white", (0.85, 0.84, 0.80), 0.0, 0.6),
        "copper": material("pad_copper_contacts", (0.85, 0.47, 0.25), 1.0, 0.3),
        "pad_light": material("pad_rim_light", (0.35, 0.85, 1.0), 0.0, 0.3, 5.0),
        "screen": material("pad_screen", (0.12, 0.45, 0.55), 0.0, 0.2, 1.5),
    }


def link(obj, parent=None, mat=None):
    if obj.name not in bpy.context.scene.collection.objects:
        for c in obj.users_collection:
            c.objects.unlink(obj)
        bpy.context.scene.collection.objects.link(obj)
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    return obj


def mesh_object(name, bm, parent=None, mat=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    link(obj, parent, mat)
    for poly in me.polygons:
        poly.use_smooth = False
    return obj


def bevel(obj, width=0.006, segments=2):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    return obj


def smooth(obj, angle=35.0):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    try:
        obj.data.set_sharp_from_angle(angle=math.radians(angle))
    except Exception:
        pass
    return obj


def box(name, size, at, parent=None, mat=None, bevel_w=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    obj = mesh_object(name, bm, parent, mat)
    if bevel_w > 0.0:
        bevel(obj, bevel_w, 2)
    return obj


def cylinder(name, radius, depth, at, parent=None, mat=None, axis="Z", segments=20, radius2=None, bevel_w=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    obj = mesh_object(name, bm, parent, mat)
    smooth(obj)
    if bevel_w > 0.0:
        bevel(obj, bevel_w, 2)
    return obj


def rod(name, a, b, radius, parent=None, mat=None, segments=10):
    """A thin cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=d.length)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, vec=(a + b) * 0.5, verts=bm.verts)
    obj = mesh_object(name, bm, parent, mat)
    smooth(obj)
    return obj


def sphere(name, radius, at, parent=None, mat=None, scale=(1, 1, 1), segments=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    obj = mesh_object(name, bm, parent, mat)
    smooth(obj, 80)
    return obj


def empty(name, at=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.05
    obj.location = at
    link(obj, parent)
    return obj


# ------------------------------------------------------------------ drone parts

ROTORS = {"FR": (1, 1), "FL": (-1, 1), "BR": (1, -1), "BL": (-1, -1)}   # (x sign, y sign); +Y is the front


def blade_bm(bm, length, root_chord, tip_chord, twist_deg, thickness, angle):
    """Adds one lofted, tapered, twisted blade along +X (rotated by `angle` around Z) to `bm`."""
    sections = 5
    rings = []
    for i in range(sections + 1):
        t = i / sections
        x = 0.022 + t * length
        chord = root_chord + (tip_chord - root_chord) * t
        if i == sections:
            chord *= 0.55                       # rounded-off tip
        twist = math.radians(twist_deg * (1.0 - t))
        th = thickness * (1.0 - 0.5 * t)
        ring = []
        for (cy, cz) in [(-0.5, -0.5), (0.5, -0.35), (0.5, 0.35), (-0.5, 0.5)]:
            y = cy * chord
            z = cz * th
            # pitch: rotate the section around the blade's long axis (X)
            yr = y * math.cos(twist) - z * math.sin(twist)
            zr = y * math.sin(twist) + z * math.cos(twist)
            # slight sweep of the tip backwards
            ring.append(bm.verts.new(Vector((x, yr - 0.15 * t * t * chord, zr))))
        rings.append(ring)
    for i in range(sections):
        a, b = rings[i], rings[i + 1]
        for j in range(4):
            bm.faces.new((a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    rot = Matrix.Rotation(angle, 3, "Z")
    verts = [v for r in rings for v in r]
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=rot)


def rotor(name, at, blade_len, spin_dir, m, parent):
    """RotorHub_<id>: hub cap plus two blades, origin on the spin axis."""
    bm = bmesh.new()
    for k in range(2):
        blade_bm(bm, blade_len, 0.034, 0.024, 12.0 * spin_dir, 0.006, k * math.pi + (0.3 if spin_dir > 0 else -0.3))
    blades = mesh_object(name, bm, parent, m["blade"])
    blades.location = at
    smooth(blades, 30)
    hub = cylinder(name + "_cap", 0.020, 0.022, (0, 0, 0.004), blades, m["alu"], segments=16, radius2=0.012)
    hub.data.materials.clear()
    hub.data.materials.append(m["alu"])
    # merge the cap into the rotor object (one node per rotor in the game)
    join_into(blades, [hub])
    return blades


def join_into(target, others):
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return target


def build_drone(stage, m, offset=(0, 0, 0)):
    root = empty("DroneV%d" % stage, offset)
    long_rotor = stage >= 2
    arm_r = 0.335 if not long_rotor else 0.355           # motor distance from the centre (m)
    blade_len = 0.135 if not long_rotor else 0.185       # blade length from the hub (m)
    arm_z = 0.40

    # body: gold-foil lower box (Ingenuity cue), white upper shell, solar deck on top
    box("Body_Foil", (0.30, 0.26, 0.10), (0, 0, 0.315), root, m["foil"], 0.012)
    box("Body_Shell", (0.29, 0.25, 0.085), (0, 0, 0.405), root, m["white"], 0.016)
    box("Body_Deck", (0.25, 0.21, 0.012), (0, -0.005, 0.452), root, m["dark"], 0.003)
    for i in range(2):
        for j in range(3):
            box("Solar_%d%d" % (i, j), (0.105, 0.058, 0.006), (-0.058 + i * 0.116, -0.07 + j * 0.065, 0.460), root, m["solar"], 0.001)
    box("Body_Stripe", (0.292, 0.006, 0.022), (0, 0.126, 0.40), root, m["orange"])
    # a small status lamp
    cylinder("Body_Status", 0.008, 0.006, (0.09, 0.09, 0.459), root, m["nav_green"], segments=10)

    for rid, (sx, sy) in ROTORS.items():
        d = Vector((sx, sy, 0)).normalized()
        start = Vector((0, 0, arm_z)) + d * 0.12
        end = Vector((0, 0, arm_z)) + d * arm_r
        rod("Arm_" + rid, start, end, 0.014, root, m["carbon"], 12)
        rod("ArmBrace_" + rid, start + Vector((0, 0, -0.06)), end + Vector((0, 0, -0.012)), 0.006, root, m["carbon"], 8)
        cylinder("Motor_" + rid, 0.034, 0.05, (end.x, end.y, arm_z + 0.012), root, m["alu"], segments=24, bevel_w=0.004)
        cylinder("MotorRing_" + rid, 0.036, 0.012, (end.x, end.y, arm_z - 0.004), root, m["dark"], segments=24)
        spin = 1 if sx * sy > 0 else -1
        rotor("RotorHub_" + rid, (end.x, end.y, arm_z + 0.048), blade_len, spin, m, root)
        # landing legs: from under the body corner, splayed out to a foot pad on the ground (z = 0)
        top = Vector((sx * 0.11, sy * 0.095, 0.27))
        foot = Vector((sx * 0.25, sy * 0.23, 0.018))
        rod("Leg_" + rid, top, foot, 0.009, root, m["carbon"], 10)
        rod("LegStrut_" + rid, Vector((sx * 0.06, sy * 0.05, 0.27)), foot + (top - foot) * 0.45, 0.005, root, m["carbon"], 8)
        cylinder("Foot_" + rid, 0.034, 0.018, (foot.x, foot.y, 0.009), root, m["dark"], segments=18, radius2=0.026)
        if stage >= 4:
            cylinder("LandingLight_" + rid, 0.016, 0.006, (end.x, end.y, arm_z - 0.013), root, m["light"], segments=14)
            sphere("NavLight_" + rid, 0.008, (end.x + d.x * 0.04, end.y + d.y * 0.04, arm_z), root,
                   m["nav_green"] if sx > 0 else m["nav_red"], segments=10, rings=6)

    if stage < 3:
        # V1/V2: small fixed camera under the nose, looking forward and a little down
        cam = box("NoseCamera", (0.055, 0.05, 0.045), (0, 0.11, 0.245), root, m["dark"], 0.006)
        cylinder("NoseCamera_Lens", 0.016, 0.02, (0, 0.142, 0.243), root, m["glass"], axis="Y", segments=18)
        empty("Camera", (0, 0.15, 0.24), root)
    else:
        # V3+: two-axis gimbal survey camera
        g = empty("Gimbal", (0, 0.10, 0.262), root)
        box("Gimbal_Mount", (0.07, 0.05, 0.012), (0, 0.10, 0.262), root, m["alu"], 0.003)
        box("Gimbal_YokeL", (0.008, 0.02, 0.06), (-0.04, 0.10, 0.232), root, m["alu"], 0.002)
        box("Gimbal_YokeR", (0.008, 0.02, 0.06), (0.04, 0.10, 0.232), root, m["alu"], 0.002)
        sphere("Gimbal_Camera", 0.033, (0, 0.10, 0.215), root, m["dark"], segments=20, rings=12)
        cylinder("Gimbal_Lens", 0.018, 0.024, (0, 0.13, 0.212), root, m["glass"], axis="Y", segments=20, radius2=0.015)
        cylinder("Gimbal_LensRing", 0.021, 0.006, (0, 0.122, 0.212), root, m["orange"], axis="Y", segments=20)
        empty("Camera", (0, 0.15, 0.21), root)
        # autopilot navigation puck (GNSS-style module on Earth; here a beacon receiver) on the deck
        cylinder("AutopilotPuck", 0.032, 0.016, (-0.06, 0.05, 0.474), root, m["white"], segments=24, bevel_w=0.003)
        cylinder("AutopilotPuck_Top", 0.022, 0.003, (-0.06, 0.05, 0.483), root, m["orange"], segments=20)

    if stage >= 2:
        # bigger battery pod slung under the body, between the legs
        cylinder("BatteryPod", 0.058, 0.20, (0, -0.01, 0.205), root, m["white"], axis="Y", segments=24)
        sphere("BatteryPod_CapF", 0.058, (0, 0.09, 0.205), root, m["white"], scale=(1, 0.45, 1), segments=24, rings=10)
        sphere("BatteryPod_CapB", 0.058, (0, -0.11, 0.205), root, m["white"], scale=(1, 0.45, 1), segments=24, rings=10)
        for k, y in enumerate((-0.06, 0.04)):
            cylinder("BatteryPod_Band%d" % k, 0.060, 0.012, (0, y, 0.205), root, m["orange"], axis="Y", segments=24)
        box("BatteryPod_Pylon", (0.03, 0.12, 0.05), (0, -0.01, 0.255), root, m["dark"], 0.004)

    if stage == 3:
        # whip antenna for the autopilot radio link
        cylinder("Antenna_Base", 0.014, 0.02, (0.08, -0.08, 0.468), root, m["dark"], segments=12)
        rod("Antenna_Whip", (0.08, -0.08, 0.47), (0.08, -0.08, 0.66), 0.0035, root, m["dark"], 8)
        sphere("Antenna_Tip", 0.007, (0.08, -0.08, 0.662), root, m["orange"], segments=10, rings=6)

    if stage >= 4:
        # long-range antenna: mast with a small dish
        cylinder("LongAntenna_Base", 0.02, 0.025, (0.07, -0.07, 0.47), root, m["dark"], segments=16)
        rod("LongAntenna_Mast", (0.07, -0.07, 0.48), (0.07, -0.07, 0.62), 0.006, root, m["alu"], 10)
        dish = sphere("LongAntenna_Dish", 0.06, (0.07, -0.07, 0.64), root, m["white"], scale=(1, 1, 0.28), segments=24, rings=12)
        rod("LongAntenna_Feed", (0.07, -0.07, 0.64), (0.07, -0.07, 0.69), 0.003, root, m["dark"], 6)
        sphere("LongAntenna_FeedHead", 0.009, (0.07, -0.07, 0.692), root, m["orange"], segments=10, rings=6)
        # rear sensor pod with three windows (spectrometer, thermal camera, laser range finder)
        box("SensorPod", (0.16, 0.07, 0.085), (0, -0.165, 0.36), root, m["white"], 0.012)
        box("SensorPod_Foil", (0.165, 0.02, 0.09), (0, -0.135, 0.36), root, m["foil"], 0.003)
        for k, x in enumerate((-0.045, 0.0, 0.045)):
            cylinder("SensorPod_Window%d" % k, 0.014 if k != 1 else 0.018, 0.012, (x, -0.202, 0.362), root, m["glass"], axis="Y", segments=16)
        # forward landing light bar under the nose
        box("LightBar", (0.12, 0.016, 0.014), (0, 0.128, 0.275), root, m["light"], 0.003)
    return root


def build_pad(m, offset=(0, 0, 0)):
    """Landing pad and dock: a hexagonal plate, painted target ring, charging plate with contacts, rim lights and a
    charger cabinet with a cable conduit. Origin at the ground centre; the charging plate top is at z = 0.085."""
    root = empty("DronePad", offset)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=6, radius=1.25)
    geom = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    verts = [e for e in geom["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, 0.06), verts=verts)
    plate = mesh_object("Pad_Plate", bm, root, m["pad"])
    bevel(plate, 0.02, 2)
    # raised rim (hexagonal frame)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, segments=6, radius=1.25)
    outer = bm.verts[:]
    bmesh.ops.create_circle(bm, cap_ends=False, segments=6, radius=1.15)
    inner = bm.verts[6:]
    for i in range(6):
        bm.faces.new((outer[i], outer[(i + 1) % 6], inner[(i + 1) % 6], inner[i]))
    geom = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    bmesh.ops.translate(bm, vec=(0, 0, 0.035), verts=[e for e in geom["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.translate(bm, vec=(0, 0, 0.06), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rim = mesh_object("Pad_Rim", bm, root, m["dark"])
    bevel(rim, 0.008, 2)
    # painted target ring and cross bars
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, segments=48, radius=0.86)
    o = bm.verts[:]
    bmesh.ops.create_circle(bm, cap_ends=False, segments=48, radius=0.76)
    inn = bm.verts[48:]
    for i in range(48):
        bm.faces.new((o[i], o[(i + 1) % 48], inn[(i + 1) % 48], inn[i]))
    bmesh.ops.translate(bm, vec=(0, 0, 0.062), verts=bm.verts)
    mesh_object("Pad_Ring", bm, root, m["pad_paint"])
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        c = Vector((math.cos(a), math.sin(a), 0)) * 1.0
        bar = box("Pad_Tick%d" % k, (0.24, 0.07, 0.004), (0, 0, 0), root, m["pad_white"])
        bar.location = (c.x, c.y, 0.062)
        bar.rotation_euler = (0, 0, a)
    # charging plate with copper contact strips, where the drone's feet stand
    box("Pad_ChargePlate", (0.66, 0.66, 0.025), (0, 0, 0.073), root, m["dark"], 0.006)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("Pad_Contact_%d%d" % (sx > 0, sy > 0), (0.12, 0.12, 0.004), (sx * 0.25, sy * 0.23, 0.087), root, m["copper"], 0.002)
    # rim lights
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        c = Vector((math.cos(a), math.sin(a), 0)) * 1.08
        cylinder("PadLight_%d" % k, 0.035, 0.03, (c.x, c.y, 0.075), root, m["pad_light"], segments=14)
    # charger cabinet at the back edge (-Y), with a screen and a cable conduit to the plate
    cab = box("Charger_Cabinet", (0.42, 0.28, 0.62), (0, -1.48, 0.31), root, m["white"], 0.02)
    box("Charger_Base", (0.48, 0.34, 0.05), (0, -1.48, 0.025), root, m["dark"], 0.01)
    box("Charger_Screen", (0.26, 0.012, 0.16), (0, -1.335, 0.44), root, m["screen"], 0.003)
    box("Charger_Stripe", (0.425, 0.284, 0.04), (0, -1.48, 0.56), root, m["pad_paint"])
    for k, x in enumerate((-0.12, 0.12)):
        box("Charger_Vent%d" % k, (0.10, 0.006, 0.12), (x, -1.338, 0.18), root, m["dark"], 0.002)
    rod("Charger_Conduit", (0, -1.33, 0.05), (0, -0.34, 0.07), 0.03, root, m["dark"], 12)
    box("Charger_ConduitClamp", (0.1, 0.06, 0.08), (0, -0.33, 0.07), root, m["alu"], 0.01)
    cylinder("Charger_Beacon", 0.03, 0.06, (0.15, -1.48, 0.65), root, m["pad_paint"], segments=14)
    return root


# ------------------------------------------------------------------ export and preview

def descendants(obj):
    out = [obj]
    for c in obj.children:
        out.extend(descendants(c))
    return out


def tri_count(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        n += len(me.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    return n


def export(root, path):
    saved = root.location.copy()
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    objs = descendants(root)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_materials="EXPORT")
    root.location = saved
    bpy.context.view_layer.update()
    log("exported %s: %d objects, %d triangles" % (os.path.basename(path), len(objs), tri_count(objs)))


def setup_render(scene, res):
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "CYCLES" if "CYCLES" in engines else engines[0]
    if scene.render.engine == "CYCLES":
        scene.cycles.device = "CPU"
        scene.cycles.samples = 64
        try:
            scene.cycles.use_denoising = True
        except Exception:
            pass
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard" if "Standard" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else scene.view_settings.view_transform
    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.42, 0.30, 0.24, 1.0)          # dusty Mars-sky tint
    bg.inputs["Strength"].default_value = 0.7


def add_sun(rot, energy=3.5):
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = energy
    sun.angle = math.radians(4)
    o = bpy.data.objects.new("Sun", sun)
    o.rotation_euler = rot
    bpy.context.scene.collection.objects.link(o)
    return o


def add_ground(size, mat):
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size)
    g = mesh_object("PreviewGround", bm, None, mat)
    return g


def look_at_camera(name, loc, target, lens=50):
    cam = bpy.data.cameras.new(name)
    cam.lens = lens
    o = bpy.data.objects.new(name, cam)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    d = Vector(target) - Vector(loc)
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = o
    return o


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log("rendered %s" % path)


def fresh():
    """A new empty scene with fresh materials, so every exported stage keeps clean, unsuffixed node names."""
    scene = reset_scene()
    MATS.clear()
    return scene, mats()


def main():
    # one clean scene per export (Blender names are unique per file: RotorHub_FL would become RotorHub_FL.001)
    for s in (1, 2, 3, 4):
        _, m = fresh()
        root = build_drone(s, m)
        hubs = sorted(o.name for o in descendants(root) if o.name.startswith("RotorHub_"))
        log("DroneV%d rotor hubs: %s" % (s, ", ".join(hubs)))
        export(root, os.path.join(OUT_GLB, "drone_v%d.glb" % s))
    fresh()
    export(build_pad(mats()), os.path.join(OUT_GLB, "drone_pad.glb"))

    # the kit scene: the four stages side by side (V1 on the left seen from the front) and the pad behind them
    scene, m = fresh()
    spacing = 1.45
    roots = [build_drone(s, m, ((2.5 - s) * spacing, 0, 0)) for s in (1, 2, 3, 4)]
    pad = build_pad(m, (0, 3.2, 0))

    # preview 1: the four stages side by side, low three-quarter view from the front (shows the pods underneath)
    setup_render(scene, (1920, 720))
    ground_mat = material("preview_ground", (0.55, 0.33, 0.2), 0.0, 0.9)
    ground = add_ground(12, ground_mat)
    add_sun((math.radians(50), 0, math.radians(30)))
    look_at_camera("PreviewCam", (0.0, 4.3, 0.95), (0, 0, 0.3), lens=27)
    pad.hide_render = True
    for o in descendants(pad):
        o.hide_render = True
    render(os.path.join(OUT_EVID, "drone_stages_preview.png"))
    # preview 2: top-down-ish view of the four stages (rotor spans)
    look_at_camera("PreviewTop", (0.0, 2.2, 5.6), (0, 0, 0.2), lens=33)
    render(os.path.join(OUT_EVID, "drone_stages_top.png"))
    # preview 3: the pad with the V4 drone docked on it
    for r in roots:
        for o in descendants(r):
            o.hide_render = True
    for o in descendants(pad):
        o.hide_render = False
    v4 = roots[3]
    saved = v4.location.copy()
    v4.location = (0, 3.2, 0.085)
    for o in descendants(v4):
        o.hide_render = False
    look_at_camera("PreviewPad", (3.2, 7.4, 2.6), (0, 3.0, 0.3), lens=38)
    render(os.path.join(OUT_EVID, "drone_pad_preview.png"))
    v4.location = saved
    ground.hide_render = False

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_SRC, "drone_kit.blend"), compress=True)
    log("saved %s" % os.path.join(OUT_SRC, "drone_kit.blend"))


try:
    main()
    log("DONE")
except Exception as exc:  # keep the error in the log file: the launcher does not show the console
    import traceback
    log("ERROR " + repr(exc))
    log(traceback.format_exc())
finally:
    with open(os.path.join(OUT_EVID, "build_log.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(LOG) + "\n")
