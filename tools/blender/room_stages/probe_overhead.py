"""Prints which 0.5 m plan cells of a map object hold geometry below a height (Blender coordinates). Headless, no save.
  blender ... --python probe_overhead.py -- <out.txt> <object> [<object> ...]"""
import bpy
import sys
args = sys.argv[sys.argv.index("--") + 1:]
out = open(args[0], "w")
dg = bpy.context.evaluated_depsgraph_get()
for name in args[1:]:
	ob = bpy.data.objects.get(name)
	if ob is None:
		out.write("missing %s\n" % name)
		continue
	ev = ob.evaluated_get(dg)
	me = ev.to_mesh()
	cells = {}
	for v in me.vertices:
		p = ev.matrix_world @ v.co
		key = (round(p.x * 2) / 2, round(p.y * 2) / 2)
		lo = cells.get(key, 99.0)
		cells[key] = min(lo, p.z)
	out.write("== %s cells %d\n" % (name, len(cells)))
	xs = sorted(set(k[0] for k in cells))
	ys = sorted(set(k[1] for k in cells), reverse=True)
	for y in ys:
		row = []
		for x in xs:
			z = cells.get((x, y))
			row.append("  .  " if z is None else "%5.2f" % z)
		out.write("%6.1f %s\n" % (y, " ".join(row)))
	out.write("x: %s\n" % " ".join("%5.1f" % x for x in xs))
	ev.to_mesh_clear()
out.close()
