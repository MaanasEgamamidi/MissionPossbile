import bpy,json,sys
from pathlib import Path
r=Path(sys.argv[sys.argv.index('--')+1]);out=r/'mars_colony_godot/docs/milestones/04_player/rig/body_sections.json'
with bpy.data.libraries.load(str(r/'mars_colony_godot/assets_src/characters/attempt01/astronaut.blend'),link=False) as (a,b):b.objects=['Body_Head','Body_Torso','Body_Arms','Body_Legs']
rows={}
for o in b.objects:
    rows[o.name]={}
    for z in [.05,.12,.3,.5,.7,.9,1.0,1.1,1.2,1.3,1.4,1.5,1.6,1.7]:
        vv=[v.co for v in o.data.vertices if abs(v.co.z-z)<.025 and v.co.x>0]
        if vv:rows[o.name][str(z)]={'bounds':[[min(v[i] for v in vv),max(v[i] for v in vv)] for i in range(3)],'mean':[sum(v[i] for v in vv)/len(vv) for i in range(3)]}
with out.open('x') as f:json.dump(rows,f,indent=2)
