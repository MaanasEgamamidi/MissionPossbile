"""Prints per-frame hips and foot heights of Mixamo FBX clips (skeleton only), to choose frame ranges for retargeting.

  blender -b --factory-startup --disable-autoexec --python analyze_mixamo_fbx.py -- <out.json> <a.fbx> [<b.fbx> ...]
Also reports the crew rig's NLA tracks and fps when run with a .blend open.
"""
import bpy, sys, json, math
argv = sys.argv[sys.argv.index("--") + 1:]
OUT, FBXS = argv[0], argv[1:]
R = {"scene_fps_before": bpy.context.scene.render.fps}
arm = bpy.data.objects.get("Armature")
if arm and arm.animation_data:
    R["tracks"] = [[t.name, [[s.name, s.action.name if s.action else None, s.frame_start, s.frame_end] for s in t.strips]]
                   for t in arm.animation_data.nla_tracks]
    R["actions"] = [[a.name, a.use_fake_user, list(a.frame_range)] for a in bpy.data.actions]
    R["hips_rest"] = list(arm.data.bones["Hips"].head_local)
for fbx in FBXS:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    src = [o for o in bpy.data.objects if o not in before and o.type == 'ARMATURE'][0]
    pre = src.data.bones[0].name.split(":")[0] + ":" if ":" in src.data.bones[0].name else ""
    act = src.animation_data.action
    f0, f1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
    rows = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        w = lambda n, tail=False: src.matrix_world @ (src.pose.bones[pre + n].tail if tail else src.pose.bones[pre + n].head)
        h = w("Hips")
        rows.append({"f": f, "hip": [round(v, 3) for v in h],
                     "ankL": round(w("LeftFoot").z, 3), "ankR": round(w("RightFoot").z, 3),
                     "toeL": round(w("LeftToeBase").z, 3), "toeR": round(w("RightToeBase").z, 3),
                     "handL": round(w("LeftHand").z, 3), "handR": round(w("RightHand").z, 3),
                     "kneeLy": round(w("LeftLeg").y - h.y, 3),
                     # pelvis heading: angle of the right-minus-left thigh line from -X (0 = facing -Y)
                     "yaw": round(math.degrees(math.atan2(-(w("RightUpLeg") - w("LeftUpLeg")).y, -(w("RightUpLeg") - w("LeftUpLeg")).x)), 1),
                     "toeYawL": round(math.degrees(math.atan2((w("LeftToeBase") - w("LeftFoot")).x, -(w("LeftToeBase") - w("LeftFoot")).y)), 1),
                     "toeYawR": round(math.degrees(math.atan2((w("RightToeBase") - w("RightFoot")).x, -(w("RightToeBase") - w("RightFoot")).y)), 1)})
    R[fbx.split("\\")[-1]] = {"range": [f0, f1], "fps": bpy.context.scene.render.fps, "rows": rows}
    for o in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(o, do_unlink=True)
open(OUT, "w").write(json.dumps(R, indent=0))
