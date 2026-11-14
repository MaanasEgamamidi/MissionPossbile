from pathlib import Path
import sys,traceback
try:
    code=Path(__file__).with_name('character_pipeline_v2.py').read_text(encoding='utf8')
    code=code.replace(' "bone=\'Chest\'":"bone=\'Chest\'",\n','')
    code=code.replace('ob.vertex_groups.remove(group)','None')
    exec(compile(code,__file__,'exec'))
except Exception:
    argv=sys.argv[sys.argv.index('--')+1:];root=Path(argv[argv.index('--root')+1]);tag=argv[argv.index('--tag')+1]
    with (root/'mars_colony_godot/docs/milestones/04_player/rig'/f'{tag}_startup_error.log').open('x') as f:f.write(traceback.format_exc())
    raise
