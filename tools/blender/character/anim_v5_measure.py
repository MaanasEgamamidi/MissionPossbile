"""Measures actions of crew_v2.blend with anim_v5_lib.measure().
  blender -b ... crew_v2.blend --python run_logged.py -- <log> anim_v5_measure.py <out.json> action[:frames[:loop]] ...
"""
import bpy, sys, json, os
argv = sys.argv[sys.argv.index("--") + 1:]
lib = os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", "..", "tools", "blender", "character", "anim_v5_lib.py")
ns = {}
exec(compile(open(os.path.normpath(lib), encoding="utf-8").read(), "anim_v5_lib.py", "exec"), ns)
out = {}
for spec in argv[1:]:
    parts = spec.split(":")
    act = bpy.data.actions[parts[0]]
    frames = int(parts[1]) if len(parts) > 1 else int(round(act.frame_range[1])) + 1
    loop = len(parts) > 2 and parts[2] == "loop"
    R, rows = ns["measure"](act, frames, loop)
    out[parts[0]] = R
    out[parts[0] + "_rows"] = [{k: (round(v, 3) if isinstance(v, float) else (
        {kk: (None if vv is None else [round(x, 3) for x in vv] if hasattr(vv, "__len__") else round(vv, 2)) for kk, vv in v.items()} if isinstance(v, dict) else None))
        for k, v in r.items() if k in ("f", "gap", "hipz", "trunk", "chest_yaw", "pelvis_roll", "knee_out", "toe_out", "arms", "low")} for r in rows]
json.dump(out, open(argv[0], "w"), indent=1)
