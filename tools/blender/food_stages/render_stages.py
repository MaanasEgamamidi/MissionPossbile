"""Check images of the food and garden upgrade stages over the real map (owner rule: headless only, never save).

Rebuilds the parts written by dump_stages.gd (Godot world coordinates) inside the intact colony map and renders fixed
views of the Greenhouse bed area and the Garden dome for V1..V4 with the Workbench engine (fast, shows clipping and
floating parts clearly; materials take their colour from each map material's base colour).

Run (Blender 5.x, headless, the .blend is opened read-only and never saved):
  blender-launcher.exe -b "G:/nasa app/grand_colony_intact/grand_colony_intact.blend" --factory-startup
      --disable-autoexec --python tools/blender/food_stages/render_stages.py -- <dump.json> <out dir> [levels] [views]
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
DUMP, OUT = args[0], args[1]
LEVELS = [int(x) for x in (args[2].split(",") if len(args) > 2 else ["1", "2", "3", "4"])]
ONLY = args[3].split(",") if len(args) > 3 else []

# Godot (x, y up, z) -> Blender (x, -z, y)
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CI = C.inverted()


def B(p):
    return Vector((p[0], -p[2], p[1]))


# name: (eye, target, lens degrees or ortho scale, ortho?, hide objects with these prefixes)
VIEWS = {
    "gh_spine": ((3.4, 1.65, 4.6), (8.6, 1.9, 10.4), 74, False, ()),
    "gh_aisle": ((4.6, 1.6, 10.25), (11.5, 1.95, 10.2), 80, False, ()),
    "gh_section": ((4.4, 1.5, 9.4), (12.0, 1.5, 9.4), 6.6, True, ()),
    "gh_up": ((7.0, 1.1, 8.4), (7.6, 2.8, 10.6), 84, False, ()),
    "dome_airlock": ((44.0, 1.7, 27.0), (51.0, 0.9, 27.0), 84, False, ()),
    "dome_console": ((46.6, 1.65, 26.6), (44.15, 0.95, 24.35), 62, False, ()),
    "dome_top": ((50.0, 12.0, 27.0), (50.0, 0.0, 27.0001), 17.0, True, ("gd_shell", "gd_gantry", "rf_")),
    "dome_north": ((50.5, 1.7, 23.0), (48.0, 1.4, 19.6), 84, False, ()),
}


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_shadows = True
    sh.shadow_intensity = 0.35
    sh.show_cavity = True
    sh.cavity_type = "WORLD"
    sh.show_specular_highlight = True
    sc.render.resolution_x = 1280
    sc.render.resolution_y = 720
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    # Workbench colours come from each material's viewport colour: copy the base colour of its shader
    for m in bpy.data.materials:
        col = None
        if m.use_nodes and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    v = n.inputs["Base Color"].default_value
                    col = (v[0], v[1], v[2], 1.0)
                    break
        if col is not None:
            m.diffuse_color = col
    cam_data = bpy.data.cameras.new("fs_cam")
    cam = bpy.data.objects.new("fs_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, cam


_unit = {}


def unit_mesh(kind, ratio):
    key = (kind, round(ratio, 3))
    if key in _unit:
        return _unit[key]
    if kind == "box":
        bpy.ops.mesh.primitive_cube_add(size=1.0)
    elif kind == "cylinder":
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=1.0, radius2=ratio, depth=1.0)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=7, radius=1.0)
    o = bpy.context.active_object
    me = o.data
    me.name = "fs_unit_%s_%s" % key
    me.materials.append(None)   # one slot, filled per object (link OBJECT)
    bpy.data.objects.remove(o)
    _unit[key] = me
    return me


_mats = {}


def material(rgb, glow):
    key = (round(rgb[0], 3), round(rgb[1], 3), round(rgb[2], 3), glow > 0)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("fs_%d" % len(_mats))
    k = 1.25 if glow > 0 else 1.0
    m.diffuse_color = (min(1, rgb[0] * k), min(1, rgb[1] * k), min(1, rgb[2] * k), 1.0)
    m.roughness = 0.6
    _mats[key] = m
    return m


def build(parts, coll):
    for p in parts:
        kind = p["kind"]
        sx, sy, sz = p["size"]
        if kind == "box":
            size = Matrix.Diagonal((sx, sy, sz, 1.0))
            me = unit_mesh("box", 1.0)
        elif kind == "cylinder":
            size = Matrix.Diagonal((sx, sy, sx, 1.0))     # bottom radius, height
            me = unit_mesh("cylinder", sz / sx if sx else 1.0)
        else:
            size = Matrix.Diagonal((sx, sy * 0.5, sz, 1.0))  # radius, height/2
            me = unit_mesh("sphere", 1.0)
        colours = p.get("colours")
        for i, x in enumerate(p["xforms"]):
            g = Matrix(((x[0], x[3], x[6], x[9]), (x[1], x[4], x[7], x[10]), (x[2], x[5], x[8], x[11]), (0, 0, 0, 1)))
            # unit primitives are built in Blender axes; a Godot unit primitive's local y is Blender's z
            o = bpy.data.objects.new("fs_%s_%d" % (p["name"], i), me)
            o.matrix_world = C @ g @ size @ CI
            rgb = colours[i] if colours else p["colour"]
            coll.objects.link(o)
            o.material_slots[0].link = "OBJECT"
            o.material_slots[0].material = material(rgb, p["glow"])


def main():
    sc, cam = setup_scene()
    dump = json.load(open(DUMP))
    for lvl in LEVELS:
        coll = bpy.data.collections.new("fs_level_%d" % lvl)
        sc.collection.children.link(coll)
        build(dump["levels"][str(lvl)], coll)
        for name, (eye, tgt, lens, ortho, hide) in VIEWS.items():
            if ONLY and name not in ONLY:
                continue
            hidden = []
            for o in sc.objects:
                if hide and o.name.startswith(hide) and not o.hide_render:
                    o.hide_render = True
                    hidden.append(o)
            square = name.endswith("_top")
            sc.render.resolution_x = 1100 if square else 1280
            sc.render.resolution_y = 1100 if square else 720
            cam.location = B(eye)
            cam.rotation_euler = (B(tgt) - B(eye)).to_track_quat("-Z", "Y").to_euler()
            cam.data.type = "ORTHO" if ortho else "PERSP"
            if ortho:
                cam.data.ortho_scale = lens
            else:
                cam.data.angle = math.radians(lens)
            cam.data.clip_start = 0.05
            cam.data.clip_end = 200
            sc.render.filepath = "%s/%s_V%d.png" % (OUT, name, lvl)
            bpy.ops.render.render(write_still=True)
            for o in hidden:
                o.hide_render = False
        for o in list(coll.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(coll)
    print("RENDER OK", OUT)


if __name__ == "__main__":
    main()
