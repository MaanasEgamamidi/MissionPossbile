"""Stack pair sheets vertically into one review image.  py -I tools/stack_sheets.py <out.jpg> <width> <sheet.jpg> [...]"""
import sys
from PIL import Image

out, width, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
ims = []
for f in files:
    im = Image.open(f).convert("RGB")
    ims.append(im.resize((width, int(im.height * width / im.width)), Image.LANCZOS))
sheet = Image.new("RGB", (width, sum(i.height for i in ims)), (0, 0, 0))
y = 0
for im in ims:
    sheet.paste(im, (0, y))
    y += im.height
sheet.save(out, quality=86)
print("wrote", out, sheet.size)
