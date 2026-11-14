"""Read-only probe before the derivative export (Prompt 02). Opens nothing itself: run with the source .blend loaded.
  blender-launcher -b --factory-startup --disable-autoexec <blend> --python probe_export.py -- --out <dir> --label <name>
Writes <label>.probe.json. Never saves the .blend."""
import bpy
import json
import os
import sys
import time
import traceback

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
OUT, LABEL = opts["--out"], opts["--label"]
SCRIPTS = r"G:\nasa app\grand_colony\scripts"
rep = {"ok": False}
try:
    t0 = time.time()
    if SCRIPTS not in sys.path:
        sys.path.insert(0, SCRIPTS)
    import gc_build
    mods = gc_build._reload()          # registers every asset function; builds nothing
    import gc_lib as L
    rep["registered_assets"] = len(L.ASSETS)
    rep["palette_roles"] = len(L.PAL)
    rep["alpha_roles"] = dict(L.ALPHA)
    rep["reload_secs"] = round(time.time() - t0, 1)

    # view-layer state of the light collections (which lights the Blender renders actually use)
    def walk(lc, out):
        out[lc.collection.name] = {"exclude": lc.exclude, "hide_viewport": lc.hide_viewport}
        for ch in lc.children:
            walk(ch, out)
    vl = {}
    walk(bpy.context.view_layer.layer_collection, vl)
    rep["layer_collections"] = {k: v for k, v in vl.items() if v["exclude"] or k in ("Lights", "Render Lights", "Fixture Lights", "Exterior env lights", "Light Probes", "Atmosphere")}

    objs = [o for o in bpy.data.objects if o.type == "MESH" and "gc_asset" in o.keys()]
    names = []
    for o in objs:
        if o["gc_asset"] not in names:
            names.append(o["gc_asset"])
    rep["gc_objects"] = len(objs)
    rep["gc_asset_names"] = len(names)
    missing = [n for n in names if n not in L.ASSETS]
    rep["missing_from_registry"] = missing

    t1 = time.time()
    tris = {}
    failed = {}
    roles_used = set()
    for n in names:
        if n in missing:
            continue
        try:
            me = L.mesh_of(n, "game")
            tris[n] = sum(p.loop_total - 2 for p in me.polygons)
            for m in me.materials:
                if m:
                    roles_used.add(m.name)
        except Exception as e:
            failed[n] = f"{type(e).__name__}: {e}"
    rep["game_mesh_secs"] = round(time.time() - t1, 1)
    rep["game_mesh_failed"] = failed
    rep["game_tris_unique"] = sum(tris.values())
    rep["game_tris_instanced"] = sum(tris.get(o["gc_asset"], 0) for o in objs)
    rep["game_tris_top"] = sorted(tris.items(), key=lambda kv: -kv[1])[:15]
    rep["materials_on_game_meshes"] = len(roles_used)
    rep["materials_not_in_palette"] = sorted(m for m in roles_used if m[3:] not in L.PAL)

    # compare with the browser export
    try:
        cj = json.load(open(r"G:\nasa app\grand_colony\game\colony.json"))
        ct = {a["n"]: a["t"] for a in cj["assets"]}
        rep["colony_json"] = {"assets": len(ct), "tris": cj["tris"],
                              "names_only_in_json": sorted(set(ct) - set(names))[:20], "names_only_in_blend": sorted(set(names) - set(ct))[:20],
                              "tri_mismatch": [(n, tris[n], ct[n]) for n in names if n in tris and n in ct and tris[n] != ct[n]][:20]}
    except Exception as e:
        rep["colony_json"] = {"_error": str(e)}

    # environment (Blender-only) objects
    env = bpy.data.collections.get("Environment (Blender only)")
    rows = []
    dg = bpy.context.evaluated_depsgraph_get()
    if env:
        for o in env.all_objects:
            if o.type != "MESH":
                rows.append({"name": o.name, "type": o.type})
                continue
            me = o.data
            row = {"name": o.name, "tris": sum(p.loop_total - 2 for p in me.polygons), "mats": [m.name if m else None for m in me.materials],
                   "colls": [c.name for c in o.users_collection], "mods": [(m.type, m.node_group.name if m.type == "NODES" and m.node_group else None) for m in o.modifiers],
                   "color_attrs": [(a.name, a.data_type, a.domain) for a in me.color_attributes],
                   "active_color": me.color_attributes.active_color.name if me.color_attributes.active_color else None,
                   "render_color": me.color_attributes.render_color_index}
            rows.append(row)
    rep["environment_objects"] = rows
    # geometry-nodes instance counts (not realised)
    inst = {}
    for oi in dg.object_instances:
        if oi.is_instance and oi.parent is not None:
            k = oi.parent.name
            inst[k] = inst.get(k, 0) + 1
    rep["gn_instances_by_parent"] = dict(sorted(inst.items(), key=lambda kv: -kv[1])[:40])
    rep["gn_instances_total"] = sum(inst.values())
    rep["gltf_exporter_available"] = hasattr(bpy.ops.export_scene, "gltf")
    try:
        props = bpy.ops.export_scene.gltf.get_rna_type().properties
        rep["gltf_export_options"] = sorted(p.identifier for p in props if p.identifier.startswith("export_"))
    except Exception as e:
        rep["gltf_export_options"] = str(e)
    rep["non_gc_colony_objects"] = [(o.name, o.type) for o in bpy.data.collections["Colony (colour)"].all_objects if "gc_asset" not in o.keys() and o.type != "LIGHT"][:60]
    rep["is_dirty"] = bpy.data.is_dirty
    rep["ok"] = True
except Exception:
    rep["error"] = traceback.format_exc()
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, LABEL + ".probe.json"), "w", encoding="utf-8") as f:
    json.dump(rep, f, indent=1, default=str)
