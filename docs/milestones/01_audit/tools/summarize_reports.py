"""Print a compact comparison of the blend audit reports. Usage: summarize_reports.py <reports_dir> [labels...]"""
import json
import sys
from pathlib import Path

d = Path(sys.argv[1])
labels = sys.argv[2:] or sorted(p.name[:-13] for p in d.glob("*.summary.json"))
for lab in labels:
    p = d / f"{lab}.summary.json"
    if not p.exists():
        print(f"## {lab}: MISSING")
        continue
    s = json.loads(p.read_text(encoding="utf-8"))
    f = s["file"]
    print(f"## {lab}")
    print(f"   saved_with={'.'.join(map(str, f['saved_with_version']))} opened_with={f['opened_with']} bytes={f['bytes']} dirty_after={s['is_dirty_after_audit']}")
    print(f"   counts={ {k: v for k, v in s['counts'].items() if v} }")
    print(f"   scenes={s['scenes']}")
    print(f"   mesh_totals={s['mesh_totals']}")
    print(f"   objects={s['objects_by_type']} instanced_tris={s['instanced_scene_tris']} meshes_shared={s['meshes_shared']} coll_instances={s['collection_instances']}")
    print(f"   modifiers={s['modifiers']}")
    print(f"   custom_props={s['custom_property_keys']}")
    print(f"   lights={s['lights']} armatures={s['armatures']} actions={len(s['actions'])} skinned={s['skinned_meshes']}")
    print(f"   materials={s['materials_summary']}")
    print(f"   images={s['images']} missing={s['missing_files']} libraries={s['libraries']}")
    print(f"   category_hits={s['category_hits']}")
    print(f"   cameras({len(s['cameras'])})={s['cameras']}")
