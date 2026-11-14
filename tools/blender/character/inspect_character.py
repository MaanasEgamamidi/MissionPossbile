"""Read-only source inventory. Run through the Store launcher, never open_mainfile."""
import bpy, json, sys, traceback
from pathlib import Path

root = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
out = root / 'mars_colony_godot/docs/milestones/04_player/rig'
out.mkdir(parents=True, exist_ok=True)
report_path = out / 'source_inventory.json'
log_path = out / 'inspect.log'
if report_path.exists() or log_path.exists():
    raise RuntimeError('Refusing to overwrite inventory or log')
log = log_path.open('x', encoding='utf-8')
report = {'blender': bpy.app.version_string, 'sources': {}}
try:
    for key, relative in [('body', 'grand_colony/work/_downloads/human_base_meshes/extracted/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend'), ('suit', 'grand_colony/grand_colony.blend')]:
        path = root / relative
        with bpy.data.libraries.load(str(path), link=False) as (src, dst):
            names = list(src.objects)
            dst.objects = names if key == 'body' else [n for n in names if 'qt_spacesuit' in n.lower()]
        objects = []
        for obj in dst.objects:
            if obj is None or obj.type != 'MESH':
                continue
            bpy.context.scene.collection.objects.link(obj)
            obj.data.calc_loop_triangles()
            objects.append({'name': obj.name, 'vertices': len(obj.data.vertices), 'triangles': len(obj.data.loop_triangles), 'bounds_local': [[min(v.co[i] for v in obj.data.vertices), max(v.co[i] for v in obj.data.vertices)] for i in range(3)], 'matrix_world': [list(r) for r in obj.matrix_world], 'materials': [m.name if m else None for m in obj.data.materials]})
        report['sources'][key] = {'path': str(path), 'object_names': names, 'meshes': objects}
        log.write(f'{key}: {len(objects)} meshes inventoried\n'); log.flush()
    report['ok'] = True
except Exception:
    report['ok'] = False
    report['error'] = traceback.format_exc()
    log.write(report['error'])
finally:
    with report_path.open('x', encoding='utf-8') as handle:
        json.dump(report, handle, indent=2)
    log.close()
