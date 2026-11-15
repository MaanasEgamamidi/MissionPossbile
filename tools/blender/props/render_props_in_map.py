"""Before / after views of the cassette props, the station markers and the airlock pressure sign IN THE MAP (owner
request 2026-11-14: no floating objects; a better cassette player). Headless; the map is never saved:
  blender-launcher -b --factory-startup --disable-autoexec "G:/nasa app/grand_colony_intact/grand_colony_intact.blend"
        --python render_props_in_map.py -- --proj <godot project> --phase before|after [--only player,tape_med_bay]
        [--samples 32]

before: rebuilds what the game drew until now, from the code that drew it (positions from
        tools/blender/props/reports/stations_before.json, the station file before this change):
        - scripts/cassettes/cassette_presenter.gd: per room cassette a box "DisplayStand" + shell + window + reels +
          label strip at the station (anchor + 1 m), unshaded, with the billboard signs "<Title>\\n<CODE> CASSETTE" and
          "E  Collect tape"; the player: stand + shell + door + three controls and "COMMAND ROOM\\nCASSETTE PLAYER";
        - scripts/world/world_collision.gd _add_foundation_marker: on every repair station an orange unshaded plate
          (0.42 x 0.27 x 0.06 m) with the billboard "T01 - Comms" style name 0.28 m above it;
        - scripts/world/airlock_hazard_presenter.gd: the pressure text floating at (22, 2.55, 10.05).
after:  the new props (assets/props/*.glb) at their surface spots (data/stations_repairs.json "prop_position" /
        "prop_yaw_deg"), the room strip recoloured and the room name printed flat on it, no markers, and the airlock
        sign as a board flat on the hangar wall.
Both phases use the same eye-level cameras (1.6 m, 65 deg horizontal FOV, Godot coordinates in SHOTS).
Billboards face the camera, as Label3D billboards do. Writes docs/revisions/evidence/props/<phase>_<shot>.png.
"""
import bpy
import json
import math
import os
import sys
import traceback

from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts["--proj"]
PHASE = opts["--phase"]
ONLY = [s for s in opts.get("--only", "").split(",") if s]
SAMPLES = int(opts.get("--samples", "32"))
OUT = os.path.join(PROJ, "docs", "revisions", "evidence", "props")
os.makedirs(OUT, exist_ok=True)
FOV = math.radians(65.0)
LOG = []


def say(*a):
    LOG.append(" ".join(str(x) for x in a))
    with open(os.path.join(PROJ, "tools", "blender", "props", "reports", "render_%s.log" % PHASE), "w", encoding="utf-8") as f:
        f.write("\n".join(LOG) + "\n")


def bl(g):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((float(g[0]), -float(g[2]), float(g[1])))


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


TAPES = {  # scripts/cassettes/cassette_catalog.gd
    "cassette_command_center": ("Command center", "CMD", "f1a35e"),
    "cassette_power_supply": ("Power supply", "PWR", "e6c85e"),
    "cassette_greenhouse": ("Greenhouse", "GRH", "79c788"),
    "cassette_green_dome": ("Green dome", "DOME", "54c9c3"),
    "cassette_med_bay": ("Med Bay", "MED", "e997aa"),
    "cassette_hangar": ("Hangar / airlock", "AIR", "8faaf0"),
}
# Eye-level cameras, Godot coordinates (same for before and after). Set from the new spots (see stations json).
SHOTS = json.load(open(os.path.join(PROJ, "tools", "blender", "props", "shots.json"), encoding="utf-8"))

try:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1280, 720, 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.eevee.taa_render_samples = SAMPLES
    except Exception:
        pass
    col = bpy.data.collections.new("PROPS_" + PHASE)
    sc.collection.children.link(col)

    cam_data = bpy.data.cameras.new("PX_cam")
    cam = bpy.data.objects.new("PX_cam", cam_data)
    sc.collection.objects.link(cam)
    cam_data.lens_unit = "FOV"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.angle = FOV
    cam_data.clip_start = 0.03
    cam_data.clip_end = 400.0
    sc.camera = cam

    MATS = {}

    def flat(hexc, unshaded=True, rough=0.6):
        key = (hexc, unshaded)
        if key in MATS:
            return MATS[key]
        m = bpy.data.materials.new("PX_" + hexc + ("_u" if unshaded else ""))
        m.use_nodes = True
        nt = m.node_tree
        p = nt.nodes.get("Principled BSDF")
        if unshaded:      # Godot SHADING_MODE_UNSHADED: the colour as is, no light
            for n in list(nt.nodes):
                if n.type != "OUTPUT_MATERIAL":
                    nt.nodes.remove(n)
            e = nt.nodes.new("ShaderNodeEmission")
            e.inputs["Color"].default_value = (*srgb(hexc), 1)
            e.inputs["Strength"].default_value = 1.0
            nt.links.new(e.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
        else:
            p.inputs["Base Color"].default_value = (*srgb(hexc), 1)
            p.inputs["Roughness"].default_value = rough
        MATS[key] = m
        return m

    def box(name, size_g, center_g, mat, yaw=0.0):
        """A box given in Godot sizes / centre."""
        me = bpy.data.meshes.new(name)
        sx, sy, sz = size_g[0] * 0.5, size_g[2] * 0.5, size_g[1] * 0.5     # Blender x, y, z half sizes
        vs = [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
        fs = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        me.from_pydata(vs, [], fs)
        o = bpy.data.objects.new(name, me)
        o.data.materials.append(mat)
        o.location = bl(center_g)
        o.rotation_euler.z = yaw
        col.objects.link(o)
        return o

    def disc(name, radius, depth, center_g, mat):
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=depth, location=bl(center_g))
        o = bpy.context.active_object
        o.name = name
        o.rotation_euler.x = 0.0          # CylinderMesh rotated PI/2 about X in Godot: axis along Godot Z = Blender -Y
        o.rotation_euler.x = math.radians(90)
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        o.data.materials.append(mat)
        return o

    BILLBOARDS = []

    def label(name, body, center_g, font_px, pixel, outline_px, color="ffffff"):
        """A Label3D billboard: centred text, white with a black outline, turned to the camera at render time."""
        objs = []
        for layer, off, hexc, push in (("_outline", outline_px * pixel * 0.5, "000000", -0.002), ("", 0.0, color, 0.0)):
            cu = bpy.data.curves.new(name + layer, "FONT")
            cu.body = body
            cu.size = font_px * pixel
            cu.align_x = "CENTER"
            cu.align_y = "CENTER"
            cu.offset = off
            o = bpy.data.objects.new(name + layer, cu)
            o.data.materials.append(flat(hexc))
            col.objects.link(o)
            o.rotation_mode = "QUATERNION"
            objs.append((o, push))
        BILLBOARDS.append((objs, bl(center_g)))
        return objs

    def flat_text(name, body, size, center_b, rot_b, hexc):
        cu = bpy.data.curves.new(name, "FONT")
        cu.body = body
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        o = bpy.data.objects.new(name, cu)
        o.data.materials.append(flat(hexc, unshaded=False, rough=0.7))
        col.objects.link(o)
        o.location = center_b
        o.rotation_euler = rot_b
        return o

    def import_glb(path, at_g, yaw_deg):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        roots = [o for o in new if o.parent is None]
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            col.objects.link(o)
        for r in roots:
            r.location = bl(at_g)
            r.rotation_mode = "XYZ"
            r.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
        return new, roots

    old = {s["id"]: s for s in json.load(open(os.path.join(PROJ, "tools", "blender", "props", "reports", "stations_before.json"), encoding="utf-8"))["stations"]}
    new = {s["id"]: s for s in json.load(open(os.path.join(PROJ, "data", "stations_repairs.json"), encoding="utf-8"))["stations"]}

    if PHASE == "before":
        for sid, s in old.items():
            st = [s["position"][0], s["position"][1] + 1.0, s["position"][2]]          # the station Area3D

            def at(dx, dy, dz, st=st):
                return [st[0] + dx, st[1] + dy, st[2] + dz]
            if s["kind"] == "repair_task":
                box(sid + "_Marker", (0.42, 0.27, 0.06), st, flat("e18b45"))
                label(sid + "_LocationLabel", s["name"], at(0, 0.28, 0), 48, 0.00125, 5)
            elif s["kind"] == "cassette_anchor":
                title, code, colour = TAPES[sid]
                box(sid + "_DisplayStand", (0.18, 0.75, 0.16), at(0, -0.49, 0), flat("1a2935"))
                box(sid + "_CassetteShell", (0.36, 0.23, 0.07), st, flat(colour))
                box(sid + "_TapeWindow", (0.27, 0.105, 0.012), at(0, 0.018, 0.042), flat("15212c"))
                for side in (-1, 1):
                    disc(sid + "_Reel%d" % side, 0.037, 0.014, at(side * 0.075, 0.02, 0.055), flat("efece0"))
                box(sid + "_LabelStrip", (0.29, 0.042, 0.014), at(0, -0.075, 0.045), flat("efece0"))
                label(sid + "_RoomLabel", "%s\n%s CASSETTE" % (title, code), at(0, 0.28, 0), 34, 0.0016, 6)
                label(sid + "_PickupLabel", "E  Collect tape", at(0, -0.24, 0), 24, 0.0016, 6)
            elif s["kind"] == "cassette_player_anchor":
                box("Player_Stand", (0.32, 0.7, 0.28), at(0, -0.48, 0), flat("1a2935"))
                box("Player_Shell", (0.58, 0.25, 0.25), st, flat("334956"))
                box("Player_Door", (0.29, 0.14, 0.02), at(-0.07, 0.02, 0.14), flat("43b8b1"))
                for i in range(3):
                    box("Player_Control%d" % i, (0.04, 0.04, 0.02), at(0.2, 0.07 - i * 0.06, 0.14), flat("f1a35e"))
                label("Player_Label", "COMMAND ROOM\nCASSETTE PLAYER", at(0, 0.34, 0), 34, 0.0016, 6)
        label("AirlockPressureSign", "EXIT VESTIBULE \u00b7 28 kPa\nSeal leaking\nSUIT REQUIRED \u00b7 safe retreat through inner door",
              [22.0, 2.55, 10.05], 38, 0.006, 10, color="ffb047")
        # the airlock sign is not a billboard: it keeps Godot's default facing (+Z)
        objs, c = BILLBOARDS.pop()
        for o, push in objs:
            o.location = c + Vector((0, -push, 0))
            o.rotation_euler = (math.radians(90), 0, 0)
            o.rotation_mode = "XYZ"
            o.rotation_euler = (math.radians(90), 0, 0)
    else:
        tape_glb = os.path.join(PROJ, "assets", "props", "cassette_tape.glb")
        player_glb = os.path.join(PROJ, "assets", "props", "cassette_player.glb")
        for sid, s in new.items():
            if s["kind"] not in ("cassette_anchor", "cassette_player_anchor"):
                continue
            pos = s.get("prop_position", s["position"])
            yaw = float(s.get("prop_yaw_deg", 0.0))
            if s["kind"] == "cassette_player_anchor":
                import_glb(player_glb, pos, yaw)
                continue
            title, code, colour = TAPES[sid]
            objs, roots = import_glb(tape_glb, pos, yaw)
            strip = flat(colour, unshaded=False, rough=0.55)
            for o in objs:
                if o.name.split(".")[0] in ("RoomStrip", "LabelLine"):
                    o.data.materials[0] = strip
            # RoomLabel: flat on the strip, reads from +Z (glb frame (0, 0.0202, -0.032), Godot)
            root = roots[0]
            bpy.context.view_layer.update()
            local = Vector((0.0, 0.032, 0.0202))       # Godot (0, 0.0202, -0.032) -> Blender
            flat_text(sid + "_RoomLabel", "%s  %s" % (code, title), 0.010, root.matrix_world @ local,
                      (0.0, 0.0, math.radians(yaw)), "1b1d20")
        # airlock sign on the hangar wall (scripts/world/airlock_hazard_presenter.gd)
        wall_z, cx, cy, w, h = 9.828, 24.85, 1.75, 1.5, 0.72
        rim = box("SignRim", (w + 0.06, h + 0.06, 0.02), (cx, cy, wall_z - 0.01), flat("e8743a", unshaded=False, rough=0.5))
        board = box("SignBoard", (w, h, 0.03), (cx, cy, wall_z - 0.015), flat("1b232b", unshaded=False, rough=0.6))
        cu = bpy.data.curves.new("SignText", "FONT")
        cu.body = "EXIT VESTIBULE \u00b7 28 kPa\nSeal leaking\nSUIT REQUIRED \u00b7 safe retreat\nthrough inner door"
        cu.size = 64 * 0.0015
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        t = bpy.data.objects.new("SignText", cu)
        t.data.materials.append(flat("ffb047"))
        col.objects.link(t)
        t.location = bl((cx, cy, wall_z - 0.032))
        t.rotation_euler = (math.radians(90), 0, math.radians(180))   # faces the hangar (-Z Godot = +Y Blender)

    def aim(eye, look):
        cam.location = eye
        cam.rotation_mode = "QUATERNION"
        cam.rotation_quaternion = (look - eye).to_track_quat("-Z", "Y")

    for shot, spec in SHOTS.items():
        if (ONLY and shot not in ONLY) or (spec.get("after_only") and PHASE == "before"):
            continue
        eye, look = bl(spec["eye"]), bl(spec["look"])
        aim(eye, look)
        bpy.context.view_layer.update()
        q = cam.matrix_world.to_quaternion()
        fwd = q @ Vector((0, 0, -1))
        for objs, c in BILLBOARDS:
            for o, push in objs:
                o.rotation_quaternion = q
                o.location = c - fwd * push
        sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (PHASE, shot))
        bpy.ops.render.render(write_still=True)
        say(PHASE, shot, spec)
    say("done")
except Exception:
    say("ERROR", traceback.format_exc())
