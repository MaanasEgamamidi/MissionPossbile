"""Derivative GLB export of one broken part (G:/nasa app/broken_parts/BPnn_*.blend) for Godot.

Run with the part .blend loaded; the source is never saved or modified on disk:
  blender-launcher -b --factory-startup --disable-autoexec <BPnn_*.blend> --python export_broken_parts.py --
        --out <godot_project_dir> [--report <dir>]

Modelled on tools/blender/export_colony_glb.py (same flat palette-role materials, same gc_cav colour attribute):
  1. registers the colony asset library (gc_build._reload) and the bp_* palette roles the part build scripts added
     (G:/nasa app/broken_parts/scripts/*.py: L.add_roles / L.mat / vapour_role / fault_red_role);
  2. takes the objects of the part's `Broken` collection that stand in for map objects (every one with
     `map_matrix_world`; context copies and "unchanged neighbour" copies are skipped, see SKIP below) and puts each
     at its map matrix, so the glb is already in Godot world coordinates (glTF +Y up: Blender (x, y, z) -> (x, z, -y));
     An object with custom property bp_kind = "effect" is exported as an effect node (stopped at the fix).
  3. splits effect geometry (spilled liquid, water spray, puddles, door seals, alarm lamps) into their own nodes so
     the game can stop them separately (PART_SPLITS);
  4. replaces the materials by flat palette materials named after their role (GC_<role>; a role that is neither in the
     colony library nor in BP_ROLES must carry a material custom property bp_role, see remap()); the Godot post-import script
     (assets/broken_parts/broken_part_post_import.gd) swaps them for res://materials/colony/<role>.tres;
  5. writes assets/broken_parts/BPnn.glb and tools/blender/broken_parts/reports/BPnn_export.json (nodes, Godot AABBs,
     palette records of the new roles) for build_broken_parts_data.py.
Node names never contain '.' (Godot's glTF import would turn "a.001" into "a_001").
"""
import bpy
import bmesh
import hashlib
import json
import os
import sys
import time
import traceback
from collections import Counter

import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts["--out"]
HERE = os.path.dirname(os.path.abspath(__file__))
REPORT_DIR = opts.get("--report", os.path.join(HERE, "reports"))
SCRIPTS = r"G:\nasa app\grand_colony\scripts"

# bp_* roles of the part build scripts: role -> (palette tuple (hex, emission, roughness, metallic), class, class params, alpha)
# alpha: None = opaque; a value marked "derivative" is a Godot opacity default for a see-through Blender material.
BP_ROLES = {
    "bp_spill": (("#36c58f", 0, 0.04, 0.0), "ceramic", dict(rough=0.03, coat=0.9, wear=0.0, grime=0.0, bump=0.0), None),   # BP01
    "bp_pink": (("#e5609c", 0, 0.45, 0.0), "plastic", dict(rough=0.45), None),                                              # BP01, BP03
    "bp_copper": (("#c27a4e", 0, 0.3, 1.0), "metal", dict(rough=0.3), None),                                                # BP03
    "bp_static": (("#c3ccd4", 1.1, 0.3, 0.0), "glow", {}, None),                                                            # BP04
    "bp_static_dk": (("#56606a", 0.9, 0.3, 0.0), "glow", {}, None),                                                         # BP04
    "bp_red": (("#d4231b", 0, 0.35, 0.0), "plastic", dict(rough=0.35), None),                                               # BP04
    "bp_crack": (("#f4f8fa", 0, 0.35, 0.0), "plastic", dict(rough=0.35, wear=0.0, grime=0.0, var=0.02), None),              # BP05
    "bp_haze": (("#e9f1f4", 0, 0.4, 0.0), "glass", dict(rough=0.45, tint=0.35, dust=0.2), 0.45),                            # BP05 (derivative)
    "bp_shard": (("#cfe9f1", 0, 0.08, 0.0), "glass", dict(rough=0.28, tint=0.35, dust=0.0), 0.35),                          # BP05 (derivative)
    "bp_led_red": (("#ff2414", 3.0, 0.3, 0.0), "glow", {}, None),                                                           # BP06-08
    "bp_vapour": (("#eef4f8", 0.4, 0.5, 0.0), "glass", dict(rough=0.6, tint=1.0, dust=0.0), 0.72),                          # BP08 (Blender alpha 0.72, redo)
    "bp_frost": (("#e3f1fa", 0, 0.55, 0.0), "plastic", dict(rough=0.55, wear=0.0, grime=0.0, var=0.08), None),            # BP08 redo
    "bp_water": (("#8fd2f2", 0, 0.06, 0.0), "plastic", dict(rough=0.06, coat=1.0, wear=0.0, grime=0.0, var=0.02), None),    # BP09
    "bp_puddle": (("#7d97a3", 0, 0.03, 0.0), "plastic", dict(rough=0.03, coat=1.0, wear=0.0, grime=0.0, var=0.05), None),   # BP09
    "bp_dust_haze": (("#c98a5a", 0, 0.9, 0.0), "glass", dict(rough=0.9, tint=1.0, dust=0.0), 0.22),                     # BP10 redo
    "bp_print": (("#5e3d2b", 0, 0.9, 0.0), "soil", dict(rough=0.92, bump=0.03, bscale=240, var=0.1), None),                 # BP10
}

# Map area (source collection) of each part: drives the render layers (ColonyZones) in the post-import script.
PART_AREA = {"BP01": "Med Bay", "BP02": "Med Bay", "BP03": "Command Room", "BP04": "Command Room", "BP05": "Garden Dome",
             "BP06": "Power Room", "BP07": "Power Room", "BP08": "", "BP09": "Greenhouse", "BP10": "Hangar"}
ONLY = {"BP10": ["hg_dust__broken"]}             # BP10 = dust: only the dust mesh; the hangar objects get a dust value
# BP08 door wall: only the faces that differ from the intact door wall (red alarm lamps, alarm bar) are exported,
# lifted 2.5 mm off the tunnel lining they cover; the rest of the portal is the unchanged SFX_tunnel_inside lining.
PORTAL_DIFF = {"tunnel_door_inner_portal__broken": "tunnel_door_inner_portal__original"}

rep = {"ok": False, "started": time.strftime("%Y-%m-%d %H:%M:%S")}


def r(v, n=6):
    return [round(float(x), n) for x in v]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def tri_count(me):
    n = len(me.polygons)
    if n == 0:
        return 0
    lt = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("loop_total", lt)
    return int((lt - 2).sum())


def godot_name(n):
    return n.replace(".", "_")


def face_attr(me, name):
    a = me.attributes.get(name)
    n = len(me.polygons)
    out = np.zeros(n, dtype=np.float32)
    if a is not None and a.domain == "FACE" and len(a.data) == n:
        try:
            a.data.foreach_get("value", out)
        except Exception:
            pass
    return out


def write_cavity(me):
    """Per-corner colour attribute gc_cav = (cavity 0..1, rounded-edge flag, part random, 1); same as export_colony_glb."""
    nv, npoly, nl, ne = len(me.vertices), len(me.polygons), len(me.loops), len(me.edges)
    if nv == 0 or npoly == 0:
        return
    co = np.empty(nv * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    nrm = np.empty(nv * 3, dtype=np.float32)
    me.vertex_normals.foreach_get("vector", nrm)
    nrm = nrm.reshape(-1, 3)
    cav = np.zeros(nv, dtype=np.float32)
    if ne:
        ed = np.empty(ne * 2, dtype=np.int32)
        me.edges.foreach_get("vertices", ed)
        ed = ed.reshape(-1, 2)
        d = co[ed[:, 1]] - co[ed[:, 0]]
        ln = np.linalg.norm(d, axis=1)
        ln[ln < 1e-9] = 1e-9
        d /= ln[:, None]
        acc = np.zeros(nv, dtype=np.float32)
        cnt = np.zeros(nv, dtype=np.float32)
        np.add.at(acc, ed[:, 0], np.einsum("ij,ij->i", nrm[ed[:, 0]], d))
        np.add.at(acc, ed[:, 1], np.einsum("ij,ij->i", nrm[ed[:, 1]], -d))
        np.add.at(cnt, ed[:, 0], 1.0)
        np.add.at(cnt, ed[:, 1], 1.0)
        cnt[cnt == 0] = 1.0
        curv = acc / cnt
        for _ in range(2):
            s = np.zeros(nv, dtype=np.float32)
            np.add.at(s, ed[:, 0], curv[ed[:, 1]])
            np.add.at(s, ed[:, 1], curv[ed[:, 0]])
            curv = 0.5 * curv + 0.5 * (s / cnt)
        cav = np.clip(curv * 2.2, 0.0, 1.0)
    lv = np.empty(nl, dtype=np.int32)
    me.loops.foreach_get("vertex_index", lv)
    lt = np.empty(npoly, dtype=np.int32)
    me.polygons.foreach_get("loop_total", lt)
    lf = np.repeat(np.arange(npoly, dtype=np.int32), lt)
    col = np.ones((nl, 4), dtype=np.float32)
    col[:, 0] = cav[lv]
    if len(lf) == nl:
        col[:, 1] = np.clip(face_attr(me, "gc_edge"), 0.0, 1.0)[lf]
        col[:, 2] = np.clip(face_attr(me, "gc_part"), 0.0, 1.0)[lf]
    else:
        col[:, 1] = 0.0
        col[:, 2] = 0.5
    ca = me.color_attributes.get("gc_cav")
    if ca is not None:
        me.color_attributes.remove(ca)
    ca = me.color_attributes.new("gc_cav", "FLOAT_COLOR", "CORNER")
    ca.data.foreach_set("color", col.reshape(-1))
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = list(me.color_attributes.keys()).index("gc_cav")


def mat_names(me):
    return [m.name if m else "" for m in me.materials]


def face_islands(bm, faces):
    """Edge-connected groups of the given bmesh faces."""
    fs = set(faces)
    seen = set()
    out = []
    for f in faces:
        if f in seen:
            continue
        seen.add(f)
        stack, isl = [f], []
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h in fs and h not in seen:
                        seen.add(h)
                        stack.append(h)
        out.append(isl)
    return out


def split_off(me, pick, name):
    """Moves the faces chosen by pick(bm, names) -> set(faces) out of mesh `me` into a new mesh. Returns (new mesh, n)."""
    names = mat_names(me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.index_update()
    chosen = pick(bm, names)
    n = len(chosen)
    if n == 0:
        bm.free()
        return None, 0
    keep = bm.copy()
    idx = {f.index for f in chosen}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in chosen], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    new = bpy.data.meshes.new(name)
    for m in me.materials:
        new.materials.append(m)
    bm.to_mesh(new)
    bm.free()
    keep.faces.index_update()
    bmesh.ops.delete(keep, geom=[f for f in keep.faces if f.index in idx], context="FACES")
    bmesh.ops.delete(keep, geom=[v for v in keep.verts if not v.link_faces], context="VERTS")
    keep.to_mesh(me)
    keep.free()
    return new, n


def by_material(role):
    def pick(bm, names):
        return {f for f in bm.faces if names[f.material_index] == "GC_" + role}
    return pick


def rubber_islands(side):
    """The meeting-edge seal pieces of a broken BP08 leaf (leaf-local x: left leaf seal at +0.85..0.9, right at -0.9..)."""
    def pick(bm, names):
        rub = [f for f in bm.faces if names[f.material_index] == "GC_kit_rubber"]
        out = set()
        for isl in face_islands(bm, rub):
            xs = [v.co.x for f in isl for v in f.verts]
            if (side == "L" and min(xs) >= 0.8) or (side == "R" and max(xs) <= -0.8):
                out.update(isl)
        return out
    return pick


def portal_diff(me, orig_me, name):
    """New mesh with the faces of `me` that the intact door wall `orig_me` does not have (by centre + material);
    faces that only changed material (recoloured lamps) are lifted 2.5 mm along their normal."""
    def key(c, m):
        return (round(c.x, 3), round(c.y, 3), round(c.z, 3), m)
    on = mat_names(orig_me)
    have, geo = set(), set()
    for p in orig_me.polygons:
        have.add(key(p.center, on[p.material_index]))
        geo.add(key(p.center, ""))
    names = mat_names(me)
    bm = bmesh.new()
    bm.from_mesh(me)
    diff = [f for f in bm.faces if key(f.calc_center_median(), names[f.material_index]) not in have]
    lifted = {f for f in diff if key(f.calc_center_median(), "") in geo}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in set(diff)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    res = bmesh.ops.split(bm, geom=list(lifted))
    moved = {v for g in res["geom"] if isinstance(g, bmesh.types.BMFace) for v in g.verts}
    bm.normal_update()
    for v in moved:
        v.co += v.normal * 0.0025
    new = bpy.data.meshes.new(name)
    for m in me.materials:
        new.materials.append(m)
    bm.to_mesh(new)
    bm.free()
    return new, len(diff), len(lifted)


# effect node name, kind, how to cut it out of which exported node
PART_SPLITS = {
    "BP01": [("mb_sink_counter__broken", "mb_sink_counter_spill__broken", by_material("bp_spill"), "effect", False)],
    "BP08": [("tunnel_door_inner_leaf_L__broken", "tunnel_door_inner_seal_L__broken", rubber_islands("L"), "seal", True),
             ("tunnel_door_inner_leaf_R__broken", "tunnel_door_inner_seal_R__broken", rubber_islands("R"), "seal", True)],
    "BP09": [("gr_rack_water_leak__broken", "gr_rack_water_spray__broken", by_material("bp_water"), "effect", False),
             ("gr_rack_water_leak__broken", "gr_rack_puddle__broken", by_material("bp_puddle"), "effect", False)],
}
GRID_SPLITS = {"BP10": {"hg_dust__broken": (12, 2)}}
EFFECT_OBJECTS ={"air_leak_vfx__broken", "gd_glass_shards__broken", "hg_dust__broken"}
RENAMES = {"tunnel_door_inner_portal__broken": "tunnel_door_inner_alarm__broken"}


try:
    T0 = time.time()
    src = bpy.data.filepath
    base = os.path.basename(src)
    PART = base[:4]
    rep["part"] = PART
    rep["source"] = {"blend": src, "sha256": sha256(src), "bytes": os.path.getsize(src), "exported_with_blender": bpy.app.version_string}
    if SCRIPTS not in sys.path:
        sys.path.insert(0, SCRIPTS)
    import gc_build
    gc_build._reload()
    import gc_lib as L
    import gc_mat
    for role, (pal, cls, params, _a) in BP_ROLES.items():
        L.PAL[role] = pal
        L.MATSPEC[role] = (cls, params)
    ALPHA = {role: v[3] for role, v in BP_ROLES.items() if v[3] is not None}
    # roles of the colony library that the map never used (so data/palette.json and materials/colony lack them, e.g. the
    # wilting-kale gr_leaf_brn) are exported under a bp_ alias with the same palette entry and class parameters
    with open(os.path.join(PROJ, "data", "palette.json"), encoding="utf-8") as f:
        PROJECT_ROLES = set(json.load(f)["roles"])
    ALIASES = {}

    sc = bpy.context.scene
    vl = bpy.context.view_layer
    broken = bpy.data.collections["Broken"]
    # free the names for the exported copies: every source object is renamed SRC__<name> (in memory only)
    SRC = {o.name: o for o in bpy.data.objects}
    for n, o in SRC.items():
        o.name = "SRC__" + n
    SRC_NAME = {o: n for n, o in SRC.items()}

    # ------------------------------------------------------------------ choose the objects
    chosen, skipped = [], []
    for o in broken.objects:
        oname = SRC_NAME[o]
        why = None
        if PART in ONLY and oname not in ONLY[PART]:
            why = "BP10 exports only the dust mesh"
        elif o.type != "MESH":
            why = "not a mesh (%s)" % o.type
        elif "map_matrix_world" not in o.keys():
            why = "no map_matrix_world (layout context)"
        elif "__context" in oname:
            why = "context copy of an unchanged map piece"
        elif str(o.get("note", "")).startswith("unchanged"):
            why = "unchanged neighbour (the map object stays)"
        if why:
            skipped.append({"name": oname, "why": why})
        else:
            chosen.append(o)
    rep["skipped"] = skipped

    # ------------------------------------------------------------------ flat palette materials
    flat, PALETTE, unknown = {}, {}, Counter()

    def class_params(role):
        cls, p = gc_mat.spec_of(role)
        p = dict(p)
        hexc, emit, rough_pal, metal_pal = L.PAL[role]
        if "rough" in p:
            r0 = p["rough"]
        elif cls == "paint":
            r0 = 0.24 + 0.42 * rough_pal
        elif cls == "plastic":
            r0 = 0.2 + 0.42 * rough_pal
        elif cls == "metal":
            r0 = 0.3
        else:
            r0 = rough_pal
        dust_k = 0.0 if cls in ("glow", "screen", "skin", "hair") else float(p.get("dust", 1.0))
        base_c = tuple(p["color"][:3]) if p.get("color") else tuple(L._lin(hexc))
        if cls != "metal":
            base_c = tuple(min(0.85, max(0.02, v)) for v in base_c)
        return {"mat_class": cls, "base_linear": r(base_c), "rough0": round(float(r0), 4), "metal0": 1.0 if cls == "metal" else 0.0,
                "var": float(p.get("var", 0.05)), "wear": float(p.get("wear", 0.0)), "grime": float(p.get("grime", 0.0)),
                "bump": float(p.get("bump", 0.01)), "bscale": float(p.get("bscale", 300)), "dust_k": dust_k,
                "edge_color": r(p.get("edge") or (0.55, 0.56, 0.57)), "edge_metal": float(p.get("edge_metal", 1.0)), "edge_rough": float(p.get("edge_rough", 0.35)),
                "coat": float(p.get("coat", 0.0)), "emit_k": float(p.get("emit", 1.0)), "tint": float(p.get("tint", 1.0)), "ior": float(p.get("ior", 1.5)),
                "explicit_colour": bool(p.get("color"))}

    def flat_mat(role):
        if role in flat:
            return flat[role]
        hexc, emit, rough, metal = L.PAL[role]
        m = bpy.data.materials.new("X_" + role)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        col = tuple(L._lin(hexc)) + (1.0,)
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit:
            bsdf.inputs["Emission Color"].default_value = col
            bsdf.inputs["Emission Strength"].default_value = emit
        a = ALPHA.get(role, L.ALPHA.get(role))
        if a is not None:
            bsdf.inputs["Alpha"].default_value = a
            m.surface_render_method = "BLENDED"
        flat[role] = m
        rec = {"rgb_linear": r(col[:3]), "hex": hexc, "emission": emit, "roughness": rough, "metallic": metal, "alpha": a,
               "alpha_source": ("palette" if role in L.ALPHA else ("derivative default" if a is not None else None)),
               "note": ("broken-part role (G:/nasa app/broken_parts/scripts), exported by tools/blender/broken_parts/export_broken_parts.py"
                        if role in BP_ROLES else None)}
        if role in ALIASES:
            rec["note"] = "alias of the colony library role %s (not used by the map, so not in the colony palette)" % ALIASES[role]
        rec.update(class_params(role))
        rec["render_rgb_linear"] = rec["base_linear"] if rec["explicit_colour"] else None
        PALETTE[role] = rec
        return m

    def remap(me):
        for i, m in enumerate(me.materials):
            if m is None or m.name.startswith("X_"):
                continue
            role = m.name[3:] if m.name.startswith("GC_") else None
            if role and role not in L.PAL and "bp_role" in m.keys():
                # a new role a part script made: material custom property bp_role = JSON
                # {"pal": [hex, emission, roughness, metallic], "class": "plastic", "params": {...}, "alpha": null}
                spec = json.loads(str(m["bp_role"]))
                L.PAL[role] = tuple(spec["pal"])
                L.MATSPEC[role] = (spec.get("class", "paint"), dict(spec.get("params", {})))
                if spec.get("alpha") is not None:
                    ALPHA[role] = float(spec["alpha"])
            if role and role in L.PAL:
                if role not in PROJECT_ROLES and not role.startswith("bp_"):
                    alias = "bp_" + role
                    L.PAL[alias] = L.PAL[role]
                    L.MATSPEC[alias] = gc_mat.spec_of(role)
                    if role in L.ALPHA:
                        L.ALPHA[alias] = L.ALPHA[role]
                    ALIASES[alias] = role
                    role = alias
                me.materials[i] = flat_mat(role)
            else:
                unknown[m.name] += 1

    # ------------------------------------------------------------------ copies at their map matrices
    out_col = bpy.data.collections.new("_bp_export")
    sc.collection.children.link(out_col)
    made = {}          # exported name -> object
    kinds = {}
    sources = {}
    mesh_copy = {}
    for o in chosen:
        oname = SRC_NAME[o]
        m = list(o["map_matrix_world"])
        M = Matrix([m[0:4], m[4:8], m[8:12], m[12:16]])
        me = mesh_copy.get(o.data.name)
        if me is None or oname in PORTAL_DIFF or any(s[0] == oname for s in PART_SPLITS.get(PART, [])):
            me = o.data.copy()
            mesh_copy[o.data.name] = me
        name = godot_name(RENAMES.get(oname, oname))
        if oname in PORTAL_DIFF:
            orig = SRC[PORTAL_DIFF[oname]]
            me, nd, nl = portal_diff(me, orig.data, name)
            rep["portal_diff"] = {"faces": nd, "lifted": nl}
        me.name = "BPM_" + name
        ob = bpy.data.objects.new(name, me)
        ob.matrix_world = M
        out_col.objects.link(ob)
        made[name] = ob
        sources[name] = oname
        kinds[name] = "effect" if (oname in EFFECT_OBJECTS or oname in PORTAL_DIFF or str(o.get("bp_kind", "")) == "effect") else "model"
        for k in ("dust", "gc_asset", "map_object", "door_id", "door_slide", "leaf_rest_x", "broken_task"):
            if k in o.keys():
                v = o[k]
                ob[k] = v if isinstance(v, (int, float, str)) else str(v)
    vl.update()

    splits = []
    for (src_name, new_name, pick, kind, parent) in PART_SPLITS.get(PART, []):
        host = made[godot_name(src_name)]
        me, n = split_off(host.data, pick, "BPM_" + new_name)
        splits.append({"from": host.name, "node": new_name, "faces": n})
        if me is None:
            continue
        ob = bpy.data.objects.new(new_name, me)
        out_col.objects.link(ob)
        if parent:
            ob.parent = host
            ob.matrix_parent_inverse = Matrix()
            ob.matrix_basis = Matrix()
        else:
            ob.matrix_world = host.matrix_world.copy()
        for k in ("dust", "broken_task"):
            if k in host.keys():
                ob[k] = host[k]
        made[new_name] = ob
        sources[new_name] = sources[host.name]
        kinds[new_name] = kind
    rep["splits"] = splits
    # BP10: the dust mesh is cut into a grid of patches (by face centre, Godot x = columns, Godot z = rows) so the T11
    # cleaning can hide it area by area (HangarDust.area_of uses the same grid over the same region)
    for host_name, (cols, rows) in GRID_SPLITS.get(PART, {}).items():
        host = made[host_name]
        mw = host.matrix_world
        cs = [mw @ p.center for p in host.data.polygons]
        gx = [c.x for c in cs]
        gz = [-c.y for c in cs]
        vs = [mw @ v.co for v in host.data.vertices]
        x0, x1 = min(v.x for v in vs), max(v.x for v in vs)
        z0, z1 = min(-v.y for v in vs), max(-v.y for v in vs)
        cell = [min(rows - 1, int((gz[i] - z0) / (z1 - z0) * rows)) * cols + min(cols - 1, int((gx[i] - x0) / (x1 - x0) * cols))
                for i in range(len(cs))]
        patches = []
        for k in range(rows * cols):
            pname = "%s_r%dc%02d" % (host_name, k // cols, k % cols)
            me, n = split_off(host.data, lambda bm, names, k=k: {f for f in bm.faces if cell[f.index] == k}, "BPM_" + pname)
            if me is None:
                continue
            ob = bpy.data.objects.new(pname, me)
            out_col.objects.link(ob)
            ob.matrix_world = mw.copy()
            for kk in ("dust", "broken_task"):
                if kk in host.keys():
                    ob[kk] = host[kk]
            made[pname] = ob
            sources[pname] = sources[host_name]
            kinds[pname] = "effect"
            patches.append({"node": pname, "row": k // cols, "col": k % cols, "faces": n})
            cell = [c for f_i, c in enumerate(cell) if c != k]      # faces left in the host, in order
        rep["grid"] = {"host": host_name, "cols": cols, "rows": rows, "region_godot": {"min": r((x0, 0, z0), 4), "max": r((x1, 0, z1), 4)},
                       "patches": patches}
    # an emptied host (all of gr_rack_water_leak went to spray + puddle) is not exported
    for n in [n for n, ob in made.items() if len(ob.data.polygons) == 0]:
        out_col.objects.unlink(made[n])
        del made[n]
    vl.update()

    area = PART_AREA[PART]
    for name, ob in made.items():
        remap(ob.data)
        write_cavity(ob.data)
        ob["part"] = PART
        ob["bp_kind"] = kinds[name]
        if area:
            ob["area"] = area
        else:
            ob["env_scenery"] = 1           # BP08: tunnel scenery, lit like environment.glb pieces
        if "dust" not in ob.keys():
            ob["dust"] = 0.5 if PART == "BP08" else 0.0
    for key, m in flat.items():
        m.name = key
    vl.update()

    # ------------------------------------------------------------------ report: nodes and Godot AABBs
    def godot_aabb(ob):
        me = ob.data
        nv = len(me.vertices)
        co = np.empty(nv * 3, dtype=np.float64)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        mw = np.array(ob.matrix_world)
        w = co @ mw[:3, :3].T + mw[:3, 3]
        g = np.stack([w[:, 0], w[:, 2], -w[:, 1]], axis=1)          # Blender (x, y, z) -> Godot (x, z, -y)
        return g.min(axis=0), g.max(axis=0)
    nodes = []
    lo_all, hi_all = np.full(3, 1e9), np.full(3, -1e9)
    for name, ob in made.items():
        lo, hi = godot_aabb(ob)
        lo_all, hi_all = np.minimum(lo_all, lo), np.maximum(hi_all, hi)
        t = ob.matrix_world.translation
        nodes.append({"name": name, "parent": ob.parent.name if ob.parent else None, "kind": kinds[name], "source_object": sources[name],
                      "map_object": ob.get("map_object", ob.get("gc_asset")), "tris": tri_count(ob.data),
                      "origin_godot": r((t.x, t.z, -t.y), 4), "aabb_min": r(lo, 4), "aabb_max": r(hi, 4),
                      "roles": sorted({m.name for m in ob.data.materials if m})})
    rep["nodes"] = nodes
    rep["bounds"] = {"center": r((lo_all + hi_all) / 2, 4), "size": r(hi_all - lo_all, 4), "min": r(lo_all, 4), "max": r(hi_all, 4)}
    rep["palette"] = PALETTE
    rep["unmapped_materials"] = dict(unknown)
    lights = []
    for o in broken.objects:
        if o.type == "LIGHT" and PART == "BP08":
            # the scene's light sits in the side-by-side layout; put it back at the map (relative to the door origin)
            door = SRC["tunnel_door_inner_portal__broken"]
            m = list(door["map_matrix_world"])
            M = Matrix([m[0:4], m[4:8], m[8:12], m[12:16]])
            p = M @ (door.matrix_world.inverted() @ o.matrix_world.translation)
            lights.append({"name": SRC_NAME[o], "type": o.data.type, "energy_blender_w": round(o.data.energy, 3), "color": r(o.data.color, 4),
                           "position_godot": r((p.x, p.z, -p.y), 4), "note": str(o.get("broken_task", ""))})
    rep["lights"] = lights

    # ------------------------------------------------------------------ export
    for o in bpy.data.objects:
        try:
            o.select_set(False)
        except Exception:
            pass
    for ob in made.values():
        ob.select_set(True)
    out_dir = os.path.join(PROJ, "assets", "broken_parts")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, PART + ".glb")
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True, export_extras=True,
              export_cameras=False, export_lights=False, export_animations=False, export_skins=False, export_morph=False,
              export_materials="EXPORT", export_texcoords=True, export_normals=True, export_tangents=False,
              export_vertex_color="NAME", export_vertex_color_name="gc_cav", export_all_vertex_colors=False)
    res = bpy.ops.export_scene.gltf(**kw)
    rep["export"] = {"path": path, "result": list(res), "bytes": os.path.getsize(path), "sha256": sha256(path),
                     "tris": sum(n["tris"] for n in nodes)}
    rep["secs"] = round(time.time() - T0, 1)
    rep["ok"] = True
except Exception:
    rep["error"] = traceback.format_exc()
os.makedirs(REPORT_DIR, exist_ok=True)
with open(os.path.join(REPORT_DIR, "%s_export.json" % rep.get("part", "unknown")), "w", encoding="utf-8") as f:
    json.dump(rep, f, indent=1, default=str)
