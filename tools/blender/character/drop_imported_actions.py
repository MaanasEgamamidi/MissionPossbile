"""Removes actions left behind by Mixamo FBX imports ('Armature.NNN|mixamo.com|Layer0') from crew_v2.blend and saves it.
  blender -b --factory-startup --disable-autoexec crew_v2.blend --python drop_imported_actions.py -- <log.json>
"""
import bpy, sys, json
out = sys.argv[sys.argv.index("--") + 1]
gone = [a.name for a in bpy.data.actions if "|mixamo.com|" in a.name]
for n in gone:
    bpy.data.actions.remove(bpy.data.actions[n])
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_mainfile()
json.dump({"removed": gone, "actions": sorted(a.name for a in bpy.data.actions)}, open(out, "w"), indent=1)
