"""Framing check of the cinematic camera paths (data/cinematics.json) IN THE INTACT MAP. Headless; the map is never saved:
  blender-launcher -b --factory-startup --disable-autoexec "G:/nasa app/grand_colony_intact/grand_colony_intact.blend"
        --python render_keyframes.py -- --proj <godot project> [--only intro,command_room] [--samples 16] [--res 960x540]

For every segment it renders the camera at the start, the middle and the end of the shot (the same eased Catmull-Rom
curve as scripts/cinematics/cinematic_rail.gd, Godot (x, y, z) -> Blender (x, -z, y), Godot's vertical FOV) into
docs/revisions/evidence/cinematics/<segment>_<a|b|c>.png, plus render_log.txt.
"""
import bpy
import json
import math
import os
import sys
import time
import traceback

from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts["--proj"]
OUT = opts.get("--out", os.path.join(PROJ, "docs", "revisions", "evidence", "cinematics"))
SAMPLES = int(opts.get("--samples", "16"))
ONLY = [p for p in opts.get("--only", "").split(",") if p]
RES = [int(v) for v in opts.get("--res", "960x540").split("x")]
FRACS = [float(v) for v in opts.get("--fracs", "0,0.5,1").split(",")]
os.makedirs(OUT, exist_ok=True)
log = []


def say(*a):
    log.append(" ".join(str(x) for x in a))
    with open(os.path.join(OUT, "render_log%s.txt" % ("_" + "_".join(ONLY) if ONLY else "")), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


def bl(g):
    return Vector((float(g[0]), -float(g[2]), float(g[1])))


def ease_io(x):
    x = min(max(x, 0.0), 1.0)
    return 0.5 - 0.5 * math.cos(math.pi * x)


def catmull(p0, p1, p2, p3, u):
    u2, u3 = u * u, u * u * u
    return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)


def seg_seconds(seg):
    return float(seg.get("seconds", seg["keys"][-1]["t"]))


def sample(seg, t):
    keys = seg["keys"]
    if len(keys) == 1:
        return Vector(keys[0]["pos"]), Vector(keys[0]["look"])
    tw = ease_io(t / max(seg_seconds(seg), 1e-4)) * float(keys[-1]["t"])
    i = 0
    while i < len(keys) - 2 and tw > float(keys[i + 1]["t"]):
        i += 1
    t0, t1 = float(keys[i]["t"]), float(keys[i + 1]["t"])
    u = min(max((tw - t0) / max(t1 - t0, 1e-4), 0.0), 1.0)
    a, b, c, d = keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, len(keys) - 1)]
    pos = catmull(Vector(a["pos"]), Vector(b["pos"]), Vector(c["pos"]), Vector(d["pos"]), u)
    look = catmull(Vector(a["look"]), Vector(b["look"]), Vector(c["look"]), Vector(d["look"]), u)
    return pos, look


try:
    T0 = time.time()
    sc = bpy.context.scene
    data = json.load(open(os.path.join(PROJ, "data", "cinematics.json"), encoding="utf-8"))
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = RES[0], RES[1], 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.eevee.taa_render_samples = SAMPLES
    except Exception:
        pass
    cam_data = bpy.data.cameras.new("CINE_cam")
    cam = bpy.data.objects.new("CINE_cam", cam_data)
    sc.collection.objects.link(cam)
    cam_data.lens_unit = "FOV"
    cam_data.sensor_fit = "VERTICAL"      # Godot Camera3D.fov is vertical (keep_aspect = KEEP_HEIGHT)
    cam_data.clip_start = 0.05
    cam_data.clip_end = 4000.0
    sc.camera = cam
    default_fov = float(data.get("camera", {}).get("fov", 62))
    for seq_id in ("intro", "tour"):
        for seg in data[seq_id]["segments"]:
            if ONLY and seg["id"] not in ONLY:
                continue
            cam_data.angle = math.radians(float(seg.get("fov", default_fov)))
            for k, frac in enumerate(FRACS):
                t = seg_seconds(seg) * frac
                pos, look = sample(seg, t)
                eye, at = bl(pos), bl(look)
                cam.location = eye
                cam.rotation_mode = "QUATERNION"
                cam.rotation_quaternion = (at - eye).to_track_quat("-Z", "Y")
                sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (seg["id"], "abcdefgh"[k]))
                t1 = time.time()
                bpy.ops.render.render(write_still=True)
                say(seg["id"], "t=%.2f" % t, "pos", [round(v, 2) for v in pos], "look", [round(v, 2) for v in look], round(time.time() - t1, 1), "s")
    say("done", round(time.time() - T0, 1), "s")
except Exception:
    say("ERROR", traceback.format_exc())
