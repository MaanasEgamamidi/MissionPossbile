"""Labels the in-map renders of render_in_map.py (plain Python + Pillow, no Blender):
  py -I tools/blender/broken_parts/annotate_in_map.py [project_dir]

  - map_overview_spots.png: the top-down overview with the 10 spots (marker + "BPnn · Tnn Name"), each repair station
    (small ring) and each eye-level camera (small arrow);
  - every BPnn_{broken,fixed}_in_map.png gets a title bar and a locator inset (the overview around the part, the part
    marked, the camera arrow). The untouched renders are kept in raw/ and every run starts from them.
"""
import json
import math
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PROJ = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
DIR = PROJ / "docs" / "revisions" / "evidence" / "broken_parts" / "in_map"
RAW = DIR / "raw"
NAMES = {"T01": "Comms", "T02": "Wires", "T03": "Rings", "T04": "Circuits", "T06": "Water", "T08": "Glass", "T09": "Mixture",
         "T10": "Equipment", "T11": "Dust", "T12": "Seal"}
ACCENT = (255, 196, 64)


def font(size, bold=True):
    for name in (("arialbd.ttf" if bold else "arial.ttf"), "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    data = json.loads((PROJ / "data" / "broken_parts.json").read_text(encoding="utf-8"))
    stations = {s["id"]: s for s in json.loads((PROJ / "data" / "stations_repairs.json").read_text(encoding="utf-8"))["stations"]}
    cams = json.loads((DIR / "part_cameras.json").read_text(encoding="utf-8")) if (DIR / "part_cameras.json").exists() else {}
    for f in sorted((DIR / "cams").glob("BP*.json")):          # per-part cameras of render_in_map.py runs win
        cams[f.stem] = json.loads(f.read_text(encoding="utf-8"))
    ov = json.loads((DIR / "overview_camera.json").read_text(encoding="utf-8"))
    W, H = ov["res"]
    cx, cy = ov["center_blender"]
    scale = ov["ortho_scale"]
    ppm = W / scale                                   # pixels per metre

    def px(g):
        """Godot (x, _, z) -> overview pixel."""
        return ((g[0] - cx) * ppm + W / 2, H / 2 - ((-g[2]) - cy) * ppm)

    base = Image.open(DIR / "overview_topdown.png").convert("RGB")

    def mark(draw, p, part, label=True, f=None, scale_=1.0):
        key = p["glb"].split("/")[-1][:4]
        b = p["model_bounds"] if p["special"] != "dust" else p["bounds"]
        c, s = b["center"], b["size"]
        a = px([c[0] - s[0] / 2, 0, c[2] + s[2] / 2])
        z = px([c[0] + s[0] / 2, 0, c[2] - s[2] / 2])
        if p["task_id"] in ("T08", "T11"):
            draw.rectangle([min(a[0], z[0]), min(a[1], z[1]), max(a[0], z[0]), max(a[1], z[1])], outline=ACCENT, width=max(1, int(2 * scale_)))
        sp = px(p["spot"])
        r = 7 * scale_
        draw.ellipse([sp[0] - r, sp[1] - r, sp[0] + r, sp[1] + r], fill=(230, 40, 30), outline=(255, 255, 255), width=max(1, int(2 * scale_)))
        st = px(stations[p["station_id"]]["position"])
        r2 = 4 * scale_
        draw.ellipse([st[0] - r2, st[1] - r2, st[0] + r2, st[1] + r2], outline=(80, 220, 255), width=max(1, int(2 * scale_)))
        cam = cams.get(key)
        if cam:
            e, l = px(cam["eye_godot"]), px(cam["look_godot"])
            ang = math.atan2(l[1] - e[1], l[0] - e[0])
            ln = 18 * scale_
            tip = (e[0] + math.cos(ang) * ln, e[1] + math.sin(ang) * ln)
            draw.line([e, tip], fill=(255, 255, 255), width=max(1, int(2 * scale_)))
            for da in (2.6, -2.6):
                draw.line([tip, (tip[0] + math.cos(ang + da) * 6 * scale_, tip[1] + math.sin(ang + da) * 6 * scale_)], fill=(255, 255, 255), width=max(1, int(2 * scale_)))
        if label:
            text = "%s · %s %s" % (key, p["task_id"], NAMES[p["task_id"]])
            tw = draw.textlength(text, font=f)
            off = {"T09": (12, -24), "T10": (12, 4), "T02": (-tw - 12, 4), "T01": (12, -6), "T03": (12, 6), "T04": (-tw / 2, 14),
                   "T12": (-tw - 8, 28), "T06": (12, 4), "T11": (-tw / 2, -44), "T08": (-tw - 14, -10)}[p["task_id"]]
            x, y = sp[0] + off[0], sp[1] + off[1]
            draw.rectangle([x - 4, y - 2, x + tw + 4, y + 20], fill=(20, 20, 24))
            draw.text((x, y), text, font=f, fill=ACCENT)

    over = base.copy()
    d = ImageDraw.Draw(over)
    f = font(16)
    for p in data["parts"]:
        mark(d, p, p, True, f)
    d.rectangle([0, 0, W, 30], fill=(20, 20, 24))
    d.text((10, 6), "Broken parts: the 10 repair spots (red = part spot, blue ring = repair station, white arrow = eye-level camera)",
           font=font(15), fill=(240, 240, 240))
    over.save(DIR / "map_overview_spots.png")

    RAW.mkdir(exist_ok=True)
    for p in data["parts"]:
        key = p["glb"].split("/")[-1][:4]
        for state in ("broken", "fixed"):
            name = "%s_%s_in_map.png" % (key, state)
            src = DIR / name
            raw = RAW / name
            if src.exists() and not _annotated(src):          # a fresh render: keep it as the raw copy
                shutil.copy2(src, raw)
            if not raw.exists():
                continue
            img = Image.open(raw).convert("RGB")
            # locator inset: the overview around the spot, 2.2x zoom
            sp = px(p["spot"])
            half_w, half_h = (150, 85) if p["task_id"] not in ("T11", "T08") else (210, 118)
            box = [int(sp[0] - half_w), int(sp[1] - half_h), int(sp[0] + half_w), int(sp[1] + half_h)]
            loc = base.copy()
            mark(ImageDraw.Draw(loc), p, p, False)
            crop = loc.crop(box).resize((300, 170) if half_w == 150 else (300, 169), Image.LANCZOS)
            img.paste(crop, (1280 - 300 - 12, 720 - 170 - 12))
            dd = ImageDraw.Draw(img)
            dd.rectangle([1280 - 300 - 13, 720 - 170 - 13, 1280 - 12, 720 - 12], outline=(240, 240, 240), width=2)
            title = "%s · %s %s — %s (%s)" % (key, p["task_id"], NAMES[p["task_id"]], "BROKEN" if state == "broken" else "FIXED / intact", p["zone"])
            tw = dd.textlength(title, font=font(20))
            dd.rectangle([0, 0, tw + 24, 34], fill=(20, 20, 24))
            dd.text((12, 6), title, font=font(20), fill=(230, 60, 40) if state == "broken" else (110, 220, 120))
            img.save(src)
    print("annotated", DIR)


def _annotated(path):
    im = Image.open(path).convert("RGB")
    return im.getpixel((3, 3)) == (20, 20, 24)


if __name__ == "__main__":
    main()
