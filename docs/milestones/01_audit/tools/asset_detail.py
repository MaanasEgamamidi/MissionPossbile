"""Read-only detail for named gameplay-critical assets in the open .blend (dimensions, parts, materials).
Run: blender -b <blend> --python asset_detail.py -- --out <dir> --label <label>
Writes <label>.assets.json. Never saves the .blend."""
import bpy
import bmesh
import json
import os
import re
import sys
import traceback
from collections import Counter
from mathutils import Vector

PATTERNS = {
    "rover": r"^(hb_rover|sf_rover)",
    "spaceship": r"^ex_lander",
    "human": r"^(md_survivor)",
    "suit": r"^(al_suit_rack|qt_spacesuit|pp_helmet|pp_glove_torn|ak_suit_shelf)",
    "crash_site": r"^sf_crash",
    "solar": r"^sf_solar",
    "moxie_o2": r"^(ls_moxie|ls_o2_tank|ls_pump_skid|ls_)",
    "power": r"^(pr_bat|pr_swgr|pr_panelboard|pw_)",
    "comms": r"^(cm_comms_console|cm_radio|sf_antenna)",
    "crops": r"^(gd_crop|gr_.*bed|gr_.*row|gr_tray|gr_seedling|gd_hydro)",
    "garage_hangar": r"^(hb_workbench|hg_crane|hg_scissor_lift|hb_)",
    "doors": r"^(hgw_door|msw_door|cmw_door|stw_door|qtw_door|lbw_door|bp_door|gd_airlock)",
    "glass": r"^(gd_shell|GCE_hall|sf_hall)",
}


def islands(me, cap=400000):
    if len(me.polygons) > cap:
        return None
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen = set()
    n = 0
    for v in bm.verts:
        if v.index in seen:
            continue
        n += 1
        stack = [v]
        seen.add(v.index)
        while stack:
            x = stack.pop()
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
    bm.free()
    return n


def main(out_dir, label):
    bpy.context.view_layer.update()
    out = {}
    done_mesh = {}
    for cat, pat in PATTERNS.items():
        rx = re.compile(pat)
        rows = []
        names = Counter()
        for o in bpy.data.objects:
            if o.type != "MESH" or not rx.search(o.name):
                continue
            base = re.sub(r"\.\d{3}$", "", o.name)
            names[base] += 1
            if names[base] > 1:
                continue  # one representative per asset name; count kept below
            me = o.data
            if me.name not in done_mesh:
                tris = sum(p.loop_total - 2 for p in me.polygons)
                zs = [v.co for v in me.vertices]
                lo = Vector((min(v.x for v in zs), min(v.y for v in zs), min(v.z for v in zs))) if zs else Vector()
                hi = Vector((max(v.x for v in zs), max(v.y for v in zs), max(v.z for v in zs))) if zs else Vector()
                done_mesh[me.name] = dict(tris=tris, verts=len(me.vertices), local_min=[round(x, 3) for x in lo], local_max=[round(x, 3) for x in hi],
                                          size=[round(x, 3) for x in (hi - lo)], islands=islands(me),
                                          materials=[m.name if m else None for m in me.materials], uv_layers=len(me.uv_layers),
                                          vertex_groups=len(o.vertex_groups), shape_keys=bool(me.shape_keys))
            d = dict(done_mesh[me.name])
            d.update(object=o.name, mesh=me.name, mesh_users=me.users, location=[round(x, 3) for x in o.matrix_world.translation],
                     rotation_z_deg=round(__import__("math").degrees(o.matrix_world.to_euler().z), 2), scale=[round(x, 3) for x in o.scale],
                     collections=[c.name for c in o.users_collection], parent=o.parent.name if o.parent else None,
                     modifiers=[m.type for m in o.modifiers], props={k: (o[k] if isinstance(o[k], (int, float, str)) else str(o[k])) for k in o.keys()})
            rows.append(d)
        for r in rows:
            r["instances_of_name"] = names[re.sub(r"\.\d{3}$", "", r["object"])]
        out[cat] = rows
    # interactables + doors (custom props used by the exporter)
    out["_interactables"] = [dict(object=o.name, inter=str(o["inter"]), location=[round(x, 3) for x in o.matrix_world.translation],
                                  collections=[c.name for c in o.users_collection]) for o in bpy.data.objects if "inter" in o.keys()]
    doors = [o for o in bpy.data.objects if "door_id" in o.keys()]
    out["_doors"] = dict(count=len(doors), ids=sorted({int(o["door_id"]) for o in doors}),
                         sample=[dict(object=o.name, door_id=int(o["door_id"]), slide=float(o["door_slide"]),
                                      location=[round(x, 3) for x in o.matrix_world.translation]) for o in doors[:8]])
    out["_gn_modifiers"] = [dict(object=o.name, group=m.node_group.name if m.node_group else None, collections=[c.name for c in o.users_collection])
                            for o in bpy.data.objects for m in o.modifiers if m.type == "NODES"]
    out["_dust_values"] = dict(Counter(round(float(o["dust"]), 2) for o in bpy.data.objects if "dust" in o.keys()).most_common(12))
    out["_lights_named"] = dict(Counter(re.sub(r"[\._]?\d+$", "", re.sub(r"\.\d{3}$", "", o.name)) for o in bpy.data.objects if o.type == "LIGHT").most_common(60))
    with open(os.path.join(out_dir, label + ".assets.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, default=str)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[0::2], argv[1::2]))
    try:
        main(opts["--out"], opts["--label"])
    except Exception:
        with open(os.path.join(opts["--out"], opts["--label"] + ".error.txt"), "w", encoding="utf-8") as f:
            f.write(traceback.format_exc())
