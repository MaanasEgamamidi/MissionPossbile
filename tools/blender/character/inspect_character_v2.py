import bpy, sys, json, traceback
from pathlib import Path
root = Path(sys.argv[sys.argv.index('--')+1]); out = root/'mars_colony_godot/docs/milestones/04_player/rig'
r = {'version': bpy.app.version_string}
with (out/'inspect_v2.log').open('x', encoding='utf8') as log:
    try:
        for key, rel in [('body','grand_colony/work/_downloads/human_base_meshes/extracted/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend'),('suit','grand_colony/grand_colony.blend')]:
            with bpy.data.libraries.load(str(root/rel), link=False) as (a,b):
                names = tuple(a.objects)
                b.objects = list(names) if key == 'body' else [n for n in names if 'qt_spacesuit' in n]
                texts = tuple(a.texts)
                b.texts = list(texts) if key == 'body' else []
            rows=[]
            for o in b.objects:
                if o is None or o.type != 'MESH': continue
                bpy.context.scene.collection.objects.link(o)
                o.data.calc_loop_triangles()
                rows.append(dict(name=o.name, triangles=len(o.data.loop_triangles), vertices=len(o.data.vertices), bounds=[[min(v.co[i] for v in o.data.vertices),max(v.co[i] for v in o.data.vertices)] for i in range(3)], matrix=[list(v) for v in o.matrix_world], materials=[m.name if m else None for m in o.data.materials]))
            r[key]={'names':names,'meshes':rows,'texts':{t.name:t.as_string() for t in b.texts if t}}
            log.write(f'{key}: {len(rows)} meshes\n');log.flush()
        r['ok']=True
    except Exception:
        r['ok']=False;r['error']=traceback.format_exc();log.write(r['error'])
    with (out/'source_inventory_v2.json').open('x',encoding='utf8') as f: json.dump(r,f,indent=2)
