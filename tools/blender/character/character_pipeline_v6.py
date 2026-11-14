from pathlib import Path
import sys,traceback
try:
    source=Path(__file__).with_name('pipeline_resolved_v5.py').read_text(encoding='utf8')
    a=source.index('                bm=bmesh.new();bm.from_mesh(q.data)\n                for co in handverts:')
    b=source.index('            before=tris(q)',a)
    source=source[:a]+'''                coordinates=[v.co.copy() for v in q.data.vertices]+handverts
                hull=convex_shell('TailoredGlove',coordinates,.012,palettes['GC_pp_suit'])
                bpy.data.objects.remove(q,do_unlink=True);q=hull
'''+source[b:]
    source=source.replace('tmp.verts.ensure_lookup_table()','tmp.verts.ensure_lookup_table();tmp.verts.index_update()')
    source=source.replace("(k*.21,-.035,.09),(.17,.31,.18)","(k*.21,-.035,.075),(.16,.30,.15)")
    source=source.replace("bevel.width=.035;bevel.segments=3","bevel.width=.045;bevel.segments=4")
    source=source.replace("result[name]={'vertices':len(ob.data.vertices),'outside':len(outside),'outside_percent':round(100*len(outside)/len(ob.data.vertices),3)}","result[name]={'vertices':len(ob.data.vertices),'outside':len(outside),'outside_percent':round(100*len(outside)/len(ob.data.vertices),3), 'outside_bounds':[[min(ob.data.vertices[i].co[j] for i in outside),max(ob.data.vertices[i].co[j] for i in outside)] for j in range(3)] if outside else [], 'outside_nearest_bones':dict(collections.Counter(closest(ob.data.vertices[i].co,[n for n in BONES if not n.startswith('HandAnchor')]) for i in outside))}")
    source=source.replace("R['defects'].extend(['Rigid suit joint cuts can open gaps during bends; no flexible bridging fabric has been authored.'","R['defects'].extend(['Suit components are rigid. Supplemental pressure liners and joint covers overlap the outer-shell cuts; joint creases remain stylized.'")
    extra=r'''
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
'''
    source=source.replace("\ntry:\n    log('Factory-scene",extra+"\ntry:\n    log('Factory-scene")
    resolved=Path(__file__).with_name('pipeline_resolved_v6.py')
    with resolved.open('x',encoding='utf8') as f:f.write(source)
    exec(compile(source,str(resolved),'exec'))
except Exception:
    argv=sys.argv[sys.argv.index('--')+1:];root=Path(argv[argv.index('--root')+1]);tag=argv[argv.index('--tag')+1]
    with (root/'docs/milestones/04_player/rig'/f'{tag}_startup_error.log').open('x') as f:f.write(traceback.format_exc())
    raise
