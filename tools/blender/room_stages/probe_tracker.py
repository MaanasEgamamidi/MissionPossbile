"""Prints the panel deck of sun tracker 0 and a few object rotations (Blender coordinates). Headless, never saves."""
import bpy
from mathutils import Vector
import sys, builtins
_out = open(sys.argv[sys.argv.index("--") + 1], "w")
def print(*a):
	builtins.print(*a, file=_out)

dg = bpy.context.evaluated_depsgraph_get()
ob = bpy.data.objects["sf_solar_tracker"]
ev = ob.evaluated_get(dg)
me = ev.to_mesh()
pts = [ev.matrix_world @ v.co for v in me.vertices]
hi = [p for p in pts if p.z > 0.9]
print("PROBE verts", len(pts), "deck verts", len(hi))
for xb in [-20.5, -20.2, -19.9, -19.6, -19.3, -19.0, -18.7, -18.4]:
	sel = [p for p in hi if abs(p.x - xb) < 0.15]
	if sel:
		print("PROBE x %.2f z %.3f..%.3f y %.2f..%.2f" % (xb, min(p.z for p in sel), max(p.z for p in sel), min(p.y for p in sel), max(p.y for p in sel)))
# the largest faces (deck) normals
faces = sorted(me.polygons, key=lambda f: -f.area)[:6]
for f in faces:
	n = ev.matrix_world.to_3x3() @ f.normal
	c = ev.matrix_world @ f.center
	print("PROBE face area %.3f normal (%.3f %.3f %.3f) centre (%.2f %.2f %.2f)" % (f.area, n.x, n.y, n.z, c.x, c.y, c.z))
for name in ["cr_console", "cr_console.001", "cr_chair", "mb_bed_bare", "md_heal_station", "ls_console", "pr_bat_rack", "cm_colony_computer", "cr_plot_table", "mb_ct"]:
	o = bpy.data.objects.get(name)
	if o:
		print("PROBE rot", name, tuple(round(v, 3) for v in o.matrix_world.to_euler()), tuple(round(v, 2) for v in o.matrix_world.translation))
ev.to_mesh_clear()
_out.close()
