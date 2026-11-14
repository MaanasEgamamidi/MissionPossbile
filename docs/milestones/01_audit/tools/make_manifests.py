"""Build the camera manifest (JSON + CSV) and the coverage table from a blend audit report.
Usage: make_manifests.py <report.json> <out_dir> <existing_renders_root>"""
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

rep = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
out = Path(sys.argv[2])
renders_root = Path(sys.argv[3])
scene = rep["scenes"][0]

AREAS = {  # area module prefix -> (display name, room/collection name)
    "a01_medbay": "Med Bay", "a02_commons": "Mess hall", "a03_rec_kitchen": "Rec kitchen", "a04_pipe_gallery": "Pipe gallery",
    "a05_hangar": "Hangar bay", "a06_service_corridor": "Service corridor", "a07_airlock": "Airlock", "a08_power": "Power Room",
    "a09_lifesupport": "Life Support", "a10_east_quarters": "East quarters", "a11_command": "Command Room",
    "a12_blast_passage": "Blast-door passage", "a13_exterior": "Exterior (crater floor)", "a14_greenhouse": "Greenhouse",
    "a15_garden_dome": "Garden dome", "x_crew_corridor": "Crew corridor", "x_west_bunk": "West bunk room", "x_plaza": "Dome plaza",
    "x_roof": "Roofs", "x_shell": "Shell (walls/doors)",
}
SHOT_AREA = {"MedBay": "Med Bay", "MessHall": "Mess hall", "RecKitchen": "Rec kitchen", "CrewCorridor": "Crew corridor", "Hangar": "Hangar bay",
             "Airlock": "Airlock", "PowerRoom": "Power Room", "LifeSupport": "Life Support", "Command": "Command Room", "EastQuarters": "East quarters",
             "Greenhouse": "Greenhouse", "WestBunk": "West bunk room", "Exterior_Airlock": "Exterior (crater floor)", "Exterior_Wide": "Exterior (crater floor)",
             "GardenDome": "Garden dome"}


def area_of(name):
    if name.startswith("Shot_"):
        return SHOT_AREA.get(name.split("_", 2)[2], "?"), "beauty"
    if name.startswith("Rv_"):
        for k, v in AREAS.items():
            if name.startswith("Rv_" + k):
                return v, "review"
        return "?", "review"
    if name.startswith("Cam_Hangar"):
        return "Hangar bay", "legacy"
    return ("Asset library" if "Library" in name else "Overview"), "legacy"


existing = defaultdict(list)
for p in renders_root.rglob("*.png"):
    existing[p.stem].append(p)

cams = []
for c in rep["cameras"]:
    area, kind = area_of(c["name"])
    stem = c["name"][3:] if c["name"].startswith("Rv_") else c["name"]
    hits = sorted(existing.get(stem, []), key=lambda p: p.stat().st_mtime, reverse=True)
    cams.append({
        "name": c["name"], "kind": kind, "area": area, "collection": c["collections"][0] if c["collections"] else None,
        "location_m": c["location"], "rotation_euler_xyz_deg": c["rotation_euler_xyz_deg"], "forward": c["forward"],
        "projection": c["type"], "lens_mm": c["lens_mm"], "sensor_width_mm": c["sensor_width"], "sensor_fit": c["sensor_fit"],
        "hfov_deg_at_16x9": c["angle_x_deg"], "vfov_deg_at_16x9": round(2 * __import__("math").degrees(__import__("math").atan(__import__("math").tan(__import__("math").radians(c["angle_x_deg"]) / 2) * 9 / 16)), 3),
        "clip_start_end_m": c["clip"], "shift": c["shift"], "dof": c["dof"]["use"], "animated": c["animated"],
        "matrix_world": c["matrix_world"],
        "existing_render_count": len(hits),
        "latest_existing_render": str(hits[0]).replace("\\", "/") if hits else None,
    })

manifest = {
    "generated": "2026-11-11",
    "source_blend": rep["file"]["filepath"],
    "source_note": "Read-only audit of the CURRENT map. The owner-supplied improved map has not been delivered; Prompt 02 must regenerate this manifest from that map's own scene.",
    "coordinate_system": "Blender: right-handed, Z up, metres. Godot/glTF: Y up, -Z forward; (x, y, z)_blender -> (x, z, -y)_godot.",
    "scene_render_settings": {k: scene[k] for k in ("engine", "resolution", "fps", "color_management", "units")},
    "cycles_settings_saved_in_file": scene.get("cycles"),
    "compositor_nodes": scene.get("compositor_nodes"),
    "caveats": [
        "The saved compositor (glare, lens distortion, colour balance, vignette blur) alters final pixels; parity references must either disable it or reproduce it in Godot, and the choice must be recorded per pair.",
        "View transform AgX with look 'AgX - Punchy' and exposure -0.45 EV is part of the reference appearance.",
        "vfov is derived for a 16:9 frame with sensor_fit AUTO (horizontal fit); recompute if a camera is rendered at another aspect ratio.",
        "No camera is animated and none uses depth of field.",
    ],
    "counts": {"total": len(cams), "beauty": sum(c["kind"] == "beauty" for c in cams), "review": sum(c["kind"] == "review" for c in cams), "legacy": sum(c["kind"] == "legacy" for c in cams)},
    "cameras": cams,
}
(out / "camera_manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
with open(out / "camera_manifest.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["name", "kind", "area", "x", "y", "z", "rot_x_deg", "rot_y_deg", "rot_z_deg", "lens_mm", "hfov_deg", "vfov_deg", "clip_start", "clip_end", "existing_renders", "latest_existing_render"])
    for c in cams:
        w.writerow([c["name"], c["kind"], c["area"], *c["location_m"], *c["rotation_euler_xyz_deg"], c["lens_mm"], c["hfov_deg_at_16x9"], c["vfov_deg_at_16x9"], *c["clip_start_end_m"], c["existing_render_count"], c["latest_existing_render"] or ""])

cov = defaultdict(lambda: {"beauty": [], "review": 0, "review_with_render": 0, "legacy": 0})
for c in cams:
    d = cov[c["area"]]
    if c["kind"] == "beauty":
        d["beauty"].append(c["name"])
    elif c["kind"] == "review":
        d["review"] += 1
        d["review_with_render"] += 1 if c["existing_render_count"] else 0
    else:
        d["legacy"] += 1
print("counts", manifest["counts"])
for a in sorted(cov):
    d = cov[a]
    print(f"{a}|{', '.join(d['beauty']) or '-'}|{d['review']}|{d['review_with_render']}|{d['legacy']}")
unknown = [c["name"] for c in cams if c["area"] == "?"]
print("unmapped:", unknown)
