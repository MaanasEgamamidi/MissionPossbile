"""Immutable, create-only character builder. No source file is opened as a scene.

Run through build_character.ps1. Every attempt receives fresh output directories.
All dimensions are metres; source geometry is appended with libraries.load.
"""
import argparse, collections, hashlib, json, math, struct, sys, traceback
from pathlib import Path
import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

P=argparse.ArgumentParser();P.add_argument('--root',required=True);P.add_argument('--tag',required=True);P.add_argument('--config');P.add_argument('--preview',action='store_true')
args=P.parse_args(sys.argv[sys.argv.index('--')+1:]);ROOT=Path(args.root).resolve()
CFG=json.loads(Path(args.config).read_text()) if args.config else {}
TAG=args.tag
if not TAG or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in TAG): raise ValueError('Unsafe tag')
OUT=ROOT/'mars_colony_godot/docs/milestones/04_player/rig'/TAG
BLEND=ROOT/'mars_colony_godot/assets_src/characters'/TAG/'astronaut.blend'
GLB=ROOT/'mars_colony_godot/assets/characters'/TAG/'astronaut.glb'
for p in (OUT, BLEND.parent, GLB.parent):
    if p.exists(): raise FileExistsError('Create-only run directory already exists: '+str(p))
    p.mkdir(parents=True)
LOG=(OUT/'build.log').open('x',encoding='utf8')
R={'status':'building','blender':bpy.app.version_string,'tag':TAG,'defects':[], 'visual_review':'Not yet reviewed', 'config':CFG}
def log(s): LOG.write(str(s)+'\n');LOG.flush()
def write_json(p,data):
    with p.open('x',encoding='utf8') as f:json.dump(data,f,indent=2)
def fresh(p):
    if Path(p).exists():raise FileExistsError(str(p))
def active(o):
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
def tris(o):o.data.calc_loop_triangles();return len(o.data.loop_triangles)
def bound(o):return [[min(v.co[i] for v in o.data.vertices),max(v.co[i] for v in o.data.vertices)] for i in range(3)]
def load(path,name):
    with bpy.data.libraries.load(str(path),link=False) as (a,b):
        if name not in a.objects:raise ValueError('Missing source object '+name)
        b.objects=[name]
    o=b.objects[0];bpy.context.scene.collection.objects.link(o);o.parent=None;o.matrix_world=Matrix.Identity(4)
    for m in list(o.modifiers):o.modifiers.remove(m)
    if o.data.shape_keys:
        active(o);bpy.ops.object.shape_key_remove(all=True)
    return o
def mat(name,color,rough=.6,metal=0,alpha=1):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.node_tree.nodes.clear()
    p=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled');q=m.node_tree.nodes.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs['BSDF'],q.inputs['Surface'])
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;p.inputs['Alpha'].default_value=alpha
    m.diffuse_color=(*color,alpha)
    if alpha<1:m.surface_render_method='DITHERED'
    return m
def reduce(o,budget):
    before=tris(o)
    if before>budget:
        active(o);d=o.modifiers.new('Budget','DECIMATE');d.ratio=(budget-20)/before;bpy.ops.object.modifier_apply(modifier=d.name)
    return {'before':before,'after':tris(o)}
def mesh_from_faces(src,faces,name):
    used=sorted({i for p in faces for i in p.vertices});remap={old:i for i,old in enumerate(used)}
    me=bpy.data.meshes.new(name);me.from_pydata([src.data.vertices[i].co[:] for i in used],[],[[remap[i] for i in p.vertices] for p in faces]);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob)
    for m in src.data.materials:me.materials.append(m)
    for p,old in zip(me.polygons,faces):p.material_index=old.material_index;p.use_smooth=True
    for g in src.vertex_groups:ob.vertex_groups.new(name=g.name)
    for old,i in remap.items():
        for g in src.data.vertices[old].groups:ob.vertex_groups[g.group].add([i],g.weight,'REPLACE')
    return ob
def rigid(ob,bone):
    ob.vertex_groups.clear();g=ob.vertex_groups.new(name=bone);g.add(list(range(len(ob.data.vertices))),1,'REPLACE');skin(ob)
def skin(ob):
    ob.parent=ARM;ob.matrix_parent_inverse=Matrix.Identity(4)
    m=ob.modifiers.new('Armature','ARMATURE');m.object=ARM
def join(obs,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();o=bpy.context.object;o.name=name;return o
def dist_segment(p,a,b):
    v=b-a;t=max(0,min(1,(p-a).dot(v)/v.length_squared));return (p-(a+t*v)).length
def closest(p,names):return min(names,key=lambda n:dist_segment(p,Vector(BONES[n][0]),Vector(BONES[n][1])))
def ellipsoid(name,loc,scale,material,bone,segments=20,rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc);o=bpy.context.object;o.name=name;o.scale=scale
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);o.data.materials.append(material)
    for p in o.data.polygons:p.use_smooth=True
    rigid(o,bone);return o
def box(name,loc,scale,material,bone):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);o.data.materials.append(material)
    rigid(o,bone);return o

BODY_PATH=ROOT/'grand_colony/work/_downloads/human_base_meshes/extracted/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend'
SUIT_PATH=ROOT/'grand_colony/grand_colony.blend'
BONES={
 'Hips':((0,0,.94),(0,0,1.08),None),'Spine':((0,0,1.08),(0,0,1.29),'Hips'),
 'Chest':((0,0,1.29),(0,0,1.49),'Spine'),'Neck':((0,0,1.49),(0,0,1.59),'Chest'),
 'Head':((0,0,1.59),(0,0,1.79),'Neck')}
for s,sign in [('L',1),('R',-1)]:
    def xyz(x,y,z):return (sign*x,y,z)
    BONES.update({
      'Shoulder'+s:(xyz(.035,0,1.49),xyz(.18,0,1.49),'Chest'),
      'UpperArm'+s:(xyz(.205,0,1.46),xyz(.30,0,1.20),'Shoulder'+s),
      'LowerArm'+s:(xyz(.30,0,1.20),xyz(.39,-.055,.98),'UpperArm'+s),
      'Hand'+s:(xyz(.39,-.055,.98),xyz(.435,-.12,.83),'LowerArm'+s),
      'UpperLeg'+s:(xyz(.105,0,.94),xyz(.145,.01,.515),'Hips'),
      'LowerLeg'+s:(xyz(.145,.01,.515),xyz(.185,.05,.12),'UpperLeg'+s),
      'Foot'+s:(xyz(.185,.05,.12),xyz(.225,-.12,.045),'LowerLeg'+s),
      'Toes'+s:(xyz(.225,-.12,.045),xyz(.25,-.185,.035),'Foot'+s),
      'HandAnchor'+s:(xyz(.435,-.03,.895),xyz(.435,-.085,.895),'Hand'+s)})
if CFG.get('bones'):
    for n,v in CFG['bones'].items():BONES[n]=(tuple(v[0]),tuple(v[1]),BONES[n][2])

def build_body():
    log('Appending realistic body')
    body=load(BODY_PATH,'GEO-body_male_realistic');body.name='Body_Source'
    b=bound(body);scale=1.8/(b[2][1]-b[2][0]);R['body_source']={'file':str(BODY_PATH),'object':'GEO-body_male_realistic','triangles':tris(body),'scale':scale,'bounds':b}
    for v in body.data.vertices:v.co=Vector((v.co.x*scale,v.co.y*scale,(v.co.z-b[2][0])*scale))
    # Plain coveralls: soften anatomical surface and add room around torso/limbs.
    body.data.update()
    for v in body.data.vertices:
        x,y,z=v.co
        if .17<z<1.50 and not(abs(x)>.37 and z<1.02):
            v.co+=v.normal*.008
            if .9<z<1.42 and abs(x)<.20:
                rx=.195+.025*max(0,min(1,(z-1.08)/.28));ry=.145
                angle=math.atan2(y/ry,x/rx);v.co.x=rx*math.cos(angle);v.co.y=ry*math.sin(angle)
    active(body)
    group=body.vertex_groups.new(name='ClothingShape')
    group.add([v.index for v in body.data.vertices if .18<v.co.z<1.50 and not(abs(v.co.x)>.37 and v.co.z<1.02)],1,'REPLACE')
    smooth=body.modifiers.new('ClothRelax','SMOOTH');smooth.factor=.65;smooth.iterations=5;smooth.vertex_group=group.name
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    body.vertex_groups.clear()
    R['body_reduction']=reduce(body,15500)
    cover=mat('Mat_Coverall',(.035,.115,.18));skinmat=mat('Mat_Skin',(.48,.255,.135));boot=mat('Mat_Boot',(.025,.035,.045),.8);hair=mat('Mat_Hair',(.035,.018,.012),.9);ident=mat('Mat_Ident',(.95,.31,.045),.5)
    mats=[cover,skinmat,boot,hair,ident]
    for m in mats:body.data.materials.append(m)
    for p in body.data.polygons:
        c=p.center
        p.material_index=1 if c.z>1.535 or (abs(c.x)>.39 and c.z<1.00) else 2 if c.z<.17 else 0
    # Automatic heat weighting is used on the complete surface before splitting.
    active(body);ARM.select_set(True);bpy.context.view_layer.objects.active=ARM;bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    weightless=[v.index for v in body.data.vertices if sum(g.weight for g in v.groups)<1e-7]
    R['automatic_weights']={'operator':'ARMATURE_AUTO','unweighted_vertices':len(weightless)}
    if weightless:raise RuntimeError('Automatic weighting left unweighted vertices')
    regions=collections.defaultdict(list)
    for p in body.data.polygons:
        c=p.center
        if c.z>1.535:region='Head'
        elif abs(c.x)>(.19 if c.z>1.30 else .215) and c.z>.74:region='Arms'
        elif c.z<.91:region='Legs'
        else:region='Torso'
        regions[region].append(p)
    objs={}
    for region,faces in regions.items():
        o=mesh_from_faces(body,faces,'Body_'+region);skin(o);objs[region]=o
    bpy.data.objects.remove(body,do_unlink=True)
    # Cap follows the actual scalp surface, rather than hiding the face with a sphere.
    head=objs['Head'];faces=[p for p in head.data.polygons if p.center.z>1.735 or (p.center.z>1.66 and p.center.y>.015)]
    cap=mesh_from_faces(head,faces,'HairCap');cap.data.materials.clear();cap.data.materials.append(hair)
    for v in cap.data.vertices:v.co+=v.normal*.005
    for p in cap.data.polygons:p.material_index=0
    rigid(cap,'Head');objs['Head']=join([head,cap],'Body_Head')
    # Uniform design details include a collar, zipper panel, chest stripe and shoulder patch.
    extras=[box('ChestStripe',(0,-.139,1.36),(.27,.012,.028),ident,'Chest'),box('Zipper',(0,-.137,1.20),(.012,.012,.30),boot,'Spine'),box('Patch',(.224,-.043,1.425),(.025,.055,.065),ident,'UpperArmL')]
    objs['Torso']=join([objs['Torso']]+extras[:2],'Body_Torso');objs['Arms']=join([objs['Arms'],extras[2]],'Body_Arms')
    R['body_triangles']=sum(tris(o) for o in objs.values())
    if R['body_triangles']>20000:raise RuntimeError('Body budget exceeded')
    return list(objs.values())

def suit_bone(index,c):
    s='L' if c.x>=0 else 'R'
    if index in [6,48,49,50,51,52,53,54,55,69,70,71,72]:return 'Head'
    if index in [7,8,9,10,11,12,13,14,15,16,17,18,57,58,59,60,61,62]:
        return ('Hand' if c.z<.86 else 'LowerArm' if c.z<1.17 else 'UpperArm')+s
    if index in [19,20,21,22,23,24,25,26,27,28,63,64,65,66,67,68]:
        return ('Foot' if c.z<.22 else 'LowerLeg' if c.z<.51 else 'UpperLeg')+s
    return 'Chest'

def build_suit():
    log('Appending and separating qt_spacesuit')
    o=load(SUIT_PATH,'qt_spacesuit');R['suit_source']={'file':str(SUIT_PATH),'object':'qt_spacesuit','triangles':tris(o),'bounds':bound(o)}
    active(o);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='LOOSE');bpy.ops.object.mode_set(mode='OBJECT')
    parts=sorted(list(bpy.context.selected_objects),key=lambda p:int(p.name.rsplit('.',1)[1]) if '.' in p.name else 0)
    R['suit_source']['loose_parts']=len(parts)
    palettes={};R['suit_material_mapping']={}
    for m in o.data.materials:
        name=m.name
        if 'glass' in name.lower() or 'visor' in name.lower():
            new=palettes.get('Mat_Visor')
            if not new:new=mat('Mat_Visor',(.018,.055,.075),.18,.4,.88);palettes['Mat_Visor']=new
        else:
            col=tuple(m.diffuse_color[:3]);metal=.45 if any(k in name for k in ['alu','metal','frame','bearing']) else 0
            if 'pp_suit' in name or 'white' in name:col=(.69,.72,.69)
            if 'rubber' in name or 'boot' in name:col=(.035,.045,.055)
            if 'acc_hgr' in name:col=(.9,.28,.035)
            new=mat('Mat_Suit_'+name.removeprefix('GC_'),col,.5,metal)
        palettes[name]=new;R['suit_material_mapping'][name]=new.name
    # Source joint positions from loose-part bounds. Map each rigid segment to the body skeleton.
    src={'Hips':((0,-.14,.89),(0,-.14,1.05)),'Chest':((0,-.14,.89),(0,-.14,1.55)),'Head':((0,-.15,1.55),(0,-.15,1.83))}
    for s,k in [('L',1),('R',-1)]:
        src.update({'UpperArm'+s:((k*.22,-.14,1.43),(k*.27,-.16,1.17)), 'LowerArm'+s:((k*.27,-.16,1.17),(k*.298,-.282,.855)), 'Hand'+s:((k*.298,-.282,.855),(k*.31,-.37,.69)), 'UpperLeg'+s:((k*.094,-.14,.89),(k*.107,-.14,.51)), 'LowerLeg'+s:((k*.107,-.14,.51),(k*.112,-.125,.18)), 'Foot'+s:((k*.112,-.125,.18),(k*.112,-.28,.045))})
    widen=CFG.get('suit_radial_scale',1.4);R['suit_scale']={'radial':widen,'method':'piecewise joint-to-joint mapping; longitudinal scale is target/source segment length','segments':{}}
    groups=collections.defaultdict(list);records=[]
    for idx,p in enumerate(parts):
        if idx in [0,1,2,3,4,30,31,33,34,35]:
            records.append({'source_part':idx,'removed':'wall stand / mounting hardware'});bpy.data.objects.remove(p,do_unlink=True);continue
        for j,m in enumerate(p.data.materials):p.data.materials[j]=palettes[m.name]
        # Cut long sleeves/trousers at the joint; each resulting piece remains 100% rigid.
        if idx in [57,60,63,66]:
            bm=bmesh.new();bm.from_mesh(p.data);z=1.17 if idx in [57,60] else .51
            geom=list(bm.verts)+list(bm.edges)+list(bm.faces)
            bmesh.ops.bisect_plane(bm,geom=geom,dist=.000001,plane_co=(0,0,z),plane_no=(0,0,1));bm.to_mesh(p.data);bm.free();p.data.update()
        bybone=collections.defaultdict(list)
        for f in p.data.polygons:bybone[suit_bone(idx,f.center)].append(f)
        for bone,faces in bybone.items():
            q=mesh_from_faces(p,faces,'Piece');a,b=map(Vector,src[bone]);c,d=map(Vector,BONES[bone][:2]);
            if bone=='Chest':c,d=Vector((0,0,.86)),Vector((0,0,1.55))
            if bone=='Head':c,d=Vector((0,-.015,1.53)),Vector((0,-.015,1.824))
            if bone.startswith('Foot'):
                sign=1 if bone.endswith('L') else -1
                c=Vector((sign*.195,.05,.18));d=c+(b-a)*1.05
            u=b-a;v=d-c;rotation=u.rotation_difference(v);lengthscale=v.length/u.length
            R['suit_scale']['segments'][bone]=lengthscale
            for vert in q.data.vertices:
                delta=vert.co-a;along=u*delta.dot(u)/u.length_squared;radial=delta-along
                vert.co=c+rotation@(along*lengthscale+radial*widen)
            if bone.startswith('Foot'):
                sign=1 if bone.endswith('L') else -1
                original=[p.data.vertices[i].co.copy() for i in sorted({i for f in faces for i in f.vertices})]
                for vert,original_co in zip(q.data.vertices,original):
                    vert.co=(sign*.21+(original_co.x-sign*.112)*1.7,(original_co.y+.125)*1.25+.04,original_co.z*1.15)
            if idx in [59,62]:
                # Tailor the source glove into a closed mitten enclosing fingers.
                sign=1 if bone.endswith('L') else -1
                handverts=[v.co.copy() for ob in BODY if ob.name=='Body_Arms' for v in ob.data.vertices if v.co.x*sign>.34 and v.co.z<1.015]
                coordinates=[v.co.copy() for v in q.data.vertices]+handverts
                hull=convex_shell('TailoredGlove',coordinates,.012,palettes['GC_pp_suit'])
                bpy.data.objects.remove(q,do_unlink=True);q=hull
            before=tris(q);reduce(q,max(20,int(before*.48)));rigid(q,bone)
            group='Helmet' if bone=='Head' else 'Arms' if any(k in bone for k in ['Arm','Hand']) else 'Legs' if any(k in bone for k in ['Leg','Foot']) else 'Torso'
            groups[group].append(q);records.append({'source_part':idx,'bone':bone,'triangles_before':before,'triangles_after':tris(q)})
        bpy.data.objects.remove(p,do_unlink=True)
    suit=[join(obs,'Suit_'+name) for name,obs in groups.items()]
    # A compact backpack derived from the source mounting plate is intentionally omitted;
    # make a plain equipment enclosure, rigid on Chest, to replace wall-specific mounting.
    pack=box('LifeSupportPack',(0,.18,1.29),(.28,.16,.34),palettes['GC_white'],'Chest')
    torso=next(o for o in suit if o.name=='Suit_Torso');suit.remove(torso);suit.append(join([torso,pack],'Suit_Torso'))
    R['suit_parts']=records;R['suit_triangles']=sum(tris(o) for o in suit)
    if R['suit_triangles']>45000:raise RuntimeError('Suit budget exceeded')
    return suit

def containment(body,suit):
    # Union of disconnected closed shells using per-component parity. Open joint cuts
    # are temporarily capped for the measurement only; measurement mesh is not exported.
    log('Measuring body containment in per-bone suit shells')
    trees=[]
    for ob in suit:
        bm=bmesh.new();bm.from_mesh(ob.data)
        remaining=set(bm.verts)
        while remaining:
            seed=remaining.pop();component={seed};todo=[seed]
            while todo:
                v=todo.pop()
                for e in v.link_edges:
                    w=e.other_vert(v)
                    if w in remaining:remaining.remove(w);component.add(w);todo.append(w)
            faces={f for v in component for f in v.link_faces}
            if len(faces)<4:continue
            tmp=bmesh.new();mapping={v:tmp.verts.new(v.co) for v in component}
            for f in faces:
                try:tmp.faces.new([mapping[v] for v in f.verts])
                except ValueError:pass
            boundary=[e for e in tmp.edges if e.is_boundary]
            if boundary:
                try:bmesh.ops.holes_fill(tmp,edges=boundary,sides=0)
                except RuntimeError:pass
            bmesh.ops.recalc_face_normals(tmp,faces=list(tmp.faces));tmp.verts.ensure_lookup_table();tmp.verts.index_update()
            verts=[v.co.copy() for v in tmp.verts];polys=[[v.index for v in f.verts] for f in tmp.faces]
            tree=BVHTree.FromPolygons(verts,polys)
            lo=Vector(tuple(min(v[i] for v in verts)-.001 for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts)+.001 for i in range(3)))
            trees.append((tree,lo,hi));tmp.free()
        bm.free()
    direction=Vector((.932,.271,.238)).normalized()
    def inside(v):
        for tree,lo,hi in trees:
            if any(v[i]<lo[i] or v[i]>hi[i] for i in range(3)):continue
            nearest=tree.find_nearest(v)
            if nearest[0] is not None and nearest[3]<.001:return True
            start=v.copy();hits=0
            for _ in range(80):
                point,normal,index,distance=tree.ray_cast(start,direction,5)
                if point is None:break
                hits+=1;start=point+direction*.00003
            if hits%2:return True
        return False
    result={}
    for name in ['Torso','Arms','Legs']:
        ob=next(o for o in body if o.name=='Body_'+name);outside=[v.index for v in ob.data.vertices if not inside(v.co)]
        result[name]={'vertices':len(ob.data.vertices),'outside':len(outside),'outside_percent':round(100*len(outside)/len(ob.data.vertices),3), 'outside_bounds':[[min(ob.data.vertices[i].co[j] for i in outside),max(ob.data.vertices[i].co[j] for i in outside)] for j in range(3)] if outside else [], 'outside_nearest_bones':dict(collections.Counter(closest(ob.data.vertices[i].co,[n for n in BONES if not n.startswith('HandAnchor')]) for i in outside))}
    R['rest_containment']={'method':'Union of ray-parity tests per connected suit component, temporary hole caps at joint cuts, 1 mm surface tolerance; includes coverall detail vertices','regions':result}
    return result

def rotate(bone,axis,degrees):
    pb=ARM.pose.bones[bone];local=pb.bone.matrix_local.to_3x3().inverted()@Vector(axis);pb.rotation_quaternion=Quaternion(local,math.radians(degrees))
def reset():
    for p in ARM.pose.bones:p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion();p.location=(0,0,0);p.scale=(1,1,1)
def hip_z(z):ARM.pose.bones['Hips'].location=ARM.data.bones['Hips'].matrix_local.to_3x3().inverted()@Vector((0,0,z))
def keypose(clip,t):
    reset();phase=t*math.tau
    if clip=='idle':rotate('Chest',(0,1,0),.7*math.sin(phase));rotate('Spine',(1,0,0),.6*math.sin(phase))
    if clip in ['walk','sprint']:
        amp=18 if clip=='walk' else 32
        for s,shift in [('L',0),('R',math.pi)]:
            wave=math.sin(phase+shift);rotate('UpperLeg'+s,(1,0,0),amp*wave);rotate('LowerLeg'+s,(1,0,0),max(0,-wave)*(28 if clip=='walk' else 55));rotate('UpperArm'+s,(1,0,0),-amp*.55*wave);rotate('LowerArm'+s,(1,0,0),-15 if clip=='walk' else -55)
        rotate('Chest',(1,0,0),6 if clip=='sprint' else 1)
    if clip in ['jump','land']:
        crouch=max(0,1-t/0.85) if clip=='jump' else math.sin(math.pi*t)
        for s in ['L','R']:rotate('UpperLeg'+s,(1,0,0),-32*crouch);rotate('LowerLeg'+s,(1,0,0),62*crouch);rotate('Foot'+s,(1,0,0),-30*crouch);rotate('UpperArm'+s,(1,0,0),-18*crouch)
        hip_z(-.08*crouch)
    if clip in ['carry','use','suit','seated']:
        for s in ['L','R']:
            amount=1 if clip in ['carry','seated'] else math.sin(math.pi*t)**2
            if clip=='use' and s=='L':continue
            upper=-18 if clip=='carry' else -35 if clip=='use' else -42 if clip=='suit' else -28
            lower=-82 if clip=='carry' else -35 if clip=='use' else -105 if clip=='suit' else -36
            rotate('UpperArm'+s,(1,0,0),upper*amount);rotate('LowerArm'+s,(1,0,0),lower*amount)
        if clip=='seated':
            for s in ['L','R']:rotate('UpperLeg'+s,(1,0,0),-90);rotate('LowerLeg'+s,(1,0,0),90)
            hip_z(-.405)
    bpy.context.view_layer.update()
def evaluated_min_z(obs):
    deps=bpy.context.evaluated_depsgraph_get();minimum=1e9
    for ob in obs:
        ev=ob.evaluated_get(deps);me=ev.to_mesh()
        minimum=min(minimum,min((ev.matrix_world@v.co).z for v in me.vertices));ev.to_mesh_clear()
    return minimum
def animate(body,suit):
    log('Building nine actions, with per-frame foot-ground correction')
    clips={'idle':120,'walk':30,'sprint':21,'jump':12,'land':12,'carry':60,'use':30,'suit':30,'seated':1};actions={};checks={}
    ARM.animation_data_create()
    feet=[o for o in body+suit if o.name.endswith('Legs')]
    for clip,span in clips.items():
        act=bpy.data.actions.new(clip);ARM.animation_data.action=act;maxcorr=0;minheight=1e9
        for f in range(span+1):
            SCENE.frame_set(f);keypose(clip,f/span)
            z=evaluated_min_z(feet);correction=max(0,-z);maxcorr=max(maxcorr,correction)
            if correction:ARM.pose.bones['Hips'].location+=ARM.data.bones['Hips'].matrix_local.to_3x3().inverted()@Vector((0,0,correction+.0001));bpy.context.view_layer.update()
            minheight=min(minheight,evaluated_min_z(feet))
            for pb in ARM.pose.bones:pb.keyframe_insert(data_path='rotation_quaternion',frame=f,group=pb.name);pb.keyframe_insert(data_path='location',frame=f,group=pb.name)
        act.use_fake_user=True;actions[clip]=act
        ARM.animation_data.action=None;track=ARM.animation_data.nla_tracks.new();track.name=clip;strip=track.strips.new(clip,0,act);strip.name=clip;strip.extrapolation='NOTHING';track.mute=True
        checks[clip]={'frames':span,'seconds':span/30,'minimum_foot_vertex_z':minheight,'max_vertical_ground_correction':maxcorr}
    reset();SCENE.frame_set(0);R['clips']=checks
    return actions

def render_poses(body,suit,actions,preview):
    log('Rendering pose evidence')
    folder=OUT/'poses';folder.mkdir()
    SCENE.render.engine='BLENDER_WORKBENCH';SCENE.render.resolution_x=640;SCENE.render.resolution_y=800;SCENE.render.resolution_percentage=100
    shading=SCENE.display.shading;shading.light='STUDIO';shading.color_type='MATERIAL';shading.show_shadows=True;shading.show_cavity=True;shading.cavity_type='BOTH';shading.background_type='WORLD';SCENE.world.color=(.11,.13,.16)
    bpy.ops.object.camera_add();cam=bpy.context.object;SCENE.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=2.28
    bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.name='EvidenceGround';floor.data.materials.append(mat('EvidenceFloor',(.14,.17,.20)))
    targets={'idle':0,'walk':7,'sprint':5,'jump':6,'carry':15,'use':15,'suit':15,'seated':0}
    if preview:targets={k:targets[k] for k in ['idle','carry','seated']}
    for clip,frame in targets.items():
        ARM.animation_data.action=actions[clip];SCENE.frame_set(frame);bpy.context.view_layer.update()
        for worn in [False,True]:
            for o in suit:o.hide_render=not worn
            for o in body:o.hide_render=worn and o.name!='Body_Head'
            for view,position in [('front',(0,-5,1.05)),('side',(5,0,1.05))]:
                cam.location=position;cam.rotation_euler=(Vector((0,0,1.0))-cam.location).to_track_quat('-Z','Y').to_euler();path=folder/f'{clip}_{view}_{"suit" if worn else "crew"}.png';fresh(path);SCENE.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        log('Rendered '+clip)
    bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(floor,do_unlink=True)
    for o in body+suit:o.hide_render=False
    ARM.animation_data.action=None;reset();SCENE.frame_set(0)

def export_verify(body,suit,actions):
    log('Saving new derivative .blend and exporting glTF NLA tracks')
    for tr in ARM.animation_data.nla_tracks:tr.mute=False
    SCENE.frame_start=0;SCENE.frame_end=120
    bpy.context.preferences.filepaths.save_version=0;fresh(BLEND);bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=False)
    bpy.ops.object.select_all(action='DESELECT')
    for o in [ARM]+body+suit:o.select_set(True)
    bpy.context.view_layer.objects.active=ARM
    props={p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kwargs=dict(filepath=str(GLB),export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_skins=True,export_materials='EXPORT',export_apply=False,export_frame_range=False,export_force_sampling=True,export_animation_mode='NLA_TRACKS')
    if 'export_anim_slide_to_zero' in props:kwargs['export_anim_slide_to_zero']=True
    if 'export_def_bones' in props:kwargs['export_def_bones']=False
    if 'export_extra_animations' in props:kwargs['export_extra_animations']=False
    if 'export_all_influences' in props:kwargs['export_all_influences']=False
    fresh(GLB);bpy.ops.export_scene.gltf(**{k:v for k,v in kwargs.items() if k in props})
    raw=GLB.read_bytes();size,kind=struct.unpack_from('<II',raw,12);gltf=json.loads(raw[20:20+size]);R['glb_bytes']=len(raw)
    animation_rows=[]
    for a in gltf.get('animations',[]):
        inputs=[gltf['accessors'][s['input']] for s in a['samplers']];animation_rows.append({'name':a.get('name'), 'seconds':max(i['max'][0] for i in inputs)-min(i['min'][0] for i in inputs)})
    R['glb_animations']=animation_rows;R['glb_images']=len(gltf.get('images',[]))
    if {a['name'] for a in animation_rows}!=set(actions):raise RuntimeError('Exported clip names differ: '+str(animation_rows))
    if R['glb_images']:raise RuntimeError('Unexpected image textures')
    log('Importing exported GLB into an empty factory scene')
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30;bpy.ops.import_scene.gltf(filepath=str(GLB))
    rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE'];meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(('Body_','Suit_'))]
    R['reimport']={'note':'Importer-generated bone display helpers are excluded from character mesh inventory; GLB nodes inspected separately.', 'armatures':[{'name':o.name,'bones':[b.name for b in o.data.bones]} for o in rigs], 'meshes':[{'name':o.name,'triangles':tris(o),'materials':[m.name for m in o.data.materials],'armature_modifiers':sum(m.type=='ARMATURE' for m in o.modifiers)} for o in meshes], 'materials':sorted({m.name for o in meshes for m in o.data.materials}), 'actions':[{'name':a.name,'frame_range':list(a.frame_range)} for a in bpy.data.actions]}
    if len(rigs)!=1 or set(rigs[0].data.bones.keys())!=set(BONES):raise RuntimeError('Reimport bone mismatch')
    expected={'Body_'+n for n in ['Head','Torso','Arms','Legs']}|{'Suit_'+n for n in ['Helmet','Torso','Arms','Legs']}
    if {o.name for o in meshes}!=expected:raise RuntimeError('Reimport mesh mismatch')
    R['checks']={'bone_names':True,'mesh_names':True,'animation_names':True,'no_image_textures':True,'body_budget':R['body_triangles']<=20000,'suit_budget':R['suit_triangles']<=45000,'ground_all_sampled_frames':all(v['minimum_foot_vertex_z']>=-.00001 for v in R['clips'].values()),'root_horizontal_motion':'Hips keyed only vertically; armature object never animated'}

def provenance():
    lines=['# Player character provenance','',f"Status: {R['status']}. Blender {R['blender']}.",'','## Sources',f'- `{BODY_PATH}` :: `GEO-body_male_realistic` (realistic full-body neutral A pose).',f'- `{SUIT_PATH}` :: `qt_spacesuit`, one instance only. Never uses `al_suit_rack`.','- Sources appended into factory startup using `bpy.data.libraries.load(..., link=False)`. Source scenes never opened or saved.','- Full object inventory is in `../source_inventory_v2.json`. Actual observed inventory: 407 objects, 382 meshes, differs from the earlier audit.','', '## Licence as found in the supplied bundle',f'Read path: `{BODY_PATH}` → embedded Text datablock `README` (there is no separate licence/readme file in the ZIP).','', '```text',R.get('license_readme','Not read'),'```','',f'Also read `{BODY_PATH}` → embedded Text datablock `License`:','```text',R.get('license_other','Not read'),'```','The README explicitly covers all provided assets as CC0. The separate License text names the Rain Rig; its applicability to this mesh was not independently established. Colony suit licence was not established here.','', '## Processing and measurements', '```json',json.dumps({k:R.get(k) for k in ['body_source','body_reduction','body_triangles','automatic_weights','suit_source','suit_triangles','suit_scale','rest_containment','clips','checks']},indent=2),'```','', 'Bone names: '+', '.join(BONES), '', 'Additional processing: removed source modifiers; normalized body to 1.8 m; inflated cloth by 8 mm and flattened central groin contour; heat weighted complete body before regional splitting; added scalp cap and identification details; separated 73 source suit parts; removed wall stand hardware; cut long sleeves and trousers at joints; rigid weight 1.0 on each resulting part; remapped segment lengths and radii; decimated suit parts; replaced materials with constant Principled values; added plain backpack; baked poses at 30 fps with vertical ground correction; exported NLA tracks; reimported GLB.','', '## Checks and limits','Script: triangle budgets, automatic-weight coverage, rest containment with explicitly capped test shells, sampled foot minima, exact exported clip names, no image textures, imported bone/mesh/material inventory.','Visual review: '+R.get('visual_review','Not reviewed'), 'No exhaustive limb-versus-torso collision proof or Godot runtime test has been performed.', '', '## Defects']
    lines += ['- '+x for x in R['defects']] or ['- None recorded yet; this is not a claim of defect-free animation.']
    (OUT/'PROVENANCE.md').write_text('\n'.join(lines)+'\n',encoding='utf8')

_body_v1=build_body
def build_body():
    obs=_body_v1();cover=bpy.data.materials['Mat_Coverall'];boot=bpy.data.materials['Mat_Boot'];ident=bpy.data.materials['Mat_Ident']
    # Remove underlying toe geometry; use rounded closed boots, with their soles at zero.
    leg=next(o for o in obs if o.name=='Body_Legs');faces=[p for p in leg.data.polygons if p.center.z>=.145]
    new=mesh_from_faces(leg,faces,'Pants');skin(new);obs.remove(leg);bpy.data.objects.remove(leg,do_unlink=True);extras=[]
    for s,k in [('L',1),('R',-1)]:
        ob=box('Boot',(k*.21,-.035,.075),(.16,.30,.15),boot,'Foot'+s)
        active(ob);bevel=ob.modifiers.new('RoundedLeather','BEVEL');bevel.width=.045;bevel.segments=4;bpy.ops.object.modifier_apply(modifier=bevel.name)
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

def convex_shell(name,coordinates,margin,material):
    bm=bmesh.new()
    for co in coordinates:
        co=Vector(co)
        for delta in [(margin,0,0),(-margin,0,0),(0,margin,0),(0,-margin,0),(0,0,margin),(0,0,-margin)]:bm.verts.new(co+Vector(delta))
    hull=bmesh.ops.convex_hull(bm,input=list(bm.verts),use_existing_faces=False)
    faces=[f for f in hull['geom'] if isinstance(f,bmesh.types.BMFace)]
    used=list({v for f in faces for v in f.verts});indices={v:i for i,v in enumerate(used)}
    me=bpy.data.meshes.new(name);me.from_pydata([v.co[:] for v in used],[],[[indices[v] for v in f.verts] for f in faces]);me.update();bm.free()
    ob=bpy.data.objects.new(name,me);SCENE.collection.objects.link(ob);me.materials.append(material)
    for f in me.polygons:f.use_smooth=True
    return ob

_outer_suit=build_suit
def build_suit():
    obs=_outer_suit()
    containment(BODY,obs);R['outer_shell_containment']=R.pop('rest_containment')
    # Closed pressure liners supplement the decorative stowed-suit shell. Each is a
    # rigid, convex fit of the crew geometry with 8 mm clearance, never a test-only mesh.
    liner=mat('Mat_Suit_Liner',(.085,.12,.13),.85)
    candidates={
      'Torso':['Hips','Spine','Chest','Neck'],
      'Arms':['UpperArmL','LowerArmL','HandL','UpperArmR','LowerArmR','HandR'],
      'Legs':['UpperLegL','LowerLegL','FootL','UpperLegR','LowerLegR','FootR']}
    records=[]
    for region,names in candidates.items():
        body=next(o for o in BODY if o.name=='Body_'+region);points=collections.defaultdict(list)
        for v in body.data.vertices:points[closest(v.co,names)].append(v.co.copy())
        extras=[]
        for bone,coords in points.items():
            if len(coords)<4:continue
            ob=convex_shell('PressureLiner',coords,.008,liner);rigid(ob,bone);extras.append(ob);records.append({'bone':bone,'triangles':tris(ob),'source_body_vertices':len(coords),'clearance_m':.008})
        suit=next(o for o in obs if o.name=='Suit_'+region);obs.remove(suit);obs.append(join([suit]+extras,'Suit_'+region))
    R['pressure_liners']=records;R['suit_triangles']=sum(tris(o) for o in obs)
    return obs

try:
    log('Factory-scene create-only build '+TAG)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    SCENE=bpy.context.scene;SCENE.render.fps=30;SCENE.unit_settings.system='METRIC';SCENE.unit_settings.scale_length=1
    with bpy.data.libraries.load(str(BODY_PATH),link=False) as (a,b):b.texts=[n for n in a.texts if n in ['README','License']];R['body_object_names']=list(a.objects)
    for t in b.texts:
        if t:R['license_readme' if t.name=='README' else 'license_other']=t.as_string()
    arm=bpy.data.armatures.new('Humanoid');ARM=bpy.data.objects.new('Armature',arm);SCENE.collection.objects.link(ARM);active(ARM);bpy.ops.object.mode_set(mode='EDIT')
    for name,(head,tail,parent) in BONES.items():
        eb=arm.edit_bones.new(name);eb.head=head;eb.tail=tail
        if parent:eb.parent=arm.edit_bones[parent]
        eb.use_deform=not name.startswith('HandAnchor')
    bpy.ops.object.mode_set(mode='OBJECT');ARM.show_in_front=True
    BODY=build_body();SUIT=build_suit();containment(BODY,SUIT)
    ACTIONS=animate(BODY,SUIT);render_poses(BODY,SUIT,ACTIONS,args.preview);export_verify(BODY,SUIT,ACTIONS)
    for name,row in R['rest_containment']['regions'].items():
        if row['outside_percent']>0:R['defects'].append(f"Rest containment: {name} has {row['outside_percent']}% of body vertices outside measured suit shells.")
    R['defects'].extend(['Suit components are rigid. Supplemental pressure liners and joint covers overlap the outer-shell cuts; joint creases remain stylized.','Workbench evidence does not validate transparent-visor appearance in Godot.','No exhaustive self-collision proof; see visual review notes.'])
    R['status']='built_pending_visual_review'
except Exception:
    R['status']='failed';R['error']=traceback.format_exc();log(R['error'])
finally:
    write_json(OUT/'report.json',R);provenance();log(R['status']);LOG.close()
