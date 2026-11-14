"""Second create-only revision; original pipeline is retained unmodified."""
from pathlib import Path
source=Path(__file__).with_name('character_pipeline.py').read_text(encoding='utf8')
changes={
 "xyz(.092,0,.94),xyz(.102,-.012,.515)":"xyz(.105,0,.94),xyz(.145,.01,.515)",
 "xyz(.102,-.012,.515),xyz(.108,0,.105)":"xyz(.145,.01,.515),xyz(.185,.05,.12)",
 "xyz(.108,0,.105),xyz(.108,-.13,.045)":"xyz(.185,.05,.12),xyz(.225,-.12,.045)",
 "xyz(.108,-.13,.045),xyz(.108,-.205,.035)":"xyz(.225,-.12,.045),xyz(.25,-.185,.035)",
 "xyz(.18,0,1.49),xyz(.32,-.005,1.21)":"xyz(.205,0,1.46),xyz(.30,0,1.20)",
 "xyz(.32,-.005,1.21),xyz(.413,-.025,.962)":"xyz(.30,0,1.20),xyz(.39,-.055,.98)",
 "xyz(.413,-.025,.962),xyz(.451,-.035,.827)":"xyz(.39,-.055,.98),xyz(.435,-.12,.83)",
 "if .83<z<1.04 and abs(x)<.09:v.co.y=max(v.co.y,-.105)":"if .9<z<1.42 and abs(x)<.20:\n                rx=.195+.025*max(0,min(1,(z-1.08)/.28));ry=.145\n                angle=math.atan2(y/ry,x/rx);v.co.x=rx*math.cos(angle);v.co.y=ry*math.sin(angle)",
 "c.z>1.51":"c.z>1.535",
 "'Chest':((0,-.14,1.05),(0,-.14,1.49))":"'Chest':((0,-.14,.89),(0,-.14,1.55))",
 "'Head':((0,-.15,1.55),(0,-.15,1.83))":"'Head':((0,-.15,1.55),(0,-.15,1.83))",
 "return 'Hips' if c.z<1.10 else 'Chest'":"return 'Chest'",
 "c,d=map(Vector,BONES[bone][:2]);u=b-a;":"c,d=map(Vector,BONES[bone][:2]);\n            if bone=='Chest':c,d=Vector((0,0,.86)),Vector((0,0,1.55))\n            if bone=='Head':c,d=Vector((0,-.015,1.53)),Vector((0,-.015,1.824))\n            if bone.startswith('Foot'):\n                sign=1 if bone.endswith('L') else -1\n                c=Vector((sign*.195,.05,.18));d=c+(b-a)*1.05\n            u=b-a;",
 "bone='Chest'":"bone='Chest'",
 "bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(GLB))":"bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30;bpy.ops.import_scene.gltf(filepath=str(GLB))",
 "meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']":"meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(('Body_','Suit_'))]",
 "'armatures':[{'name'":"'note':'Importer-generated bone display helpers are excluded from character mesh inventory; GLB nodes inspected separately.', 'armatures':[{'name'",
 "widen=CFG.get('suit_radial_scale',1.25)":"widen=CFG.get('suit_radial_scale',1.4)",
 "hip_z(-.405)":"hip_z(-.405)",
}
for old,new in changes.items():
    if old not in source:raise RuntimeError('Revision anchor missing: '+old)
    source=source.replace(old,new)
insert=r'''
_base_build_body=build_body
def build_body():
    obs=_base_build_body()
    # Smooth the cloth surface without touching face/hands; add structured boots and collar.
    cover=bpy.data.materials['Mat_Coverall'];boot=bpy.data.materials['Mat_Boot'];ident=bpy.data.materials['Mat_Ident']
    for ob in obs:
        if ob.name not in ['Body_Torso','Body_Legs']:continue
        group=ob.vertex_groups.new(name='ClothSmooth')
        ids=[v.index for v in ob.data.vertices if .19<v.co.z<1.48]
        if ids:group.add(ids,1,'REPLACE')
        active(ob);mod=ob.modifiers.new('GarmentSmooth','SMOOTH');mod.factor=.7;mod.iterations=8;mod.vertex_group=group.name;bpy.ops.object.modifier_apply(modifier=mod.name);ob.vertex_groups.remove(group)
    leg=next(o for o in obs if o.name=='Body_Legs');extras=[]
    for s,k in [('L',1),('R',-1)]:extras.append(ellipsoid('CrewBoot',(k*.215,-.025,.08),(.09,.185,.08),boot,'Foot'+s,24,12))
    obs.remove(leg);obs.append(join([leg]+extras,'Body_Legs'))
    bpy.ops.mesh.primitive_torus_add(major_radius=.064,minor_radius=.014,major_segments=32,minor_segments=8,location=(0,0,1.525));collar=bpy.context.object
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);collar.data.materials.append(cover);rigid(collar,'Neck')
    torso=next(o for o in obs if o.name=='Body_Torso');obs.remove(torso);obs.append(join([torso,collar],'Body_Torso'))
    R['body_triangles']=sum(tris(o) for o in obs)
    return obs
'''
source=source.replace("\ntry:\n    log('Factory-scene",insert+"\ntry:\n    log('Factory-scene")
exec(compile(source,str(Path(__file__)), 'exec'))
