"""Luminance statistics of PNG captures.  py -I tools/image_stats.py <out.json> label=path [label=path ...]
mean_lum: mean linear luminance (Rec.709, sRGB decoded). p99: 99th percentile of sRGB luma. bright: share of pixels with luma > 0.5."""
import json
import sys

import numpy as np
from PIL import Image

out = {}
for a in sys.argv[2:]:
    label, path = a.split("=", 1)
    im = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0
    lin = np.where(im <= 0.04045, im / 12.92, ((im + 0.055) / 1.055) ** 2.4)
    y = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722
    luma = im[..., 0] * 0.2126 + im[..., 1] * 0.7152 + im[..., 2] * 0.0722
    out[label] = {"file": path, "mean_lum": round(float(y.mean()), 5), "p99_luma": round(float(np.percentile(luma, 99)), 4), "max_luma": round(float(luma.max()), 4),
                  "bright_share": round(float((luma > 0.5).mean()), 5)}
    print(f"{label:34s} mean_lum {out[label]['mean_lum']:.5f}  p99 {out[label]['p99_luma']:.3f}  max {out[label]['max_luma']:.3f}  bright {out[label]['bright_share']:.4f}")
json.dump(out, open(sys.argv[1], "w", encoding="utf-8"), indent=1)
