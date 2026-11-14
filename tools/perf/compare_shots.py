"""Perf overhaul: image comparison of benchmark stills (tools/perf/run_perf_ab.sh saves one per view and run).
  py -I tools/perf/compare_shots.py <baseline_dir> <other_dir> <out_dir> <tag>
For each view PNG in both folders prints and writes (<out_dir>/shots_<tag>.json):
  mean_abs   mean absolute difference of the sRGB pixels, 0-255 scale (0 = identical)
  changed    fraction of pixels whose largest channel difference is over 8/255 (a visible change)
  ssim       structural similarity of the luma at 960x540 (1.0 = identical; Gaussian 11x11, sigma 1.5)
and saves <out_dir>/sheets_<tag>/<view>.jpg: baseline | other | difference x4.
Temporal effects that differ between any two runs (crew idle animation, dust noise) show up as small changes too:
compare against the off-vs-off noise floor when it is available.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def gaussian_ssim(a, b):
    from numpy.lib.stride_tricks import sliding_window_view  # noqa: F401  (numpy >= 1.20)
    k = np.exp(-((np.arange(11) - 5) ** 2) / (2 * 1.5 ** 2))
    k /= k.sum()

    def blur(x):
        x = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, x)
        return np.apply_along_axis(lambda c: np.convolve(c, k, mode="same"), 0, x)

    c1, c2 = 0.01 ** 2, 0.03 ** 2
    mu_a, mu_b = blur(a), blur(b)
    sa = blur(a * a) - mu_a ** 2
    sb = blur(b * b) - mu_b ** 2
    sab = blur(a * b) - mu_a * mu_b
    s = ((2 * mu_a * mu_b + c1) * (2 * sab + c2)) / ((mu_a ** 2 + mu_b ** 2 + c1) * (sa + sb + c2))
    return float(s.mean())


def luma(img):
    x = np.asarray(img.convert("RGB").resize((960, 540), Image.BILINEAR), dtype=np.float64) / 255.0
    return 0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2]


base, other, out, tag = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
sheets = out / f"sheets_{tag}"
sheets.mkdir(parents=True, exist_ok=True)
rows = {}
for p in sorted(base.glob("*.png")):
    q = other / p.name
    if not q.exists():
        continue
    a = Image.open(p).convert("RGB")
    b = Image.open(q).convert("RGB")
    if b.size != a.size:
        b = b.resize(a.size)
    xa = np.asarray(a, dtype=np.int16)
    xb = np.asarray(b, dtype=np.int16)
    d = np.abs(xa - xb)
    row = {
        "mean_abs": round(float(d.mean()), 3),
        "changed": round(float((d.max(axis=2) > 8).mean()), 5),
        "ssim": round(gaussian_ssim(luma(a), luma(b)), 5),
    }
    rows[p.stem] = row
    print(f"{p.stem:22s} mean_abs {row['mean_abs']:7.3f}  changed {100 * row['changed']:6.2f} %  ssim {row['ssim']:.4f}")
    w, h = a.size
    sheet = Image.new("RGB", (w * 3 // 2, h // 2))
    sheet.paste(a.resize((w // 2, h // 2)), (0, 0))
    sheet.paste(b.resize((w // 2, h // 2)), (w // 2, 0))
    diff = Image.fromarray(np.clip(d * 4, 0, 255).astype(np.uint8))
    sheet.paste(diff.resize((w // 2, h // 2)), (w, 0))
    sheet.save(sheets / f"{p.stem}.jpg", quality=88)
(out / f"shots_{tag}.json").write_text(json.dumps(rows, indent=2))
