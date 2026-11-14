"""Builds one contact sheet per clip from the stills retarget_mixamo_clip.py --render writes.
  python -I make_anim_sheets_v4.py <stills_dir> <out_dir>
Stills are named <clip>_<view>_<suit|body>_<frame>.png; each sheet row is one view/outfit, frames left to right.
"""
import sys, os, re
from collections import defaultdict
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
pat = re.compile(r"^(.+)_(front|side|back)_(suit|body)_(\d+)\.png$")
clips = defaultdict(lambda: defaultdict(list))
for name in os.listdir(src):
    m = pat.match(name)
    if m:
        clips[m[1]][(m[2], m[3])].append((int(m[4]), os.path.join(src, name)))
ROWS = [("front", "suit"), ("side", "suit"), ("back", "suit"), ("front", "body"), ("side", "body")]
for clip, rows in clips.items():
    rows_present = [r for r in ROWS if r in rows]
    cols = max(len(v) for v in rows.values())
    w, h, lab = 200, 293, 18
    sheet = Image.new("RGB", (cols * w + 90, len(rows_present) * (h + lab) + 24), (25, 30, 38))
    d = ImageDraw.Draw(sheet)
    d.text((6, 4), f"{clip}  (frame numbers at 30 fps)", fill=(255, 255, 255))
    for ri, r in enumerate(rows_present):
        y = 24 + ri * (h + lab)
        d.text((6, y + h // 2), f"{r[0]}\n{r[1]}", fill=(220, 220, 220))
        for ci, (f, p) in enumerate(sorted(rows[r])):
            im = Image.open(p).convert("RGB").resize((w, h))
            sheet.paste(im, (90 + ci * w, y))
            d.text((90 + ci * w + 4, y + h + 2), f"f{f}", fill=(255, 255, 255))
    sheet.save(os.path.join(out, f"{clip}_sheet.png"))
    print(os.path.join(out, f"{clip}_sheet.png"))
