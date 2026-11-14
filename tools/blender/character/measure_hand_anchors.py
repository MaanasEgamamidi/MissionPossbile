import bpy,sys,json
from pathlib import Path
from mathutils import Matrix
from mathutils.bvhtree import BVHTree
root=Path(sys.argv[sys.argv.index('--')+1]);out=root/'mars_colony_godot/docs/milestones/04_player/rig/hand_anchor_measurements.json'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(root/'mars_colony_godot/assets/characters/astronaut.glb'))
arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');arm.animation_data_clear()
for p in arm.pose.bones:p.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update();ob=bpy.data.objects['Body_Arms'];deps=bpy.context.evaluated_depsgraph_get();ev=ob.evaluated_get(deps);me=ev.to_mesh()
tree=BVHTree.FromPolygons([ev.matrix_world@v.co for v in me.vertices],[list(f.vertices) for f in me.polygons]);rows={}
for side in ['L','R']:
    anchor=arm.matrix_world@arm.pose.bones['HandAnchor'+side].head;hit=tree.find_nearest(anchor)
    rows[side]={'anchor_world':list(anchor),'nearest_body_surface':list(hit[0]),'distance_m':hit[3],'surface_offset_m':list(hit[0]-anchor)}
ev.to_mesh_clear()
with out.open('x') as f:json.dump({'method':'Rest pose nearest surface on reimported Body_Arms; this measures proximity, not anatomical palm landmarks.','hands':rows},f,indent=2)
