"""Print the audit details needed for the asset-readiness report, and diff the grand_colony variants.
Usage: report_details.py <reports_dir> <label> [other_label ...]"""
import json
import sys
from collections import Counter
from pathlib import Path

d = Path(sys.argv[1])
lab = sys.argv[2]
R = json.loads((d / f"{lab}.json").read_text(encoding="utf-8"))


def tree(n, ind=0, out=None):
    out = [] if out is None else out
    out.append(f"{'  ' * ind}{n['name']}  [direct={n['direct_objects']} all={n['all_objects']} tris={n['instanced_tris']:,}{' HIDDEN_RENDER' if n.get('hide_render') else ''}]")
    for c in n.get("children", []):
        tree(c, ind + 1, out)
    return out


print("== scene settings")
for s in R["scenes"]:
    print(json.dumps({k: s[k] for k in ("name", "engine", "resolution", "fps", "frame_range", "active_camera", "units", "color_management", "gravity", "cycles", "eevee", "compositor_nodes") if k in s}, default=str))
print("== worlds", json.dumps(R["worlds"]))
print("== scene bbox", json.dumps(R["scene_bbox"]))
print("== collection tree")
for t in R["collection_trees"]:
    print("\n".join(tree(t["tree"])))
print("== collection bboxes (top level)")
for k, v in R["collection_bboxes"].items():
    if v and k.count("/") == 1:
        print(f"   {k}: size={v['size']} min={v['min']} max={v['max']}")
print("== objects misc", {k: R["objects"][k] for k in ("parented", "hidden_in_render", "lod_like_name_tokens", "non_unit_scale_objects", "negative_scale_objects", "meshes_used_once", "meshes_shared", "mesh_objects")})
print("== name prefixes", R["objects"]["name_prefixes_top"])
print("== top shared meshes", R["objects"]["top_shared_meshes"][:25])
print("== top meshes by tris")
for m in R["meshes_top_by_tris"][:25]:
    print(f"   {m['name']}: tris={m['tris']:,} users={m['users']} mats={m['materials']} uv={m['uv_layers']} colattr={m['color_attributes']}")
print("== meshes with color attributes")
for m in R["meshes_with_color_attributes_sample"]:
    print(f"   {m['name']}: tris={m['tris']:,} colattr={m['color_attributes']} mats={m['materials']}")
ms = R["materials_summary"]
print("== materials: node kinds", ms["node_kind_totals"])
print("== glass/transmissive", ms["transmissive_or_glass"])
print("== emissive", ms["emissive"][:40])
print("== volume materials", [m["name"] for m in R["materials"] if m.get("has_volume")])
attr = Counter()
print("== node groups", R["node_groups"])
print("== images", R["images"])
ls = R["lights_summary"]
print("== lights summary", json.dumps({k: ls[k] for k in ("by_type", "energy_sum_by_type", "unique_light_datablocks", "light_objects")}))
print("== lights by collection", ls["by_collection"])
pref = Counter(l["name"].split("_")[0] for l in R["lights"])
print("== light name prefixes", dict(pref.most_common(20)))
shapes = Counter((l["type"], l.get("shape")) for l in R["lights"])
print("== light shapes", dict((str(k), v) for k, v in shapes.items()))
en = sorted(R["lights"], key=lambda l: -l["energy"])
print("== strongest lights", [(l["name"], l["type"], l["energy"], l.get("size"), l.get("size_y")) for l in en[:8]])
print("== suns", [(l["name"], l["energy"], l["color"], l.get("angle"), l["location"], l["collections"]) for l in R["lights"] if l["type"] == "SUN"])
print("== lights with temperature/exposure/normalize keys sample", {k: en[0].get(k) for k in ("exposure", "temperature", "use_temperature", "normalize", "use_custom_distance", "cutoff_distance")})
print("== lightprobes", Counter(p["type"] for p in R["lightprobes"]), R["lightprobes"][:3])
cams = R["cameras"]
print("== cameras", len(cams), dict(Counter(c["name"].split("_")[0] for c in cams)))
print("== camera lens/sensor", dict(Counter((c["lens_mm"], c["sensor_width"], c["sensor_fit"], c["type"]) for c in cams).most_common(12)))
print("== camera clip", dict(Counter(tuple(c["clip"]) for c in cams).most_common(6)), "dof on:", sum(1 for c in cams if c["dof"]["use"]), "animated:", sum(1 for c in cams if c["animated"]))
for c in cams:
    if c["name"].startswith("Shot_"):
        print(f"   {c['name']}: loc={c['location']} rot={c['rotation_euler_xyz_deg']} lens={c['lens_mm']} fovx={c['angle_x_deg']} coll={c['collections']}")
print("== category search")
for k, v in R["category_search"].items():
    print(f" - {k}: hits={v['object_hits']} tris={v['tris']:,} types={v['types']} colls={v['collections'][:6]}")
    print(f"     roots={v['root_objects_top'][:8]}")
    print(f"     names={v['sample_names'][:24]}")

for other in sys.argv[3:]:
    O = json.loads((d / f"{other}.json").read_text(encoding="utf-8"))
    print(f"== DIFF {lab} vs {other}")
    for key in ("counts", "mesh_totals"):
        if R[key] != O[key]:
            print("   differs:", key, {k: (R[key].get(k), O[key].get(k)) for k in R[key] if R[key].get(k) != O[key].get(k)})
        else:
            print("   same:", key)
    for i, (a, b) in enumerate(zip(R["scenes"], O["scenes"])):
        diff = {k: (a.get(k), b.get(k)) for k in a if a.get(k) != b.get(k)}
        print("   scene diff:", json.dumps(diff, default=str)[:1500])
    ca = {c["name"]: c for c in R["cameras"]}
    cb = {c["name"]: c for c in O["cameras"]}
    print("   cameras only in A:", sorted(set(ca) - set(cb))[:10], "only in B:", sorted(set(cb) - set(ca))[:10])
    moved = [n for n in ca if n in cb and (ca[n]["matrix_world"] != cb[n]["matrix_world"] or ca[n]["lens_mm"] != cb[n]["lens_mm"])]
    print("   cameras with different transform/lens:", len(moved), moved[:10])
    la = {l["name"]: l for l in R["lights"]}
    lb = {l["name"]: l for l in O["lights"]}
    print("   lights only in A:", sorted(set(la) - set(lb))[:10], "only in B:", sorted(set(lb) - set(la))[:10])
    ld = [n for n in la if n in lb and any(la[n].get(k) != lb[n].get(k) for k in ("energy", "color", "location", "size", "size_y", "type", "shape"))]
    print("   lights with different energy/colour/position/size:", len(ld), [(n, la[n]["energy"], lb[n]["energy"]) for n in ld[:8]])
    lk = set()
    for n in la:
        if n in lb:
            for k in set(la[n]) | set(lb[n]):
                if la[n].get(k) != lb[n].get(k):
                    lk.add(k)
    print("   light keys that differ anywhere:", sorted(lk))
    ma = {m["name"]: m for m in R["materials"]}
    mb = {m["name"]: m for m in O["materials"]}
    md = [n for n in ma if n in mb and ma[n] != mb[n]]
    print("   materials differing:", len(md), md[:10], "only A:", sorted(set(ma) - set(mb))[:5], "only B:", sorted(set(mb) - set(ma))[:5])
    print("   worlds same:", R["worlds"] == O["worlds"])
    print("   objects block same:", R["objects"] == O["objects"], "| collection trees same:", R["collection_trees"] == O["collection_trees"], "| bbox same:", R["scene_bbox"] == O["scene_bbox"])
