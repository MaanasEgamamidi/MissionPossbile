"""Eye-level cameras for render_props_in_map.py (Godot coordinates), written to tools/blender/props/shots.json:
  py make_shots.py <godot project>
tape_<room> / player: one wide camera that sees both the old floating model (station before the change, anchor + 1 m)
and the new prop on its surface; <shot>_close: the new prop from the anchor side, 0.9 m away (after only).
station_t01: the T01 repair station (its orange marker plate before); airlock_sign: the old and the new pressure sign.
Hand overrides in OVERRIDE keep cameras out of furniture (checked in the renders).
"""
import json
import math
import os
import sys

PROJ = sys.argv[1]
old = {s["id"]: s for s in json.load(open(os.path.join(PROJ, "tools", "blender", "props", "reports", "stations_before.json")))["stations"]}
new = {s["id"]: s for s in json.load(open(os.path.join(PROJ, "data", "stations_repairs.json")))["stations"]}
EYE = 1.6
OVERRIDE = {
    "station_t01": {"eye": [29.2, 1.64, -15.2], "look": [31.55, 1.0, -12.95]},
    "airlock_sign": {"eye": [22.6, 1.64, 5.4], "look": [23.4, 2.0, 9.9]},
}
shots = {}
for sid, s in new.items():
    if s["kind"] not in ("cassette_anchor", "cassette_player_anchor"):
        continue
    name = "player" if s["kind"] == "cassette_player_anchor" else "tape_" + s["room_id"]
    prop = s["prop_position"]
    anchor = s["position"]
    o = old[sid]["position"]
    old_c = [o[0], o[1] + 0.9, o[2]]
    dx, dz = anchor[0] - prop[0], anchor[2] - prop[2]
    d = math.hypot(dx, dz) or 1.0
    dx, dz = dx / d, dz / d
    mid = [(prop[0] + old_c[0]) * 0.5, (prop[1] + old_c[1]) * 0.5, (prop[2] + old_c[2]) * 0.5]
    sep = math.hypot(prop[0] - old_c[0], prop[2] - old_c[2])
    dist = max(1.8, sep * 0.9 + 1.2)
    shots[name] = {"eye": [round(mid[0] + dx * dist, 2), round(anchor[1] + EYE, 2), round(mid[2] + dz * dist, 2)],
                   "look": [round(v, 3) for v in mid]}
    close = 1.1 if name == "player" else 0.8
    shots[name + "_close"] = {"eye": [round(prop[0] + dx * close, 2), round(anchor[1] + EYE, 2), round(prop[2] + dz * close, 2)],
                              "look": [prop[0], prop[1] + (0.1 if name == "player" else 0.01), prop[2]], "after_only": True}
shots.update(OVERRIDE)
for k, v in json.load(open(os.path.join(PROJ, "tools", "blender", "props", "shot_overrides.json"))).items() if os.path.exists(os.path.join(PROJ, "tools", "blender", "props", "shot_overrides.json")) else []:
    shots[k] = v
json.dump(shots, open(os.path.join(PROJ, "tools", "blender", "props", "shots.json"), "w"), indent=1)
for k, v in shots.items():
    print(k, v)
