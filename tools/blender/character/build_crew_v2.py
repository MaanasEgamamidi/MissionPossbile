"""Crew character v2: built from the owner's low-poly base (simple-low-poly-character.zip, PlayerCharacter.fbx).

Run inside Blender (MCP: exec(open(path).read())) or headless:
  blender -b --factory-startup --python build_crew_v2.py -- [--export]

Makes:
  Body_Head, Body_Torso, Body_Arms, Body_Legs  - the crew member in a teal flight suit (references: refs/crew_unsuited)
  Suit_Torso, Suit_Arms, Suit_Legs, Suit_Helmet - an orange low-poly spacesuit in the style of the owner's screenshots
on the existing 23-bone astronaut armature (bones re-centred in the new limbs), keeping all nine clips.
Saves assets_src/characters/crew_v2/crew_v2.blend; with --export also writes assets/characters/astronaut.glb.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

ROOT = r"G:\nasa app\mars_colony_godot"
SRC_FBX = os.path.join(ROOT, r"assets_src\characters\crew_v2\PlayerCharacter.fbx")
RIG_BLEND = os.path.join(ROOT, r"assets_src\characters\astronaut_pre_mixamo_walk.blend")
OUT_BLEND = os.path.join(ROOT, r"assets_src\characters\crew_v2\crew_v2.blend")
OUT_GLB = os.path.join(ROOT, r"assets\characters\astronaut.glb")
HEIGHT = 1.80
REPORT = {}

# ------------------------------------------------------------------ materials
def mat(name, col, rough=0.7, metal=0.0, emit=None, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*col, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = 1.5
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        m.surface_render_method = 'BLENDED' if hasattr(m, "surface_render_method") else None
        if hasattr(m, "blend_method"):
            m.blend_method = 'BLEND'
    m.diffuse_color = (*col, alpha)
    return m

M = {}
def make_materials():
    M["skin"] = mat("Mat_Skin", (0.62, 0.42, 0.31), 0.6)
    M["hair"] = mat("Mat_Hair", (0.04, 0.03, 0.025), 0.8)
    M["flight"] = mat("Mat_FlightSuit", (0.045, 0.20, 0.235), 0.75)
    M["flight_dark"] = mat("Mat_FlightSuitSeam", (0.03, 0.13, 0.155), 0.8)
    M["boot"] = mat("Mat_Boot", (0.05, 0.05, 0.055), 0.6)
    M["tape"] = mat("Mat_NameTape", (0.70, 0.70, 0.67), 0.7)
    M["ident"] = mat("Mat_Ident", (0.72, 0.38, 0.27), 0.6)
    M["eye"] = mat("Mat_Eye", (0.03, 0.025, 0.02), 0.3)
    M["orange"] = mat("Mat_SuitOrange", (0.86, 0.25, 0.04), 0.55)
    M["white"] = mat("Mat_SuitWhite", (0.88, 0.88, 0.86), 0.5)
    M["dark"] = mat("Mat_SuitDark", (0.05, 0.05, 0.06), 0.6)
    M["grey"] = mat("Mat_SuitGrey", (0.35, 0.37, 0.40), 0.45, 0.4)
    M["visor"] = mat("Mat_Visor", (0.02, 0.04, 0.07), 0.05, 0.3, alpha=0.4)
    M["glow"] = mat("Mat_SuitGlow", (0.25, 0.95, 1.0), 0.3, emit=(0.25, 0.95, 1.0))
    M["screen"] = mat("Mat_SuitScreen", (0.45, 0.95, 0.85), 0.3, emit=(0.45, 0.95, 0.85))
    M["lamp"] = mat("Mat_SuitLamp", (1.0, 0.75, 0.2), 0.3, emit=(1.0, 0.75, 0.2))

def slot(ob, key):
    m = M[key]
    i = ob.data.materials.find(m.name)
    if i < 0:
        ob.data.materials.append(m); i = len(ob.data.materials) - 1
    return i

# ------------------------------------------------------------------ helpers
def fc(f):
    return f.calc_center_median()

def side_of(x):
    return "L" if x > 0 else "R"

def select_only(objs, active):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active

def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

# ------------------------------------------------------------------ 1. load
def load():
    # start from an empty scene without reloading the file (reloading breaks the MCP session's context)
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.fbx(filepath=SRC_FBX)
    src = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    src.modifiers.clear()
    zs = [(src.matrix_world @ v.co).z for v in src.data.vertices]
    s = HEIGHT / (max(zs) - min(zs))
    src.scale = (s, s, s)
    select_only([src], src)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    with bpy.data.libraries.load(RIG_BLEND, link=False) as (df, dt):
        dt.objects = ["Armature"]
    arm = dt.objects[0]
    bpy.context.scene.collection.objects.link(arm)
    REPORT["scale"] = round(s, 4)
    return src, arm

# split the base into its shells (skin body, hair, shirt, trousers, shoes) by source material
def split_shells(src):
    names = {}
    for i, m in enumerate(src.data.materials):
        c = m.node_tree.nodes["Principled BSDF"].inputs[0].default_value if m.use_nodes else m.diffuse_color
        if c[0] > 0.7 and c[1] > 0.4 and c[2] > 0.2 and c[1] < 0.7: names[i] = "skin"
        elif c[0] > 0.9 and c[1] > 0.9: names[i] = "trousers"
        elif c[0] > 0.6 and c[1] < 0.3: names[i] = "shirt"
        else: names[i] = "black"
    shells = {}
    for key in set(names.values()):
        bm = bmesh.new(); bm.from_mesh(src.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if names[f.material_index] != key], context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        shells[key] = new_obj("shell_" + key, bm)
    # black = hair (high) + shoes (low)
    blk = shells.pop("black")
    for key, test in (("hair", lambda z: z > 1.0), ("shoes", lambda z: z <= 1.0)):
        bm = bmesh.new(); bm.from_mesh(blk.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not test(fc(f).z)], context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        shells[key] = new_obj("shell_" + key, bm)
    bpy.data.objects.remove(blk); bpy.data.objects.remove(src)
    for ob in shells.values():
        ob.data.materials.clear()
    return shells

# ------------------------------------------------------------------ 2. fit bones to the limbs
def fit_bones(arm, skin):
    vs = [v.co.copy() for v in skin.data.vertices]
    def centre(z, side, kind, dz=0.03):
        sgn = 1 if side == "L" else -1
        if kind == "arm":
            pts = [v for v in vs if sgn * v.x > 0.21 and abs(v.z - z) < dz]
        else:
            pts = [v for v in vs if sgn * v.x > 0.005 and abs(v.z - z) < dz and v.z < 0.9]
        if len(pts) < 3:
            return None
        return Vector(((min(p.x for p in pts) + max(p.x for p in pts)) / 2, (min(p.y for p in pts) + max(p.y for p in pts)) / 2, z))
    select_only([arm], arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    moved = {}
    for s in ("L", "R"):
        anchor_off = eb["HandAnchor" + s].head - eb["Hand" + s].head
        anchor_vec = eb["HandAnchor" + s].tail - eb["HandAnchor" + s].head
        for b, end, kind in (("LowerArm" + s, "head", "arm"), ("Hand" + s, "head", "arm"), ("Hand" + s, "tail", "arm"),
                             ("LowerLeg" + s, "head", "leg"), ("Foot" + s, "head", "leg")):
            p = getattr(eb[b], end)
            c = centre(p.z, s, kind)
            if c is None:
                continue
            moved[b + "." + end] = [round(v, 3) for v in (c - p)]
            setattr(eb[b], end, c)
            par = eb[b].parent
            if end == "head" and par is not None and eb[b].use_connect is False and (par.tail - p).length < 1e-4:
                par.tail = c
            if end == "head" and par is not None:
                par.tail = c if (par.tail - p).length < 0.02 else par.tail
        eb["HandAnchor" + s].head = eb["Hand" + s].head + anchor_off
        eb["HandAnchor" + s].tail = eb["HandAnchor" + s].head + anchor_vec
        # upper leg / upper arm heads: centre in x,y only at their height
        for b, kind in (("UpperLeg" + s, "leg"), ("UpperArm" + s, "arm")):
            p = eb[b].head
            c = centre(p.z - (0.06 if kind == "leg" else 0.05), s, kind)
            if c is not None and kind == "leg":
                eb[b].head = Vector((c.x, c.y, p.z)); moved[b + ".head"] = [round(v, 3) for v in (eb[b].head - p)]
    bpy.ops.object.mode_set(mode='OBJECT')
    REPORT["bone_moves"] = moved

# ------------------------------------------------------------------ 3. weights
def weight(arm, skin, shells):
    select_only([skin, arm], arm)
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    zero = [v.index for v in skin.data.vertices if not v.groups or sum(g.weight for g in v.groups) < 1e-4]
    REPORT["skin_zero_weight_verts"] = len(zero)
    # anchors must not deform anything
    for n in ("HandAnchorL", "HandAnchorR"):
        g = skin.vertex_groups.get(n)
        if g: skin.vertex_groups.remove(g)
    for ob in shells:
        ob.parent = arm
        mod = ob.modifiers.new("Armature", 'ARMATURE'); mod.object = arm
        for g in skin.vertex_groups:
            ob.vertex_groups.new(name=g.name)
        dt = ob.modifiers.new("dt", 'DATA_TRANSFER')
        dt.object = skin; dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}
        dt.vert_mapping = 'POLYINTERP_NEAREST'
        dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
        ob.modifiers.move(len(ob.modifiers) - 1, 0)
        select_only([ob], ob)
        bpy.ops.object.modifier_apply(modifier="dt")

def rigid(ob, arm, bone):
    ob.parent = arm
    g = ob.vertex_groups.new(name=bone)
    g.add([v.index for v in ob.data.vertices], 1.0, 'REPLACE')
    mod = ob.modifiers.new("Armature", 'ARMATURE'); mod.object = arm

# ------------------------------------------------------------------ 4. dress the crew member (teal flight suit)
def dress(arm, sh):
    skin, hair, shirt, trousers, shoes = sh["skin"], sh["hair"], sh["shirt"], sh["trousers"], sh["shoes"]
    for ob, key in ((skin, "skin"), (hair, "hair"), (shirt, "flight"), (trousers, "flight"), (shoes, "boot")):
        ob.data.materials.append(M[key])
        for p in ob.data.polygons: p.material_index = 0
    eb = arm.data.bones
    wrist = {s: eb["Hand" + s].head_local for s in "LR"}
    elbow = {s: eb["LowerArm" + s].head_local for s in "LR"}
    # long sleeves: arm skin above the wrist takes the flight-suit colour; collar shows a little skin
    fi, si = slot(skin, "flight"), 0
    sleeves = 0
    for p in skin.data.polygons:
        c = p.center
        s = side_of(c.x)
        if abs(c.x) > 0.19 and c.z > 1.0:
            axis = (wrist[s] - elbow[s]).normalized()
            if (c - wrist[s]).dot(axis) < -0.015:
                p.material_index = fi; sleeves += 1
        # under the trousers / shirt the skin is never seen: keep it flight coloured so gaps never show skin
        elif c.z < 1.45 and abs(c.x) < 0.2 and c.z > 0.1:
            p.material_index = fi
    REPORT["sleeve_faces"] = sleeves
    # shoulder patch (left arm, outer faces) and name tape (left chest)
    ii = slot(skin, "ident")
    for p in skin.data.polygons:
        c = p.center
        if c.x > 0.19 and 1.30 < c.z < 1.42 and p.normal.x > 0.55:
            p.material_index = ii
    ti = slot(shirt, "tape")
    si2 = slot(shirt, "ident")
    for p in shirt.data.polygons:
        c = p.center
        if 0.04 < c.x < 0.16 and 1.33 < c.z < 1.40 and p.normal.y < -0.6:
            p.material_index = ti
        if c.x > 0.17 and 1.30 < c.z < 1.43 and p.normal.x > 0.55:
            p.material_index = si2
    # belt line: trousers faces at the top band darker
    di = slot(trousers, "flight_dark")
    tz = max(v.co.z for v in trousers.data.vertices)
    for p in trousers.data.polygons:
        if p.center.z > tz - 0.04:
            p.material_index = di

def add_face_details(head_obj):
    """Small eyes and brows on the face: low-poly boxes placed on the face front."""
    vs = [v.co for v in head_obj.data.vertices]
    face = [v for v in vs if 1.60 < v.z < 1.72]
    front_y = min(v.y for v in face)
    bm = bmesh.new()
    eye_z = 1.668
    for sx in (-1, 1):
        x = sx * 0.034
        ys = [v.y for v in vs if abs(v.x - x) < 0.015 and abs(v.z - eye_z) < 0.015]
        y = (min(ys) if ys else front_y) - 0.002
        for (dz, sz, key) in ((0.0, (0.022, 0.006, 0.010), "eye"), (0.022, (0.030, 0.006, 0.006), "hair")):
            m = Matrix.Translation((x, y + 0.002, eye_z + dz)) @ Matrix.Diagonal((*sz, 1))
            r = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
            for f in {f for v in r["verts"] for f in v.link_faces}:
                f.material_index = 0 if key == "eye" else 1
    ob = new_obj("face_details", bm)
    ob.data.materials.append(M["eye"]); ob.data.materials.append(M["hair"])
    return ob

# ------------------------------------------------------------------ 5. spacesuit
def build_suit(arm, skin):
    eb = arm.data.bones
    # shell = copy of the skin body without head and neck, pushed out along normals
    bm = bmesh.new(); bm.from_mesh(skin.data)
    dl = bm.verts.layers.deform.verify()
    neck_z = eb["Neck"].head_local.z + 0.01
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if fc(f).z > neck_z], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.normal_update()
    for v in bm.verts:
        push = 0.035 if v.co.z > 0.95 else 0.03
        if abs(v.co.x) > 0.19 and v.co.z > 0.9:
            push = 0.028  # arms
        v.co += v.normal * push
        if v.co.z < 0.0:
            v.co.z = 0.0
    # boots a bit chunkier
    for v in bm.verts:
        if v.co.z < 0.16:
            foot_c = Vector((math.copysign(0.11, v.co.x), v.co.y, v.co.z))
            d = v.co - foot_c; d.z = 0
            v.co.x += d.x * 0.18; v.co.y += d.y * 0.10
    suit = new_obj("suit_shell", bm)
    for g in skin.vertex_groups:          # same order as the copied deform layer
        suit.vertex_groups.new(name=g.name)
    suit.parent = arm
    mod = suit.modifiers.new("Armature", 'ARMATURE'); mod.object = arm
    for k in ("orange", "white", "dark", "ident"):
        slot(suit, k)
    wrist = {s: eb["Hand" + s].head_local for s in "LR"}
    elbow = {s: eb["LowerArm" + s].head_local for s in "LR"}
    knee = {s: eb["LowerLeg" + s].head_local for s in "LR"}
    O, W, D, I = 0, 1, 2, 3
    for p in suit.data.polygons:
        c, n = p.center, p.normal
        s = side_of(c.x)
        idx = O
        is_arm = abs(c.x) > 0.25 or (abs(c.x) > 0.19 and c.z > 0.9)   # hands hang below 0.9 m, outside the legs
        if is_arm:
            axis = (wrist[s] - elbow[s]).normalized()
            t = (c - wrist[s]).dot(axis)
            if t > -0.01:
                idx = W                                   # gloves
            elif -0.05 < t <= -0.01:
                idx = W                                   # cuff
            elif (c - elbow[s]).length < 0.06 and n.y > 0.2:
                idx = D                                   # elbow pad
            elif 1.30 < c.z < 1.42 and n.x * (1 if s == "L" else -1) > 0.55:
                idx = I                                   # shoulder patch (crew colour)
            elif 1.38 < c.z < 1.44:
                idx = W                                   # upper-arm stripe
        else:
            if c.z < 0.025:
                idx = D                                   # soles
            elif c.z < 0.17:
                idx = W                                   # boots
            elif c.z < 0.20:
                idx = D                                   # boot rim
            elif abs(c.z - knee[s].z) < 0.05 and n.y < -0.3:
                idx = D                                   # knee pads
            elif 0.66 < c.z < 0.70:
                idx = W                                   # thigh stripe
            elif 0.97 < c.z < 1.03:
                idx = W                                   # belt
            elif 1.40 < c.z < 1.44 and n.y < 0.0:
                idx = W                                   # chest stripe
        p.material_index = idx
    return suit

def helmet_and_kit(arm, suit):
    eb = arm.data.bones
    head_c = (eb["Head"].head_local + eb["Head"].tail_local) / 2 + Vector((0, -0.005, -0.015))
    # suit extents for placing pack and panel
    sv = [v.co for v in suit.data.vertices]
    back_y = max(v.y for v in sv if 1.15 < v.z < 1.40 and abs(v.x) < 0.12)
    front_y = min(v.y for v in sv if 1.22 < v.z < 1.36 and abs(v.x) < 0.10)
    parts = {}
    # ---- helmet shell
    bm = bmesh.new()
    r = 0.178
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=9, radius=r, matrix=Matrix.Translation(head_c))
    cut = head_c.z - r * 0.62
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut], context='VERTS')
    # neck ring
    ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=14, radius1=0.15, radius2=0.145, depth=0.06,
                                 matrix=Matrix.Translation((head_c.x, head_c.y, cut - 0.015)))
    ring_faces = {f for v in ring["verts"] for f in v.link_faces}
    for f in bm.faces:
        c = fc(f); d = (c - head_c).normalized()
        if f in ring_faces:
            f.material_index = 2                       # orange ring
        elif d.y < -0.45 and -0.42 < d.z < 0.55 and abs(d.x) < 0.80:
            f.material_index = 1                       # visor
        elif abs(c.x - head_c.x) < 0.035 and d.z > 0.1:
            f.material_index = 2                       # orange crest stripe
        else:
            f.material_index = 0
    bm.normal_update()
    # side lamps
    for sx in (-1, 1):
        lamp = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.028, radius2=0.028, depth=0.03,
                                     matrix=Matrix.Translation(head_c + Vector((sx * (r + 0.005), 0.0, 0.0))) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        for v in lamp["verts"]:
            for f in v.link_faces:
                f.material_index = 3
    h = new_obj("Suit_Helmet", bm)
    for k in ("white", "visor", "orange", "glow"):
        h.data.materials.append(M[k])
    rigid(h, arm, "Neck")
    parts["helmet"] = h
    # ---- backpack with two glowing tanks (joined into Suit_Torso)
    bm = bmesh.new()
    pz = 1.24
    body = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, back_y + 0.06, pz)) @ Matrix.Diagonal((0.34, 0.12, 0.44, 1)))
    for v in body["verts"]:
        for f in v.link_faces: f.material_index = 0
    for sx in (-1, 1):
        t = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.07, radius2=0.07, depth=0.40,
                                  matrix=Matrix.Translation((sx * 0.085, back_y + 0.15, pz)))
        for v in t["verts"]:
            for f in v.link_faces:
                f.material_index = 1
        # narrow light strip down the back of each tank
        g = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((sx * 0.085, back_y + 0.15 + 0.071, pz)) @ Matrix.Diagonal((0.026, 0.008, 0.26, 1)))
        for v in g["verts"]:
            for f in v.link_faces:
                f.material_index = 2
    for f in bm.faces:
        if f.material_index not in (0, 1, 2): f.material_index = 0
    pack = new_obj("Pack_tmp", bm)
    for k in ("grey", "white", "glow"):
        pack.data.materials.append(M[k])
    # ---- chest panel
    bm = bmesh.new()
    panel_c = Vector((0.0, front_y - 0.012, 1.29))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(panel_c) @ Matrix.Diagonal((0.17, 0.035, 0.13, 1)))
    for f in bm.faces: f.material_index = 0
    scr = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(panel_c + Vector((0, -0.017, 0.02))) @ Matrix.Diagonal((0.12, 0.006, 0.05, 1)))
    for v in scr["verts"]:
        for f in v.link_faces: f.material_index = 1
    for i, (bx, col) in enumerate(((-0.05, 2), (-0.015, 3), (0.02, 2), (0.055, 3))):
        b = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(panel_c + Vector((bx, -0.019, -0.035))) @ Matrix.Diagonal((0.018, 0.008, 0.018, 1)))
        for v in b["verts"]:
            for f in v.link_faces: f.material_index = col
    panel = new_obj("Panel_tmp", bm)
    for k in ("grey", "screen", "lamp", "dark"):
        panel.data.materials.append(M[k])
    for ob in (pack, panel):
        rigid(ob, arm, "Chest")
    parts["pack"], parts["panel"] = pack, panel
    return parts

# ------------------------------------------------------------------ 6. split into the game's named parts
HEAD = {"Head", "Neck"}
ARMS = {"UpperArmL", "LowerArmL", "HandL", "UpperArmR", "LowerArmR", "HandR"}
LEGS = {"UpperLegL", "LowerLegL", "FootL", "ToesL", "UpperLegR", "LowerLegR", "FootR", "ToesR"}

def region_of_face(ob, p):
    tot = {}
    for vi in p.vertices:
        for g in ob.data.vertices[vi].groups:
            n = ob.vertex_groups[g.group].name
            tot[n] = tot.get(n, 0.0) + g.weight
    if not tot:
        return "torso"
    b = max(tot, key=tot.get)
    return "head" if b in HEAD else "arms" if b in ARMS else "legs" if b in LEGS else "torso"

def split_regions(ob, prefix, keep=("head", "torso", "arms", "legs")):
    out = {}
    regions = [region_of_face(ob, p) for p in ob.data.polygons]
    for reg in keep:
        if reg not in regions:
            continue
        cp = ob.copy(); cp.data = ob.data.copy(); bpy.context.scene.collection.objects.link(cp)
        bm = bmesh.new(); bm.from_mesh(cp.data); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i, r in enumerate(regions) if r != reg], context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
        bm.to_mesh(cp.data); bm.free()
        cp.name = prefix + reg.capitalize()
        out[reg] = cp
    bpy.data.objects.remove(ob)
    return out

def join(objs, name):
    objs = [o for o in objs if o is not None]
    select_only(objs, objs[0])
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name; o.data.name = name
    return o

def clean_materials(ob):
    used = {p.material_index for p in ob.data.polygons}
    # rebuild slot list keeping only used materials
    keep = [ob.data.materials[i] for i in sorted(used)]
    remap = {old: new for new, old in enumerate(sorted(used))}
    idx = [remap[p.material_index] for p in ob.data.polygons]
    ob.data.materials.clear()          # note: clearing resets every face's material index, so re-apply after
    for m in keep:
        ob.data.materials.append(m)
    for p, i in zip(ob.data.polygons, idx):
        p.material_index = i

# ------------------------------------------------------------------ main
def build(export=False):
    src, arm = load()
    make_materials()
    sh = split_shells(src)
    fit_bones(arm, sh["skin"])
    weight(arm, sh["skin"], [sh[k] for k in ("hair", "shirt", "trousers", "shoes")])
    dress(arm, sh)
    face = add_face_details(sh["skin"])
    rigid(face, arm, "Head")
    suit = build_suit(arm, sh["skin"])
    kit = helmet_and_kit(arm, suit)
    # body parts
    body_parts = {}
    for k in ("skin", "hair", "shirt", "trousers", "shoes"):
        for reg, ob in split_regions(sh[k], k + "_").items():
            body_parts.setdefault(reg, []).append(ob)
    body_parts["head"].append(face)
    named = {}
    for reg, obs in body_parts.items():
        named["Body_" + reg.capitalize()] = join(obs, "Body_" + reg.capitalize())
    suit_parts = split_regions(suit, "suit_", keep=("torso", "arms", "legs"))
    named["Suit_Torso"] = join([suit_parts.get("torso"), kit["pack"], kit["panel"]], "Suit_Torso")
    named["Suit_Arms"] = join([suit_parts["arms"]], "Suit_Arms")
    named["Suit_Legs"] = join([suit_parts["legs"]], "Suit_Legs")
    named["Suit_Helmet"] = kit["helmet"]
    for n, ob in named.items():
        clean_materials(ob)
        ob.parent = arm
        mods = [m for m in ob.modifiers if m.type == 'ARMATURE']
        for m in mods[1:]:
            ob.modifiers.remove(m)
        if not mods:
            m = ob.modifiers.new("Armature", 'ARMATURE'); m.object = arm
        for g in list(ob.vertex_groups):
            if g.name.startswith("HandAnchor"):
                ob.vertex_groups.remove(g)
        for p in ob.data.polygons:
            p.use_smooth = False
    REPORT["meshes"] = {n: {"tris": sum(len(p.vertices) - 2 for p in o.data.polygons), "mats": [m.name for m in o.data.materials]} for n, o in named.items()}
    REPORT["tris_total"] = sum(v["tris"] for v in REPORT["meshes"].values())
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name not in named:
            bpy.data.objects.remove(o)
    arm.data.display_type = 'STICK'; arm.show_in_front = True
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    arm.animation_data.action = None
    bpy.context.preferences.filepaths.save_version = 0
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    REPORT["saved"] = OUT_BLEND
    return REPORT

if __name__ == "__main__" and "--" in sys.argv and bpy.app.background:
    build()
