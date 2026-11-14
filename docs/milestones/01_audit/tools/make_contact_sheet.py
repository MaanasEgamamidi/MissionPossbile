"""Assemble a labelled contact sheet from existing image files (no rendering).
Usage: make_contact_sheet.py <out.jpg> <cols> <thumb_width> <label=path> [<label=path> ...]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out, cols, tw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
items = [a.split("=", 1) for a in sys.argv[4:]]
th = int(tw * 9 / 16)
bar = 22
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + bar)), (24, 24, 24))
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 13)
except Exception:
    font = ImageFont.load_default()
for i, (label, path) in enumerate(items):
    x, y = (i % cols) * tw, (i // cols) * (th + bar)
    try:
        im = Image.open(path).convert("RGB")
        im.thumbnail((tw, th))
        sheet.paste(im, (x + (tw - im.width) // 2, y + bar + (th - im.height) // 2))
    except Exception as e:
        draw.text((x + 6, y + bar + 6), f"missing: {e}", fill=(255, 90, 90), font=font)
    draw.text((x + 6, y + 4), label, fill=(240, 200, 120), font=font)
Path(out).parent.mkdir(parents=True, exist_ok=True)
sheet.save(out, quality=88)
print("wrote", out, sheet.size)
