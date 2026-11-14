"""Prints markdown tables from perf_bench JSON files: python summarise.py a.json [b.json ...]"""
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        r = json.load(f)
    i = r["info"]
    print(f"\n### {path.split('/')[-1]} - {i['quality']}, cap {i['cap_fps']}, host {i['host_session']}, {i['window']}")
    print("| View | Frames | Mean FPS | Frame p50 / p95 / p99 ms | CPU ms mean / p95 | GPU ms mean / p95 | Draw calls mean | Primitives mean | Video MB | Private / WS MB after | 60 FPS? |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for v in r["views"]:
        s = v["summary"]
        fm = s["frame_ms"]
        pm = v.get("process_memory_after", {})
        ok = "yes" if fm["p95"] <= 16.7 else ("mean only" if fm["mean"] <= 16.7 else "no")
        print(f"| {v['view']} | {v['frames']} | {s['fps_mean']:.1f} | {fm['p50']:.1f} / {fm['p95']:.1f} / {fm['p99']:.1f} | "
              f"{s['cpu_ms']['mean']:.1f} / {s['cpu_ms']['p95']:.1f} | {s['gpu_ms']['mean']:.1f} / {s['gpu_ms']['p95']:.1f} | "
              f"{s['draw_calls']['mean']:.0f} | {s['primitives']['mean'] / 1e6:.2f} M | {s['video_mem_mb']['mean']:.0f} | "
              f"{pm.get('private_mb', 0):.0f} / {pm.get('working_set_mb', 0):.0f} | {ok} |")
    sw = r.get("quality_switch_memory", [])
    if sw:
        print("\nQuality switches (private / working set / static / video MB): " + "; ".join(
            f"#{m['switch']} {m.get('private_mb', 0):.0f}/{m.get('working_set_mb', 0):.0f}/{m['static_mb']:.0f}/{m['video_mb']:.0f}" for m in sw))
    print("\nInfo: " + json.dumps(i))
