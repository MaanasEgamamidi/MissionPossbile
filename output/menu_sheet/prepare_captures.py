from pathlib import Path
root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent
for name in ('stations', 'info_panels', 'puzzles'):
    src = (root / f'tools/godot/capture_{name}.gd').read_text(encoding='utf-8')
    src = src.replace('res://_test_saves/capture_', 'res://_test_saves/menu_sheet_capture_')
    if name == 'stations':
        src = src.replace('const SIZES := [[Vector2i(1280, 720), 1.0, "720"], [Vector2i(1920, 1080), 1.0, "1080"], [Vector2i(1280, 720), 1.5, "720_text150"]]', 'const SIZES := [[Vector2i(1920, 1080), 1.0, "1080"]]')
    if name == 'puzzles':
        start = src.index('\t\tawait _solve(id)\n')
        end = src.index('\tif only.is_empty() or only.has("wrong"):', start)
        src = src[:start] + src[end:]
    (out / f'capture_{name}.gd').write_text(src, encoding='utf-8')
print('Prepared isolated capture scripts')
