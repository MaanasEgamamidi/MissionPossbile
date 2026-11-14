import bpy, sys, json
from pathlib import Path
from mathutils import Vector
root=Path(sys.argv[sys.argv.index('--')+1]);out=root/'docs/milestones/04_player/rig'
for n in ['suit_parts.json','source_suit_front.png','source_suit_side.png','parts.log']:
    if (out/n).exists(): raise RuntimeError('Existing output: '+n)
log=(out/'parts.log').open('x');log.write('Starting\n');log.flush()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
with bpy.data.libraries.load(str(root/'grand_colony/grand_colony.blend'),link=False) as (a,b): b.objects=['qt_spacesuit']
o=b.objects[0];bpy.context.scene.collection.objects.link(o);o.parent=None;o.matrix_world.identity()
bpy.context.view_layer.objects.active=o;o.select_set(True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='LOOSE');bpy.ops.object.mode_set(mode='OBJECT')
rows=[]
for o in list(bpy.context.selected_objects):
    o.data.calc_loop_triangles()
    lo=[min(v.co[i] for v in o.data.vertices) for i in range(3)];hi=[max(v.co[i] for v in o.data.vertices) for i in range(3)]
    counts={}
    for p in o.data.polygons:
        n=o.data.materials[p.material_index].name;counts[n]=counts.get(n,0)+len(p.vertices)-2
    rows.append(dict(name=o.name,bounds=[lo,hi],triangles=len(o.data.loop_triangles),materials=counts))
with (out/'suit_parts.json').open('x') as f:json.dump(rows,f,indent=2)
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=640;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True
scene.display.shading.background_type='WORLD';scene.world.color=(0.12,0.12,0.12)
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=2.2
for name,pos in [('front',(0,-5,1)),('side',(5,0,1))]:
    cam.location=pos;cam.rotation_euler=(Vector((0,-.12,.94))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(out/f'source_suit_{name}.png');bpy.ops.render.render(write_still=True)
log.write('Complete\n');log.close()
