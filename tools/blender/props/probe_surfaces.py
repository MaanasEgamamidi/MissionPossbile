"""Find visual support surfaces (desks, shelves, crates) around the cassette anchors in the intact map. Headless; the map
is never saved:
  blender-launcher -b --factory-startup --disable-autoexec "G:/nasa app/grand_colony_intact/grand_colony_intact.blend"
        --python probe_surfaces.py -- --proj <godot project> [--radius 3.0] [--out <txt>]
Prints, per anchor of data/stations_repairs.json (cassette tapes and the player), every object whose top a downward ray
hits between 0.35 m and 1.6 m (Godot coordinates: x, y up, z = -Blender y), with its x/z extent and hit count.
"""
import bpy
import json
import os
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts["--proj"]
RADIUS = float(opts.get("--radius", "3.0"))
OUT = opts.get("--out", os.path.join(PROJ, "tools", "blender", "props", "reports", "surfaces.txt"))
os.makedirs(os.path.dirname(OUT), exist_ok=True)


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
stations = json.load(open(os.path.join(PROJ, "data", "stations_repairs.json"), encoding="utf-8"))["stations"]
lines = []
if "--point" in opts:      # what surrounds one Godot point: the nearest hit in the six axis directions
    gx, gy, gz = (float(v) for v in opts["--point"].split(","))
    for label, d in (("+x", (1, 0, 0)), ("-x", (-1, 0, 0)), ("+z", (0, 0, 1)), ("-z", (0, 0, -1)), ("+y", (0, 1, 0)), ("-y", (0, -1, 0))):
        hit, loc, nor, idx, ob, mat = sc.ray_cast(dg, Vector((gx, -gz, gy)), Vector((d[0], -d[2], d[1])), distance=6.0)
        lines.append("%s %s" % (label, "%s at godot (%.3f, %.3f, %.3f) normal (%.2f, %.2f, %.2f)" % (ob.name, loc.x, loc.z, -loc.y, nor.x, nor.z, -nor.y) if hit else "nothing"))
    stations = []
if "--centers" in opts:    # "x,z;x,z": probe around these Godot points instead of the anchors
    stations = [{"id": "c%d" % i, "kind": "cassette_anchor", "position": [float(c.split(",")[0]), 0.0, float(c.split(",")[1])]}
                for i, c in enumerate(opts["--centers"].split(";"))]
for st in stations:
    if st["kind"] not in ("cassette_anchor", "cassette_player_anchor"):
        continue
    gx, gy, gz = st["position"]
    lines.append("== %s (%.2f, %.2f, %.2f)" % (st["id"], gx, gy, gz))
    groups = {}
    steps = int(RADIUS / 0.1)
    for ix in range(-steps, steps + 1):
        for iz in range(-steps, steps + 1):
            x = gx + ix * 0.1
            z = gz + iz * 0.1
            hit, loc, nor, idx, ob, mat = sc.ray_cast(dg, Vector((x, -z, 2.3)), Vector((0, 0, -1)), distance=2.1)
            if not hit or nor.z < 0.9:
                continue
            y = loc.z
            if y < 0.35 or y > 1.6:
                continue
            key = "%s@%.2f" % (ob.name, round(y / 0.02) * 0.02)
            g = groups.setdefault(key, [x, x, z, z, 0])
            g[0] = min(g[0], x); g[1] = max(g[1], x); g[2] = min(g[2], z); g[3] = max(g[3], z); g[4] += 1
    for key, g in sorted(groups.items()):
        if g[4] >= 4 and "crop" not in key:
            lines.append("  %s x[%.2f..%.2f] z[%.2f..%.2f] n=%d" % (key, g[0], g[1], g[2], g[3], g[4]))
open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("\n".join(lines))
