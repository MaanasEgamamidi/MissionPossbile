"""Dumps world bounding boxes (Blender coordinates) of the map objects in the four upgrade rooms, the sun trackers and
the roof over the Command Room, so the room-stage builders can be placed clear of them.

Run headless with the intact map loaded (never saved):
  blender-launcher -b --factory-startup --disable-autoexec <grand_colony_intact.blend> --python dump_rooms.py -- --out <json>
"""
import bpy
import json
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
OUT = opts["--out"]

ROOMS = {
	"Power Room": (26, -10, 42, -2, 3.48),
	"Life Support": (34, -2, 42, 10, 3.48),
	"Med Bay": (-12, 8, 0, 18, 3.0),
	"Command Room": (24, 10, 34, 18, 3.0),
}
PAD = 0.6

dg = bpy.context.evaluated_depsgraph_get()
out = {"rooms": {}, "trackers": [], "roof": []}
for name in ROOMS:
	out["rooms"][name] = []


def bbox(ob):
	ev = ob.evaluated_get(dg)
	pts = [ev.matrix_world @ Vector(c) for c in ev.bound_box]
	mn = [min(p[i] for p in pts) for i in range(3)]
	mx = [max(p[i] for p in pts) for i in range(3)]
	return mn, mx


for ob in bpy.data.objects:
	if ob.type not in {"MESH", "CURVE", "EMPTY"} or ob.type == "EMPTY":
		continue
	try:
		mn, mx = bbox(ob)
	except Exception:
		continue
	cols = [c.name for c in ob.users_collection]
	rec = {"name": ob.name, "asset": ob.get("gc_asset", ""), "cols": cols, "min": [round(v, 3) for v in mn], "max": [round(v, 3) for v in mx], "hide_render": ob.hide_render}
	if ob.name.startswith("sf_solar_tracker"):
		out["trackers"].append(rec)
		continue
	for rn, (x0, y0, x1, y1, ceil) in ROOMS.items():
		if mx[0] > x0 - PAD and mn[0] < x1 + PAD and mx[1] > y0 - PAD and mn[1] < y1 + PAD:
			if mn[2] > ceil + 0.3:
				if rn == "Command Room":
					out["roof"].append(rec)
				continue
			if (mx[0] - mn[0]) > 25 or (mx[1] - mn[1]) > 25:
				continue
			out["rooms"][rn].append(rec)

with open(OUT, "w") as f:
	json.dump(out, f, indent=0)
print("DUMPED", {k: len(v) for k, v in out["rooms"].items()}, len(out["trackers"]), len(out["roof"]))
