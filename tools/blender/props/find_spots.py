"""Pick support spots for the cassette props: merges the visual height map (scan_heights.py, Blender, intact map) with
the collision height map + capsule-clear floor map + zones (a Godot probe of the running game, same grid). Plain
Python 3:
  py find_spots.py <vis.json> <col.json> [--tape 0.10] [--top 6]
A spot is good when, over a square of half size --tape around it, the visual top is flat (+-6 mm, one object) and the
collision top is present and between 1 cm under and 3.5 cm over the visual top, at 0.55 to 1.15 m; and a capsule-clear
floor cell of the right zone lies 0.30 to 0.60 m away (where the station's anchor goes).
"""
import json
import math
import sys

args = sys.argv[1:]
vis = json.load(open(args[0]))
col = json.load(open(args[1]))
opts = dict(zip(args[2::2], args[3::2]))
HALF = float(opts.get("--tape", "0.10"))
TOP = int(opts.get("--top", "6"))
ROOMS = {  # rect name: (zones, current anchor x, z)
    "cmd": (["Command Room"], [(27.0, -14.8), (28.4, -13.0)]),
    "pwr": (["Power Room"], [(31.0, 4.0)]),
    "grh": (["Greenhouse"], [(-5.0, 2.0)]),
    "dome": (["Garden dome"], [(50.0, 23.0)]),
    "med": (["Med Bay"], [(-8.0, -12.0)]),
    "hgr": (["Hangar bay", "Airlock"], [(25.0, -1.3)]),
}
objects = vis["objects"]
for name, (zones, anchors) in ROOMS.items():
    V, C = vis[name], col[name]
    step, nx, nz, x0, z0 = V["step"], V["nx"], V["nz"], V["x0"], V["z0"]
    r = int(round(HALF / step))
    clear = [(ix, iz) for iz in range(nz) for ix in range(nx) if C["c"][iz][ix][1] == 1 and C["c"][iz][ix][2] in zones]
    found = []
    for iz in range(r, nz - r):
        for ix in range(r, nx - r):
            v = V["h"][iz][ix]
            if v is None or not (0.55 <= v[0] <= 1.15):
                continue
            y, ob = v
            ok = True
            worst = 0.0
            for dz in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    w = V["h"][iz + dz][ix + dx]
                    c = C["c"][iz + dz][ix + dx][0]
                    if w is None or w[1] != ob or abs(w[0] - y) > 0.006 or c is None or not (-0.01 <= c - y <= 0.035):
                        ok = False
                        break
                    worst = max(worst, abs(c - y))
                if not ok:
                    break
            if not ok:
                continue
            x, z = x0 + ix * step, z0 + iz * step
            best = None
            for cx, cz in clear:
                d = math.hypot((cx - ix) * step, (cz - iz) * step)
                if 0.30 <= d <= 0.60 and (best is None or abs(d - 0.42) < abs(best[2] - 0.42)):
                    best = (x0 + cx * step, z0 + cz * step, d)
            if best is None:
                continue
            move = min(math.hypot(x - ax, z - az) for ax, az in anchors)
            found.append((move, objects[ob], round(x, 2), round(y, 3), round(z, 2), round(worst, 3), (round(best[0], 2), round(best[1], 2), round(best[2], 2))))
    found.sort()
    print("==", name, len(found), "spots")
    seen = {}
    for f in found:
        seen.setdefault(f[1], []).append(f)
    for ob, fs in sorted(seen.items(), key=lambda kv: kv[1][0][0]):
        print("  %-24s n=%-4d nearest: move %.2f m spot (%.2f, %.3f, %.2f) col+%.3f anchor %s" % (ob, len(fs), fs[0][0], fs[0][2], fs[0][3], fs[0][4], fs[0][5], fs[0][6]))
        for f in fs[1:TOP]:
            pass
