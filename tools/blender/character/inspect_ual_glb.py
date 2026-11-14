"""Inspects a Quaternius UAL glb: armature, bones, actions, and per-action hips/foot motion.
  blender -b --factory-startup --disable-autoexec --python inspect_ual_glb.py -- <out.json> <file.glb> [action ...]
"""
import bpy, sys, json, math
argv = sys.argv[sys.argv.index("--") + 1:]
OUT, GLB, WANT = argv[0], argv[1], argv[2:]
bpy.ops.import_scene.gltf(filepath=GLB)
arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
R = {"armatures": [a.name for a in arms], "objects": [[o.name, o.type, o.parent.name if o.parent else None] for o in bpy.data.objects],
     "fps": bpy.context.scene.render.fps}
A = arms[0]
R["matrix_world"] = [list(r) for r in A.matrix_world]
R["bones"] = [[b.name, b.parent.name if b.parent else None, [round(v, 3) for v in (A.matrix_world @ b.head_local)],
               [round(v, 3) for v in (A.matrix_world @ b.tail_local)]] for b in A.data.bones]
R["actions"] = [[a.name, list(a.frame_range)] for a in bpy.data.actions]
R["nla"] = [[t.name, [s.action.name for s in t.strips]] for t in (A.animation_data.nla_tracks if A.animation_data else [])]
def setact(a):
    if A.animation_data is None: A.animation_data_create()
    for t in A.animation_data.nla_tracks: t.mute = True
    A.animation_data.action = a
    if a.slots: A.animation_data.action_slot = a.slots[0]
P = lambda n: A.matrix_world @ A.pose.bones[n].head
for name in WANT:
    act = next((a for a in bpy.data.actions if a.name == name or a.name.startswith(name)), None)
    if act is None: R[name] = "missing"; continue
    setact(act)
    f0, f1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
    rows = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        h = P("pelvis"); v = P("thigh_r") - P("thigh_l")
        rows.append({"f": f, "hip": [round(x, 3) for x in h], "root": [round(x, 3) for x in P("root")],
                     "ankL": [round(x, 3) for x in P("foot_l")], "ankR": [round(x, 3) for x in P("foot_r")],
                     "ballLz": round(P("ball_l").z, 3), "ballRz": round(P("ball_r").z, 3),
                     "handLz": round(P("hand_l").z, 3), "handRz": round(P("hand_r").z, 3),
                     "yaw": round(math.degrees(math.atan2(-v.y, -v.x)), 1)})
    R[name] = {"action": act.name, "range": [f0, f1], "rows": rows}
open(OUT, "w").write(json.dumps(R, indent=0))
