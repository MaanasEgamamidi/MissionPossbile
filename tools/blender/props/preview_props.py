"""Studio preview of the two cassette prop glbs (assets/props), headless:
  blender-launcher -b --factory-startup --disable-autoexec --python preview_props.py -- --proj <godot project>
Writes docs/revisions/evidence/props/preview_cassette_player.png and preview_cassette_tape.png.
"""
import bpy
import math
import os
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opts = dict(zip(argv[0::2], argv[1::2]))
PROJ = opts["--proj"]
OUT = os.path.join(PROJ, "docs", "revisions", "evidence", "props")
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1280, 800
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.08, 0.085, 0.095, 1)
sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
bpy.ops.mesh.primitive_plane_add(size=6)
floor = bpy.context.active_object
fm = bpy.data.materials.new("floor")
fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.23, 0.21, 1)
floor.data.materials.append(fm)
for loc, energy in (((1.5, -2.0, 2.5), 300), ((-2.0, -1.0, 1.5), 120), ((0.5, 2.0, 2.0), 150)):
    l = bpy.data.lights.new("l", "AREA")
    l.energy = energy
    l.size = 1.5
    lo = bpy.data.objects.new("l", l)
    sc.collection.objects.link(lo)
    lo.location = loc
    lo.rotation_mode = "QUATERNION"
    lo.rotation_quaternion = (Vector((0, 0, 0.1)) - Vector(loc)).to_track_quat("-Z", "Y")
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 50


def shoot(glb, name, eye, look):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROJ, "assets", "props", glb))
    new = [o for o in bpy.data.objects if o not in before]
    cam.location = eye
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (Vector(look) - Vector(eye)).to_track_quat("-Z", "Y")
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)


shoot("cassette_player.glb", "preview_cassette_player.png", (0.35, -0.75, 0.55), (0.0, 0.0, 0.1))
shoot("cassette_tape.glb", "preview_cassette_tape.png", (0.08, -0.2, 0.22), (0.0, 0.0, 0.01))
