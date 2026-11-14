"""Independent verification of the actual GLB, without opening any .blend."""
import bpy,json,sys,traceback,hashlib
from pathlib import Path
from mathutils import Vector
root=Path(sys.argv[sys.argv.index('--')+1]);tag=sys.argv[sys.argv.index('--')+2]
glb=root/'mars_colony_godot/assets/characters'/tag/'astronaut.glb';out=root/'mars_colony_godot/docs/milestones/04_player/rig'/(tag+'_glb_validation')
if out.exists():raise FileExistsError(out)
out.mkdir();log=(out/'verify.log').open('x');r={'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest()}
try:
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.render.fps=30;bpy.ops.import_scene.gltf(filepath=str(glb))
    arm=next(o for o in scene.objects if o.type=='ARMATURE');meshes=[o for o in scene.objects if o.type=='MESH' and o.name.startswith(('Body_','Suit_'))]
    for o in scene.objects:
        if o.type=='MESH' and o not in meshes:o.hide_render=True
    for tr in arm.animation_data.nla_tracks:tr.mute=True
    actions={a.name:a for a in bpy.data.actions};r['weights']={}
    for o in meshes:
        weights=[[g.weight for g in v.groups if g.weight>1e-7] for v in o.data.vertices]
        r['weights'][o.name]={'unweighted':sum(not w for w in weights),'maximum_influences':max(map(len,weights)), 'maximum_sum_error':max(abs(sum(w)-1) for w in weights)}
    r['animated_ground']={}
    for name,act in actions.items():
        arm.animation_data.action=act
        if act.slots:arm.animation_data.action_slot=act.slots[0]
        minz=1e9;maxrootxy=0
        for frame in range(round(act.frame_range[0]),round(act.frame_range[1])+1):
            scene.frame_set(frame);bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
            for o in meshes:
                if not o.name.endswith('Legs'):continue
                ev=o.evaluated_get(deps);me=ev.to_mesh();minz=min(minz,min((ev.matrix_world@v.co).z for v in me.vertices));ev.to_mesh_clear()
            pos=arm.matrix_world@arm.pose.bones['Hips'].head;maxrootxy=max(maxrootxy,abs(pos.x),abs(pos.y))
        r['animated_ground'][name]={'minimum_world_z':minz,'maximum_hips_horizontal_offset':maxrootxy,'seconds':float((act.frame_range[1]-act.frame_range[0])/30)}
        log.write(name+' checked\n');log.flush()
    scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=640;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.background_type='WORLD';scene.world.color=(.11,.13,.16)
    bpy.ops.object.camera_add(location=(5,0,1.05));cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=2.28;cam.rotation_euler=(Vector((0,0,1))-cam.location).to_track_quat('-Z','Y').to_euler()
    for name,frame in [('carry',15),('sprint',5),('seated',0)]:
        arm.animation_data.action=actions[name]
        if actions[name].slots:arm.animation_data.action_slot=actions[name].slots[0]
        scene.frame_set(frame)
        for worn in [False,True]:
            for o in meshes:o.hide_render=(not worn) if o.name.startswith('Suit_') else (worn and o.name!='Body_Head')
            scene.render.filepath=str(out/f'{name}_side_{"suit" if worn else "crew"}.png');bpy.ops.render.render(write_still=True)
    r['passed']=all(v['minimum_world_z']>=-.0001 for v in r['animated_ground'].values()) and all(v['unweighted']==0 and v['maximum_sum_error']<1e-5 for v in r['weights'].values())
except Exception:r['passed']=False;r['error']=traceback.format_exc();log.write(r['error'])
finally:
    with (out/'validation.json').open('x') as f:json.dump(r,f,indent=2)
    log.close()
