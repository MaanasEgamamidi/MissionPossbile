"""Visual top-surface height map of the intact map over a few Godot rectangles (cassette spot search). Headless; the map
is never saved:
  blender-launcher -b --factory-startup --disable-autoexec "G:/nasa app/grand_colony_intact/grand_colony_intact.blend"
        --python scan_heights.py -- --rects "name:x0,x1,z0,z1;..." --step 0.05 --out <json>
Writes {name: {"x0","z0","step","nx","nz","h": [[top y or null, object name index], ...]}, "objects": [...]} in Godot
coordinates (y up, z = -Blender y). Only upward-facing hits between 0.3 m and 1.8 m are kept.
"""
import bpy
import json
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
STEP = float(opts.get("--step", "0.05"))


def lc_find(lc, name):
    if lc.collection.name == name:
        return lc
    for ch in lc.children:
        f = lc_find(ch, name)
        if f:
            return f
    return None


for n in ("Exterior atmosphere", "Exterior motes", "Atmosphere"):
    lc = lc_find(bpy.context.view_layer.layer_collection, n)
    if lc:
        lc.exclude = True
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
sc = bpy.context.scene
objects = []
index = {}
out = {"objects": objects}
for spec in opts["--rects"].split(";"):
    name, r = spec.split(":")
    x0, x1, z0, z1 = (float(v) for v in r.split(","))
    nx = int(round((x1 - x0) / STEP)) + 1
    nz = int(round((z1 - z0) / STEP)) + 1
    rows = []
    for iz in range(nz):
        row = []
        z = z0 + iz * STEP
        for ix in range(nx):
            x = x0 + ix * STEP
            hit, loc, nor, idx, ob, mat = sc.ray_cast(dg, Vector((x, -z, 2.4)), Vector((0, 0, -1)), distance=2.5)
            if hit and nor.z > 0.9 and 0.3 <= loc.z <= 1.8:
                if ob.name not in index:
                    index[ob.name] = len(objects)
                    objects.append(ob.name)
                row.append([round(loc.z, 3), index[ob.name]])
            else:
                row.append(None)
        rows.append(row)
    out[name] = {"x0": x0, "z0": z0, "step": STEP, "nx": nx, "nz": nz, "h": rows}
json.dump(out, open(opts["--out"], "w"))
