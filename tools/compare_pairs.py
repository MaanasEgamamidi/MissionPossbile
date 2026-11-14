"""Compare Godot captures with the Cycles reference renders, camera by camera (Prompt 02).
  py -I tools/compare_pairs.py <reference.zip|dir> <godot_dir> <out_dir> <tag>
Writes <out_dir>/metrics_<tag>.json and .csv, and one side-by-side JPEG per camera in <out_dir>/sheets_<tag>/.

These are image statistics. They do not measure lighting accuracy and are reported next to, not instead of, the
100-point visual rubric.
  ssim           structural similarity of the two sRGB luma images after resizing both to 960x540; Gaussian window
                 11x11, sigma 1.5, K1 0.01, K2 0.03, dynamic range 1.0 (Wang et al. 2004 settings)
  lum_ratio      mean linear luminance of the Godot image / of the reference (Rec.709 weights, sRGB decoded)
  ev_diff        log2(lum_ratio): negative = Godot darker
  de76_mean      mean CIE76 colour difference in CIELAB (D65) at 480x270
  rg_shift, bg_shift   Godot (R/G, B/G of the mean linear colour) divided by the reference's: >1 = redder / bluer
  clip_hi, clip_lo     fraction of pixels with luma > 0.98 / < 0.02
  grid_ev        3x3 grid (rows top to bottom) of per-cell ev_diff, to locate where the exposure differs
"""
import csv
import io
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ref_src, godot_dir, out_dir, tag = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
out_dir.mkdir(parents=True, exist_ok=True)
sheets = out_dir / f"sheets_{tag}"
sheets.mkdir(exist_ok=True)


def load_refs():
    refs = {}
    p = Path(ref_src)
    if p.is_file():
        z = zipfile.ZipFile(p)
        for n in z.namelist():
            if n.lower().endswith(".png"):
                refs[Path(n).stem] = Image.open(io.BytesIO(z.read(n))).convert("RGB")
    else:
        for f in p.glob("*.png"):
            refs[f.stem] = Image.open(f).convert("RGB")
    return refs


def to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def luma(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def gauss_blur(img, sigma=1.5, size=11):
    x = np.arange(size) - size // 2
    k = np.exp(-(x ** 2) / (2 * sigma ** 2))
    k /= k.sum()
    pad = size // 2
    a = np.pad(img, ((0, 0), (pad, pad)), mode="reflect")
    a = np.apply_along_axis(lambda r: np.convolve(r, k, mode="valid"), 1, a)
    a = np.pad(a, ((pad, pad), (0, 0)), mode="reflect")
    return np.apply_along_axis(lambda c: np.convolve(c, k, mode="valid"), 0, a)


def ssim(a, b):
    c1, c2 = 0.01 ** 2, 0.03 ** 2
    mu_a, mu_b = gauss_blur(a), gauss_blur(b)
    va = gauss_blur(a * a) - mu_a ** 2
    vb = gauss_blur(b * b) - mu_b ** 2
    cov = gauss_blur(a * b) - mu_a * mu_b
    s = ((2 * mu_a * mu_b + c1) * (2 * cov + c2)) / ((mu_a ** 2 + mu_b ** 2 + c1) * (va + vb + c2))
    return float(s.mean())


def lab(lin):
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


try:
    font = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 16)
except Exception:
    font = ImageFont.load_default()

refs = load_refs()
rows = []
for name in sorted(refs):
    g = godot_dir / f"{name}.png"
    if not g.exists():
        rows.append({"camera": name, "status": "no Godot capture"})
        continue
    ri, gi = refs[name], Image.open(g).convert("RGB")
    size = (960, 540)
    ra = np.asarray(ri.resize(size, Image.LANCZOS), dtype=np.float64) / 255.0
    ga = np.asarray(gi.resize(size, Image.LANCZOS), dtype=np.float64) / 255.0
    rl, gl = to_lin(ra), to_lin(ga)
    ry, gy = luma(rl), luma(gl)
    ratio = float(gy.mean() / max(ry.mean(), 1e-9))
    rm, gm = rl.reshape(-1, 3).mean(0), gl.reshape(-1, 3).mean(0)
    small = (480, 270)
    rs = to_lin(np.asarray(ri.resize(small, Image.LANCZOS), dtype=np.float64) / 255.0)
    gs = to_lin(np.asarray(gi.resize(small, Image.LANCZOS), dtype=np.float64) / 255.0)
    de = float(np.sqrt(((lab(rs) - lab(gs)) ** 2).sum(-1)).mean())
    grid = []
    for i in range(3):
        row = []
        for j in range(3):
            sl = (slice(i * 180, (i + 1) * 180), slice(j * 320, (j + 1) * 320))
            row.append(round(float(np.log2(max(gy[sl].mean(), 1e-9) / max(ry[sl].mean(), 1e-9))), 2))
        grid.append(row)
    rows.append({
        "camera": name, "status": "ok", "ref_size": list(ri.size), "godot_size": list(gi.size),
        "ssim": round(ssim(luma(ra), luma(ga)), 4), "lum_ref": round(float(ry.mean()), 4), "lum_godot": round(float(gy.mean()), 4),
        "lum_ratio": round(ratio, 3), "ev_diff": round(float(np.log2(max(ratio, 1e-9))), 2), "de76_mean": round(de, 2),
        "rg_shift": round(float((gm[0] / gm[1]) / (rm[0] / rm[1])), 3), "bg_shift": round(float((gm[2] / gm[1]) / (rm[2] / rm[1])), 3),
        "contrast_ref": round(float(luma(ra).std()), 4), "contrast_godot": round(float(luma(ga).std()), 4),
        "clip_hi_ref": round(float((luma(ra) > 0.98).mean()), 4), "clip_hi_godot": round(float((luma(ga) > 0.98).mean()), 4),
        "clip_lo_ref": round(float((luma(ra) < 0.02).mean()), 4), "clip_lo_godot": round(float((luma(ga) < 0.02).mean()), 4),
        "grid_ev": grid,
    })
    w, h = 800, 450
    sheet = Image.new("RGB", (w * 2 + 6, h + 26), (20, 20, 20))
    sheet.paste(ri.resize((w, h), Image.LANCZOS), (0, 26))
    sheet.paste(gi.resize((w, h), Image.LANCZOS), (w + 6, 26))
    d = ImageDraw.Draw(sheet)
    d.text((6, 4), f"{name}   Cycles reference (2026-11-08)", fill=(240, 200, 120), font=font)
    d.text((w + 12, 4), f"Godot 4.7.2 capture, {tag}   ev {rows[-1]['ev_diff']:+.2f}  ssim {rows[-1]['ssim']:.3f}  dE {rows[-1]['de76_mean']:.1f}", fill=(140, 210, 240), font=font)
    sheet.save(sheets / f"{name}.jpg", quality=88)

ok = [r for r in rows if r.get("status") == "ok"]
summary = {"tag": tag, "pairs": len(ok), "missing": [r["camera"] for r in rows if r.get("status") != "ok"],
           "mean_ssim": round(float(np.mean([r["ssim"] for r in ok])), 4) if ok else None,
           "mean_abs_ev": round(float(np.mean([abs(r["ev_diff"]) for r in ok])), 3) if ok else None,
           "mean_de76": round(float(np.mean([r["de76_mean"] for r in ok])), 2) if ok else None,
           "settings": "960x540 Lanczos; SSIM on sRGB luma, Gaussian 11x11 sigma 1.5, K1 0.01 K2 0.03; dE76 at 480x270"}
(out_dir / f"metrics_{tag}.json").write_text(json.dumps({"summary": summary, "pairs": rows}, indent=1), encoding="utf-8")
with open(out_dir / f"metrics_{tag}.csv", "w", newline="", encoding="utf-8") as f:
    keys = ["camera", "ssim", "lum_ref", "lum_godot", "lum_ratio", "ev_diff", "de76_mean", "rg_shift", "bg_shift", "contrast_ref", "contrast_godot",
            "clip_hi_ref", "clip_hi_godot", "clip_lo_ref", "clip_lo_godot"]
    wr = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
    wr.writeheader()
    for r in ok:
        wr.writerow(r)
print(json.dumps(summary))
for r in ok:
    print(f"{r['camera']:28s} ev {r['ev_diff']:+.2f}  ssim {r['ssim']:.3f}  dE {r['de76_mean']:5.1f}  rg {r['rg_shift']:.2f} bg {r['bg_shift']:.2f}  contrast {r['contrast_ref']:.3f}/{r['contrast_godot']:.3f}  clipHi {r['clip_hi_ref']:.3f}/{r['clip_hi_godot']:.3f}")
