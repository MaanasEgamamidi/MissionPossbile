"""Intact copy of the colony map: the same map with every broken / damaged story prop replaced by its intact twin.

Owner request 2026-11-14: the Godot map must be the original map "without any of the impurities" (the broken parts
of the old tutorial story: burnt switchgear, alarm battery racks, broken comms console, dead ceiling lights, ...),
with intact floors in every room. The new tutorial's broken parts are built separately (G:\\nasa app\\broken_parts)
and are NOT put in this map.

Run with the SOURCE .blend loaded; the source is never saved, the result is written as a copy:
  blender-launcher -b --factory-startup --disable-autoexec G:\\nasa app\\grand_colony\\grand_colony.blend
        --python make_intact_map.py -- --out <intact.blend> --report <report.json>
Then export the copy with tools\\export_from_blender.ps1 -Blend <intact.blend>.

Object NAMES are kept (game data binds stations and records to them, e.g. "pr_swgr_burnt"); only the mesh and the
gc_asset property change. The exterior crash site of the transfer lander stays (owner's choice).
"""
import bpy
import json
import math
import sys
import time
import traceback

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
OUT = opts["--out"]
REPORT = opts.get("--report", OUT + ".json")
SCRIPTS = r"G:\nasa app\grand_colony\scripts"

# broken asset -> intact twin already used elsewhere in the map
SWAP = {
    "pr_swgr_burnt": "pr_swgr",            # Power Room: switchboard section 3 (fire)
    "pr_bat_rack_alarm": "pr_bat_rack",    # battery racks in alarm
    "pr_bat_rack_open": "pr_bat_rack",     # rack with a module pulled out
    "pr_bat_hv_alarm": "pr_bat_hv",
    "cr_console_alarm": "cr_console",      # Command Room: console with alarm screens
    "gr_rack_fault": "gr_rack",            # Greenhouse: rack tripped in the brownout (dark, fault tag)
    "gr_tray_wilt_a": "gr_tray_romaine",   # its wilted tiers (no feed, no light) -> healthy tiers
    "gr_tray_wilt_b": "gr_tray_butter_m",
    "ls_air_unit_open": "ls_air_unit",     # Life Support: air unit opened, duct hanging
    "co_meal_spill": "co_meal",            # Mess Hall: tipped mug, water spilled
    "co_chair_down": "co_chair",           # Mess Hall: chair knocked over in the aisle -> standing
    "rf_tile_lt_dead": "rf_tile_lt_lamp",  # failed ceiling lights
    "rf_tile_dk_dead": "rf_tile_dk_lamp",
    "rf_tile_eng_dead": "rf_tile_eng_lamp",
}
# twins whose fixture lights (collection "Fixture Lights", named FX_<twin>...) the swapped object gets too
LIGHTS_OF = {"gr_rack", "rf_tile_lt_lamp", "rf_tile_dk_lamp", "rf_tile_eng_lamp"}
# damage on the floor: removed
REMOVE = {"pr_scorch", "pr_barrier", "pr_ext_used"}
# rebuilt intact under the same gc_asset (no twin exists)
REBUILD = {"cm_comms_console": "cm_comms_console_ok"}

rep = {"ok": False, "started": time.strftime("%Y-%m-%d %H:%M:%S"), "source": bpy.data.filepath, "out": OUT,
       "swapped": [], "removed": [], "rebuilt": [], "lights_added": []}


def cm_comms_console_ok(b):
    """cm_comms_console as it is when it works: both bays closed, every card in, cover on, no test leads,
    radio display and status windows green."""
    import gc_kit as K
    import areas.a11_command as A
    H = 0.74
    b.bx(-0.78, -0.36, 0.0, 0.78, 0.4, 0.06, 'kit_rubber', r=0.004)
    b.bx(-0.8, -0.2, 0.06, 0.8, 0.42, H, 'cr_housing')
    b.bx(-0.8, -0.38, 0.06, 0.8, -0.2, H, 'cr_housing')
    b.bx(-0.81, -0.45, H, 0.81, 0.42, H + 0.032, 'cr_top', r=0.004)
    b.bx(-0.81, -0.465, H - 0.006, 0.81, -0.43, H + 0.036, 'kit_rubber', r=0.014)
    # two closed, vented bay fronts (left: radio drawer, right: the card cage behind its cover)
    for x0, x1 in ((-0.74, -0.06), (0.06, 0.74)):
        b.bx(x0, -0.39, 0.12, x1, -0.38, 0.68, 'cr_housing', r=0.004)
        if b.hi:
            cx = (x0 + x1) / 2
            for k in range(8):
                b.bx(cx - 0.2, -0.395, 0.3 + k * 0.03, cx + 0.2, -0.389, 0.314 + k * 0.03, 'kit_seam', r=0.0)
            b.bx(cx - 0.05, -0.405, 0.6, cx + 0.05, -0.389, 0.62, 'kit_alu', r=0.005)
            b.bx(cx + 0.24, -0.392, 0.62, cx + 0.26, -0.386, 0.635, 'kit_led_grn', r=0.0)
    # upper turret: radios + the radio display on a face tilted back ~13.5 deg
    by, bz, ty, tz = -0.1, H + 0.032, 0.08, 1.52
    b.prism([(by, bz), (ty, tz), (0.42, tz), (0.42, bz)], -0.8, 0.8, 'cr_housing', plane='YZ')
    t = math.degrees(math.atan2(ty - by, tz - bz))
    piv = (0.0, (by + ty) / 2, (bz + tz) / 2)
    tilt = -t

    def at(x, dy, z):
        q = A._rx((x, dy, z - piv[2]), tilt)
        return (q[0], piv[1] + q[1], piv[2] + q[2])
    A.tbox(b, piv, tilt, (0.0, piv[1] - 0.006, 1.15), (1.56, 0.012, 0.7), 'kit_frame', r=0.004)
    o = at(-0.36, -0.032, 1.22)
    A.monitor(b, o, 0.62, 0.36, 'scr_green', tilt=tilt, d=0.02, arm=False)                 # CARRIER OK
    if b.hi:
        for (u, v, du, dv) in ((0.0, 0.05, 0.42, 0.07), (-0.12, -0.06, 0.16, 0.025), (0.08, -0.06, 0.2, 0.025),
                               (0.0, 0.14, 0.56, 0.012), (0.0, -0.14, 0.56, 0.012)):
            A.obox(b, o, tilt, 0.0, (u, -0.0045, v), (du, 0.0012, dv), 'cr_bezel', r=0.0)
    for k, z in enumerate((1.36, 1.23, 1.1, 0.97)):
        A.tbox(b, piv, tilt, (0.42, piv[1] - 0.02, z), (0.62, 0.016, 0.115), 'cr_bezel', r=0.003)
        A.tbox(b, piv, tilt, (0.3, piv[1] - 0.03, z + 0.01), (0.16, 0.006, 0.05), 'scr_green', r=0.0)
        if b.hi:
            for j in range(3):
                A.tcyl(b, piv, tilt, (0.52 + j * 0.08, piv[1] - 0.032, z), 0.018, 0.02, 'kit_alu', seg=12)
    # desk mic on a gooseneck + handset on its hook
    b.cyl((-0.55, -0.22, H + 0.032), 0.06, 0.025, 'cr_bezel', seg=12)
    b.sweep([(-0.55, -0.22, H + 0.05), (-0.55, -0.22, H + 0.2), (-0.53, -0.27, H + 0.33), (-0.5, -0.33, H + 0.36)],
            0.006, 'kit_frame', seg=6)
    b.capsule((-0.5, -0.335, H + 0.36), (-0.49, -0.37, H + 0.355), 0.014, 'cr_bezel', seg=8)
    b.box((0.73, -0.06, 0.92), (0.05, 0.03, 0.22), 'cr_bezel', r=0.01)
    b.capsule((0.73, -0.09, 0.95), (0.73, -0.09, 1.13), 0.02, 'cr_bezel', seg=8)
    # coax risers from the turret up the wall to the roof dish
    for x in (0.55, 0.62):
        b.cyl((x, 0.36, 1.52), 0.011, 1.42, 'kit_rubber', seg=8)
    if b.hi:
        for z in (1.8, 2.3, 2.75):
            b.bx(0.5, 0.33, z, 0.67, 0.42, z + 0.03, 'kit_frame', r=0.004)
    K.sign(b, (-0.4, -0.38, 0.685), 'cmd', w=0.3, h=0.048)


def colony_objects():
    out = []

    def walk(c):
        for o in c.objects:
            if o.type == 'MESH' and 'gc_asset' in o.keys():
                out.append(o)
        for ch in c.children:
            walk(ch)
    walk(bpy.data.collections['Colony (colour)'])
    return out


try:
    if SCRIPTS not in sys.path:
        sys.path.insert(0, SCRIPTS)
    import gc_build
    gc_build._reload()
    import gc_lib as L
    L.ASSETS["cm_comms_console_ok"] = dict(cat=L.ASSETS["cm_comms_console"]["cat"], fn=cm_comms_console_ok,
                                           bevel=L.ASSETS["cm_comms_console"]["bevel"])

    objs = colony_objects()
    first = {}
    for o in objs:
        first.setdefault(str(o["gc_asset"]), o)
    fx = [l for l in bpy.data.collections["Fixture Lights"].objects if l.type == 'LIGHT']

    def lights_of(template, twin):
        inv = template.matrix_world.inverted()
        out = []
        for l in fx:
            if not l.name.startswith("FX_" + twin):
                continue
            rel = inv @ l.matrix_world
            if abs(rel.translation.x) < 1.2 and abs(rel.translation.y) < 1.2 and -3.0 < rel.translation.z < 3.0:
                out.append((l, rel))
        return out

    for o in list(objs):
        a = str(o["gc_asset"])
        if a in SWAP:
            twin = SWAP[a]
            src = first[twin]
            old_mesh = o.data.name
            o.data = src.data
            o["gc_asset"] = twin
            rec = {"object": o.name, "from": a, "to": twin, "mesh_from": old_mesh, "mesh_to": src.data.name,
                   "area": o.users_collection[0].name}
            if twin in LIGHTS_OF:
                for l, rel in lights_of(src, twin):
                    n = l.copy()
                    n.data = l.data          # same fixture (shared light data, as the other instances)
                    for c in l.users_collection:
                        c.objects.link(n)
                    n.matrix_world = o.matrix_world @ rel
                    rep["lights_added"].append({"light": n.name, "for": o.name, "copied_from": l.name,
                                                "at": [round(v, 3) for v in n.matrix_world.translation]})
            rep["swapped"].append(rec)
        elif a in REMOVE:
            rep["removed"].append({"object": o.name, "gc_asset": a, "area": o.users_collection[0].name,
                                   "at": [round(v, 3) for v in o.matrix_world.translation]})
            bpy.data.objects.remove(o)
        elif a in REBUILD:
            me = L.mesh_of(REBUILD[a], "render")
            old_mesh = o.data.name
            o.data = me
            rep["rebuilt"].append({"object": o.name, "gc_asset": a, "builder": REBUILD[a], "mesh_from": old_mesh,
                                   "mesh_to": me.name, "tris": sum(len(p.vertices) - 2 for p in me.polygons)})

    expect = {"swapped": 20, "removed": 3, "rebuilt": 1, "lights_added": 3 + 6}
    got = {k: len(rep[k]) for k in expect}
    rep["counts"] = got
    assert got == expect, "unexpected counts %s (expected %s)" % (got, expect)
    left = sorted({str(o["gc_asset"]) for o in colony_objects()} & (set(SWAP) | REMOVE))
    assert not left, "broken assets still placed: %s" % left
    bpy.ops.wm.save_as_mainfile(filepath=OUT, copy=True, compress=True)
    rep["ok"] = True
except Exception:
    rep["error"] = traceback.format_exc()
rep["finished"] = time.strftime("%Y-%m-%d %H:%M:%S")
with open(REPORT, "w", encoding="utf-8") as f:
    json.dump(rep, f, indent=1)
print("MAKE_INTACT", "ok" if rep["ok"] else "FAILED")
