"""Derivative GLB export of the colony map for Godot (Prompt 02, visual-fidelity revision).

Run with the SOURCE .blend loaded; the source is never saved or modified on disk:
  blender-launcher -b --factory-startup --disable-autoexec <source.blend> --python export_colony_glb.py --
        --out <godot_project_dir> --report <dir> [--detail render|game] [--decimate-over 120000] [--decimate-to 100000]

What it does, all in memory:
  1. registers the colony asset functions (gc_build._reload);
  2. --detail render (default): keeps the bevelled, smooth-shaded meshes the Cycles renders use; the few meshes above
     --decimate-over triangles (crops, survivor, suit rack) are reduced to --decimate-to with a Decimate modifier.
     --detail game: regenerates every asset at the browser game's flat-shaded detail level instead;
  3. writes a per-corner colour attribute  gc_cav = (cavity, rounded-edge flag, part random, 1)  from the mesh's own
     curvature and the gc_edge / gc_part face attributes the build scripts store. The Godot surface shader uses it for
     grime, edge wear and per-part variation, as the Blender materials do. No texture is baked;
  4. replaces the procedural Blender materials by flat palette materials named after their palette role, and records
     each role's material class and parameters (gc_lib.MATSPEC / gc_mat.CLASSES) for the Godot material generator;
  5. packs the terrain's four colour attributes into COLOR_0, UV and UV2 for the Godot terrain shader;
  6. realises the geometry-nodes rock scatter as ordinary objects that share the rock meshes;
  7. writes assets/colony/colony.glb, environment.glb, terrain.glb, data/colony_manifest.json, data/palette.json,
     data/colliders.json.

Unsupported source features are listed in the report instead of being dropped silently.
"""
import bpy
import hashlib
import json
import os
import sys
import time
import traceback
from collections import Counter

import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts["--out"]
REPORT_DIR = opts.get("--report", PROJ)
DETAIL = opts.get("--detail", "render")
DECIMATE_OVER = int(opts.get("--decimate-over", "120000"))
DECIMATE_TO = int(opts.get("--decimate-to", "100000"))
NO_DECIMATE = {"gd_shell", "ex_lander"}          # hero silhouettes: keep every triangle
SCRIPTS = r"G:\nasa app\grand_colony\scripts"
GAME_JSON = r"G:\nasa app\grand_colony\game\colony.json"

# transmissive source materials that the game palette does not mark see-through: derivative opacity defaults (tunable in Godot)
DERIVED_ALPHA = {"glass": 0.22, "sf_hall_glass": 0.18, "en_water": 0.55, "gd_water": 0.55}
SKIP_ENV_COLLECTIONS = {"Exterior atmosphere", "Exterior motes", "Exterior env lights"}   # volumes / emissive motes / lights: not mesh-exportable

rep = {"ok": False, "started": time.strftime("%Y-%m-%d %H:%M:%S"), "detail": DETAIL}


def r(v, n=6):
    return [round(float(x), n) for x in v]


def mat4(m):
    return [r(row) for row in m]


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


def enum_ids(op_props, name):
    try:
        return [e.identifier for e in op_props[name].enum_items]
    except Exception:
        return []


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
    """Per-corner colour attribute gc_cav = (cavity 0..1, rounded-edge flag, part random, 1)."""
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
        np.add.at(acc, ed[:, 0], np.einsum("ij,ij->i", nrm[ed[:, 0]], d))       # > 0: the neighbour rises above the tangent plane = concave
        np.add.at(acc, ed[:, 1], np.einsum("ij,ij->i", nrm[ed[:, 1]], -d))
        np.add.at(cnt, ed[:, 0], 1.0)
        np.add.at(cnt, ed[:, 1], 1.0)
        cnt[cnt == 0] = 1.0
        curv = acc / cnt
        for _ in range(2):                                                     # spread the crease a couple of edges outwards
            s = np.zeros(nv, dtype=np.float32)
            np.add.at(s, ed[:, 0], curv[ed[:, 1]])
            np.add.at(s, ed[:, 1], curv[ed[:, 0]])
            curv = 0.5 * curv + 0.5 * (s / cnt)
        cav = np.clip(curv * 2.2, 0.0, 1.0)
    lv = np.empty(nl, dtype=np.int32)
    me.loops.foreach_get("vertex_index", lv)
    lt = np.empty(npoly, dtype=np.int32)
    me.polygons.foreach_get("loop_total", lt)
    lf = np.repeat(np.arange(npoly, dtype=np.int32), lt)                       # loop -> face (loops are stored face by face)
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


try:
    T0 = time.time()
    src = bpy.data.filepath
    rep["source"] = {"blend": src, "sha256": sha256(src), "bytes": os.path.getsize(src), "saved_with": list(bpy.data.version),
                     "exported_with_blender": bpy.app.version_string}
    if SCRIPTS not in sys.path:
        sys.path.insert(0, SCRIPTS)
    import gc_build
    gc_build._reload()
    import gc_lib as L
    import gc_export as E
    import gc_place as P
    import gc_shell
    import gc_mat

    sc = bpy.context.scene
    vl = bpy.context.view_layer
    vl.update()

    # ------------------------------------------------------------------ flat palette materials + class parameters
    flat = {}
    PALETTE = {}
    unknown_mats = Counter()

    def mat_class(role):
        """(class, params) the Blender material of this role was built with."""
        try:
            cls, params = gc_mat.spec_of(role)
            return cls, dict(params)
        except Exception:
            if role in L.MATSPEC:
                return L.MATSPEC[role][0], dict(L.MATSPEC[role][1])
            return None, {}

    def class_params(role):
        """Everything gc_mat._surface reads for this role, resolved to numbers."""
        cls, p = mat_class(role)
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
        if cls in ("glow", "screen", "skin", "hair"):
            dust_k = 0.0
        else:
            dust_k = float(p.get("dust", 1.0))
        base = tuple(p["color"][:3]) if p.get("color") else tuple(L._lin(hexc))
        if cls != "metal":
            base = tuple(min(0.85, max(0.02, v)) for v in base)             # gc_mat._clamp_albedo
        return {"mat_class": cls, "base_linear": r(base), "rough0": round(float(r0), 4), "metal0": 1.0 if cls == "metal" else 0.0,
                "var": float(p.get("var", 0.05)), "wear": float(p.get("wear", 0.0)), "grime": float(p.get("grime", 0.0)),
                "bump": float(p.get("bump", 0.01)), "bscale": float(p.get("bscale", 300)), "dust_k": dust_k,
                "edge_color": r(p.get("edge") or (0.55, 0.56, 0.57)), "edge_metal": float(p.get("edge_metal", 1.0)), "edge_rough": float(p.get("edge_rough", 0.35)),
                "coat": float(p.get("coat", 0.0)), "emit_k": float(p.get("emit", 1.0)), "tint": float(p.get("tint", 1.0)), "ior": float(p.get("ior", 1.5)),
                "explicit_colour": bool(p.get("color"))}

    def flat_mat(role, alpha=None, note=None):
        if role in flat:
            return flat[role]
        hexc, emit, rough, metal = L.PAL[role]
        m = bpy.data.materials.new("X_" + role)       # renamed to the bare role just before export
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        col = tuple(L._lin(hexc)) + (1.0,)
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit:
            bsdf.inputs["Emission Color"].default_value = col
            bsdf.inputs["Emission Strength"].default_value = emit
        a = L.ALPHA.get(role, alpha)
        if a is not None:
            bsdf.inputs["Alpha"].default_value = a
            m.surface_render_method = "BLENDED"
        m["gc_role"] = role
        flat[role] = m
        rec = {"rgb_linear": r(col[:3]), "hex": hexc, "emission": emit, "roughness": rough, "metallic": metal,
               "alpha": a, "alpha_source": ("palette" if role in L.ALPHA else ("derivative default" if a is not None else None)), "note": note}
        rec.update(class_params(role))
        rec["render_rgb_linear"] = rec["base_linear"] if rec["explicit_colour"] else None
        PALETTE[role] = rec
        return m

    def special_mat(name, base=(0.5, 0.5, 0.5), rough=0.9, alpha=None, note="", cls="rock"):
        key = "special:" + name
        if key in flat:
            return flat[key]
        m = bpy.data.materials.new("X_" + name)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = tuple(base) + (1.0,)
        bsdf.inputs["Roughness"].default_value = rough
        if alpha is not None:
            bsdf.inputs["Alpha"].default_value = alpha
            m.surface_render_method = "BLENDED"
        flat[key] = m
        PALETTE[name] = {"rgb_linear": r(base), "hex": None, "emission": 0, "roughness": rough, "metallic": 0.0, "alpha": alpha,
                         "alpha_source": "derivative default" if alpha is not None else None, "note": note, "special": True,
                         "mat_class": cls, "base_linear": r(base), "rough0": rough, "metal0": 0.0, "var": 0.08, "wear": 0.0, "grime": 0.0, "bump": 0.03,
                         "bscale": 60.0, "dust_k": 0.0, "edge_color": [0.55, 0.56, 0.57], "edge_metal": 1.0, "edge_rough": 0.35, "coat": 0.0, "emit_k": 1.0,
                         "tint": 1.0, "ior": 1.5, "explicit_colour": False, "render_rgb_linear": None}
        return m

    def remap(me):
        """Swap the procedural materials on a mesh for flat ones. Returns the list of source material names."""
        srcs = []
        for i, m in enumerate(me.materials):
            if m is None or m.name.startswith("X_"):
                continue
            srcs.append(m.name)
            role = m.name[3:] if m.name.startswith("GC_") else None
            if m.name == "GC_terrain_mars":
                me.materials[i] = special_mat("terrain_mars", base=(1.0, 1.0, 1.0), rough=0.92, cls="terrain",
                                              note="terrain shader: albedo and masks come from vertex data (COLOR_0, UV, UV2)")
            elif m.name == "GC_terrain_basalt":
                me.materials[i] = special_mat("terrain_basalt", base=(0.115, 0.095, 0.08), rough=0.9, cls="rock",
                                              note="procedural rock in Blender; flat stand-in inside the albedo range 0.08-0.12 stated in gc_terrain.rock_material")
            elif role and role in L.PAL:
                me.materials[i] = flat_mat(role, alpha=DERIVED_ALPHA.get(role))
            elif m.name.startswith("SFX_decal_"):
                me.materials[i] = special_mat(m.name[4:], base=(0.03, 0.025, 0.02), rough=1.0, alpha=0.55, cls="decal",
                                              note="procedural decal with soft alpha in Blender; flat translucent stand-in")
            else:
                unknown_mats[m.name] += 1
                me.materials[i] = special_mat("unmapped_" + m.name, base=(1.0, 0.0, 1.0), rough=0.8, note="no palette role; magenta marker")
        return srcs

    # ------------------------------------------------------------------ colony objects
    colony = E.colony_objects()
    Mexp = E._meta()
    names = []
    for o in colony:
        if o["gc_asset"] not in names:
            names.append(o["gc_asset"])
    src_render_tris = sum(tri_count(o.data) for o in colony)
    t = time.time()
    meshes = {}
    decimated = {}
    if DETAIL == "game":
        for n in names:
            me = L.mesh_of(n, "game")
            if hasattr(me, "shade_flat"):
                me.shade_flat()            # the game detail level is authored to be drawn flat-shaded
            me.update()
            meshes[n] = me
        rep["shading"] = "flat (as in the browser export)"
    else:
        tmp_col = bpy.data.collections.new("_export_tmp")
        sc.collection.children.link(tmp_col)
        for o in colony:
            n = o["gc_asset"]
            if n in meshes:
                continue
            me = o.data
            tc = tri_count(me)
            if tc > DECIMATE_OVER and n not in NO_DECIMATE:
                tob = bpy.data.objects.new("_dec_" + n, me)
                tmp_col.objects.link(tob)
                mod = tob.modifiers.new("dec", "DECIMATE")
                mod.decimate_type = "COLLAPSE"
                mod.ratio = DECIMATE_TO / float(tc)
                mod.use_collapse_triangulate = True
                bpy.context.view_layer.update()
                dgx = bpy.context.evaluated_depsgraph_get()
                nm = bpy.data.meshes.new_from_object(tob.evaluated_get(dgx), preserve_all_data_layers=True, depsgraph=dgx)
                nm.name = "GCD_" + n
                decimated[n] = [tc, tri_count(nm)]
                tmp_col.objects.unlink(tob)
                bpy.data.objects.remove(tob)
                me = nm
            meshes[n] = me
        sc.collection.children.unlink(tmp_col)
        bpy.data.collections.remove(tmp_col)
        rep["shading"] = "as authored (smooth with rounded edges)"
    rep["mesh_prepare_secs"] = round(time.time() - t, 1)
    rep["decimated"] = decimated

    t = time.time()
    mat_sources = set()
    for n, me in meshes.items():
        mat_sources.update(remap(me))
        write_cavity(me)
    rep["cavity_secs"] = round(time.time() - t, 1)

    # mean diffuse albedo of each room (rho of the bounce estimate): face area x luminance of the face's palette colour
    mesh_alb = {}
    for n_, me in meshes.items():
        npoly = len(me.polygons)
        if npoly == 0:
            mesh_alb[n_] = (0.0, 0.0)
            continue
        area = np.empty(npoly, dtype=np.float32)
        mi = np.empty(npoly, dtype=np.int32)
        me.polygons.foreach_get("area", area)
        me.polygons.foreach_get("material_index", mi)
        lum = np.zeros(max(len(me.materials), 1), dtype=np.float32)
        for i, m in enumerate(me.materials):
            role = m.get("gc_role") if m else None
            if role and role in PALETTE:
                c = PALETTE[role]["base_linear"]
                lum[i] = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) * (0.3 if PALETTE[role]["metal0"] > 0.5 else 1.0)
        mesh_alb[n_] = (float(area.sum()), float((area * lum[np.clip(mi, 0, len(lum) - 1)]).sum()))
    room_sum = {}
    objects = []
    area_counts = Counter()
    for o in colony:
        n = o["gc_asset"]
        o.data = meshes[n]                      # in memory only
        area = o.users_collection[0].name
        cls = E.classify(n, Mexp)
        o["area"] = area
        o["cls"] = cls
        area_counts[area] += 1
        rec = {"name": o.name, "gc_asset": n, "area": area, "cls": cls, "matrix_world": mat4(o.matrix_world), "tris": tri_count(meshes[n]),
               "dust": round(float(o["dust"]), 3) if "dust" in o.keys() else None}
        if "door_id" in o.keys():
            rec["door_id"] = int(o["door_id"])
            rec["door_slide"] = float(o["door_slide"])
        if "inter" in o.keys():
            rec["inter"] = str(o["inter"])
        objects.append(rec)
        x, y = o.matrix_world.translation.x, o.matrix_world.translation.y
        for (rn, x0, y0, x1, y1) in P.ROOMS_META:
            if x0 - 0.05 < x < x1 + 0.05 and y0 - 0.05 < y < y1 + 0.05:
                a, la = mesh_alb[n]
                s2 = abs(o.matrix_world.to_3x3().determinant()) ** (2.0 / 3.0)
                acc = room_sum.setdefault(rn, [0.0, 0.0])
                acc[0] += a * s2
                acc[1] += la * s2
                break
    ROOM_ALBEDO = {rn: round(v[1] / v[0], 4) for rn, v in room_sum.items() if v[0] > 0}
    rep["room_mean_albedo"] = ROOM_ALBEDO
    rep["colony"] = {"objects": len(colony), "assets": len(names), "render_tris_in_source": src_render_tris,
                     "tris_unique": sum(tri_count(m) for m in meshes.values()), "tris_instanced": sum(o["tris"] for o in objects),
                     "by_area": dict(area_counts), "by_class": dict(Counter(o["cls"] for o in objects)),
                     "doors": len({o["door_id"] for o in objects if "door_id" in o}), "door_leaves": sum(1 for o in objects if "door_id" in o),
                     "interactables": sorted(o["inter"] for o in objects if "inter" in o), "source_materials": len(mat_sources)}

    # ------------------------------------------------------------------ environment
    env_root = bpy.data.collections.get("Environment (Blender only)")
    env_objs, env_skipped = [], []
    gravel = {}
    dg = bpy.context.evaluated_depsgraph_get()
    if env_root:
        for o in list(env_root.all_objects):
            cols = {c.name for c in o.users_collection}
            if o.type != "MESH":
                env_skipped.append({"name": o.name, "type": o.type, "why": "not a mesh (lights go to the manifest)"})
                continue
            if cols & SKIP_ENV_COLLECTIONS:
                env_skipped.append({"name": o.name, "type": "MESH", "materials": [m.name for m in o.data.materials if m],
                                    "why": "volume or emissive particle stand-in; glTF has no volumes"})
                continue
            if any(m.type == "NODES" for m in o.modifiers):
                gravel[o.name] = {"modifier_groups": [m.node_group.name for m in o.modifiers if m.type == "NODES" and m.node_group], "base_tris": tri_count(o.data)}
            env_objs.append(o)
    rocks = []
    rock_src = Counter()
    rock_other = 0
    realised = bpy.data.collections.new("Terrain rocks (realised)")
    sc.collection.children.link(realised)
    for oi in dg.object_instances:
        if not oi.is_instance or oi.parent is None:
            continue
        srcob = oi.object.original
        if srcob is None or srcob.type != "MESH" or srcob.name == oi.parent.original.name:
            rock_other += 1
            continue
        mw = oi.matrix_world.copy()
        nob = bpy.data.objects.new("rock_%04d" % len(rocks), srcob.data)
        nob.matrix_world = mw
        nob["scatter_source"] = srcob.name
        realised.objects.link(nob)
        rocks.append(nob)
        rock_src[srcob.name] += 1
    vl.update()
    env_terrain = [o for o in env_objs if o.name.startswith("Terrain_") and o.name != "Terrain_rocks"]
    env_export = [o for o in env_objs if o.name != "Terrain_rocks"] + rocks
    env_mat_sources = set()
    for o in env_export:
        env_mat_sources.update(remap(o.data))

    # terrain: pack the four source colour attributes for the Godot terrain shader
    #   COLOR_0 = (albedo rgb, bare-rock mask)      UV  = (pebble factor, hollow/ridge)      UV2 = (track rut offset or 99, metres along the track)
    alb_sum = np.zeros(3)
    alb_n = 0
    uncoloured = []
    packed = 0
    for o in env_terrain:
        me = o.data
        ca = me.color_attributes
        if "gc_alb" not in ca:
            uncoloured.append(o)
            continue
        nv, nl = len(me.vertices), len(me.loops)

        def get(name, _ca=ca, _nv=nv):
            a = np.empty(_nv * 4, dtype=np.float32)
            _ca[name].data.foreach_get("color", a)
            return a.reshape(-1, 4)
        alb = get("gc_alb")
        ma = get("gc_ma") if "gc_ma" in ca else np.zeros((nv, 4), np.float32)
        mb = get("gc_mb") if "gc_mb" in ca else np.zeros((nv, 4), np.float32)
        trk = get("gc_trk") if "gc_trk" in ca else np.zeros((nv, 4), np.float32)
        alb_sum += alb[:, :3].sum(axis=0)
        alb_n += nv
        rockm, dune = ma[:, 2], ma[:, 3]
        hol, grav = mb[:, 0], mb[:, 3]
        tsd, tal, tkind = trk[:, 0], trk[:, 1], trk[:, 2]
        gauge = 1.0 + (tkind > 1.5) * 0.2
        off = np.where(tkind > 0.5, np.abs(np.abs(tsd) - gauge), 99.0).astype(np.float32)
        pebble = ((1.0 - dune) * (0.35 + 0.65 * grav)).astype(np.float32)
        pack = np.ones((nv, 4), dtype=np.float32)
        pack[:, :3] = alb[:, :3]
        pack[:, 3] = np.clip(rockm, 0.0, 1.0)
        old = ca.get("gc_pack")
        if old is not None:
            ca.remove(old)
        pk = ca.new("gc_pack", "FLOAT_COLOR", "POINT")
        pk.data.foreach_set("color", pack.reshape(-1))
        ca.active_color = pk
        ca.render_color_index = list(ca.keys()).index("gc_pack")
        lv = np.empty(nl, dtype=np.int32)
        me.loops.foreach_get("vertex_index", lv)
        for uvname, a0, a1 in (("UVMap", pebble, np.clip(hol, -1.0, 1.0)), ("UV2", off, tal)):
            uvl = me.uv_layers.get(uvname) or me.uv_layers.new(name=uvname)
            uv = np.empty((nl, 2), dtype=np.float32)
            uv[:, 0] = a0[lv]
            uv[:, 1] = 1.0 - a1[lv]            # the glTF exporter writes (u, 1 - v); pre-flip so Godot reads the value itself
            uvl.data.foreach_set("uv", uv.reshape(-1))
        packed += 1
    mean_alb = (alb_sum / max(alb_n, 1)).tolist()
    for o in uncoloured:      # e.g. the outer plain: same Blender material but no colour attribute; never export it white
        for i in range(len(o.data.materials)):
            o.data.materials[i] = special_mat("terrain_outer", base=tuple(mean_alb), rough=0.95, cls="rock",
                                              note="terrain mesh without a colour attribute; flat mean of the tiles' gc_alb (%d vertices)" % alb_n)
    rep["environment"] = {
        "exported_objects": len(env_export), "terrain_tiles": len(env_terrain), "rocks_realised": len(rocks), "rock_sources": dict(rock_src),
        "scatter_instances_not_realised": rock_other,
        "exported_tris": sum(tri_count(o.data) for o in env_export), "terrain_tris": sum(tri_count(o.data) for o in env_terrain),
        "rock_tris_instanced": sum(tri_count(o.data) for o in rocks),
        "by_collection": dict(Counter(o.users_collection[0].name for o in env_export)),
        "skipped": env_skipped, "geometry_nodes_on_exported_objects": gravel,
        "terrain_packing": {"tiles_packed": packed, "COLOR_0": "gc_alb rgb + gc_ma.b (bare rock)", "UV": "pebble factor from gc_ma.a and gc_mb.a; gc_mb.r (hollow/ridge)",
                            "UV2": "rut offset from gc_trk.r and .b (99 = no track); gc_trk.g (metres along)",
                            "not_carried": ["gc_ma.r strata weight", "gc_ma.g strata palette", "gc_mb.g ejecta", "gc_mb.b dune profile", "gc_trk.a crater floor"],
                            "mean_gc_alb_linear": [round(v, 4) for v in mean_alb], "uncoloured_objects_given_flat_mean": [o.name for o in uncoloured]},
        "source_materials": sorted(env_mat_sources),
    }
    rep["unmapped_materials"] = dict(unknown_mats)

    for key, m in flat.items():
        m.name = key.split(":", 1)[1] if key.startswith("special:") else key

    # ------------------------------------------------------------------ manifest: lights, cameras, probes, rooms
    excluded = {}

    def walk(lc):
        excluded[lc.collection.name] = lc.exclude
        for ch in lc.children:
            walk(ch)
    walk(vl.layer_collection)

    lights = []
    for o in bpy.data.objects:
        if o.type != "LIGHT":
            continue
        l = o.data
        coll = o.users_collection[0].name if o.users_collection else None
        rec = {"name": o.name, "type": l.type, "collection": coll, "in_blender_render": not excluded.get(coll, False) and not o.hide_render,
               "energy": round(float(l.energy), 5), "color": r(l.color), "matrix_world": mat4(o.matrix_world),
               "use_shadow": bool(getattr(l, "use_shadow", True))}
        for a in ("shape", "size", "size_y", "spot_size", "spot_blend", "shadow_soft_size", "angle", "normalize", "exposure", "use_temperature", "temperature",
                  "use_custom_distance", "cutoff_distance", "spread"):
            if hasattr(l, a):
                v = getattr(l, a)
                rec[a] = round(v, 5) if isinstance(v, float) else v
        lights.append(rec)
    cams = []
    for o in bpy.data.objects:
        if o.type != "CAMERA":
            continue
        c = o.data
        cams.append({"name": o.name, "collection": o.users_collection[0].name if o.users_collection else None, "matrix_world": mat4(o.matrix_world),
                     "type": c.type, "lens": round(c.lens, 4), "sensor_width": round(c.sensor_width, 4), "sensor_height": round(c.sensor_height, 4),
                     "sensor_fit": c.sensor_fit, "angle_x": round(c.angle_x, 6), "angle_y": round(c.angle_y, 6), "clip_start": round(c.clip_start, 4),
                     "clip_end": round(c.clip_end, 3), "shift_x": c.shift_x, "shift_y": c.shift_y})
    probes = [{"name": o.name, "type": o.data.type, "matrix_world": mat4(o.matrix_world), "influence_distance": round(float(getattr(o.data, "influence_distance", 0.0)), 4),
               "influence_type": getattr(o.data, "influence_type", None)} for o in bpy.data.objects if o.type == "LIGHT_PROBE"]
    vs = sc.view_settings
    world = sc.world
    game_json = json.load(open(GAME_JSON))
    env_tiles = [o for o in env_export if o in env_terrain and "gc_pack" in o.data.color_attributes]
    env_plain = [o for o in env_export if o not in env_tiles]
    manifest = {
        "schema": 2, "generated": time.strftime("%Y-%m-%d %H:%M:%S"), "source": rep["source"], "detail": DETAIL,
        "axes": "Blender right-handed Z-up metres. glTF/Godot: (x, y, z)_blender -> (x, z, -y).",
        "render_reference": {"resolution": [sc.render.resolution_x, sc.render.resolution_y], "view_transform": vs.view_transform, "look": vs.look,
                             "exposure": round(vs.exposure, 4), "gamma": round(vs.gamma, 4), "engine_saved": sc.render.engine,
                             "world": world.name if world else None},
        "rooms": [{"name": n, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "ceiling": P.ROOM_H.get(n, 3.0), "dust": P.ROOM_DUST.get(n), "mean_albedo": ROOM_ALBEDO.get(n)}
                  for (n, x0, y0, x1, y1) in P.ROOMS_META],
        "dome": P.DOME, "airlock": P.AIRLOCK, "spawn_old_demo": P.SPAWN,
        "pads_y_up": game_json.get("pads"), "roofs_y_up": game_json.get("roofs"),
        "objects": objects, "lights": lights, "cameras": cams, "light_probes": probes,
        "counts": {"objects": len(objects), "lights": len(lights), "lights_in_blender_render": sum(1 for l in lights if l["in_blender_render"]),
                   "cameras": len(cams), "probes": len(probes), "environment_objects": len(env_export)},
        "environment_objects": [{"name": o.name, "collection": o.users_collection[0].name, "matrix_world": mat4(o.matrix_world), "tris": tri_count(o.data),
                                 "mesh": o.data.name, "file": "terrain" if o in env_tiles else "environment"} for o in env_export],
    }
    os.makedirs(os.path.join(PROJ, "data"), exist_ok=True)
    os.makedirs(os.path.join(PROJ, "assets", "colony"), exist_ok=True)
    with open(os.path.join(PROJ, "data", "colony_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, separators=(",", ":"))
    with open(os.path.join(PROJ, "data", "palette.json"), "w", encoding="utf-8") as f:
        json.dump({"schema": 2, "source": "gc_lib.PAL / ALPHA / MATSPEC and gc_mat.CLASSES via export_colony_glb.py",
                   "note": "rgb is linear. Class parameters are the ones gc_mat._surface reads. emission is the palette's game value, not a calibrated light output.",
                   "dust_linear": list(gc_mat.DUST_LIN), "dust_roughness": gc_mat.DUST_ROUGH, "roles": PALETTE}, f, indent=1)
    with open(os.path.join(PROJ, "data", "colliders.json"), "w", encoding="utf-8") as f:
        json.dump({"schema": 1, "source": GAME_JSON, "source_sha256": sha256(GAME_JSON),
                   "note": "Collision definitions of the browser export, already in Y-up metres (x, z, -y). c = centre, h = half extents, q = quaternion xyzw. For Prompt 04.",
                   "assets": {a["n"]: {k: a[k] for k in ("cls", "cols", "mass", "shape", "zone") if k in a} for a in game_json["assets"]}}, f, separators=(",", ":"))

    # ------------------------------------------------------------------ export
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    vc_modes = enum_ids(props, "export_vertex_color")
    rep["gltf_vertex_color_modes"] = vc_modes

    def export(path, obs, colour_name):
        for o in bpy.data.objects:
            try:
                o.select_set(False)
            except Exception:
                pass
        sel = 0
        for o in obs:
            try:
                o.select_set(True)
                sel += 1
            except Exception:
                pass
        kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True, export_extras=True,
                  export_cameras=False, export_lights=False, export_animations=False, export_skins=False, export_morph=False,
                  export_materials="EXPORT", export_texcoords=True, export_normals=True, export_tangents=False,
                  export_hierarchy_full_collections=True, export_gpu_instances=False)
        if colour_name and "NAME" in vc_modes:
            kw.update(export_vertex_color="NAME", export_vertex_color_name=colour_name, export_all_vertex_colors=False)
        elif colour_name and "ACTIVE" in vc_modes:
            kw.update(export_vertex_color="ACTIVE", export_all_vertex_colors=False)
        elif "NONE" in vc_modes:
            kw.update(export_vertex_color="NONE")
        t = time.time()
        res = bpy.ops.export_scene.gltf(**kw)
        return {"path": path, "selected": sel, "result": list(res), "secs": round(time.time() - t, 1), "bytes": os.path.getsize(path) if os.path.exists(path) else 0,
                "sha256": sha256(path) if os.path.exists(path) else None, "vertex_color": kw.get("export_vertex_color"), "vertex_color_name": colour_name}

    for o in env_plain:
        if "gc_cav" not in o.data.color_attributes:
            write_cavity(o.data)
    rep["exports"] = [export(os.path.join(PROJ, "assets", "colony", "colony.glb"), colony, "gc_cav"),
                      export(os.path.join(PROJ, "assets", "colony", "environment.glb"), env_plain, "gc_cav"),
                      export(os.path.join(PROJ, "assets", "colony", "terrain.glb"), env_tiles, "gc_pack")]
    rep["palette_roles_written"] = len(PALETTE)
    rep["manifest_counts"] = manifest["counts"]
    rep["secs"] = round(time.time() - T0, 1)
    rep["ok"] = True
except Exception:
    rep["error"] = traceback.format_exc()
os.makedirs(REPORT_DIR, exist_ok=True)
with open(os.path.join(REPORT_DIR, "export_report.json"), "w", encoding="utf-8") as f:
    json.dump(rep, f, indent=1, default=str)
