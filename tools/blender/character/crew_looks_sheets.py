"""Assembles crew look contact sheets from render_crew_looks.py output.  python -I crew_looks_sheets.py <looks_dir>"""
import sys, os, json, glob
from PIL import Image, ImageDraw, ImageFont

D = sys.argv[1]; RAW = os.path.join(D, "raw")
crew = json.load(open(os.path.join(D, "crew_design.json")))
try:
    FONT = ImageFont.truetype("arial.ttf", 18); SMALL = ImageFont.truetype("arial.ttf", 14)
except OSError:
    FONT = SMALL = ImageFont.load_default()
BG = (24, 26, 30)

def im(n):
    p = os.path.join(RAW, n)
    return Image.open(p).convert("RGB") if os.path.exists(p) else Image.new("RGB", (10, 10), (80, 0, 0))

def row(names, h=None):
    ims = [im(n) for n in names]
    if h: ims = [i.resize((int(i.width * h / i.height), h), Image.LANCZOS) for i in ims]
    W = sum(i.width for i in ims) + 6 * (len(ims) - 1); H = max(i.height for i in ims)
    out = Image.new("RGB", (W, H), BG); x = 0
    for i in ims:
        out.paste(i, (x, 0)); x += i.width + 6
    return out

def stack(rows, title=None):
    th = 34 if title else 0
    W = max(r.width for r in rows); H = sum(r.height for r in rows) + 6 * (len(rows) - 1) + th
    out = Image.new("RGB", (W, H), BG); y = th
    if title:
        ImageDraw.Draw(out).text((8, 7), title, fill=(235, 235, 235), font=FONT)
    for r in rows:
        out.paste(r, (0, y)); y += r.height + 6
    return out

def label(img, text):
    ImageDraw.Draw(img).text((6, 4), text, fill=(230, 230, 230), font=SMALL)
    return img

for c in crew:
    i = c["id"]
    t = f"Crew {i} - {c['name']}: {c['hair']}{' + beard' if c['beard'] else ''}, Feminine={c['feminine']:.0f}, height {c.get('height', 1)}, skin #{c['skin']}, hair #{c['hair_col']}, accent #{c['accent']} {c.get('symbol', '')} / {c.get('band', '')}"
    r1 = row([f"c{i}_body_{v}.png" for v in ("front", "3q", "side", "back")] + [f"c{i}_suit_{v}.png" for v in ("front", "back", "3q")])
    r2 = row([f"c{i}_head_{v}.png" for v in ("front", "3q", "side", "back", "back3q")] + [f"c{i}_helmet_{v}.png" for v in ("front", "3q", "back")] + [f"c{i}_far_back.png"], h=300)
    stack([r1, r2], t).save(os.path.join(D, f"crew{i}_{c['name']}.png"))

lineups = {
    "lineup_unsuited_front": [f"c{c['id']}_body_front.png" for c in crew],
    "lineup_unsuited_3q": [f"c{c['id']}_body_3q.png" for c in crew],
    "lineup_suited_back": [f"c{c['id']}_suit_back.png" for c in crew],
    "lineup_suited_front": [f"c{c['id']}_suit_front.png" for c in crew],
    "lineup_heads_3q": [f"c{c['id']}_head_3q.png" for c in crew],
    "lineup_heads_back3q": [f"c{c['id']}_head_back3q.png" for c in crew],
    "lineup_helmets_front": [f"c{c['id']}_helmet_front.png" for c in crew],
    "lineup_helmets_back": [f"c{c['id']}_helmet_back.png" for c in crew],
}
rs = []
for k, names in lineups.items():
    rows = row(names, h=330 if ("head" in k or "helmet" in k) else 400)
    rs.append(label(rows, k.replace("_", " ")))
    rows.save(os.path.join(D, k + ".png"))
far = row([f"c{c['id']}_far_back.png" for c in crew])
far.resize((far.width * 2, far.height * 2), Image.NEAREST).save(os.path.join(D, "lineup_far_back_10m.png"))
stack(rs, "All four crew").save(os.path.join(D, "lineup_all.png"))

poses = sorted(glob.glob(os.path.join(RAW, "pose_*.png")))
if poses:
    ids = sorted({os.path.basename(p).split("_")[1] for p in poses})
    rr = []
    for cid in ids:
        for clip in ("idle", "walk", "sprint", "jump_start", "jump", "land"):
            pass
        names = [os.path.basename(p) for p in poses if os.path.basename(p).split("_")[1] == cid]
        order = []
        for clip in ("idle", "walk", "sprint", "jump_start", "jump", "land"):
            order += sorted(n for n in names if n.startswith(f"pose_{cid}_{clip}_") and n[len(f"pose_{cid}_{clip}_"):-4].isdigit())
        rr.append(label(row(order[:12]), cid + " idle / walk / sprint")); rr.append(row(order[12:]))
    stack(rr, "Hair clearance in clips (side view): idle, walk, sprint, jump_start, jump, land").save(os.path.join(D, "poses_hair_clearance.png"))
print("sheets written to", D)
