"""Perf overhaul: one table comparing the A/B benchmark runs of tools/perf/run_perf_ab.sh.
  py -I tools/perf/summarise_ab.py "G:/nasa app/_perf"
For each view: GPU ms mean, frame ms p50, draw calls, primitives (M) per run, then the change of the mean of the two
'default' runs (and of the two 'all' runs) against the mean of the two 'off' runs. The off-vs-off spread is printed
so drift between runs can be told apart from a real change.
"""
import json
import sys
from pathlib import Path

d = Path(sys.argv[1])
runs = {}
for p in sorted(d.glob("ab_*_*.json")):
    n, mode = p.stem.split("_")[1:3]
    r = json.loads(p.read_text(encoding="utf-8"))
    runs[(int(n), mode)] = {v["view"]: v["summary"] for v in r["views"]}

order = sorted(runs)
views = list(next(iter(runs.values())).keys()) if runs else []


def avg(mode, view, key, stat="mean"):
    vals = [runs[k][view][key][stat] for k in order if k[1] == mode and view in runs[k]]
    return sum(vals) / len(vals) if vals else None


def pct(a, b):
    return f"{100.0 * (b - a) / a:+.0f} %" if a and b is not None else "-"


for key, label, stat in [("gpu_ms", "GPU ms (mean)", "mean"), ("frame_ms", "Frame ms (p50)", "p50"),
                         ("draw_calls", "Draw calls (mean)", "mean"), ("primitives", "Primitives (mean)", "mean")]:
    print(f"\n### {label}\n")
    print("| View | " + " | ".join(f"{n} {m}" for n, m in order) + " | off spread | default vs off | all vs off |")
    print("|---|" + "---|" * (len(order) + 3))
    for v in views:
        cells = []
        offs = []
        for k in order:
            x = runs[k].get(v, {}).get(key, {}).get(stat)
            if k[1] == "off" and x is not None:
                offs.append(x)
            cells.append("-" if x is None else (f"{x / 1e6:.2f} M" if key == "primitives" else (f"{x:.0f}" if key == "draw_calls" else f"{x:.1f}")))
        spread = pct(min(offs), max(offs)) if len(offs) > 1 else "-"
        o, df, al = avg("off", v, key, stat), avg("default", v, key, stat), avg("all", v, key, stat)
        print(f"| {v} | " + " | ".join(cells) + f" | {spread} | {pct(o, df)} | {pct(o, al)} |")
