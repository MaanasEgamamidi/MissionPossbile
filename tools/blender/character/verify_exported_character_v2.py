from pathlib import Path
code=Path(__file__).with_name('verify_exported_character.py').read_text(encoding='utf8')
code=code.replace("(tag+'_glb_validation')","(tag+'_glb_validation_v2')")
code=code.replace("scene.world.color=(.11,.13,.16)","scene.world=bpy.data.worlds.new('EvidenceWorld');scene.world.color=(.11,.13,.16)")
exec(compile(code,__file__,'exec'))
