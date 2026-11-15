"""Cassette props for the Command Room reader (owner request 2026-11-14: "make a better render of the cassette tape
player in the comms/command room"). Headless, from an empty scene; nothing is saved but the two glb files:
  blender-launcher -b --factory-startup --disable-autoexec --python build_props.py -- --proj <godot project>

  assets/props/cassette_player.glb   a chunky retro mission tape deck: ivory body, charcoal cheeks and front panel, a
                                     cassette with turning-reel hubs behind a smoked window, four big labelled piano
                                     keys (PLAY, STOP, EJECT, NEXT), a small green counter screen, a speaker grille,
                                     a volume knob, a carry handle and rubber feet. 0.50 x 0.30 m, 0.25 m to the
                                     handle top. Origin: bottom centre (it stands on its feet at y = 0), front = +Z.
  assets/props/cassette_tape.glb     one room cassette lying flat, 1.5 x real size (0.15 x 0.096 x 0.018 m; a real
                                     compact cassette is 100 x 64 x 12 mm): smoke shell, cream label, window with two
                                     white toothed hubs and brown tape, head edge with its holes and five screws.
                                     The mesh "RoomStrip" (material tape_room_strip) is the coloured band the game
                                     recolours per room (CassetteCatalog colours); the room name is a flat Label3D the
                                     game lays on that band. Origin: bottom centre, label up, text reads from +Z.

Map style: low-poly pieces with small bevels and flat palette-like materials (named prop_*), no textures and no
baking. Every size is designer balance (the 1.5 x cassette scale keeps it readable at kid eye height).
"""
import bpy
import bmesh
import math
import os
import sys

from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts.get("--proj", os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
OUT = os.path.join(PROJ, "assets", "props")
os.makedirs(OUT, exist_ok=True)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"
sc.unit_settings.scale_length = 1.0

MATS = {}


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def material(name, hexc, metallic=0.0, rough=0.6, emit=0.0, alpha=1.0):
    if name in MATS:
        return MATS[name]
    color = srgb(hexc)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = rough
    if emit > 0.0:
        key = "Emission Color" if "Emission Color" in p.inputs else "Emission"
        p.inputs[key].default_value = (*color, 1.0)
        p.inputs["Emission Strength"].default_value = emit
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    m.diffuse_color = (*color, alpha)
    MATS[name] = m
    return m


M = {
    "ivory": material("prop_deck_ivory", "e4ddc9", 0.0, 0.55),
    "charcoal": material("prop_deck_charcoal", "2a2e33", 0.1, 0.6),
    "panel": material("prop_deck_panel", "1d2126", 0.15, 0.5),
    "rubber": material("prop_rubber_black", "141516", 0.0, 0.85),
    "chrome": material("prop_brushed_steel", "b9bcc0", 1.0, 0.32),
    "orange": material("prop_mission_orange", "e8743a", 0.0, 0.45),
    "play": material("prop_key_play_green", "3fae5a", 0.0, 0.4),
    "stop": material("prop_key_stop_red", "d0402f", 0.0, 0.4),
    "eject": material("prop_key_eject_yellow", "e9b62f", 0.0, 0.4),
    "next": material("prop_key_next_blue", "3f7fd6", 0.0, 0.4),
    "ink": material("prop_print_ink", "1b1d20", 0.0, 0.7),
    "white_ink": material("prop_print_white", "f2efe6", 0.0, 0.6),
    "screen": material("prop_screen_green", "0f3b25", 0.0, 0.25, 0.6),
    "screen_text": material("prop_screen_text", "7dff9e", 0.0, 0.3, 3.0),
    "grille": material("prop_grille_dark", "0d0f11", 0.3, 0.55),
    "glass": material("prop_smoked_window", "1a2a33", 0.0, 0.08, 0.0, 0.35),
    "shell": material("prop_tape_shell", "26282c", 0.0, 0.35),
    "label": material("prop_tape_label", "efe7cf", 0.0, 0.7),
    "strip": material("tape_room_strip", "f1a35e", 0.0, 0.55),
    "hub": material("prop_tape_hub_white", "f4f2ec", 0.0, 0.45),
    "tape": material("prop_tape_brown", "5a3420", 0.2, 0.45),
    "screw": material("prop_screw_steel", "9a9da2", 1.0, 0.35),
}


def link(obj, parent=None, mat=None):
    sc.collection.objects.link(obj)
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    return obj


def mesh_object(name, bm, parent=None, mat=None, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = smooth
    return link(bpy.data.objects.new(name, me), parent, mat)


def bevel(obj, width, segments=2, angle=40):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    return obj


def box(name, size, at, parent=None, mat=None, bevel_w=0.0, segments=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    obj = mesh_object(name, bm, parent, mat)
    if bevel_w > 0.0:
        bevel(obj, bevel_w, segments)
    return obj


def cylinder(name, radius, depth, at, parent=None, mat=None, axis="Z", segments=24, radius2=None, bevel_w=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    obj = mesh_object(name, bm, parent, mat, smooth=True)
    try:
        obj.data.set_sharp_from_angle(angle=math.radians(35))
    except Exception:
        pass
    if bevel_w > 0.0:
        bevel(obj, bevel_w, 2)
    return obj


def prism(name, points, z0, z1, parent=None, mat=None, bevel_w=0.0):
    """An extruded polygon (x, y points, counter-clockwise) from z0 to z1."""
    bm = bmesh.new()
    low = [bm.verts.new((x, y, z0)) for x, y in points]
    high = [bm.verts.new((x, y, z1)) for x, y in points]
    bm.faces.new(list(reversed(low)))
    bm.faces.new(high)
    n = len(points)
    for i in range(n):
        bm.faces.new((low[i], low[(i + 1) % n], high[(i + 1) % n], high[i]))
    obj = mesh_object(name, bm, parent, mat)
    if bevel_w > 0.0:
        bevel(obj, bevel_w, 1)
    return obj


def text(name, body, size, at, parent=None, mat=None, depth=0.0008, facing="up", thicken=0.0, align="CENTER"):
    """Text as real mesh (no texture): lying on a top face ("up", reads from -Y) or on a front face ("front")."""
    cu = bpy.data.curves.new(name + "_curve", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.extrude = depth * 0.5
    cu.offset = thicken
    cu.resolution_u = 3
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    sc.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(cu)
    if facing == "front":
        me.transform(Matrix.Rotation(math.radians(90), 4, "X"))
    me.transform(Matrix.Translation(Vector(at)))
    obj = link(bpy.data.objects.new(name, me), parent, mat)
    return obj


def triangle_icon(name, cx, cy, s, z, parent, mat, flip=False):
    d = -1 if flip else 1
    return prism(name, [(cx - 0.5 * s * d, cy - 0.55 * s), (cx + 0.6 * s * d, cy), (cx - 0.5 * s * d, cy + 0.55 * s)][::d], z, z + 0.0016, parent, mat)


def empty(name):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    return e


def toothed_hub(name, cx, cy, z, r, parent, depth=0.002, teeth=6):
    """A white tape hub ring with inward teeth, lying flat at height z."""
    ring = cylinder(name, r, depth, (cx, cy, z + depth * 0.5), parent, M["hub"], segments=20)
    cylinder(name + "_hole", r * 0.62, depth * 1.2, (cx, cy, z + depth * 0.6), parent, M["shell"], segments=16)
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        t = box(name + "_tooth%d" % i, (r * 0.32, r * 0.18, depth * 1.25), (r * 0.52, 0.0, 0.0), parent, M["hub"])
        t.data.transform(Matrix.Rotation(a, 4, "Z"))
        t.data.transform(Matrix.Translation((cx, cy, z + depth * 0.62)))
    return ring


# ---------------------------------------------------------------------------------------------- cassette tape
def build_tape(root_name="CassetteTape", parent=None, at=(0.0, 0.0, 0.0), rot=None, strip_mat=None):
    """Lying flat, base at z = 0, label up; text up = +Y. Returns the root empty."""
    root = empty(root_name)
    if parent is not None:
        root.parent = parent
    W, D, T = 0.15, 0.096, 0.018
    box("Shell", (W, D, T), (0, 0, T * 0.5), root, M["shell"], 0.0035, 2)
    top = T
    # cream label (top face), with the room colour band across its top
    box("Label", (0.134, 0.062, 0.0008), (0, 0.010, top + 0.0004), root, M["label"])
    box("RoomStrip", (0.134, 0.018, 0.0010), (0, 0.032, top + 0.0007), root, strip_mat or M["strip"])
    box("LabelLine", (0.134, 0.0025, 0.0010), (0, -0.0085, top + 0.0007), root, strip_mat or M["strip"])
    # window: smoked band with brown tape and two white toothed hubs
    box("Window", (0.086, 0.026, 0.0012), (0, 0.006, top + 0.0012), root, M["panel"])
    cylinder("TapePackL", 0.0125, 0.0008, (-0.031, 0.006, top + 0.0019), root, M["tape"], segments=20)
    cylinder("TapePackR", 0.0085, 0.0008, (0.031, 0.006, top + 0.0019), root, M["tape"], segments=20)
    toothed_hub("HubL", -0.031, 0.006, top + 0.0018, 0.0068, root)
    toothed_hub("HubR", 0.031, 0.006, top + 0.0018, 0.0068, root)
    # head edge (near side, -Y): the raised trapezoid with its holes
    prism("HeadBump", [(-0.047, -0.048), (0.047, -0.048), (0.036, -0.030), (-0.036, -0.030)], top - 0.0005, top + 0.0016, root, M["shell"], 0.0008)
    for i, x in enumerate((-0.03, -0.012, 0.012, 0.03)):
        cylinder("HeadHole%d" % i, 0.0026 if i in (1, 2) else 0.0036, 0.0006, (x, -0.040, top + 0.0019), root, M["grille"], segments=12)
    for i, (x, y) in enumerate(((-0.069, 0.042), (0.069, 0.042), (-0.069, -0.042), (0.069, -0.042), (0.0, -0.025))):
        cylinder("Screw%d" % i, 0.0022, 0.0006, (x, y, top + 0.0003), root, M["screw"], segments=10)
    if rot is not None:
        root.rotation_euler = rot
    root.location = at
    return root


# ---------------------------------------------------------------------------------------------- tape deck
def build_player():
    root = empty("CassettePlayer")
    W, D = 0.50, 0.30
    FOOT = 0.012
    H = 0.15
    z0, z1 = FOOT, FOOT + H
    front = -D * 0.5
    for i, (x, y) in enumerate(((-0.2, -0.11), (0.2, -0.11), (-0.2, 0.11), (0.2, 0.11))):
        cylinder("Foot%d" % i, 0.017, FOOT + 0.002, (x, y, (FOOT + 0.002) * 0.5), root, M["rubber"], segments=16)
    # body and charcoal side cheeks
    box("Body", (W - 0.04, D, H), (0, 0, (z0 + z1) * 0.5), root, M["ivory"], 0.010)
    for s in (-1, 1):
        box("Cheek_%s" % ("L" if s < 0 else "R"), (0.03, D + 0.008, H + 0.006), (s * (W * 0.5 - 0.015), 0, (z0 + z1) * 0.5), root, M["charcoal"], 0.009)
    # front panel (charcoal), a thin orange pinstripe above it
    fp_z0, fp_z1 = z0 + 0.012, z1 - 0.018
    box("FrontPanel", (W - 0.07, 0.008, fp_z1 - fp_z0), (0, front - 0.002, (fp_z0 + fp_z1) * 0.5), root, M["panel"], 0.003)
    box("Pinstripe", (W - 0.07, 0.004, 0.005), (0, front - 0.001, fp_z1 + 0.007), root, M["orange"])
    fz = front - 0.006           # front face of the panel
    # cassette bay (left): orange bezel, dark cavity, a tape standing in it with its hubs, smoked glass in front
    bx, bz, bw, bh, bd = -0.095, (fp_z0 + fp_z1) * 0.5 + 0.006, 0.17, 0.092, 0.02
    box("BayCavity", (bw, 0.004, bh), (bx, fz - 0.0005, bz), root, M["grille"])
    for s in (-1, 1):       # a deep bezel frame: the tape sits in it, behind the smoked glass
        box("BayFrame_%s" % ("L" if s < 0 else "R"), (0.009, bd, bh + 0.018), (bx + s * (bw * 0.5 + 0.0045), fz - bd * 0.5, bz), root, M["orange"], 0.002)
        box("BayFrame_%s" % ("B" if s < 0 else "T"), (bw, bd, 0.009), (bx, fz - bd * 0.5, bz + s * (bh * 0.5 + 0.0045)), root, M["orange"], 0.002)
    bay_tape = build_tape("BayTape", root, (bx, fz - 0.001, bz), (math.radians(90), 0, 0), M["orange"])
    bay_tape.scale = (0.95, 0.88, 0.6)
    box("BayGlass", (bw, 0.002, bh), (bx, fz - bd + 0.003, bz), root, M["glass"])
    text("BayCaption", "MISSION TAPE", 0.0072, (bx, fz - bd - 0.0005, bz - bh * 0.5 - 0.0045), root, M["ink"], facing="front", thicken=0.0003)
    # counter screen (right top) with its green read-out
    sx, sz = 0.115, fp_z1 - 0.026
    box("ScreenBezel", (0.136, 0.006, 0.044), (sx, fz - 0.002, sz), root, M["charcoal"], 0.003)
    box("Screen", (0.12, 0.004, 0.032), (sx, fz - 0.004, sz), root, M["screen"])
    text("ScreenText", "TAPE 01  000", 0.0165, (sx, fz - 0.0068, sz), root, M["screen_text"], facing="front", thicken=0.0003)
    # speaker grille (right bottom): a framed plate with horizontal bars
    gx, gz, gw, gh = 0.115, fp_z0 + 0.03, 0.14, 0.05
    box("GrilleFrame", (gw + 0.01, 0.004, gh + 0.01), (gx, fz - 0.001, gz), root, M["charcoal"], 0.002)
    box("GrilleBack", (gw, 0.004, gh), (gx, fz - 0.002, gz), root, M["grille"])
    for i in range(6):
        box("GrilleBar%d" % i, (gw - 0.006, 0.006, 0.0042), (gx, fz - 0.005, gz - gh * 0.5 + 0.0055 + i * 0.0078), root, M["chrome"], 0.0012, 1)
    # four big piano keys along the top front edge, each with its icon; the word printed behind each key
    keys = (("PLAY", "play"), ("STOP", "stop"), ("EJECT", "eject"), ("NEXT", "next"))
    kw, kd, kh, pitch = 0.074, 0.058, 0.022, 0.083
    ky = front + 0.048
    kx0 = -0.175
    for i, (word, mk) in enumerate(keys):
        x = kx0 + i * pitch
        box("Key_" + word, (kw, kd, kh), (x, ky, z1 + kh * 0.5 - 0.004), root, M[mk], 0.006)
        icon_z = z1 + kh - 0.004
        iy = ky + 0.011          # icon on the upper half of the key top, the word printed on its lower half
        ink = M["ink"] if word == "EJECT" else M["white_ink"]
        if word == "PLAY":
            triangle_icon("Icon_PLAY", x, iy, 0.02, icon_z, root, ink)
        elif word == "STOP":
            box("Icon_STOP", (0.018, 0.018, 0.0016), (x, iy, icon_z + 0.0008), root, ink)
        elif word == "EJECT":
            prism("Icon_EJECT", [(x - 0.011, iy - 0.001), (x + 0.011, iy - 0.001), (x, iy + 0.010)], icon_z, icon_z + 0.0016, root, ink)
            box("Icon_EJECT_bar", (0.022, 0.004, 0.0016), (x, iy - 0.0065, icon_z + 0.0008), root, ink)
        else:
            triangle_icon("Icon_NEXT_a", x - 0.007, iy, 0.014, icon_z, root, ink)
            triangle_icon("Icon_NEXT_b", x + 0.004, iy, 0.014, icon_z, root, ink)
            box("Icon_NEXT_bar", (0.003, 0.016, 0.0016), (x + 0.0135, iy, icon_z + 0.0008), root, ink)
        text("Word_" + word, word, 0.0135, (x, ky - 0.014, icon_z), root, ink, depth=0.0016, thicken=0.0005)
    # volume knob (right top) with a pointer line, and its little VOL print
    kx, kyy = 0.185, front + 0.058
    cylinder("VolumeKnob", 0.028, 0.026, (kx, kyy, z1 + 0.013), root, M["charcoal"], segments=28, bevel_w=0.004)
    cylinder("VolumeCap", 0.021, 0.004, (kx, kyy, z1 + 0.027), root, M["chrome"], segments=24)
    box("VolumePointer", (0.004, 0.018, 0.002), (kx, kyy + 0.008, z1 + 0.0295), root, M["orange"])
    text("Word_VOL", "VOL", 0.014, (kx, kyy + 0.045, z1 + 0.0004), root, M["ink"], thicken=0.0005)
    # top: stencil name plate and a carry handle at the back
    box("NamePlate", (0.20, 0.034, 0.0014), (-0.11, 0.07, z1 + 0.0007), root, M["charcoal"], 0.002)
    text("NameText", "COMMAND DECK", 0.017, (-0.11, 0.07, z1 + 0.0016), root, M["white_ink"], thicken=0.0005)
    for s in (-1, 1):
        box("HandlePost_%s" % ("L" if s < 0 else "R"), (0.022, 0.03, 0.07), (s * 0.19, 0.105, z1 + 0.035), root, M["charcoal"], 0.006)
    box("HandleBar", (0.40, 0.03, 0.022), (0, 0.105, z1 + 0.07), root, M["chrome"], 0.009)
    box("HandleGrip", (0.18, 0.036, 0.028), (0, 0.105, z1 + 0.07), root, M["rubber"], 0.010)
    return root


def export(root, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + list(root.children_recursive):
        o.select_set(True)
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_materials="EXPORT")
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in [root] + list(root.children_recursive):
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            me.calc_loop_triangles()
            tris += len(me.loop_triangles)
            o.evaluated_get(dg).to_mesh_clear()
    print("EXPORTED", path, "triangles", tris)
    return path


tape = build_tape()
export(tape, "cassette_tape.glb")
for o in [tape] + list(tape.children_recursive):
    bpy.data.objects.remove(o, do_unlink=True)
player = build_player()
export(player, "cassette_player.glb")
