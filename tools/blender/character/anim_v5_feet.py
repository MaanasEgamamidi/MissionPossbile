"""Dumps per-frame ankle and ball-of-foot positions of actions (diagnostics for stance drift).
  blender -b ... crew_v2.blend --python run_logged.py -- <log> anim_v5_feet.py <out.json> action:frames ...
Also accepts --build <build args> to first run anim_v5_build.py's clip builders without export (not used by default).
"""
import bpy, sys, json, os
argv = sys.argv[sys.argv.index("--") + 1:]
lib = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", "..", "tools", "blender", "character", "anim_v5_lib.py"))
ns = {}
exec(compile(open(lib, encoding="utf-8").read(), "anim_v5_lib.py", "exec"), ns)
out = {}
for spec in argv[1:]:
    name, frames = spec.split(":")
    rows = []
    for f in range(int(frames)):
        ns["eval_action"](bpy.data.actions[name], f)
        pbs = ns["ARM"].pose.bones
        rows.append({s: [round(v, 4) for v in list(pbs["Foot" + s].head) + list(pbs["Toes" + s].head)] for s in ("L", "R")})
    out[name] = rows
out["rest"] = {s: [round(ns["HEAD"]["Foot" + s].z, 4), round(ns["HEAD"]["Toes" + s].z, 4)] for s in ("L", "R")}
json.dump(out, open(argv[0], "w"))
