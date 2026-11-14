"""Create the standalone final builder without changing earlier scripts."""
from pathlib import Path
import sys,traceback
root=Path(sys.argv[sys.argv.index('--')+1])
out=root/'mars_colony_godot/docs/milestones/04_player/rig'
with (out/'prepare_final.log').open('x',encoding='utf8') as log:
    try:
        source=Path(__file__).with_name('pipeline_resolved_v6.py').read_text(encoding='utf8')
        source=source.replace("R['body_reduction']=reduce(body,15500)","""R['body_reduction']=reduce(body,15500)
    bm=bmesh.new();bm.from_mesh(body.data)
    for cut in [1.535,.98]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=(0,0,cut),plane_no=(0,0,1))
    bm.to_mesh(body.data);bm.free();body.data.update()""")
        source=source.replace("(abs(c.x)>.39 and c.z<1.00)","(abs(c.x)>.30 and c.z<.98)")
        source=source.replace("'jump':6","'jump':0")
        source=source.replace("for delta in [(margin,0,0),(-margin,0,0),(0,margin,0),(0,-margin,0),(0,0,margin),(0,0,-margin)]:bm.verts.new(co+Vector(delta))","for delta in [(margin,0,0),(-margin,0,0),(0,margin,0),(0,-margin,0),(0,0,margin),(0,0,-margin)]:\n            point=co+Vector(delta);point.z=max(0,point.z);bm.verts.new(point)")
        source=source.replace("for tr in ARM.animation_data.nla_tracks:tr.mute=False\n    SCENE.frame_start", "for tr in ARM.animation_data.nla_tracks:tr.mute=True\n    SCENE.frame_start")
        source=source.replace("bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=False)\n    bpy.ops.object.select_all", "bpy.ops.wm.save_as_mainfile(filepath=str(BLEND),check_existing=False)\n    for tr in ARM.animation_data.nla_tracks:tr.mute=False\n    bpy.ops.object.select_all")
        source=source.replace("R['glb_animations']=animation_rows;R['glb_images']=len(gltf.get('images',[]))", """R['glb_animations']=animation_rows;R['glb_images']=len(gltf.get('images',[]))
    R['glb_sha256']=hashlib.sha256(raw).hexdigest()
    R['glb_mesh_nodes']=[n.get('name') for n in gltf['nodes'] if 'mesh' in n]
    expected_nodes={'Body_'+n for n in ['Head','Torso','Arms','Legs']}|{'Suit_'+n for n in ['Helmet','Torso','Arms','Legs']}
    if set(R['glb_mesh_nodes'])!=expected_nodes:raise RuntimeError('Unexpected GLB mesh nodes')
    R['outputs']={'blend':str(BLEND),'glb':str(GLB),'poses':str(OUT/'poses')}""")
        source=source.replace("BODY=build_body();SUIT=build_suit();containment(BODY,SUIT)","""BODY=build_body();SUIT=build_suit();containment(BODY,SUIT)
    if R['body_triangles']>20000 or R['suit_triangles']>45000:raise RuntimeError('Final geometry budget exceeded')
    R['bone_names']=list(BONES)
    R['source_sha256_before']={str(p):hashlib.file_digest(p.open('rb'),'sha256').hexdigest() for p in [BODY_PATH,SUIT_PATH]}
    R['mesh_weight_checks']={}
    for ob in BODY+SUIT:
        weights=[[g.weight for g in v.groups if g.weight>1e-6 and ob.vertex_groups[g.group].name in BONES] for v in ob.data.vertices]
        R['mesh_weight_checks'][ob.name]={'unweighted':sum(not w for w in weights),'max_influences':max(map(len,weights)), 'max_sum_error':max(abs(sum(w)-1) for w in weights)}
        if ob.name.startswith('Suit_') and any(len(w)!=1 or abs(w[0]-1)>1e-5 for w in weights):raise RuntimeError('Non-rigid suit weights')""")
        source=source.replace("R['status']='built_pending_visual_review'", """R['source_sha256_after']={str(p):hashlib.file_digest(p.open('rb'),'sha256').hexdigest() for p in [BODY_PATH,SUIT_PATH]}
    R['checks']['source_hashes_unchanged']=R['source_sha256_before']==R['source_sha256_after']
    R['status']='built_pending_visual_review'""")
        extra=r'''
def provenance():
    lines=['# Player character provenance','',f"Status: {R['status']}; Blender {R['blender']}; coordinate system: Blender Z up, facing -Y; GLB +Y up.",'','## Exact sources',f'- `{BODY_PATH}` :: `GEO-body_male_realistic`, realistic full-body A pose.',f'- `{SUIT_PATH}` :: `qt_spacesuit`, one instance. `al_suit_rack` is not loaded.','- Read-only references: `docs/milestones/01_audit/asset_readiness.md`, section 6, and `mars_colony_godot/tools/export_from_blender.ps1`.','- Appended into a factory scene via `bpy.data.libraries.load(path, link=False)`; source scenes never opened or saved.','- Source object names are listed in this run report and `../source_inventory_v2.json`. The supplied bundle actually yielded 407 object names / 382 meshes, differing from the old 227-mesh audit.','', '## Licence text found in the bundle',f'Path read: `{BODY_PATH}` → embedded Text datablock `README`. ZIP and extracted-file inventories had no separate README/licence file.','```text',R.get('license_readme','Unavailable'),'```',f'Also read `{BODY_PATH}` → embedded Text datablock `License`:','```text',R.get('license_other','Unavailable'),'```','The README states CC0 for the provided assets. The separate License text names the Rain Rig and CC BY 4.0; its applicability to this mesh was not independently established. No licence for the colony suit was established in this task.','', '## Processing',
    '1. Removed modifiers and shape keys from the appended body; normalized the base to 1.800 m. Inflated clothed regions by 8 mm, relaxed the mesh, and shaped the torso into a plain coverall. Decimated before automatic heat weights; cut collar and cuffs; assigned constant coverall/skin/boot materials.',
    '2. Used ARMATURE_AUTO on the complete body, checked weight coverage, then split into Body_Head, Body_Torso, Body_Arms and Body_Legs. Added a scalp hair cap, raised collar, curved specialist chest stripe, shoulder patch and closed rounded boots; underlying bare foot faces removed.',
    '3. Split qt_spacesuit into 73 loose parts. Removed 10 wall-stand/mounting pieces (exact indices in report). Divided long sleeves and trousers at elbow/knee planes, then mapped source segments to the body joints with recorded length scales and radial scale 1.4. Kept each resulting piece rigidly weighted to one bone. Boots use a separate recorded fit: source-centred X ×1.7, Y ×1.25, Z ×1.15; centres X ±0.21, Y +0.04. Tailored source gloves into closed convex mittens using body-hand clearance.',
    '4. Reduced source suit pieces to approximately 48% (small pieces have a 20-triangle target floor). Added a simple life-support backpack, spherical overlapping elbow/knee/hip covers and 8 mm pressure liners. Liners are actual exported geometry, each a rigid convex shell enclosing its assigned body region. Sole clearance is clamped at z=0. These additions are included in the final suit budget.',
    '5. Replaced procedural materials with constant Principled BSDF values. Mat_Visor: dark blue-green, alpha 0.88, roughness 0.18, metallic 0.4. No images or baking. Mat_Ident is shared by patch and chest stripe for recolouring.',
    '6. Created 23 named bones, including hand-parented palm anchors. Authored nine actions at 30 fps from code poses. Carry/use/suit/seated hands use analytic two-bone positioning; gait and jump use keyed rotations. Sampled all frames and corrected negative foot minima using vertical Hips translation only. Armature-object and horizontal Hips movement are absent. Jump ends with repeated takeoff-pose samples; the game must clamp playback at clip end.',
    '7. Saved one new derivative .blend with muted NLA tracks for clean rest-pose editing; exported nine separately named NLA tracks to GLB. Imported that GLB into an empty factory scene at 30 fps, checking exact bones/mesh nodes/clip names. Importer-generated bone display geometry is excluded from character mesh inventory; raw GLB mesh-node names are checked separately.',
    '8. Rendered eight representative poses × front/side × crew/suit using Workbench at 640×800. Workbench does not validate Godot transparency or game rendering. No Godot process was run.', '', '## Measured results','```json',json.dumps({k:R.get(k) for k in ['body_source','body_reduction','body_triangles','automatic_weights','suit_source','suit_triangles','suit_scale','outer_shell_containment','rest_containment','pressure_liners','mesh_weight_checks','clips','glb_animations','reimport','checks','source_sha256_before','source_sha256_after']},indent=2),'```','', 'Bone names: '+', '.join(BONES), '', '## Checks and limitations','Script checks: source hashes, geometry budgets, body-weight coverage, rigid suit weights, per-frame foot minimum, exact raw-GLB mesh/clip names, imported bones/meshes/materials, no image textures. Rest containment uses per-connected-component ray parity with 1 mm tolerance and temporary caps on open shell cuts. Both outer-shell-only and complete-suit results are reported. This does not prove fit or absence of collisions throughout animation.','Visual review: '+R.get('visual_review','Pending for this run.'),'The seated pose is authored for an approximately 0.45 m seat; there is no exported chair. Hold and loop flags are game playback settings, not glTF semantics.','', '## Known defects']
    lines.extend('- '+d for d in R.get('defects',[]))
    with (OUT/'PROVENANCE.md').open('x',encoding='utf8') as f:f.write('\n'.join(lines)+'\n')
'''
        source=source.replace("\ntry:\n    log('Factory-scene",extra+"\ntry:\n    log('Factory-scene")
        target=Path(__file__).with_name('build_character.py')
        with target.open('x',encoding='utf8') as f:f.write(source)
        compile(source,str(target),'exec');log.write('Created and syntax-checked standalone build_character.py\n')
    except Exception:log.write(traceback.format_exc());raise
