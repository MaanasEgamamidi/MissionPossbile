"""Rover upgrade look, preview renders (worker ROVER, 2026-11-14).

Renders the .glb files that tools/blender/rover_stages/export_preview.gd writes (the map rover sf_rover plus the add-on
parts of rover_stages.gd, in the rover body frame) from two angles each, and stitches contact sheets. Preview only:
nothing here is imported by the game, no texture is baked, no source .blend is touched (a fresh factory scene is used).

Run (headless):
  blender-launcher.exe -b --factory-startup --disable-autoexec --python tools/blender/rover_stages/render_preview.py -- \
      <glb dir> <out dir> [build names ...]
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB_DIR = os.path.abspath(argv[0]) if len(argv) > 0 else os.path.abspath("assets_src/rover_stages/preview")
OUT_DIR = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.abspath("docs/revisions/evidence/rover_stages")
ONLY = argv[2:]

RES = (960, 640)

# The map rover's materials use the game's colony_surface shader, which glTF cannot carry: give them plain colours here.
MAP_COLOURS = {
    "sf_white": (0.82, 0.82, 0.80, 0.0, 0.45, 0.0),
    "sf_win": (0.04, 0.06, 0.08, 0.2, 0.1, 0.0),
    "orange": (0.85, 0.30, 0.06, 0.0, 0.5, 0.0),
    "gunmetal": (0.16, 0.17, 0.19, 0.6, 0.45, 0.0),
    "steel_dk": (0.22, 0.23, 0.25, 0.8, 0.4, 0.0),
    "steel": (0.55, 0.56, 0.58, 0.9, 0.3, 0.0),
    "rubber": (0.03, 0.03, 0.03, 0.0, 0.9, 0.0),
    "lamp_white": (1.0, 0.97, 0.9, 0.0, 0.3, 4.0),
    "offwhite": (0.72, 0.70, 0.66, 0.0, 0.55, 0.0),
    "yellow": (0.9, 0.7, 0.08, 0.0, 0.5, 0.0),
    "kit_fl_grate": (0.12, 0.12, 0.13, 0.7, 0.5, 0.0),
    "scr_red": (0.8, 0.05, 0.03, 0.0, 0.4, 1.0),
    "sf_pv": (0.03, 0.06, 0.18, 0.4, 0.25, 0.0),
    "kit_led_amb": (1.0, 0.55, 0.1, 0.0, 0.4, 3.0),
}

VIEWS = {
    "front": (Vector((-6.6, 8.2, 4.4)), Vector((0.0, 0.0, 1.35))),
    "rear": (Vector((7.0, -8.0, 5.0)), Vector((0.0, 0.0, 1.3))),
    "side": (Vector((9.5, 0.0, 1.8)), Vector((0.0, 0.0, 1.5))),
    "back": (Vector((-1.5, -9.0, 3.6)), Vector((0.0, 0.0, 1.6))),
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = RES
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.38, 0.30, 1.0)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    # ground
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.20, 0.10, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    ground.data.materials.append(gm)
    # sun + fill
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 10))
    sun = bpy.context.active_object
    sun.data.energy = 4.0
    sun.rotation_euler = (0.75, 0.15, -0.9)
    bpy.ops.object.light_add(type="AREA", location=(-4, 6, 6))
    fill = bpy.context.active_object
    fill.data.energy = 600
    fill.data.size = 6
    fill.rotation_euler = (0.9, 0, -2.4)
    bpy.ops.object.camera_add()
    scene.camera = bpy.context.active_object
    scene.camera.data.lens = 38
    return scene


def tint_map_materials():
    for m in bpy.data.materials:
        # back faces are not drawn in the game: hide them here too, so a wrongly wound face would show as a hole
        m.use_backface_culling = True
        base = m.name.split(".")[0]
        if base not in MAP_COLOURS or not m.use_nodes:
            continue
        r, g, b, metal, rough, emit = MAP_COLOURS[base]
        p = m.node_tree.nodes.get("Principled BSDF")
        if p is None:
            continue
        # the importer feeds the mesh's vertex colour into Base Color: cut that link so the plain colour shows
        for link in list(m.node_tree.links):
            if link.to_node == p:
                m.node_tree.links.remove(link)
        p.inputs["Base Color"].default_value = (r, g, b, 1)
        p.inputs["Metallic"].default_value = metal
        p.inputs["Roughness"].default_value = rough
        if emit > 0:
            key = "Emission Color" if "Emission Color" in p.inputs else "Emission"
            p.inputs[key].default_value = (r, g, b, 1)
            p.inputs["Emission Strength"].default_value = emit


def aim(cam, at, frm):
    cam.location = frm
    cam.rotation_euler = (at - frm).to_track_quat("-Z", "Y").to_euler()


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def save_sheet(tiles, cols, path):
    h, w = tiles[0].shape[:2]
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.ones((rows * h, cols * w, 4), dtype=np.float32)
    for i, t in enumerate(tiles):
        r, c = divmod(i, cols)
        # image rows are bottom-up in Blender
        y0 = (rows - 1 - r) * h
        sheet[y0:y0 + h, c * w:(c + 1) * w] = t
    img = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    img.pixels[:] = sheet.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    names = sorted(f[:-4] for f in os.listdir(GLB_DIR) if f.endswith(".glb"))
    if ONLY:
        names = [n for n in names if n in ONLY]
    fronts = []
    for name in names:
        scene = reset_scene()
        bpy.ops.import_scene.gltf(filepath=os.path.join(GLB_DIR, name + ".glb"))
        tint_map_materials()
        tiles = []
        for view, (frm, at) in VIEWS.items():
            aim(scene.camera, at, frm)
            path = os.path.join(OUT_DIR, "_tmp_%s_%s.png" % (name, view))
            render(scene, path)
            tiles.append(load_rgba(path))
            os.remove(path)
        fronts.append(tiles[0])
        save_sheet(tiles, 2, os.path.join(OUT_DIR, "%s.png" % name))
        print("RENDERED", name)
    if len(fronts) > 1 and not ONLY:
        save_sheet(fronts, 3, os.path.join(OUT_DIR, "overview_all_builds.png"))
        print("RENDERED overview")


main()
