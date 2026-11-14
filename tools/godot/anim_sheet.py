"""Tiles capture_anim.gd frames into contact sheets for judging.
Run: python -I anim_sheet.py <capture folder> [<out folder>]
Writes <clip>_sheet.png (side row over front row) per posed clip, and play_sheet_<n>.png for gameplay frames.
"""
import sys, os, re
from PIL import Image, ImageDraw

src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else src
os.makedirs(out, exist_ok=True)
files = sorted(f for f in os.listdir(src) if f.endswith(".png") and "_sheet" not in f)


def tile(paths, cols, w, h, labels):
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * h), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGB")
        # crop the centre square-ish region where the character is, then scale
        W, H = im.size
        box = (int(W * 0.2), int(H * 0.05), int(W * 0.8), int(H * 0.95))
        im = im.crop(box).resize((w, h))
        x, y = (i % cols) * w, (i // cols) * h
        sheet.paste(im, (x, y))
        d.text((x + 4, y + 4), labels[i], fill=(255, 255, 0))
    return sheet


clips = {}
for f in files:
    m = re.match(r"(.+)_(side|front)_(\d)\.png$", f)
    if m:
        clips.setdefault(m.group(1), {}).setdefault(m.group(2), []).append(f)
for clip, views in clips.items():
    paths, labels = [], []
    for view in ("side", "front"):
        for f in sorted(views.get(view, [])):
            paths.append(os.path.join(src, f)); labels.append(f[:-4])
    tile(paths, 8, 220, 300, labels).save(os.path.join(out, clip + "_sheet.png"))

play = [f for f in files if f.startswith("play_")]
for n in range(0, len(play), 24):
    chunk = play[n:n + 24]
    tile([os.path.join(src, f) for f in chunk], 8, 220, 300, [f[:-4] for f in chunk]).save(
        os.path.join(out, "play_sheet_%d.png" % (n // 24)))
print("sheets:", sorted(os.listdir(out)))
