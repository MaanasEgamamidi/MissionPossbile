#!/usr/bin/env python3
"""Build distributable copies without importing or changing the source project."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
from web_profile import configure as configure_web

LIVE = Path(__file__).resolve().parent
ROOT = LIVE.parent
BUILD = LIVE / '.build'
DIST = LIVE / 'dist'


def run(args, log=None):
    print('+', ' '.join(map(str, args)), flush=True)
    if log:
        with log.open('w') as out:
            result = subprocess.run(list(map(str, args)), stdout=out, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f'Command failed; see {log}')
        # Godot can return success even when export or script compilation failed.
        errors = [line for line in log.read_text(errors='replace').splitlines()
                  if 'ERROR:' in line or 'Export failed' in line or 'Failed to export' in line]
        if errors:
            raise RuntimeError('\n'.join(errors[:12]) + f'\nSee {log}')
    else:
        subprocess.run(list(map(str, args)), check=True)


def stage_project(target):
    stage = BUILD / target
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    paths = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
    skip = {'.git', '.godot', '.github', 'live', 'assets_src', 'docs', 'tests', 'tmp', 'output', 'Prompt'}
    for name in paths:
        path = Path(name)
        if not name or path.parts[0] in skip or path.suffix in {'.md', '.py', '.ps1', '.blend', '.blend1'}:
            continue
        source = ROOT / path
        if source.is_file():
            dest = stage / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
    # VoiceService already handles an absent extension. Only Windows has bundled binaries.
    if target != 'windows':
        shutil.rmtree(stage / 'addons/twovoip', ignore_errors=True)
    project = stage / 'project.godot'
    text = project.read_text()
    # Editor plugins are unnecessary in exported staging copies.
    import re
    text = re.sub(r'enabled=PackedStringArray\([^\n]*\)', 'enabled=PackedStringArray()', text)
    if target == 'macos':
        text = text.replace('[rendering]', '[rendering]\ntextures/vram_compression/import_etc2_astc=true')
    if target == 'web':
        text = text.replace('"Forward Plus"', '"GL Compatibility"')
        text = text.replace('[rendering]', '''[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
textures/vram_compression/import_etc2_astc=true
anti_aliasing/quality/msaa_3d.web=0
scaling_3d/scale.web=0.65
scaling_3d/mode.web=0
shadows/shadow_atlas/size.web=0''')
        text = text.replace('window/size/mode=2', 'window/size/mode=0')
    if target == 'web':
        text = text.replace('[application]', '[application]\nrun/max_fps=60')
        text += '\n[shader_globals]\nbrowser_detail={"type": "bool", "value": false}\n'
        configure_web(stage)
    project.write_text(text)
    return stage


def export(godot, templates, target):
    stage = stage_project(target)
    platform = {'web': 'Web', 'windows': 'Windows Desktop', 'macos': 'macOS'}[target]
    output = DIST / ('play/game/index.html' if target == 'web' else f'downloads/MarsColony-{target}/MarsColony.exe' if target == 'windows' else 'downloads/MarsColony-macos.zip')
    output.parent.mkdir(parents=True, exist_ok=True)
    opts = {
        'web': {'custom_template/release': str(templates / 'web_nothreads_release.zip'),
                'variant/extensions_support': False, 'variant/thread_support': False,
                'vram_texture_compression/for_desktop': True,
                'vram_texture_compression/for_mobile': True,
                'html/canvas_resize_policy': 0, 'progressive_web_app/enabled': False},
        'windows': {'custom_template/release': str(templates / 'windows_release_x86_64.exe'),
                    'binary_format/embed_pck': True, 'binary_format/architecture': 'x86_64',
                    'application/modify_resources': False, 'debug/export_console_wrapper': 0},
        'macos': {'custom_template/release': str(templates / 'macos.zip'),
                  'custom_template/debug': str(templates / 'macos.zip'),
                  'texture_format/etc2_astc': True, 'texture_format/s3tc_bptc': True,
                  'application/bundle_identifier': 'org.marscolony.game',
                  'application/app_category': 'public.app-category.games',
                  'application/short_version': '0.1.0', 'application/version': '0.1.0',
                  'codesign/codesign': 1, 'notarization/notarization': 0,
                  'privacy/microphone_usage_description': 'Optional in-game voice chat.'}
    }[target]
    options = '\n'.join(f'{key}={json.dumps(value)}' for key, value in opts.items())
    preset = f'''[preset.0]
name="Live"
platform="{platform}"
runnable=true
advanced_options=true
export_filter="all_resources"
include_filter="data/*.json,data/*.bin,data/*.csv,data/weather/bundle/*"
exclude_filter="tools/*,addons/funplay_mcp/*,*.md,*.py,*.ps1"
export_path="{output}"
script_export_mode=2
[preset.0.options]
{options}
'''
    (stage / 'export_presets.cfg').write_text(preset)
    run([godot, '--headless', '--path', stage, '--import'], BUILD / f'{target}-import.log')
    run([godot, '--headless', '--path', stage, '--export-release', 'Live', output], BUILD / f'{target}-export.log')
    if not output.is_file() or output.stat().st_size < 1024:
        raise RuntimeError(f'Missing export: {output}')
    if target == 'web':
        shutil.copy2(LIVE / 'play.html', DIST / 'play/index.html')
        shutil.copy2(LIVE / 'mouse-capture.js', output.parent / 'mouse-capture.js')
        shutil.copy2(LIVE / 'browser-controls.js', output.parent / 'browser-controls.js')
        shutil.copy2(LIVE / 'browser-settings.js', output.parent / 'browser-settings.js')
        shutil.copy2(LIVE / 'browser-toolbar.js', output.parent / 'browser-toolbar.js')
        html = output.read_text()
        output.write_text(html.replace('<script src="index.js"></script>', '<script src="browser-toolbar.js"></script><script src="browser-settings.js"></script><script src="index.js"></script>').replace('<canvas id="canvas">', '<canvas id="canvas" width="1280" height="720" style="width:100vw;height:100vh">').replace('</body>', '<script src="mouse-capture.js"></script><script src="browser-controls.js"></script></body>'))
    if target == 'windows':
        with zipfile.ZipFile(DIST / 'downloads/MarsColony-windows.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in output.parent.rglob('*'):
                if file.is_file():
                    archive.write(file, file.relative_to(output.parent.parent))
        shutil.rmtree(output.parent)
    shutil.rmtree(stage)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=shutil.which('godot') or 'godot')
    parser.add_argument('--templates', type=Path, required=True, help='Directory containing official matching export templates')
    parser.add_argument('--target', choices=['all', 'web', 'windows', 'macos'], default='all')
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    DIST.mkdir(exist_ok=True)
    for file in ('index.html', 'style.css', 'app.js', '.nojekyll'):
        shutil.copy2(LIVE / file, DIST / file)
    shutil.copytree(LIVE / 'assets', DIST / 'assets', dirs_exist_ok=True)
    manifest_path = DIST / 'builds.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for target in (['web', 'windows', 'macos'] if args.target == 'all' else [args.target]):
        export(args.godot, args.templates.resolve(), target)
        manifest[target] = 'play/index.html' if target == 'web' else f'downloads/MarsColony-{target}.zip'
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Built at {DIST}')


if __name__ == '__main__':
    main()
