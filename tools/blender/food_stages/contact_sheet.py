"""V1..V4 contact sheets of the render_stages.py check images: one JPG per view, 2 x 2, labelled.
  py -I tools/blender/food_stages/contact_sheet.py <dir with <view>_V<n>.png> [--delete-png]
"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

folder = sys.argv[1]
views = sorted({os.path.basename(p).rsplit("_V", 1)[0] for p in glob.glob(os.path.join(folder, "*_V[1-4].png"))})
try:
    font = ImageFont.truetype("arial.ttf", 30)
except OSError:
    font = ImageFont.load_default()
for view in views:
    tiles = []
    for lvl in range(1, 5):
        path = os.path.join(folder, "%s_V%d.png" % (view, lvl))
        im = Image.open(path).convert("RGB")
        im = ImageEnhance.Brightness(im).enhance(1.3)
        w = 800
        im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 92, 44), fill=(20, 20, 20))
        d.text((12, 5), "V%d" % lvl, fill=(255, 220, 90), font=font)
        tiles.append(im)
    tw, th = tiles[0].size
    sheet = Image.new("RGB", (2 * tw + 6, 2 * th + 6), (0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 2) * (tw + 6), (i // 2) * (th + 6)))
    out = os.path.join(folder, "%s_V1-V4.jpg" % view)
    sheet.save(out, quality=84)
    print("wrote", out, sheet.size)
    if "--delete-png" in sys.argv:
        for lvl in range(1, 5):
            os.remove(os.path.join(folder, "%s_V%d.png" % (view, lvl)))
