"""Check renders of the room upgrade stages (worker 4, 2026-11-14).

Loads the intact map (never saved), adds the triangles of every stage part dumped by tests/test_room_stages.gd --dump
(Godot world coordinates, converted here to Blender's Z-up), marks station standing spots (red discs) and door
keep-out boxes (yellow), and renders Workbench images: a top view and eye-height views of each room at each level, plus
outdoor views of the sun trackers and the Command Room roof. It also intersects every stage part with the map's real
triangles (BVH overlap, not boxes) and writes clip_report.txt next to the images.

  blender-launcher -b --factory-startup --disable-autoexec <grand_colony_intact.blend> --python render_rooms.py --
        --parts <parts.json> --out <dir> [--only "Med Bay"] [--levels 1,2,3,4] [--no-render]
"""
import bpy
import json
import os
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = {}
i = 0
while i < len(argv):
	if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
		opts[argv[i]] = argv[i + 1]
		i += 2
	else:
		opts[argv[i]] = "1"
		i += 1
PARTS = opts.get("--parts", "")
OUT = opts["--out"]
ONLY = opts.get("--only", "")
LEVELS = [int(v) for v in opts.get("--levels", "1,2,3,4").split(",")]
RENDER = "--no-render" not in opts
os.makedirs(OUT, exist_ok=True)

# name: (x0, y0, x1, y1, ceiling, track, [(camera xy, look-at xyz), ...])
ROOMS = {
	"Power Room": (26, -10, 42, -2, 3.48, "energy", [((31.5, -8.6), (26.6, -3.6, 1.6)), ((29.5, -4.4), (26.4, -3.5, 2.2)), ((33.0, -7.0), (27.0, -2.6, 2.4))]),
	"Life Support": (34, -2, 42, 10, 3.48, "life_support", [((37.3, 2.2), (39.6, 6.5, 1.3)), ((38.2, 4.0), (34.5, 7.4, 1.4)), ((36.0, 1.0), (39.5, 9.6, 1.6))]),
	"Med Bay": (-12, 8, 0, 18, 3.0, "health", [((-8.0, 13.0), (-6.5, 17.6, 1.6)), ((-4.6, 13.6), (-1.0, 10.8, 1.2)), ((-9.0, 11.0), (-1.5, 11.5, 1.4))]),
	"Command Room": (24, 10, 34, 18, 3.0, "command", [((31.0, 17.3), (30.5, 10.2, 1.9)), ((27.0, 15.0), (32.5, 17.3, 1.4)), ((28.0, 12.9), (31.0, 14.0, 0.9))]),
}
OUTDOOR = {
	"solar_west": ((-14.0, -9.0, 6.5), (-25.5, 6.0, 1.0), "energy"),
	"solar_east": ((42.0, -16.0, 7.0), (54.0, -1.0, 1.0), "energy"),
	"command_roof": ((25.0, 9.0, 7.0), (32.4, 16.4, 3.8), "command"),
}

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
scene.display.shading.show_shadows = False
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "WORLD"
scene.display.shading.show_object_outline = True
scene.render.resolution_x = 1280
scene.render.resolution_y = 800
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = 0.9
scene.view_settings.gamma = 1.0

for ob in scene.objects:
	ob.color = (0.55, 0.55, 0.53, 1.0)
	if "Glass" in "".join(c.name for c in ob.users_collection):
		ob.hide_render = True

parts = {}
if PARTS and os.path.exists(PARTS):
	with open(PARTS) as f:
		parts = json.load(f)

coll = bpy.data.collections.new("RoomStageCheck")
scene.collection.children.link(coll)


def g2b(v):
	return (v[0], -v[2], v[1])


def add_tris(name, tris, color):
	verts = [g2b(v) for v in tris]
	faces = [(i, i + 1, i + 2) for i in range(0, len(verts) - 2, 3)]
	me = bpy.data.meshes.new(name)
	me.from_pydata(verts, [], faces)
	me.update()
	ob = bpy.data.objects.new(name, me)
	ob.color = color
	coll.objects.link(ob)
	return ob


def add_box(name, lo, hi, color):
	me = bpy.data.meshes.new(name)
	x0, y0, z0 = lo
	x1, y1, z1 = hi
	v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
	f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
	me.from_pydata(v, [], f)
	ob = bpy.data.objects.new(name, me)
	ob.color = color
	coll.objects.link(ob)
	return ob


def add_disc(name, x, y, r, color):
	import math
	n = 24
	v = [(x, y, 0.02)] + [(x + r * math.cos(6.2832 * k / n), y + r * math.sin(6.2832 * k / n), 0.02) for k in range(n)]
	f = [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)]
	me = bpy.data.meshes.new(name)
	me.from_pydata(v, [], f)
	ob = bpy.data.objects.new(name, me)
	ob.color = color
	coll.objects.link(ob)
	return ob


markers = []
for st in parts.get("keepout_discs", []):
	markers.append(add_disc("ko_" + st["id"], st["x"], -st["z"], st["r"], (0.95, 0.2, 0.15, 1.0)))
for d in parts.get("keepout_boxes", []):
	mn = g2b(d["min"])
	mx = g2b(d["max"])
	lo = (min(mn[0], mx[0]), min(mn[1], mx[1]), 0.0)
	hi = (max(mn[0], mx[0]), max(mn[1], mx[1]), 0.03)
	markers.append(add_box("door_" + d["id"], lo, hi, (1.0, 0.85, 0.1, 1.0)))

level_objs = {}
for key, plist in parts.get("levels", {}).items():
	objs = []
	for i, p in enumerate(plist):
		c = p.get("color", [0.3, 0.6, 0.9])
		objs.append(add_tris("%s_%d" % (key, i), p["tris"], (c[0], c[1], c[2], 1.0)))
	level_objs[key] = objs

# ---------------------------------------------------------------- clip report (exact triangles)
dg = bpy.context.evaluated_depsgraph_get()


def world_bvh(ob):
	ev = ob.evaluated_get(dg)
	me = ev.to_mesh()
	verts = [ev.matrix_world @ v.co for v in me.vertices]
	polys = [tuple(p.vertices) for p in me.polygons]
	ev.to_mesh_clear()
	if not polys:
		return None
	return BVHTree.FromPolygons(verts, polys)


def bbox_of(ob):
	pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	return (min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)), (max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))


def boxes_meet(a, b, pad=0.0):
	return all(a[0][i] - pad <= b[1][i] and b[0][i] - pad <= a[1][i] for i in range(3))


report = []
scene_cache = {}
bvh_cache = {}
for key, objs in level_objs.items():
	for ob in objs:
		pb = bbox_of(ob)
		pbvh = world_bvh(ob)
		if pbvh is None:
			continue
		hits = set()
		for so in scene.objects:
			if so.type != "MESH" or so.users_collection[0] == coll or so.hide_render:
				continue
			if so.name not in scene_cache:
				try:
					scene_cache[so.name] = bbox_of(so)
				except Exception:
					scene_cache[so.name] = None
			sb = scene_cache[so.name]
			if sb is None or (sb[1][0] - sb[0][0]) > 40 or (sb[1][1] - sb[0][1]) > 40:
				continue
			if not boxes_meet(pb, sb):
				continue
			if so.name not in bvh_cache:
				bvh_cache[so.name] = world_bvh(so)
			sbvh = bvh_cache[so.name]
			if sbvh is not None and pbvh.overlap(sbvh):
				hits.add(so.name)
		if hits:
			report.append("%s surface %s touches: %s" % (key, ob.name.split("_")[-1], ", ".join(sorted(hits))))
with open(os.path.join(OUT, "clip_report.txt"), "w") as f:
	f.write("\n".join(report) + "\n")


# ---------------------------------------------------------------- renders

def show_level(track, level):
	for key, objs in level_objs.items():
		vis = key == "%s:%d" % (track, level)
		for ob in objs:
			ob.hide_render = not vis


def cam_obj():
	cd = bpy.data.cameras.new("RS_Cam")
	cam = bpy.data.objects.new("RS_Cam", cd)
	scene.collection.objects.link(cam)
	scene.camera = cam
	return cam


def look_at(cam, loc, target):
	cam.location = loc
	d = Vector(target) - Vector(loc)
	cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


hidden_for_top = []


def hide_ceiling(x0, y0, x1, y1, ceil):
	global hidden_for_top
	hidden_for_top = []
	for ob in scene.objects:
		if ob.type not in {"MESH", "CURVE"} or ob.hide_render or ob.users_collection[0] == coll:
			continue
		bb = scene_cache.get(ob.name) or bbox_of(ob)
		if bb[1][0] > x0 - 3 and bb[0][0] < x1 + 3 and bb[1][1] > y0 - 3 and bb[0][1] < y1 + 3 and (bb[0][2] > ceil - 0.6 or bb[1][2] > ceil + 1.0):
			ob.hide_render = True
			hidden_for_top.append(ob)


def render(path):
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


if RENDER:
	cam = cam_obj()
	for rn, (x0, y0, x1, y1, ceil, track, views) in ROOMS.items():
		if ONLY and ONLY != rn:
			continue
		slug = rn.lower().replace(" ", "_")
		for lvl in LEVELS:
			show_level(track, lvl)
			for m in markers:
				m.hide_render = False
			hide_ceiling(x0, y0, x1, y1, ceil)
			cam.data.type = "ORTHO"
			w = (x1 - x0) + 1.6
			h = (y1 - y0) + 1.6
			scene.render.resolution_x = 1280
			scene.render.resolution_y = int(1280 * h / w)
			cam.data.ortho_scale = max(w, h)
			cam.location = ((x0 + x1) / 2, (y0 + y1) / 2, 30.0)
			cam.rotation_euler = (0, 0, 0)
			cam.data.clip_end = 200
			render(os.path.join(OUT, "%s_v%d_top.png" % (slug, lvl)))
			for ob in hidden_for_top:
				ob.hide_render = False
			for m in markers:
				m.hide_render = True
			scene.render.resolution_x = 1280
			scene.render.resolution_y = 800
			cam.data.type = "PERSP"
			cam.data.lens = 18
			cam.data.clip_start = 0.05
			for vi, (e, t) in enumerate(views):
				look_at(cam, (e[0], e[1], 1.65), t)
				render(os.path.join(OUT, "%s_v%d_eye%d.png" % (slug, lvl, vi)))
	for on, (loc, target, track) in OUTDOOR.items():
		if ONLY and ONLY != on:
			continue
		for m in markers:
			m.hide_render = True
		for lvl in LEVELS:
			show_level(track, lvl)
			cam.data.type = "PERSP"
			cam.data.lens = 24
			look_at(cam, loc, target)
			render(os.path.join(OUT, "%s_v%d.png" % (on, lvl)))
print("RENDERED", OUT)
