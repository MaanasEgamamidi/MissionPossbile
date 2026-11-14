"""Try lighting-preset variants on a few cameras and print how each compares with the Cycles reference.
  py -I tools/lighting_experiment.py <out_dir> <cams csv> <variants.json> [size]
variants.json: {"variant name": {"dotted.key": value, ...}, ...}  applied on top of data/lighting_preset.json.
Nothing here changes the saved preset or the main world scene; variants are built to scenes/world/_exp_world.tscn.
Regional EV differences (Godot minus reference, linear luminance): whole frame, top quarter, middle, bottom 30 %."""
import io
import json
import subprocess
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

PROJ = Path(__file__).resolve().parents[1]
GODOT = r"C:\Users\josev\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
REF = r"G:\nasa app\grand_colony_drive\beauty_shots_cycles_1080p.zip"
out_dir, cams, variants_path = Path(sys.argv[1]).resolve(), sys.argv[2], sys.argv[3]
size = sys.argv[4] if len(sys.argv) > 4 else "960x540"
out_dir.mkdir(parents=True, exist_ok=True)
base = json.loads((PROJ / "data" / "lighting_preset.json").read_text(encoding="utf-8"))
variants = json.loads(Path(variants_path).read_text(encoding="utf-8"))
z = zipfile.ZipFile(REF)
w, h = (int(v) for v in size.split("x"))


def lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def stats(img):
    a = lin(np.asarray(img.convert("RGB").resize((w, h), Image.LANCZOS), dtype=np.float64) / 255.0)
    y = a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722
    m = a.reshape(-1, 3).mean(0)
    return {"all": y.mean(), "top": y[: h // 4].mean(), "mid": y[h // 4: int(h * 0.7)].mean(), "bot": y[int(h * 0.7):].mean(), "rg": m[0] / m[1], "bg": m[2] / m[1],
            "std": (np.asarray(img.convert("L").resize((w, h)), dtype=np.float64) / 255.0).std()}


refs = {c: stats(Image.open(io.BytesIO(z.read(c + ".png")))) for c in cams.split(",")}
results = {}
for name, over in variants.items():
    p = json.loads(json.dumps(base))
    for k, v in over.items():
        d = p
        ks = k.split(".")
        for kk in ks[:-1]:
            d = d[kk]
        d[ks[-1]] = v
    exp_dir = PROJ / "data" / "_exp"
    exp_dir.mkdir(exist_ok=True)
    (exp_dir / "preset.json").write_text(json.dumps(p), encoding="utf-8")
    # materials depend on the preset too (emission scale, glass); regenerate only when a material key changed
    if any(k.startswith("materials.") for k in over):
        (PROJ / "data" / "lighting_preset.json.bak_exp").write_text(json.dumps(base, indent=1), encoding="utf-8")
        (PROJ / "data" / "lighting_preset.json").write_text(json.dumps(p, indent=1), encoding="utf-8")
        subprocess.run(["py", "-I", str(PROJ / "tools" / "gen_materials.py"), str(PROJ)], capture_output=True)
        (PROJ / "data" / "lighting_preset.json").write_text(json.dumps(base, indent=1), encoding="utf-8")
        (PROJ / "data" / "lighting_preset.json.bak_exp").unlink()
    subprocess.run([GODOT, "--headless", "--path", str(PROJ), "--script", "res://tools/godot/build_world.gd", "--", "--preset", "res://data/_exp/preset.json",
                    "--scene", "res://scenes/world/_exp_world.tscn", "--env", "res://scenes/world/lighting/_exp_env.tres"], capture_output=True)
    vdir = out_dir / name
    vdir.mkdir(exist_ok=True)
    subprocess.run([GODOT, "--path", str(PROJ), "--script", "res://tools/godot/capture_views.gd", "--", "--out", str(vdir), "--cams", cams, "--size", size,
                    "--frames", "80", "--world", "res://scenes/world/_exp_world.tscn"], capture_output=True)
    results[name] = {"overrides": over, "views": {}}
    gpu = {}
    try:
        gpu = {v["camera"]: v["render_gpu_ms"] for v in json.loads((vdir / "capture_report.json").read_text(encoding="utf-8"))["views"]}
    except Exception:
        pass
    for c in cams.split(","):
        f = vdir / (c + ".png")
        if not f.exists():
            print(f"{name:26s} {c}: NO CAPTURE")
            continue
        s, r = stats(Image.open(f)), refs[c]
        ev = {k: round(float(np.log2(max(s[k], 1e-9) / max(r[k], 1e-9))), 2) for k in ("all", "top", "mid", "bot")}
        row = {"gpu_ms": gpu.get(c), "ev": ev, "rg_shift": round(float(s["rg"] / r["rg"]), 3), "bg_shift": round(float(s["bg"] / r["bg"]), 3), "contrast": [round(float(r["std"]), 3), round(float(s["std"]), 3)]}
        results[name]["views"][c] = row
        print(f"{name:26s} {c[5:]:18s} ev all {ev['all']:+.2f} top {ev['top']:+.2f} mid {ev['mid']:+.2f} bot {ev['bot']:+.2f}  rg {row['rg_shift']:.2f} bg {row['bg_shift']:.2f}  contrast {row['contrast'][0]:.3f}/{row['contrast'][1]:.3f}  gpu {row['gpu_ms']} ms")
(out_dir / "experiment_results.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
