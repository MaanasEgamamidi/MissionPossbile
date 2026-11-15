"""Visual check of the exported broken parts IN THE MAP (owner request 2026-11-14). Headless; the map is never saved:
  blender-launcher -b --factory-startup --disable-autoexec "G:/nasa app/grand_colony_intact/grand_colony_intact.blend"
        --python render_in_map.py -- --proj <godot project> [--parts BP01,BP02] [--samples 32] [--overview 1]
        [--eye x,y,z --look x,y,z]   (Godot coordinates; use with one part only)

For every part of data/broken_parts.json, from ONE eye-level camera (1.6 m, 65 deg horizontal FOV) placed where a
player stands at the part's repair station (data/stations_repairs.json), backed away from the part along the
station direction until the part spans about a third of the frame (never out of its room):
  BPnn_fixed_in_map.png   the intact map as it is;
  BPnn_broken_in_map.png  the exported assets/broken_parts/BPnn.glb imported in place (glTF Y-up -> Blender Z-up, no
                          other transform) with the map objects it replaces hidden (BP08: the tunnel leaves cut out of a
                          copy of SFX_tunnel_inside; BP10: every Hangar object at the part's broken dust value).
The glb's flat palette materials are swapped back to the map's GC_<role> materials (bp_* ones appended from the part
.blend), so the two images differ only by the part. Also renders overview_topdown.png (roofs and glass hall hidden,
orthographic) plus overview_camera.json for annotate_in_map.py, which labels the spots and adds the locator insets.
"""
import bpy
import bmesh
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
OUT = opts.get("--out", os.path.join(PROJ, "docs", "revisions", "evidence", "broken_parts", "in_map"))
SAMPLES = int(opts.get("--samples", "32"))
ONLY = [p for p in opts.get("--parts", "").split(",") if p]
DO_OVERVIEW = opts.get("--overview", "1") == "1"
PART_DIR = r"G:\nasa app\broken_parts"
FOV = math.radians(65.0)
EYE = 1.6
os.makedirs(OUT, exist_ok=True)
log = []


LOG_NAME = "render_log%s.txt" % ("_" + "_".join(ONLY) if ONLY else "")     # one log per run: helpers render in parallel


def say(*a):
    log.append(" ".join(str(x) for x in a))
    with open(os.path.join(OUT, LOG_NAME), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


def bl(g):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((float(g[0]), -float(g[2]), float(g[1])))


# per-part camera overrides (Godot coordinates): the dome and the hangar are rooms you look across, not at one object
CAM_OVERRIDE = {
    "T08": {"eye": [50.0, 1.6, 25.6], "look": [50.0, 3.4, 33.0]},     # from the dome's middle towards the south panes
    "T11": {"eye": [15.4, 1.6, 1.4], "look": [24.5, 0.2, -5.0]},       # across the hangar floor from its south-west corner
    # backing away along the station direction would put the camera behind beds / other racks / machines:
    "T10": {"eye": [-3.6, 1.6, -12.8], "look": [-3.4, 0.9, -17.3]},    # Med Bay floor in front of the equipment wall
    "T03": {"eye": [35.8, 1.6, 5.0], "look": [36.6, 1.1, 9.3]},        # Power Room aisle in front of the switchgear
    "T06": {"eye": [2.45, 1.6, 9.5], "look": [0.85, 0.7, 9.5]},        # the aisle next to the rack (the station's aisle)
}

try:
    T0 = time.time()
    sc = bpy.context.scene
    data = json.load(open(os.path.join(PROJ, "data", "broken_parts.json"), encoding="utf-8"))
    stations = {s["id"]: s for s in json.load(open(os.path.join(PROJ, "data", "stations_repairs.json"), encoding="utf-8"))["stations"]}
    manifest = json.load(open(os.path.join(PROJ, "data", "colony_manifest.json"), encoding="utf-8"))
    rooms = {r["name"]: r for r in manifest["rooms"]}
    parts = [p for p in data["parts"] if not ONLY or p["glb"].split("/")[-1][:4] in ONLY]

    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1280, 720, 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.eevee.taa_render_samples = SAMPLES
    except Exception:
        pass

    # bp_* materials of the part files (the map has none of them)
    for p in data["parts"]:
        path = os.path.join(PART_DIR, p["part"] + ".blend")
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.materials = [n for n in src.materials if (n.startswith("GC_bp_") or n == "GC_gr_leaf_brn") and n not in bpy.data.materials]

    def gc_material(name):
        base = name.split(".")[0]
        for cand in ("GC_" + base, "GC_" + base[3:] if base.startswith("bp_") else None):
            if cand and cand in bpy.data.materials:
                return bpy.data.materials[cand]
        return None

    # import every glb into its own collection, hidden
    imported = {}
    missing_mats = set()
    for p in parts:
        key = p["glb"].split("/")[-1][:4]
        col = bpy.data.collections.new("BPX_" + key)
        sc.collection.children.link(col)
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(PROJ, "assets", "broken_parts", key + ".glb"))
        new = [o for o in bpy.data.objects if o not in before]
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            col.objects.link(o)
            if o.type == "MESH":
                for i, m in enumerate(o.data.materials):
                    g = gc_material(m.name) if m else None
                    if g is not None:
                        o.data.materials[i] = g
                    elif m is not None:
                        missing_mats.add(m.name)
            o.hide_render = True
        imported[key] = new
        say("imported", key, len(new), "objects")
    say("materials without a GC_ twin (kept flat):", sorted(missing_mats))

    # BP08: a copy of the tunnel lining without the inner door leaves (same slab as EnvironmentCollision)
    tunnel = bpy.data.objects.get("SFX_tunnel_inside")
    tunnel_full = tunnel.data if tunnel else None
    tunnel_cut = None
    if tunnel:
        bm = bmesh.new()
        bm.from_mesh(tunnel.data)
        mw = tunnel.matrix_world
        dead = []
        for f in bm.faces:
            ok = True
            for v in f.verts:
                w = mw @ v.co
                if not (20.2 - 0.012 <= w.x <= 23.8 + 0.012 and -10.65 <= w.y <= -10.30 and -0.01 <= w.z <= 3.02):
                    ok = False
                    break
            if ok:
                dead.append(f)
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        tunnel_cut = bpy.data.meshes.new("SFX_tunnel_inside_no_inner_leaves")
        for m in tunnel.data.materials:
            tunnel_cut.materials.append(m)
        bm.to_mesh(tunnel_cut)
        bm.free()
        say("tunnel cut: removed", len(dead), "leaf faces")

    cam_data = bpy.data.cameras.new("BPX_cam")
    cam = bpy.data.objects.new("BPX_cam", cam_data)
    sc.collection.objects.link(cam)
    cam_data.lens_unit = "FOV"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.angle = FOV
    cam_data.clip_start = 0.05
    cam_data.clip_end = 400.0
    sc.camera = cam

    def aim(eye, look):
        cam.location = eye
        d = look - eye
        cam.rotation_mode = "QUATERNION"
        cam.rotation_quaternion = d.to_track_quat("-Z", "Y")

    def room_of(zone):
        return rooms.get(zone)

    cams = {}
    for p in parts:
        key = p["glb"].split("/")[-1][:4]
        tid = p["task_id"]
        if "--eye" in opts and "--look" in opts:          # one-off camera from the command line (Godot x,y,z)
            eye = bl([float(v) for v in opts["--eye"].split(",")])
            look = bl([float(v) for v in opts["--look"].split(",")])
        elif tid in CAM_OVERRIDE:
            eye, look = bl(CAM_OVERRIDE[tid]["eye"]), bl(CAM_OVERRIDE[tid]["look"])
        else:
            b = p["model_bounds"]
            c, s = b["center"], b["size"]
            look = bl([c[0], min(c[1], 1.1), c[2]])
            st = stations[p["station_id"]]["position"]
            sb = bl(st)
            d = Vector((sb.x - look.x, sb.y - look.y, 0.0))
            dist0 = d.length
            d.normalize()
            w = max(s[0], s[2], s[1] * 0.8)
            dist = max(dist0, 3.0 * w / (2.0 * math.tan(FOV / 2.0)))
            r = room_of(p["zone"])
            if r:      # stay 0.3 m inside the room rectangle
                lim = dist
                for axis, lo, hi in ((0, r["x0"] + 0.3, r["x1"] - 0.3), (1, r["y0"] + 0.3, r["y1"] - 0.3)):
                    if abs(d[axis]) > 1e-6:
                        edge = hi if d[axis] > 0 else lo
                        lim = min(lim, (edge - look[axis]) / d[axis])
                dist = max(min(dist, lim), dist0)
            eye = Vector((look.x + d.x * dist, look.y + d.y * dist, sb.z + EYE))
        aim(eye, look)
        cams[key] = {"eye_godot": [round(eye.x, 3), round(eye.z, 3), round(-eye.y, 3)], "look_godot": [round(look.x, 3), round(look.z, 3), round(-look.y, 3)]}
        hide = [bpy.data.objects[n] for n in p["hide_objects"] if n in bpy.data.objects]
        # fixed: the map as it is
        sc.render.filepath = os.path.join(OUT, key + "_fixed_in_map.png")
        t = time.time()
        bpy.ops.render.render(write_still=True)
        say(key, "fixed", round(time.time() - t, 1), "s", cams[key])
        # broken: the glb in place, the replaced objects hidden
        for o in hide:
            o.hide_render = True
        for o in imported[key]:
            o.hide_render = False
        dusted = []
        if p.get("special") == "door_901" and tunnel_cut is not None:
            tunnel.data = tunnel_cut
        if p.get("special") == "dust":
            hc = bpy.data.collections.get(p["dust"]["area"])
            for o in hc.all_objects if hc else []:
                dusted.append((o, o.get("dust")))
                o["dust"] = float(p["dust"]["broken_value"])
            bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(OUT, key + "_broken_in_map.png")
        t = time.time()
        bpy.ops.render.render(write_still=True)
        say(key, "broken", round(time.time() - t, 1), "s")
        for o in hide:
            o.hide_render = False
        for o in imported[key]:
            o.hide_render = True
        if tunnel_full is not None:
            tunnel.data = tunnel_full
        for o, v in dusted:
            if v is None:
                del o["dust"]
            else:
                o["dust"] = v
    os.makedirs(os.path.join(OUT, "cams"), exist_ok=True)
    for k, v in cams.items():             # one file per part (parallel runs never share a file); annotate_in_map merges them
        json.dump(v, open(os.path.join(OUT, "cams", k + ".json"), "w"), indent=1)

    if DO_OVERVIEW:
        # top-down: roofs, the glass hall and the atmosphere volumes off
        def lc_find(lc, name):
            if lc.collection.name == name:
                return lc
            for ch in lc.children:
                f = lc_find(ch, name)
                if f:
                    return f
            return None
        for n in ("Roofs", "Glass hall", "Exterior atmosphere", "Exterior motes", "Atmosphere"):
            lc = lc_find(bpy.context.view_layer.layer_collection, n)
            if lc:
                lc.exclude = True
        x0, x1, y0, y1 = -16.0, 62.0, -40.0, 21.0          # Blender: the colony rooms + plaza + garden dome
        cam_data.type = "ORTHO"
        aspect = 1280 / 720
        scale = max(x1 - x0, (y1 - y0) * aspect)
        cam_data.ortho_scale = scale
        cam.location = Vector(((x0 + x1) / 2, (y0 + y1) / 2, 60.0))
        cam.rotation_mode = "XYZ"
        cam.rotation_euler = (0.0, 0.0, 0.0)
        sc.render.filepath = os.path.join(OUT, "overview_topdown.png")
        t = time.time()
        bpy.ops.render.render(write_still=True)
        json.dump({"center_blender": [(x0 + x1) / 2, (y0 + y1) / 2], "ortho_scale": scale, "res": [1280, 720]},
                  open(os.path.join(OUT, "overview_camera.json"), "w"), indent=1)
        say("overview", round(time.time() - t, 1), "s")
    say("done", round(time.time() - T0, 1), "s")
except Exception:
    say("ERROR", traceback.format_exc())
