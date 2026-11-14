"""Crew variants on the shared crew rig (crew_v2.blend), round 2 (Fable crew verdict 1, "BLENDER fixes" 1-11).
Re-runnable: everything it adds is removed and rebuilt on each run; rig, actions and NLA tracks are not touched.

  blender -b --factory-startup --disable-autoexec crew_v2.blend --python run_logged.py -- <log> crew_variants.py
          <report.json> [--save] [--export]

Exported contract (exact names; the game shows/hides per crew):
  Hair_Ponytail, Hair_Curly, Hair_Bob, Hair_Buzz          unsuited hair (Mat_Hair, 100% Head)
  HairIn_Ponytail, HairIn_Curly, HairIn_Bob, HairIn_Buzz  flattened hair that fits inside the helmet (Mat_Hair, Head)
  Hair_Beard                                              beard + moustache, copies the face weights; also used suited
  Ident_Symbol_Triangle/_Plus/_Circle/_Diamond            backpack, helmet back and chest copies; Mat_Ident on a
                                                          Mat_SuitDark plate (helmet copy on the helmet's bone)
  Ident_Band_Solid/_Double/_Dots/_Chevron                 helmet band + backpack band in that pattern (Mat_Ident)
  shape key "Feminine" on Body_Head/Torso/Arms/Legs, Suit_Torso/Arms/Legs (body + face)
Fixed for everyone: suit forearm rings, upper-arm bands, thigh stripes; flight-suit shoulder patches (white border),
upper-back yoke and collar ring (all Mat_Ident). Suit_Helmet is rebuilt: lower/wider visor, ring clear of the chin.
Face: eye whites (Mat_EyeWhite), pupils, raised friendlier brows, lash triangles that only open with Feminine.
"""
import bpy, bmesh, math, os, sys, json, struct
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
REPORT_PATH = argv[0] if argv and not argv[0].startswith("--") else None
SAVE = "--save" in argv
EXPORT = "--export" in argv
ROOT = r"G:\nasa app\mars_colony_godot"
GLB = os.path.join(ROOT, r"assets\characters\astronaut.glb")
BLEND = bpy.data.filepath
MTIME = os.path.getmtime(BLEND)
ARM = bpy.data.objects["Armature"]
OB = bpy.data.objects
R = {"blend": BLEND}
D2R = math.pi / 180

MAT = bpy.data.materials
def get_mat(name, col):
    m = MAT.get(name)
    if m is None:
        m = MAT.new(name); m.use_nodes = True
        p = m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = (*col, 1); p.inputs["Roughness"].default_value = 0.5
        m.diffuse_color = (*col, 1)
    return m
MAT_HAIR, MAT_EYE, MAT_SKIN, MAT_IDENT = MAT["Mat_Hair"], MAT["Mat_Eye"], MAT["Mat_Skin"], MAT["Mat_Ident"]
MAT_DARK, MAT_WHITE = MAT["Mat_SuitDark"], MAT["Mat_SuitWhite"]
MAT_EYEWHITE = get_mat("Mat_EyeWhite", (0.86, 0.86, 0.83))

HAIR = ("Ponytail", "Curly", "Bob", "Buzz")
SYMBOLS = ("Triangle", "Plus", "Circle", "Diamond")
BANDS = ("Solid", "Double", "Dots", "Chevron")
OWNED = [f"Hair_{h}" for h in HAIR] + [f"HairIn_{h}" for h in HAIR] + ["Hair_Beard"] + \
        [f"Ident_Symbol_{s}" for s in SYMBOLS] + [f"Ident_Band_{b}" for b in BANDS]
FEM_MESHES = ("Body_Head", "Body_Torso", "Body_Arms", "Body_Legs", "Suit_Torso", "Suit_Arms", "Suit_Legs")
ADDED = "crew_ident_add"
FACE_PART = "crew_face_part"

def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

def bump(x, c, hw):
    u = (x - c) / hw
    return max(0.0, 1 - u * u) ** 2

def interp(table, x):
    if x <= table[0][0]: return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]

def dir_of(az, el):
    """az 0 = front (-Y), positive toward the character's left (+X); el up from horizontal."""
    return Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))

def components(bm):
    seen, out = set(), []
    for v in bm.verts:
        if v in seen: continue
        stack, comp = [v], []
        seen.add(v)
        while stack:
            x = stack.pop(); comp.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o not in seen:
                    seen.add(o); stack.append(o)
        out.append(comp)
    return out

# ---------------------------------------------------------------- 0. clean slate for everything this script owns
for n in FEM_MESHES:
    if OB[n].data.shape_keys:
        OB[n].shape_key_clear()
for n in OWNED:
    if n in OB:
        me = OB[n].data; bpy.data.objects.remove(OB[n])
        if me.users == 0: bpy.data.meshes.remove(me)

head = OB["Body_Head"]
COLL = head.users_collection
def make_obj(name, bm, mats, groups):
    """New skinned mesh object; bm's deform layer indices refer to `groups` order."""
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    for c in COLL: c.objects.link(ob)
    ob.parent = ARM; ob.matrix_parent_inverse = head.matrix_parent_inverse.copy()
    for m in mats: me.materials.append(m)
    for p in me.polygons: p.use_smooth = False
    for g in groups: ob.vertex_groups.new(name=g)
    mod = ob.modifiers.new("Armature", 'ARMATURE'); mod.object = ARM
    return ob

def set_w(bm, verts, weights):
    dl = bm.verts.layers.deform.verify()
    for v in verts:
        for g, w in weights.items():
            v[dl][g] = w

# ---------------------------------------------------------------- 1. Body_Head: face parts (eyes, whites, brows, lashes)
hm = head.data
for m in (MAT_EYE, MAT_HAIR, MAT_EYEWHITE):
    if hm.materials.find(m.name) < 0:
        hm.materials.append(m)
I_SKIN, I_EYE, I_HAIR, I_WHITE = (hm.materials.find(n) for n in ("Mat_Skin", "Mat_Eye", "Mat_Hair", "Mat_EyeWhite"))
bm = bmesh.new(); bm.from_mesh(hm)
dl = bm.verts.layers.deform.verify()
fp = bm.verts.layers.int.get(FACE_PART) or bm.verts.layers.int.new(FACE_PART)
G_HEAD = head.vertex_groups["Head"].index
drop = set()
for comp in components(bm):
    mats = {f.material_index for v in comp for f in v.link_faces}
    if any(v[fp] > 0 for v in comp) or (mats <= {I_HAIR, I_EYE, I_WHITE} and len(comp) <= 8) or (mats <= {I_HAIR} and len(comp) > 8):
        drop |= {f for v in comp for f in v.link_faces}
bmesh.ops.delete(bm, geom=list(drop), context='FACES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.verts.index_update()
SKULL = BVHTree.FromPolygons([v.co.copy() for v in bm.verts],
                             [[v.index for v in f.verts] for f in bm.faces if f.material_index == I_SKIN])
C = Vector((0.0, 0.008, 1.685))                       # skull centre used for hair layout

def surf_front(x, z):
    hit = SKULL.ray_cast(Vector((x, -0.4, z)), Vector((0, 1, 0)), 1.0)
    return hit[0].y if hit[0] is not None else -0.1

FEM_TARGET = {}          # bmesh vert -> feminine position (face parts only); turned into indices after to_mesh
def box(centre, size, mi, part, fem=None, rot=None):
    m = Matrix.Translation(centre) @ (rot.to_4x4() if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    for v in r["verts"]:
        v[dl][G_HEAD] = 1.0; v[fp] = part
        for f in v.link_faces: f.material_index = mi
        if fem: FEM_TARGET[v] = fem(v.co.copy())
    return r["verts"]

EYE_Z, EYE_X = 1.670, 0.034
def eye_scale(co):                                   # Feminine: eyes 15% taller
    return Vector((co.x, co.y, EYE_Z + (co.z - EYE_Z) * 1.15))
for sx in (-1, 1):
    x = sx * EYE_X
    # follow the face's curve (yaw) so the white shows evenly on both sides of a centred pupil
    xl, xr = x - 0.009, x + 0.009
    yl = min(surf_front(xl, EYE_Z + dz) for dz in (-0.006, 0.0, 0.006))
    yr = min(surf_front(xr, EYE_Z + dz) for dz in (-0.006, 0.0, 0.006))
    ym = min(surf_front(x, EYE_Z + dz) for dz in (-0.006, 0.0, 0.006))
    y = min((yl + yr) / 2, ym)
    yaw = Matrix.Rotation(math.atan2(yr - yl, xr - xl), 3, 'Z')
    nrm = yaw @ Vector((0, -1, 0))
    box(Vector((x, y, EYE_Z)) + nrm * 0.0008, (0.0176, 0.004, 0.0124), I_WHITE, 2, eye_scale, yaw)      # eye white
    box(Vector((x, y, EYE_Z - 0.0003)) + nrm * 0.0018, (0.0092, 0.004, 0.0116), I_EYE, 1, eye_scale, yaw)  # pupil
    # lash: a small triangle prism at the outer corner; hidden inside the head at 0, out at Feminine 1
    xo, zo = sx * (EYE_X + 0.012), EYE_Z + 0.004
    yo = surf_front(xo, zo)
    tri = [Vector((xo - sx * 0.002, 0, zo - 0.004)), Vector((xo + sx * 0.007, 0, zo + 0.005)), Vector((xo - sx * 0.003, 0, zo + 0.004))]
    vs = []
    for dy in (-0.0025, 0.0015):
        for p in tri:
            out = Vector((p.x, yo + dy, p.z))
            v = bm.verts.new(out + Vector((0, 0.012, 0)) + (Vector((xo, yo, zo)) - out) * 0.6)
            v[dl][G_HEAD] = 1.0; v[fp] = 4
            FEM_TARGET[v] = out
            vs.append(v)
    a, b = vs[:3], vs[3:]
    fs = [bm.faces.new(a), bm.faces.new(list(reversed(b)))]
    for i in range(3):
        j = (i + 1) % 3
        fs.append(bm.faces.new((a[i], b[i], b[j], a[j])))
    for f in fs: f.material_index = I_EYE
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    # brow: a 3-segment strip, raised (~5 mm) with the inner end tilted up; Feminine thins and arches it
    xs = [0.019, 0.030, 0.041, 0.051]
    zs = [1.7005, 1.6995, 1.6975, 1.6945]
    arch = [-0.0004, 0.0018, 0.0016, -0.0012]
    rings = []
    for k, (bx, bz) in enumerate(zip(xs, zs)):
        X = sx * bx
        ys = surf_front(X, bz)
        ring = []
        for (dz, dy) in ((-0.0026, -0.0012), (0.0026, -0.0012), (0.0026, 0.0028), (-0.0026, 0.0028)):
            v = bm.verts.new(Vector((X, ys + dy - 0.0006, bz + dz)))
            v[dl][G_HEAD] = 1.0; v[fp] = 3
            FEM_TARGET[v] = Vector((X, ys + dy - 0.0006 + 0.0022, bz + arch[k] + dz * 0.62))
            ring.append(v)
        rings.append(ring)
    fs = []
    for k in range(3):
        for i in range(4):
            j = (i + 1) % 4
            fs.append(bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i])))
    fs.append(bm.faces.new(rings[0])); fs.append(bm.faces.new(list(reversed(rings[-1]))))
    for f in fs: f.material_index = I_HAIR
    bmesh.ops.recalc_face_normals(bm, faces=fs)
bm.verts.index_update()
FEM_IDX = {v.index: t for v, t in FEM_TARGET.items()}
bm.to_mesh(hm); bm.free()
for p in hm.polygons: p.use_smooth = False

def skull_r(d):
    hit = SKULL.ray_cast(C, d, 0.5)
    return (hit[0] - C).length if hit[0] is not None else 0.09

def skin_h(az, z):
    o = Vector((C.x, C.y, z)); d = Vector((math.sin(az), -math.cos(az), 0))
    hit = SKULL.ray_cast(o, d, 0.4)
    return (hit[0] - o).length if hit[0] is not None else 0.0

# ---------------------------------------------------------------- 2. hair
def build_cap(bm, segs, rings, point, lip_in, push_out=True, margin=0.0035):
    crown = bm.verts.new(point(0.0, 0.0))
    grid = []
    for j in range(1, rings + 1):
        grid.append([bm.verts.new(point(-math.pi + 2 * math.pi * i / segs, j / rings)) for i in range(segs)])
    fs = [bm.faces.new((crown, grid[0][(i + 1) % segs], grid[0][i])) for i in range(segs)]
    for j in range(rings - 1):
        for i in range(segs):
            fs.append(bm.faces.new((grid[j][i], grid[j][(i + 1) % segs], grid[j + 1][(i + 1) % segs], grid[j + 1][i])))
    rim = grid[-1]
    inner = [bm.verts.new(lip_in(v.co, -math.pi + 2 * math.pi * i / segs)) for i, v in enumerate(rim)]
    for i in range(segs):
        fs.append(bm.faces.new((rim[i], rim[(i + 1) % segs], inner[(i + 1) % segs], inner[i])))
    if push_out:
        lip = set(inner)
        for _ in range(6):
            moved = 0
            for f in fs:
                if any(v in lip for v in f.verts): continue
                for pt in [f.calc_center_median()] + [(e.verts[0].co + e.verts[1].co) / 2 for e in f.edges]:
                    d = pt - C
                    need = skull_r(d.normalized()) + margin - d.length
                    if need > 0:
                        for v in f.verts:
                            if v not in lip: v.co += (v.co - C).normalized() * need
                        moved += 1
                        break
            if not moved: break
    return fs

def cap_point(he_table, th_fn):
    def point(az, t):
        he = interp(he_table, abs(az) / D2R) * D2R
        el = math.pi / 2 - t * (math.pi / 2 - he)
        d = dir_of(az, el)
        return C + d * (skull_r(d) + th_fn(az, t))
    return point

def lip_scalp(p, az):
    d = (p - C).normalized()
    return C + d * (skull_r(d) - 0.002)

def strand(bm, root_az, root_el, drop, fwd=0.004, w0=0.016, w1=0.006, th=0.007):
    """Short hanging strand (temple hair) from a point on the scalp."""
    d = dir_of(root_az, root_el)
    top = C + d * (skull_r(d) + 0.004)
    rings = []
    for k in range(4):
        t = k / 3
        z = top.z - drop * t
        h = max(skin_h(root_az, z) + 0.004, (top.xy - C.xy).length * (1 - 0.15 * t))
        c = Vector((C.x + math.sin(root_az) * h, C.y - math.cos(root_az) * h - fwd * t, z))
        out = Vector((math.sin(root_az), -math.cos(root_az), 0)); side = Vector((0, 0, 1)).cross(out)
        w = w0 + (w1 - w0) * t
        rings.append([bm.verts.new(c + side * sw * w / 2 + out * so * th) for sw, so in ((-1, 0), (1, 0), (1, 1), (-1, 1))])
    fs = []
    for k in range(3):
        for i in range(4):
            j = (i + 1) % 4
            fs.append(bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i])))
    fs.append(bm.faces.new(list(reversed(rings[-1]))))
    return fs

HC = None   # helmet centre, set in section 3 (used by the inner hair clamp)

def hair_style(style, inner):
    bm = bmesh.new()
    k = 0.42 if inner else 1.0          # inner hair: flattened so it fits inside the helmet
    if style == "Buzz":
        HE = [(0, 30), (25, 33), (45, 26), (70, 14), (90, 6), (130, -12), (180, -22)]
        build_cap(bm, 16, 4, cap_point(HE, lambda az, t: 0.0055 * (0.8 if inner else 1.0)), lip_scalp)
    elif style == "Curly":
        HE = [(0, 26), (30, 25), (55, 14), (80, 4), (100, 2), (135, -14), (180, -24)]
        th = lambda az, t: (0.010 + 0.040 * (1 - t ** 2)) * k
        pt = cap_point(HE, th)
        SEG, RING = 18, 6
        def curly_point(az, t):
            p = pt(az, t)
            i = round((az + math.pi) / (2 * math.pi) * SEG); j = round(t * RING)
            if 0 < j < RING:
                p += (p - C).normalized() * (0.0056 if (i + j) % 2 == 0 else -0.002) * (1.0 - 0.5 * t) * k
            return p
        build_cap(bm, SEG, RING, curly_point, lip_scalp)
        golden = math.pi * (3 - math.sqrt(5)); n = 0
        for q in range(60):
            zf = 1 - (q + 0.5) / 60 * 1.3
            if zf < -0.3: break
            az = (q * golden) % (2 * math.pi) - math.pi
            el = math.asin(max(-1, min(1, zf)))
            he = interp(HE, abs(az) / D2R)
            if el < (he + 9) * D2R: continue
            t = (math.pi / 2 - el) / (math.pi / 2 - he * D2R)
            d = dir_of(az, el)
            rr = (0.0135 + 0.003 * ((q * 7) % 3) / 2) * (0.75 if inner else 1.0)
            cen = C + d * (skull_r(d) + th(az, t) - 0.003)
            u = d.cross(Vector((0, 0, 1))) if abs(d.z) < 0.95 else Vector((1, 0, 0))
            u.normalize(); w = d.cross(u)
            rot = Matrix.Rotation(q * 1.3, 3, d)
            vv = [bm.verts.new(p) for p in (cen + rot @ (u * rr), cen - rot @ (u * rr), cen + rot @ (w * rr),
                                              cen - rot @ (w * rr), cen + d * rr * 0.6, cen - d * rr * 0.6)]
            for a, b in ((0, 2), (2, 1), (1, 3), (3, 0)):
                bm.faces.new((vv[a], vv[b], vv[4])); bm.faces.new((vv[b], vv[a], vv[5]))
            n += 1
        R["curly_blobs"] = n
    elif style == "Ponytail":
        # centre parting: the hairline dips at the part and hair sweeps back; thin rim (soft edge)
        HE = [(0, 29), (10, 24), (40, 19), (80, 3), (100, 0), (140, -16), (180, -22)]
        def th(az, t):
            v = (0.004 + 0.011 * (1 - t)) * (0.6 if inner else 1.0)
            if abs(az) < 3 * D2R and t > 0.3: v -= 0.0045 * (0.6 if inner else 1.0)
            return max(0.0025, v)
        build_cap(bm, 16, 5, cap_point(HE, th), lip_scalp)
        for sx in (-1, 1):
            strand(bm, sx * 60 * D2R, 12 * D2R, 0.055 if not inner else 0.045)
        if not inner:
            d0 = dir_of(math.pi, 58 * D2R)
            S = C + d0 * skull_r(d0)
            path = [S - d0 * 0.010, S + d0 * 0.016, S + d0 * 0.028 + Vector((0, 0.004, 0.008))]
            for step in ((0, 0.026, 0.026), (0, 0.05, 0.012), (0, 0.048, -0.032), (0, 0.032, -0.068), (0, 0.014, -0.078)):
                path.append(path[-1] + Vector(step))
            radii = [0.029, 0.037, 0.029, 0.043, 0.046, 0.044, 0.036, 0.022]
            tip = path[-1] + Vector((0, 0.004, -0.045))
            R["ponytail_tip"] = [round(x, 3) for x in tip]
            N6 = 6; tube = []
            for q, (p, r) in enumerate(zip(path, radii)):
                tan = (path[min(q + 1, len(path) - 1)] - path[max(q - 1, 0)]).normalized()
                u = Vector((1, 0, 0)); v = tan.cross(u).normalized()
                tube.append([bm.verts.new(p + u * (math.cos(2 * math.pi * (i + 0.5) / N6) * r * 1.12) + v * (math.sin(2 * math.pi * (i + 0.5) / N6) * r)) for i in range(N6)])
            for q in range(len(tube) - 1):
                for i in range(N6):
                    bm.faces.new((tube[q][i], tube[q][(i + 1) % N6], tube[q + 1][(i + 1) % N6], tube[q + 1][i]))
            tv = bm.verts.new(tip)
            for i in range(N6):
                bm.faces.new((tube[-1][i], tube[-1][(i + 1) % N6], tv))
            bm.faces.new(list(reversed(tube[0])))
        else:
            # small flattened gather at the crown back instead of the tail
            d0 = dir_of(math.pi, 50 * D2R); S = C + d0 * (skull_r(d0) + 0.006)
            r = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.022, matrix=Matrix.Translation(S) @ Matrix.Diagonal((1.2, 0.7, 1.0, 1)))
    elif style == "Bob":
        E_SIDE0, E_BOTTOM, PART_AZ = -8.0, -60.0, 36.0
        def bob_end(a):
            if abs(a) <= 40:
                return 13 + (a + 40) / 80 * 13
            return interp([(40, 4), (52, -30), (66, -52), (80, E_BOTTOM), (180, E_BOTTOM)], abs(a)) if a < 0 else \
                interp([(40, 26), (50, -18), (64, -48), (80, E_BOTTOM), (180, E_BOTTOM)], a)
        def th_bob(az, t):
            a = az / D2R
            v = 0.010 + 0.010 * (1 - t)
            if a < 0: v += 0.004 * smooth(0, 40, -a)
            if abs(a - PART_AZ) < 4 and t < 0.75: v -= 0.008
            return max(0.003, v * (0.5 if inner else 1.0))
        Z_BOTTOM = [(0, 1.60), (90, 1.585), (140, 1.592), (180, 1.598)]
        flare = 0.006 if inner else 0.014
        def bob_point(az, t):
            a = az / D2R
            e = 90 - t * (90 - bob_end(a))
            if e >= E_SIDE0:
                d = dir_of(az, e * D2R)
                return C + d * (skull_r(d) + th_bob(az, t))
            d = dir_of(az, E_SIDE0 * D2R)
            top = C + d * (skull_r(d) + th_bob(az, 1.0))
            frac = (E_SIDE0 - e) / (E_SIDE0 - E_BOTTOM)
            z = top.z - frac * (top.z - interp(Z_BOTTOM, abs(a)))
            h = max((top.xy - C.xy).length + flare * frac, skin_h(az, z) + (0.008 if inner else 0.012))
            if frac > 0.8: h -= 0.012 * (frac - 0.8) / 0.2
            return Vector((C.x + math.sin(az) * h, C.y - math.cos(az) * h, z))
        def lip_bob(p, az):
            if p.z > C.z - 0.02: return lip_scalp(p, az)
            o = Vector((C.x, C.y, p.z)); q = p - o
            return o + q * ((q.length - (0.009 if inner else 0.014)) / q.length) + Vector((0, 0, 0.004))
        build_cap(bm, 20, 8, bob_point, lip_bob)
    if inner:
        lim = HR - 0.020                              # inside the helmet facets with clearance
        for v in bm.verts:
            d = v.co - HC
            if d.length > lim: v.co = HC + d.normalized() * lim
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_w(bm, bm.verts, {0: 1.0})
    return bm

# ---------------------------------------------------------------- 3. helmet rebuild (visor lower/wider; neck ring clear of the chin)
hel = OB["Suit_Helmet"]
HELMET_BONE = hel.vertex_groups[0].name if len(hel.vertex_groups) else "Neck"
hb = ARM.data.bones["Head"]
HC = (hb.head_local + hb.tail_local) / 2 + Vector((0, -0.005, -0.015))
HR = 0.192                                   # +1.4 cm over v2 so head turns inside the Neck-rigid helmet stay clear
mats = [MAT_WHITE, MAT["Mat_Visor"], MAT["Mat_SuitOrange"], MAT["Mat_SuitGlow"]]
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=HR, matrix=Matrix.Translation(HC))
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < HC.z - HR * 0.85], context='VERTS')
z_edge = min(v.co.z for v in bm.verts)
r_edge = max((v.co.xy - HC.xy).length for v in bm.verts if abs(v.co.z - z_edge) < 1e-4)
for f in bm.faces:
    c = f.calc_center_median(); d = (c - HC).normalized()
    el = math.asin(max(-1, min(1, d.z))) / D2R; az = math.degrees(math.atan2(d.x, -d.y))
    if abs(az) < 70 and el < 37:                              # whole front incl. the bottom row (no stray white facet)
        f.material_index = 1                                  # visor: lower and wider so chin, cheeks, hairline show
    elif abs(c.x - HC.x) < 0.035 and el > 38:
        f.material_index = 2                                  # orange crest
    else:
        f.material_index = 0
ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=16, radius1=0.150, radius2=r_edge + 0.004, depth=0.034,
                             matrix=Matrix.Translation((HC.x, HC.y, z_edge - 0.017 + 0.003)))
for v in ring["verts"]:
    for f in v.link_faces: f.material_index = 2
for sx in (-1, 1):
    lamp = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.028, radius2=0.028, depth=0.03,
                                 matrix=Matrix.Translation(HC + Vector((sx * (HR + 0.005), 0.0, 0.0))) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    for v in lamp["verts"]:
        for f in v.link_faces: f.material_index = 3
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
set_w(bm, bm.verts, {0: 1.0})
hel.vertex_groups.clear(); hel.vertex_groups.new(name=HELMET_BONE)
hel.data.materials.clear()
for m in mats: hel.data.materials.append(m)
bm.to_mesh(hel.data); bm.free()
for p in hel.data.polygons: p.use_smooth = False
R["helmet"] = {"bone": HELMET_BONE, "bottom_edge_z": round(z_edge, 3), "bottom_edge_r": round(r_edge, 3),
               "tris": sum(len(p.vertices) - 2 for p in hel.data.polygons)}

# hair objects (inner hair needs HC)
hair = {}
for h in HAIR:
    hair[f"Hair_{h}"] = make_obj(f"Hair_{h}", hair_style(h, False), [MAT_HAIR], ["Head"])
    hair[f"HairIn_{h}"] = make_obj(f"HairIn_{h}", hair_style(h, True), [MAT_HAIR], ["Head"])

# --- beard: cheeks, jaw, chin (+1 cm), sideburns up to the buzz hairline, moustache block; copies the face weights
hm = head.data
names = [g.name for g in head.vertex_groups]
def beard_face(p):
    c, n = p.center, p.normal
    ax = abs(c.x)
    if c.y > 0.024 or c.z < 1.548 or c.z > 1.708: return False
    if c.z < 1.575 and n.z > -0.35 and c.y > -0.02: return False   # neck
    if ax > 0.058 and -0.046 < c.y < 0.024: return True            # sideburns: wide, up under the buzz hairline
    if c.z > 1.668: return False
    if ax < 0.033: return c.z < 1.598                               # chin below the mouth
    return c.z < 1.640                                              # cheeks and jaw
sel = [p for p in hm.polygons if p.material_index == I_SKIN and beard_face(p)]
vids = sorted({i for p in sel for i in p.vertices})
nrm = {i: Vector() for i in vids}
for p in sel:
    for i in p.vertices: nrm[i] += p.normal * p.area
bm = bmesh.new(); dlb = bm.verts.layers.deform.verify()
outer, innerv, src = {}, {}, {}
for i in vids:
    co = hm.vertices[i].co; n = nrm[i].normalized()
    extra = 0.010 * smooth(1.600, 1.575, co.z) * smooth(0.05, 0.02, abs(co.x)) if co.y < -0.03 else 0.0
    th = 0.007 - 0.0035 * smooth(1.62, 1.69, co.z)                  # thins toward the hairline so it blends in
    outer[i] = bm.verts.new(co + n * (th + extra) + Vector((0, 0, -0.4 * extra)))
    innerv[i] = bm.verts.new(co - n * 0.003)
beard_faces = []
for p in sel:
    beard_faces.append(bm.faces.new([outer[i] for i in p.vertices]))
    beard_faces.append(bm.faces.new([innerv[i] for i in reversed(p.vertices)]))   # closed solid: no see-through slivers
edges = {}
for p in sel:
    for k in range(len(p.vertices)):
        a, b = p.vertices[k], p.vertices[(k + 1) % len(p.vertices)]
        edges.setdefault(tuple(sorted((a, b))), []).append((a, b, p.center.copy()))
for key, es in edges.items():
    if len(es) == 1:
        a, b, pc = es[0]
        beard_faces.append(bm.faces.new((outer[b], outer[a], innerv[a], innerv[b])))
bmesh.ops.recalc_face_normals(bm, faces=beard_faces)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
for i in vids:
    for vv in (outer[i], innerv[i]):
        if vv.is_valid:
            for g in hm.vertices[i].groups:
                if g.weight > 1e-4: vv[dlb][g.group] = g.weight
# moustache block over the upper lip
mz, mzw = 1.613, 0.0065
sec = []
for x in (-0.029, -0.014, 0.0, 0.014, 0.029):
    ys = surf_front(x, mz)
    drop_ = 0.004 * (abs(x) / 0.029) ** 2
    sec.append([bm.verts.new(Vector((x, ys + dy, mz + dz - drop_))) for dz, dy in ((-mzw, -0.009), (mzw, -0.007), (mzw, 0.003), (-mzw, 0.003))])
for q in range(4):
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((sec[q][i], sec[q][j], sec[q + 1][j], sec[q + 1][i]))
bm.faces.new(sec[0]); bm.faces.new(list(reversed(sec[-1])))
for v in [v for s in sec for v in s]:
    v[dlb][head.vertex_groups["Head"].index] = 1.0
fs_m = [f for f in bm.faces if any(v in sec[0] or v in sec[-1] or any(v in s for s in sec) for v in f.verts)]
bmesh.ops.recalc_face_normals(bm, faces=fs_m)
hair["Hair_Beard"] = make_obj("Hair_Beard", bm, [MAT_HAIR], names)
R["hair"] = {n: {"tris": sum(len(p.vertices) - 2 for p in o.data.polygons)} for n, o in hair.items()}

# ---------------------------------------------------------------- 4. identity geometry on suit + flight-suit meshes
def ident_bm(ob, extra_mats=()):
    me = ob.data
    for m in (MAT_IDENT,) + tuple(extra_mats):
        if me.materials.find(m.name) < 0: me.materials.append(m)
    bm = bmesh.new(); bm.from_mesh(me)
    lay = bm.faces.layers.int.get(ADDED) or bm.faces.layers.int.new(ADDED)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[lay] == 1], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    st = {"bm": bm, "lay": lay, "dl": bm.verts.layers.deform.verify(), "orig": set(bm.verts), "before": set(bm.faces),
          "mi": me.materials.find(MAT_IDENT.name), "ob": ob}
    st["bvh"] = BVHTree.FromBMesh(bm)
    src = [(v.co.copy(), dict(v[st["dl"]].items())) for v in bm.verts]
    kd = KDTree(len(src))
    for i, (co, _) in enumerate(src): kd.insert(co, i)
    kd.balance(); st["kd"] = kd; st["src"] = src
    return st

def copy_weights(st, verts):
    for v in verts:
        _, i, _ = st["kd"].find(v.co)
        for g, w in st["src"][i][1].items():
            v[st["dl"]][g] = w

def finish(st):
    bm = st["bm"]
    new = [f for f in bm.faces if f not in st["before"]]
    for f in new: f[st["lay"]] = 1
    bm.to_mesh(st["ob"].data); bm.free()
    for p in st["ob"].data.polygons: p.use_smooth = False
    return len(new)

def slice_center(st, p0, ax, t, keep):
    pts = []
    for e in st["bm"].edges:
        a, b = e.verts[0], e.verts[1]
        if a not in st["orig"] or b not in st["orig"]: continue
        da, db = (a.co - p0).dot(ax) - t, (b.co - p0).dot(ax) - t
        if da * db < 0:
            p = a.co + (b.co - a.co) * (da / (da - db))
            if keep(p): pts.append(p)
    c = sum(pts, Vector()) / len(pts)
    return c - ax * ((c - p0).dot(ax) - t)

def outer_hit(bvh, c, d, maxd=0.35, layer=0.05):
    """Distance to the outermost surface along the ray: flight-suit meshes keep a skin layer under the cloth."""
    hit = bvh.ray_cast(c, d, maxd)
    if hit[0] is None: return None
    first = best = (hit[0] - c).length
    while True:
        o = c + d * (best + 0.0005)
        h2 = bvh.ray_cast(o, d, maxd)
        if h2[0] is None: break
        nd = (h2[0] - c).length
        if nd - first > layer: break
        best = nd
    return best

def wrap_shell(st, centers, axes, ref, angs, off_in, off_out, closed, mi):
    """Shell hugging the mesh: rows (center, axis), columns at angles around the axis from ref; rays from the centre."""
    bm = st["bm"]; rows = []
    for c, ax in zip(centers, axes):
        u = (ref - ax * ref.dot(ax)).normalized(); v = ax.cross(u)
        ro, ri, last = [], [], 0.05
        for a in angs:
            d = u * math.cos(a) + v * math.sin(a)
            dist = outer_hit(st["bvh"], c, d)
            dist = dist if dist is not None else last
            last = dist
            ro.append(bm.verts.new(c + d * (dist + off_out))); ri.append(bm.verts.new(c + d * (dist + off_in)))
        rows.append((ro, ri))
    J = len(angs); K = len(rows); fs = []
    for k in range(K - 1):
        for j in range(J if closed else J - 1):
            jj = (j + 1) % J
            fs.append(bm.faces.new((rows[k][0][j], rows[k][0][jj], rows[k + 1][0][jj], rows[k + 1][0][j])))
            fs.append(bm.faces.new((rows[k][1][jj], rows[k][1][j], rows[k + 1][1][j], rows[k + 1][1][jj])))
    for k in (0, K - 1):
        for j in range(J if closed else J - 1):
            jj = (j + 1) % J
            fs.append(bm.faces.new((rows[k][0][j], rows[k][0][jj], rows[k][1][jj], rows[k][1][j])))
    if not closed:
        for j in (0, J - 1):
            for k in range(K - 1):
                fs.append(bm.faces.new((rows[k][0][j], rows[k + 1][0][j], rows[k + 1][1][j], rows[k][1][j])))
    for f in fs: f.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    verts = [v for r in rows for side in r for v in side]
    copy_weights(st, verts)
    return verts

def ring_angles(n): return [2 * math.pi * (i + 0.5) / n for i in range(n)]
def arc_angles(half, n): return [-half + 2 * half * i / (n - 1) for i in range(n)]

def limb_rows(st, a, b, ts, sx, reach=0.10):
    ax = (b - a).normalized()
    def keep(p):
        q = p - a; return sx * p.x > 0.12 and (q - ax * q.dot(ax)).length < reach
    return [slice_center(st, a, ax, t, keep) for t in ts], [ax] * len(ts)

bones = ARM.data.bones
def arm_pts(s):
    return bones["UpperArm" + s].head_local, bones["LowerArm" + s].head_local, bones["Hand" + s].head_local

# --- Suit_Arms: forearm rings 0.06 m and upper-arm bands 0.05 m
st = ident_bm(OB["Suit_Arms"])
for s, sx in (("L", 1), ("R", -1)):
    sh, el, wr = arm_pts(s)
    fl = (wr - el).length
    cs, axs = limb_rows(st, el, wr, [fl - 0.115, fl - 0.085, fl - 0.055], sx)
    wrap_shell(st, cs, axs, Vector((sx, 0, 0)), ring_angles(10), -0.004, 0.010, True, st["mi"])
    ul = (el - sh).length
    cs, axs = limb_rows(st, sh, el, [ul - 0.115, ul - 0.090, ul - 0.065], sx)
    wrap_shell(st, cs, axs, Vector((sx, 0, 0)), ring_angles(10), -0.004, 0.009, True, st["mi"])
R["suit_arms_ident_faces"] = finish(st)

# --- thigh stripes ~0.05 m wide, hip to knee (upper part in Suit_Torso, lower in Suit_Legs)
def ring_strip(bm, pts_out, pts_in):
    vs = [[bm.verts.new(lo), bm.verts.new(hi), bm.verts.new(hi2), bm.verts.new(li)] for (lo, hi), (li, hi2) in zip(pts_out, pts_in)]
    fs = []
    for k in range(len(vs) - 1):
        a, b = vs[k], vs[k + 1]
        for s in range(4):
            fs.append(bm.faces.new((a[s], b[s], b[(s + 1) % 4], a[(s + 1) % 4])))
    fs.append(bm.faces.new(list(reversed(vs[0])))); fs.append(bm.faces.new(vs[-1]))
    return fs, [v for q in vs for v in q]

def thigh_stripe(st, z0, z1, steps):
    bm = st["bm"]
    for sx in (-1, 1):
        out_, in_ = [], []
        for k in range(steps + 1):
            z = z0 + (z1 - z0) * k / steps
            pts = []
            for e in bm.edges:
                a, b = e.verts[0].co, e.verts[1].co
                if e.verts[0] not in st["orig"] or sx * a.x < 0.03 or sx * b.x < 0.03 or abs(a.x) > 0.33: continue
                if (a.z - z) * (b.z - z) < 0:
                    pts.append(a + (b - a) * ((z - a.z) / (b.z - a.z)))
            if not pts: continue
            xo = max(sx * p.x for p in pts)
            near = [p for p in pts if sx * p.x > xo - 0.02]
            yc = sum(p.y for p in near) / len(near); w = 0.025
            out_.append((Vector((sx * (xo + 0.007), yc - w, z)), Vector((sx * (xo + 0.007), yc + w, z))))
            in_.append((Vector((sx * (xo - 0.012), yc - w, z)), Vector((sx * (xo - 0.012), yc + w, z))))
        if len(out_) >= 2:
            fs, vs = ring_strip(bm, out_, in_)
            for f in fs: f.material_index = st["mi"]
            bmesh.ops.recalc_face_normals(bm, faces=fs)
            copy_weights(st, vs)

st = ident_bm(OB["Suit_Torso"])          # also drops round-1 fixed pack band/cap
thigh_stripe(st, 0.77, 0.93, 3)
grey = OB["Suit_Torso"].data.materials.find("Mat_SuitGrey"); white = OB["Suit_Torso"].data.materials.find("Mat_SuitWhite")
bm = st["bm"]
pack_v = [v.co.copy() for f in bm.faces if f.material_index == grey and f.calc_center_median().y > 0.05 for v in f.verts]
PX0, PX1 = min(c.x for c in pack_v), max(c.x for c in pack_v)
PY0, PY1 = min(c.y for c in pack_v), max(c.y for c in pack_v)
PZ0, PZ1 = min(c.z for c in pack_v), max(c.z for c in pack_v)
tank_v = [v.co.copy() for f in bm.faces if f.material_index == white and f.calc_center_median().y > PY1 - 0.02 for v in f.verts]
TY1 = max(c.y for c in tank_v); TZ0 = min(c.z for c in tank_v); TZ1 = max(c.z for c in tank_v)
R["pack_box"] = [round(x, 3) for x in (PX0, PX1, PY0, PY1, PZ0, PZ1, TY1, TZ0, TZ1)]
CHEST_BVH = st["bvh"]
R["suit_torso_ident_faces"] = finish(st)
st = ident_bm(OB["Suit_Legs"])
thigh_stripe(st, 0.54, 0.77, 4)
R["suit_legs_ident_faces"] = finish(st)

# --- flight suit: shoulder patches (white border) on both arms, upper-back yoke, collar ring
st = ident_bm(OB["Body_Arms"], (MAT_WHITE,))
wi = OB["Body_Arms"].data.materials.find("Mat_SuitWhite")
for s, sx in (("L", 1), ("R", -1)):
    sh, el, wr = arm_pts(s)
    ul = (el - sh).length
    tc = (1.46 - 1.362) / (1.46 - 1.20) * ul
    cs, axs = limb_rows(st, sh, el, [tc - 0.058, tc, tc + 0.058], sx)
    rad = outer_hit(st["bvh"], cs[1], Vector((sx, 0, 0))) or 0.05
    R["patch_arm_radius_" + s] = round(rad, 3)
    wrap_shell(st, cs, axs, Vector((sx, 0, 0)), arc_angles(0.048 / rad, 7), -0.003, 0.004, False, wi)
    cs, axs = limb_rows(st, sh, el, [tc - 0.050, tc, tc + 0.050], sx)
    wrap_shell(st, cs, axs, Vector((sx, 0, 0)), arc_angles(0.040 / rad, 7), 0.002, 0.0075, False, st["mi"])
R["body_arms_ident_faces"] = finish(st)

st = ident_bm(OB["Body_Torso"])
up = Vector((0, 0, 1))
def torso_center(z, reach):
    return slice_center(st, Vector((0, 0, 0)), up, z, lambda p: abs(p.x) < reach)
zs = [1.395, 1.415, 1.435]
wrap_shell(st, [torso_center(z, 0.2) for z in zs], [up] * 3, Vector((0, 1, 0)), arc_angles(55 * D2R, 13), -0.003, 0.005, False, st["mi"])
# collar: a clean ring that follows the shirt's open neck edge, 0.03 m down the shirt, 0.006 m proud
bmT = st["bm"]
skin_i = OB["Body_Torso"].data.materials.find("Mat_Skin")
def _neck_edge(e):
    if e.verts[0] not in st["orig"] or e.verts[1] not in st["orig"]: return False
    if min(v.co.z for v in e.verts) < 1.43 or max(abs(v.co.x) for v in e.verts) > 0.13: return False
    mats = [f.material_index for f in e.link_faces]
    # outline of the skin-coloured neck band that sits over the shirt: its outer (lower) loop is the visible neckline
    return mats.count(skin_i) == 1
bnd = [e for e in bmT.edges if _neck_edge(e)]
R["collar_neck_edges"] = len(bnd)
bverts = {v for e in bnd for v in e.verts}
NC = sum((v.co for v in bverts), Vector()) / len(bverts)
R["collar_neck_z"] = [round(min(v.co.z for v in bverts), 3), round(max(v.co.z for v in bverts), 3)]
def neck_point(a):
    d = Vector((math.sin(a), -math.cos(a)))
    best = None
    for e in bnd:
        p, q = e.verts[0].co, e.verts[1].co
        p2, q2 = p.xy - NC.xy, q.xy - NC.xy
        s = q2 - p2
        den = d.x * s.y - d.y * s.x
        if abs(den) < 1e-9: continue
        t = (p2.x * s.y - p2.y * s.x) / den          # distance along d
        u = (p2.x * d.y - p2.y * d.x) / den          # position along the edge
        if t > 0 and -1e-6 <= u <= 1 + 1e-6 and (best is None or t > best[0]):   # outermost loop
            best = (t, p.z + (q.z - p.z) * u)
    return best
NA = 24
NP = [neck_point(2 * math.pi * (k + 0.5) / NA) for k in range(NA)]
R["collar_angles_missing"] = sum(1 for p in NP if p is None)
for k in range(NA):
    if NP[k] is None:
        for dk in range(1, NA):
            cand = NP[(k - dk) % NA] or NP[(k + dk) % NA]
            if cand: NP[k] = cand; break
for _ in range(2):                                     # smooth the outline so the ring edge is clean, not saw-toothed
    NP = [((NP[k - 1][0] + 2 * NP[k][0] + NP[(k + 1) % NA][0]) / 4, (NP[k - 1][1] + 2 * NP[k][1] + NP[(k + 1) % NA][1]) / 4) for k in range(NA)]
neck_point = lambda a: NP[int(round(a / (2 * math.pi) * NA - 0.5)) % NA]
rows = []
for drop_, off_o, off_i in ((-0.003, 0.006, -0.004), (0.015, 0.006, -0.004), (0.030, 0.006, -0.004)):
    ro, ri = [], []
    for k in range(NA):
        a = 2 * math.pi * (k + 0.5) / NA
        t, z0 = neck_point(a)
        dh = Vector((math.sin(a), -math.cos(a), 0))
        z = z0 - drop_
        if drop_ <= 0:
            r = t
        else:
            r = outer_hit(st["bvh"], Vector((NC.x, NC.y, z)), dh, 0.3, 0.03) or t
            r = min(r, t + 0.6 * drop_ + 0.012)       # follow the shirt but never flare into the shoulders
            r = max(r, t)
        c = Vector((NC.x, NC.y, z))
        ro.append(bmT.verts.new(c + dh * (r + off_o))); ri.append(bmT.verts.new(c + dh * (r + off_i)))
    rows.append((ro, ri))
fs = []
for k in range(2):
    for j in range(NA):
        jj = (j + 1) % NA
        fs.append(bmT.faces.new((rows[k][0][j], rows[k][0][jj], rows[k + 1][0][jj], rows[k + 1][0][j])))
        fs.append(bmT.faces.new((rows[k][1][jj], rows[k][1][j], rows[k + 1][1][j], rows[k + 1][1][jj])))
for k in (0, 2):
    for j in range(NA):
        jj = (j + 1) % NA
        fs.append(bmT.faces.new((rows[k][0][j], rows[k][0][jj], rows[k][1][jj], rows[k][1][j])))
for f in fs: f.material_index = st["mi"]
bmesh.ops.recalc_face_normals(bmT, faces=fs)
copy_weights(st, [v for r in rows for side in r for v in side])
R["body_torso_ident_faces"] = finish(st)

# ---------------------------------------------------------------- 5. Ident_Symbol_* and Ident_Band_* (rigid: pack/chest -> Chest, helmet -> its bone)
G_CHEST, G_HELM = 0, 1
GROUPS = ["Chest", HELMET_BONE]

def poly_shape(name, s):
    h = s / 2
    if name == "Triangle":
        return [Vector((0, 0.5 * s)), Vector((-0.5 * s, -0.37 * s)), Vector((0.5 * s, -0.37 * s))]
    if name == "Plus":
        a = s / 6
        return [Vector(p) for p in ((a, h), (-a, h), (-a, a), (-h, a), (-h, -a), (-a, -a), (-a, -h), (a, -h), (a, -a), (h, -a), (h, a), (a, a))]
    if name == "Circle":
        return [Vector((math.cos(2 * math.pi * i / 16) * h, math.sin(2 * math.pi * i / 16) * h)) for i in range(16)]
    if name == "Diamond":
        return [Vector((0, h)), Vector((-0.42 * s, 0)), Vector((0, -h)), Vector((0.42 * s, 0))]
    if name == "Square":
        return [Vector((h, h)), Vector((-h, h)), Vector((-h, -h)), Vector((h, -h))]

def prism(bm, poly, P, n, upv, z0, z1, mi, g):
    right = upv.cross(n).normalized(); upv = n.cross(right).normalized()
    back = [bm.verts.new(P + right * p.x + upv * p.y + n * z0) for p in poly]
    front = [bm.verts.new(P + right * p.x + upv * p.y + n * z1) for p in poly]
    fs = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        fs.append(bm.faces.new((back[i], back[j], front[j], front[i])))
    for f in fs: f.material_index = mi
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    set_w(bm, back + front, {g: 1.0})

# chest symbol spot: on the suit chest, viewer's left of the chest panel (character's right)
CHEST_X, CHEST_Z = -0.128, 1.315
hit = CHEST_BVH.ray_cast(Vector((CHEST_X, -0.5, CHEST_Z)), Vector((0, 1, 0)), 1.0)
CHEST_P, CHEST_N = hit[0], Vector((hit[1].x, hit[1].y, 0)).normalized()
R["chest_symbol_at"] = [round(x, 3) for x in CHEST_P]
PACK_P = Vector((0.0, TY1, TZ1 - 0.085))
HB_EL = 14 * D2R
HELM_BACK_N = dir_of(math.pi, HB_EL)
HELM_BACK_P = HC + HELM_BACK_N * HR * math.cos(math.pi / 16)       # facet plane depth

def drop_inside_faces(bm):
    """Helmet pieces: the shell is single-sided, so anything facing the inside of the helmet shows through the visor
    (the round-2 'brim' look). Remove inward-facing faces of the helmet-weighted pieces."""
    dl_ = bm.verts.layers.deform.verify()
    bm.normal_update()
    kill = []
    for f in bm.faces:
        if all(v[dl_].get(G_HELM, 0.0) > 0.5 for v in f.verts):
            c = f.calc_center_median()
            if f.normal.dot((c - HC).normalized()) < -0.2:
                kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')

idents = {}
for sname in SYMBOLS:
    bm = bmesh.new(); bm.verts.layers.deform.verify()
    for P, n, s, plate, g, zp in ((PACK_P, Vector((0, 1, 0)), 0.135, 0.158, G_CHEST, -0.004),
                                  (HELM_BACK_P, HELM_BACK_N, 0.08, 0.096, G_HELM, -0.004),
                                  (CHEST_P, CHEST_N, 0.06, 0.074, G_CHEST, -0.005)):
        upv = Vector((0, 0, 1))
        prism(bm, poly_shape("Square", plate), P, n, upv, zp, 0.012, 1, g)
        prism(bm, poly_shape(sname, s), P, n, upv, 0.012, 0.024 if s > 0.1 else 0.020, 0, g)
    drop_inside_faces(bm)
    idents[f"Ident_Symbol_{sname}"] = make_obj(f"Ident_Symbol_{sname}", bm, [MAT_IDENT, MAT_DARK], GROUPS)

def helm_band(bm, el_lo, el_hi, azs, closed):
    """Band that hugs the dome: curved outer face <= 0.012 m proud of the facets, no brim overhang."""
    R_OUT, R_IN = HR - 0.001, HR * 0.955          # facet centres sit at ~0.97 HR: 4-6 mm proud, inside the outline
    rows = []
    for az in azs:
        lo, hi = el_lo(az), el_hi(az)
        els = [lo + (hi - lo) * q / 3 for q in range(4)]
        rows.append([HC + dir_of(az, e) * R_OUT for e in els] + [HC + dir_of(az, e) * R_IN for e in reversed(els)])
    vs = [[bm.verts.new(p) for p in r] for r in rows]
    n = len(vs[0]); fs = []
    for k in range(len(vs) if closed else len(vs) - 1):
        a, b = vs[k], vs[(k + 1) % len(vs)]
        for s in range(n):
            fs.append(bm.faces.new((a[s], b[s], b[(s + 1) % n], a[(s + 1) % n])))
    if not closed:
        fs.append(bm.faces.new(list(reversed(vs[0])))); fs.append(bm.faces.new(vs[-1]))
    for f in fs: f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    set_w(bm, [v for r in vs for v in r], {G_HELM: 1.0})

def pack_box(bm, cx, cz, w, h, ang=0.0):
    y0, y1 = PY1 - 0.02, TY1 + 0.011
    m = Matrix.Translation((cx, (y0 + y1) / 2, cz)) @ Matrix.Rotation(ang, 4, 'Y') @ Matrix.Diagonal((w, y1 - y0, h, 1))
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    for f in {f for v in r["verts"] for f in v.link_faces}: f.material_index = 0
    set_w(bm, r["verts"], {G_CHEST: 1.0})

FULL = [2 * math.pi * i / 32 for i in range(32)]
PW = (PX1 - PX0) + 0.016
BZ = TZ0 + 0.045                          # pack band centre near the bottom of the tanks
for bname in BANDS:
    bm = bmesh.new(); bm.verts.layers.deform.verify()
    if bname == "Solid":
        helm_band(bm, lambda a: 38 * D2R, lambda a: 53 * D2R, FULL, True)
        pack_box(bm, 0, BZ, PW, 0.062)
    elif bname == "Double":
        helm_band(bm, lambda a: 37.5 * D2R, lambda a: 43.5 * D2R, FULL, True)
        helm_band(bm, lambda a: 48 * D2R, lambda a: 54 * D2R, FULL, True)
        pack_box(bm, 0, BZ - 0.021, PW, 0.022); pack_box(bm, 0, BZ + 0.021, PW, 0.022)
    elif bname == "Dots":
        for q in range(12):
            a0 = 2 * math.pi * q / 12
            helm_band(bm, lambda a: 39 * D2R, lambda a: 53 * D2R, [a0 - 7 * D2R, a0, a0 + 7 * D2R], False)
        for cx in (-0.105, 0.0, 0.105):
            pack_box(bm, cx, BZ, 0.058, 0.058)
    elif bname == "Chevron":
        mid = lambda a: (43 + 11 * min(1.0, abs(math.sin(a)) * 1.3)) * D2R      # V at the front and back
        helm_band(bm, lambda a: mid(a) - 6 * D2R, lambda a: mid(a) + 6 * D2R, FULL, True)
        dx, dz = 0.085, 0.05
        ang = math.atan2(dz, dx)
        for sx in (-1, 1):
            pack_box(bm, sx * dx / 2 * 1.05, BZ + dz / 2 - 0.012, math.hypot(dx, dz) + 0.03, 0.03, -sx * ang)
    drop_inside_faces(bm)
    idents[f"Ident_Band_{bname}"] = make_obj(f"Ident_Band_{bname}", bm, [MAT_IDENT], GROUPS)
R["ident"] = {n: sum(len(p.vertices) - 2 for p in o.data.polygons) for n, o in idents.items()}

# ---------------------------------------------------------------- 6. "Feminine" shape key (body + face)
ARM_BONES = {"UpperArmL", "LowerArmL", "HandL", "UpperArmR", "LowerArmR", "HandR"}
D_SHOULDER = 0.08 * 0.205
def fem_offset(co, groups, is_head, rigid):
    if rigid: return Vector()
    tot = sum(w for _, w in groups) or 1.0
    a = min(1.0, sum(w for n, w in groups if n in ARM_BONES) / tot + 0.5 * sum(w for n, w in groups if n in ("ShoulderL", "ShoulderR")) / tot)
    a_up = min(1.0, sum(w for n, w in groups if n in ("UpperArmL", "UpperArmR", "ShoulderL", "ShoulderR")) / tot)
    a_low = min(1.0, sum(w for n, w in groups if n in ("LowerArmL", "LowerArmR", "HandL", "HandR")) / tot)
    x, y, z = co
    sg = 1.0 if x >= 0 else -1.0
    ts = smooth(0.07, 0.19, abs(x)) * smooth(1.27, 1.40, z)
    dx = -sg * D_SHOULDER * max(a_up * (0.35 + 0.65 * smooth(1.20, 1.42, z)) + a_low * 0.35, ts)
    body = 1.0 - a
    dx += -x * 0.06 * bump(z, 1.07, 0.14) * body                  # waist taper
    dx += x * 0.03 * bump(z, 0.875, 0.13) * body                   # hips: a little
    dy = -y * 0.02 * bump(z, 1.07, 0.14) * body
    dz = 0.0
    neck = 0.07 * bump(z, 1.535, 0.06) * smooth(0.085, 0.055, abs(x)) * body   # slimmer neck
    dx += -x * neck; dy += -(y - 0.01) * neck
    if is_head and z > 1.555:
        jaw = bump(z, 1.598, 0.045) * smooth(0.04, -0.02, y)
        dx += -x * 0.15 * jaw
        if y < -0.05 and z < 1.598 and abs(x) < 0.045:              # smaller, softer chin
            c = smooth(1.598, 1.575, z) * smooth(0.045, 0.015, abs(x))
            dy += 0.004 * c; dz += 0.002 * c; dx += -x * 0.08 * c
        if y < -0.085 and 1.683 < z < 1.718 and abs(x) < 0.065:     # softer brow ridge
            dy += 0.0028 * bump(z, 1.700, 0.018)
        if y < -0.098 and 1.615 < z < 1.675 and abs(x) < 0.03:      # smaller nose
            dy += (-0.098 - y) * 0.40; dx += -x * 0.15
    return Vector((dx, dy, dz))

def pack_components(ob):
    me = ob.data
    gi = ob.vertex_groups.get("Chest")
    if gi is None: return set()
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    out = set()
    for comp in components(bm):
        ok = len(comp) <= 120
        for v in comp:
            gs = me.vertices[v.index].groups
            if not (len(gs) == 1 and gs[0].group == gi.index and gs[0].weight > 0.999):
                ok = False; break
        if ok: out |= {v.index for v in comp}
    bm.free()
    return out

R["feminine"] = {}
for n in FEM_MESHES:
    ob = OB[n]; me = ob.data
    gnames = [g.name for g in ob.vertex_groups]
    rig = pack_components(ob) if n == "Suit_Torso" else set()
    ob.shape_key_add(name="Basis", from_mix=False)
    k = ob.shape_key_add(name="Feminine", from_mix=False)
    k.slider_min, k.slider_max = 0.0, 1.0
    mx = 0.0
    for v in me.vertices:
        if n == "Body_Head" and v.index in FEM_IDX:
            tgt = FEM_IDX[v.index]
            base = fem_offset(tgt, [(gnames[g.group], g.weight) for g in v.groups], False, False)   # follow the face field
            k.data[v.index].co = tgt + Vector((base.x, base.y, 0))
            continue
        off = fem_offset(v.co, [(gnames[g.group], g.weight) for g in v.groups], n == "Body_Head", v.index in rig)
        k.data[v.index].co = v.co + off
        mx = max(mx, off.length)
    k.value = 0.0
    R["feminine"][n] = {"max_offset_m": round(mx, 4), "rigid_pack_verts": len(rig)}

# ---------------------------------------------------------------- 7. report, export, save
def tri_count(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
R["meshes"] = {o.name: {"tris": tri_count(o), "mats": [m.name for m in o.data.materials],
                        "groups": [g.name for g in o.vertex_groups] if len(o.vertex_groups) <= 2 else "body",
                        "shape_keys": [kb.name for kb in o.data.shape_keys.key_blocks] if o.data.shape_keys else []}
               for o in OB if o.type == 'MESH' and o.parent == ARM}
R["tris_total_all_meshes"] = sum(v["tris"] for v in R["meshes"].values())

if EXPORT:
    ARM.animation_data.action = None
    for pb in ARM.pose.bones: pb.matrix_basis = Matrix.Identity(4)
    for tr in ARM.animation_data.nla_tracks: tr.mute = False
    bpy.ops.object.select_all(action='DESELECT')
    for o in OB:
        if o == ARM or o.parent == ARM:
            o.hide_set(False); o.hide_render = False; o.select_set(True)
    bpy.context.view_layer.objects.active = ARM
    props = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kw = dict(filepath=GLB, export_format='GLB', use_selection=True, export_yup=True, export_animations=True,
              export_skins=True, export_materials='EXPORT', export_apply=False, export_frame_range=False,
              export_force_sampling=True, export_animation_mode='NLA_TRACKS', export_anim_slide_to_zero=True,
              export_def_bones=False, export_extra_animations=False, export_all_influences=False, export_morph=True)
    bpy.ops.export_scene.gltf(**{k: v for k, v in kw.items() if k in props})
    raw = open(GLB, "rb").read()
    size = struct.unpack_from('<I', raw, 12)[0]
    g = json.loads(raw[20:20 + size])
    R["glb"] = {"mesh_nodes": {n["name"]: {"skin": "skin" in n,
                                            "targets": g["meshes"][n["mesh"]].get("extras", {}).get("targetNames"),
                                            "materials": sorted({g["materials"][p["material"]]["name"] for p in g["meshes"][n["mesh"]]["primitives"] if "material" in p})}
                               for n in g["nodes"] if "mesh" in n},
                "materials": sorted(m["name"] for m in g["materials"]),
                "animations": sorted(a["name"] for a in g.get("animations", []))}
    for tr in ARM.animation_data.nla_tracks: tr.mute = True

if SAVE:
    if abs(os.path.getmtime(BLEND) - MTIME) > 1e-3:
        R["saved"] = "SKIPPED: crew_v2.blend changed on disk while this ran (another session); re-run"
    else:
        ARM.animation_data.action = None
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_mainfile()
        R["saved"] = BLEND

if REPORT_PATH:
    json.dump(R, open(REPORT_PATH, "w"), indent=1)
print(json.dumps({k: R[k] for k in R if k not in ("meshes", "glb")}, indent=1))
