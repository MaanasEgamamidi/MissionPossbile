"""Resolve immutable prototypes into a standalone, create-only production script."""
from pathlib import Path
import traceback,sys
try:
    code=Path(__file__).with_name('character_pipeline_v2.py').read_text(encoding='utf8')
    code=code.replace(' "bone=\'Chest\'":"bone=\'Chest\'",\n','')
    code=code.replace("exec(compile(source,str(Path(__file__)), 'exec'))",'RESOLVED=source')
    ns={'__file__':__file__};exec(compile(code,__file__,'exec'),ns);source=ns['RESOLVED']
    start=source.index('\n_base_build_body=build_body');end=source.index("\ntry:\n    log('Factory-scene",start)
    source=source[:start]+source[end:]
    source=source.replace("R['body_reduction']=reduce(body,16500)","""active(body)
    group=body.vertex_groups.new(name='ClothingShape')
    group.add([v.index for v in body.data.vertices if .18<v.co.z<1.50 and not(abs(v.co.x)>.37 and v.co.z<1.02)],1,'REPLACE')
    smooth=body.modifiers.new('ClothRelax','SMOOTH');smooth.factor=.65;smooth.iterations=5;smooth.vertex_group=group.name
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    body.vertex_groups.clear()
    R['body_reduction']=reduce(body,15500)""")
    source=source.replace("if c.z>1.535:region='Head'","if c.z>1.535:region='Head'")
    source=source.replace("before=tris(q);reduce(q,max(20,int(before*.48)));rigid(q,bone)","""if bone.startswith('Foot'):
                sign=1 if bone.endswith('L') else -1
                original=[p.data.vertices[i].co.copy() for i in sorted({i for f in faces for i in f.vertices})]
                for vert,original_co in zip(q.data.vertices,original):
                    vert.co=(sign*.21+(original_co.x-sign*.112)*1.7,(original_co.y+.125)*1.25+.04,original_co.z*1.15)
            if idx in [59,62]:
                # Tailor the source glove into a closed mitten enclosing fingers.
                sign=1 if bone.endswith('L') else -1
                handverts=[v.co.copy() for ob in BODY if ob.name=='Body_Arms' for v in ob.data.vertices if v.co.x*sign>.34 and v.co.z<1.015]
                bm=bmesh.new();bm.from_mesh(q.data)
                for co in handverts:
                    for delta in [(0,0,.012),(0,0,-.012),(.012,0,0),(-.012,0,0),(0,.012,0),(0,-.012,0)]:bm.verts.new(co+Vector(delta))
                result=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
                unused=list(result.get('geom_interior',[]))+list(result.get('geom_unused',[]))
                if unused:bmesh.ops.delete(bm,geom=list(set(unused)),context='VERTS')
                bm.to_mesh(q.data);bm.free();q.data.update()
                for poly in q.data.polygons:poly.material_index=list(q.data.materials).index(palettes['GC_pp_suit'])
            before=tris(q);reduce(q,max(20,int(before*.48)));rigid(q,bone)""")
    source=source.replace("'Head':((0,-.15,1.55),(0,-.15,1.83))","'Head':((0,-.15,1.55),(0,-.15,1.83))")
    source=source.replace("crouch=math.sin(t*math.pi) if clip=='jump' else 1-t","crouch=max(0,1-t/0.85) if clip=='jump' else math.sin(math.pi*t)")
    source=source.replace("'No exhaustive self-collision proof; visual review still required.'","'No exhaustive self-collision proof; see visual review notes.'")
    extra=r'''
_body_v1=build_body
def build_body():
    obs=_body_v1();cover=bpy.data.materials['Mat_Coverall'];boot=bpy.data.materials['Mat_Boot'];ident=bpy.data.materials['Mat_Ident']
    # Remove underlying toe geometry; use rounded closed boots, with their soles at zero.
    leg=next(o for o in obs if o.name=='Body_Legs');faces=[p for p in leg.data.polygons if p.center.z>=.145]
    new=mesh_from_faces(leg,faces,'Pants');skin(new);obs.remove(leg);bpy.data.objects.remove(leg,do_unlink=True);extras=[]
    for s,k in [('L',1),('R',-1)]:
        ob=box('Boot',(k*.21,-.035,.09),(.17,.31,.18),boot,'Foot'+s)
        active(ob);bevel=ob.modifiers.new('RoundedLeather','BEVEL');bevel.width=.035;bevel.segments=3;bpy.ops.object.modifier_apply(modifier=bevel.name)
        for p in ob.data.polygons:p.use_smooth=True
        extras.append(ob)
    obs.append(join([new]+extras,'Body_Legs'))
    torso=next(o for o in obs if o.name=='Body_Torso')
    # Replace buried straight stripe with a curved raised stripe on the garment front.
    faces=[p for p in torso.data.polygons if not(torso.data.materials[p.material_index].name in ['Mat_Ident','Mat_Boot'])]
    new=mesh_from_faces(torso,faces,'CoverallTop');skin(new);obs.remove(torso);bpy.data.objects.remove(torso,do_unlink=True)
    verts=[];faces=[]
    for z in [1.365,1.397]:
        for i in range(17):
            angle=math.radians(225+90*i/16);verts.append((.216*math.cos(angle),.151*math.sin(angle),z))
    for i in range(16):faces.append((i,i+1,i+18,i+17))
    me=bpy.data.meshes.new('CurvedIdent');me.from_pydata(verts,[],faces);me.materials.append(ident);stripe=bpy.data.objects.new('CurvedIdent',me);SCENE.collection.objects.link(stripe);rigid(stripe,'Chest')
    bpy.ops.mesh.primitive_torus_add(major_radius=.064,minor_radius=.014,major_segments=32,minor_segments=8,location=(0,0,1.525));collar=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);collar.data.materials.append(cover);rigid(collar,'Neck')
    obs.append(join([new,stripe,collar],'Body_Torso'))
    R['body_triangles']=sum(tris(o) for o in obs)
    return obs

_suit_v1=build_suit
def build_suit():
    obs=_suit_v1();material=bpy.data.materials['Mat_Suit_pp_bearing'];groups={'Arms':[],'Legs':[]}
    for s in ['L','R']:
        for prefix,radius,group in [('LowerArm',.105,'Arms'),('LowerLeg',.125,'Legs'),('UpperLeg',.135,'Legs')]:
            bone=prefix+s;ob=ellipsoid('JointCover',BONES[bone][0],(radius,radius,radius),material,bone,20,12);groups[group].append(ob)
    for region,extras in groups.items():
        ob=next(o for o in obs if o.name=='Suit_'+region);obs.remove(ob);obs.append(join([ob]+extras,'Suit_'+region))
    R['suit_triangles']=sum(tris(o) for o in obs)
    return obs

def aim_bone(name,head,tail):
    pb=ARM.pose.bones[name];rest=pb.bone.matrix_local.to_quaternion();direction=pb.bone.tail_local-pb.bone.head_local
    quat=direction.rotation_difference(tail-head)@rest;pb.matrix=Matrix.Translation(head)@quat.to_matrix().to_4x4();bpy.context.view_layer.update()
def arm_ik(s,target,pole,hand_direction):
    upper=ARM.pose.bones['UpperArm'+s];lower=ARM.pose.bones['LowerArm'+s]
    start=upper.head.copy();l1=upper.bone.length;l2=lower.bone.length;direction=target-start;distance=min(direction.length,l1+l2-.001);direction.normalize();target=start+direction*distance
    u=pole-start;u-=direction*u.dot(direction);u.normalize();a=(l1*l1-l2*l2+distance*distance)/(2*distance);h=math.sqrt(max(0,l1*l1-a*a));elbow=start+direction*a+u*h
    aim_bone('UpperArm'+s,start,elbow);aim_bone('LowerArm'+s,elbow,target);aim_bone('Hand'+s,target,target+hand_direction.normalized()*.1)
_pose_v1=keypose
def keypose(clip,t):
    _pose_v1(clip,t)
    if clip not in ['carry','use','suit','seated']:return
    # First restore arm rotations, then solve elbows from explicit hand targets.
    for s in ['L','R']:
        for prefix in ['UpperArm','LowerArm','Hand']:ARM.pose.bones[prefix+s].rotation_quaternion=Quaternion()
    bpy.context.view_layer.update()
    for s,k in [('L',1),('R',-1)]:
        if clip=='use' and s=='L':continue
        rest=ARM.pose.bones['Hand'+s].head.copy();direction=Vector((0,-1,0))
        if clip=='carry':target=Vector((k*.25,-.36,1.27))
        elif clip=='seated':target=Vector((k*.23,-.29,.63));direction=Vector((0,-1,-.28))
        elif clip=='use':target=rest.lerp(Vector((k*.24,-.49,1.31)),math.sin(math.pi*t)**2)
        else:
            points=[(0,rest),(.3,Vector((k*.19,-.29,1.34))),(.65,Vector((k*.16,-.23,1.54))),(1,rest)]
            for (ta,pa),(tb,pb) in zip(points,points[1:]):
                if ta<=t<=tb:
                    blend=(t-ta)/(tb-ta);blend=blend*blend*(3-2*blend);target=pa.lerp(pb,blend);break
            direction=Vector((0,-.1,1))
        arm_ik(s,target,Vector((k*.8,-.08,1.0)),direction)
    bpy.context.view_layer.update()
'''
    source=source.replace("\ntry:\n    log('Factory-scene",extra+"\ntry:\n    log('Factory-scene")
    resolved=Path(__file__).with_name('pipeline_resolved_v5.py')
    with resolved.open('x',encoding='utf8') as f:f.write(source)
    exec(compile(source,str(resolved),'exec'))
except Exception:
    argv=sys.argv[sys.argv.index('--')+1:];root=Path(argv[argv.index('--root')+1]);tag=argv[argv.index('--tag')+1]
    with (root/'mars_colony_godot/docs/milestones/04_player/rig'/f'{tag}_startup_error.log').open('x') as f:f.write(traceback.format_exc())
    raise
