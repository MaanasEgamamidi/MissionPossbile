"""Second step after export_broken_parts.py (run once per part .blend). Plain Python, no Blender:
  py -I tools/blender/broken_parts/build_broken_parts_data.py [project_dir]

  1. adds the palette records of the new broken-part roles (bp_*) from the export reports to data/palette.json
     (existing roles are never changed);
  2. writes their materials materials/colony/bp_<role>.tres with tools/gen_materials.py, run on a scratch copy so the
     242 colony materials are not rewritten; only the new bp_* files are copied in;
  3. writes assets/broken_parts/BPnn.glb.import (post-import script broken_part_post_import.gd) where missing;
  4. writes data/broken_parts.json (the contract of docs/revisions/BROKEN_PARTS_BRIEF.md) from the reports + PARTS.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJ = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
REPORTS = Path(__file__).resolve().parent / "reports"

# Per-part game data. spot = the brief's Godot spot (BROKEN_PARTS_BRIEF.md table); zone = ColonyZones zone name;
# hide_objects = map objects (data/colony_manifest.json names) the broken model replaces while the task is broken.
PARTS = [
    dict(task_id="T09", part="BP01_lab_test_tubes", key="BP01", zone="Med Bay", spot=[-11.5, 0, -12.45],
         hide_objects=["mb_sink_counter"], prompt="[E] Fix the test-tube rack", special=""),
    dict(task_id="T10", part="BP02_plug_in_equipment", key="BP02", zone="Med Bay", spot=[-3.9, 0, -17.5],
         hide_objects=["md_heal_station", "mb_pdu", "mb_ct"], prompt="[E] Fix the unplugged equipment", special=""),
    dict(task_id="T02", part="BP03_wires_task", key="BP03", zone="Command Room", spot=[25.1, 0, -17.4],
         hide_objects=["cr_rack"], prompt="[E] Fix the wires", special=""),
    dict(task_id="T01", part="BP04_comms_task", key="BP04", zone="Command Room", spot=[30.15, 0, -11.7],
         hide_objects=["cr_console_alarm"], prompt="[E] Fix the radio signal", special=""),
    dict(task_id="T08", part="BP05_dome_glass", key="BP05", zone="Garden dome", spot=[50.0, 0, 27.0],
         hide_objects=["gd_shell"], prompt="[E] Repair the broken glass", special=""),
    dict(task_id="T03", part="BP06_circle_electrical", key="BP06", zone="Power Room", spot=[36.9, 0, 9.4],
         hide_objects=["pr_swgr.003", "pr_swgr.004", "pr_inverter", "pr_inverter.001"], prompt="[E] Fix the power dials", special=""),
    dict(task_id="T04", part="BP07_circuit_puzzle", key="BP07", zone="Power Room", spot=[30.0, 0, 9.45],
         hide_objects=["pw_panel"], prompt="[E] Repair the power circuit", special=""),
    dict(task_id="T12", part="BP08_airlock_air_leak", key="BP08", zone="Airlock", spot=[22.0, 0, 10.45],
         hide_objects=[], prompt="[E] Repair the air leak", special="door_901"),
    dict(task_id="T06", part="BP09_water_pipe", key="BP09", zone="Greenhouse", spot=[0.85, 0, 10.6],
         hide_objects=["gr_rack.002", "gr_tray_romaine.001", "gr_tray_kale", "gr_tray_harvested"], prompt="[E] Fix the broken pipe", special=""),
    dict(task_id="T11", part="BP10_hangar_dust", key="BP10", zone="Hangar bay", spot=[22.0, 0, -3.0],
         hide_objects=[], prompt="[E] Clean the dusty hangar", special="dust"),
]
ROOM_OF = {"T01": "command_center", "T02": "command_center", "T03": "power_supply", "T04": "power_supply", "T06": "greenhouse",
           "T08": "green_dome", "T09": "med_bay", "T10": "med_bay", "T11": "hangar", "T12": "hangar"}
# Glass-shader settings of the see-through broken-part roles (designer balance, not from a source): gen_materials gives every
# glass role the clear-glazing roughness 0.03 and grazing-angle opacity 0.85, which makes mist puffs look like bubbles.
MAT_OVERRIDES = {
    "bp_vapour": {"opacity": 0.66, "roughness": 0.8, "edge_opacity": 0.3},    # thick cartoon cloud puffs (redo), softer at the silhouette
    "bp_haze": {"roughness": 0.45, "edge_opacity": 0.7},                      # frosted / crazed glass (Blender rough 0.45)
    "bp_shard": {"roughness": 0.28},                                          # Blender rough 0.28
    "bp_dust_haze": {"opacity": 0.22, "roughness": 0.9, "edge_opacity": 0.04},  # floating dust: soft, thinner at its edge
}
DUST_BROKEN = 3.0       # BP10_hangar_dust.blend: every Broken hangar object has dust = 3.0 (dust_map = the map's 0.55)

ABOUT = {
    "what": "The 10 broken parts of the new tutorial (G:/nasa app/broken_parts/BPnn_*.blend), exported to Godot by "
            "tools/blender/broken_parts/export_broken_parts.py + build_broken_parts_data.py. Contract: docs/revisions/BROKEN_PARTS_BRIEF.md.",
    "coordinates": "Godot world metres. Each glb is already placed (Blender map_matrix_world, Blender (x, y, z) -> Godot (x, z, -y)): "
                   "instance it at the origin (identity transform) under the world.",
    "glb": "Root node = the glb's file name (BP01..BP10). Its children are the nodes listed in `nodes` (name, kind, parent). "
           "Materials are the shared res://materials/colony/<role>.tres (assets/broken_parts/broken_part_post_import.gd), render layers "
           "come from ColonyZones like the map's pieces, and every mesh has the `dust` instance uniform set.",
    "kind": "model = the broken object itself (fades/shrinks out at the fix); effect = vapour / water spray / puddle / spilled liquid / "
            "glass shards / dust / alarm lamps, stopped at the same moment; seal = BP08 door seal piece, a child of its leaf.",
    "hide_objects": "data/colony_manifest.json object names hidden while broken; hide_nodes = the same as Godot node names under the "
                    "Colony instance of scenes/world/colony_world.tscn (the glTF import turns 'a.001' into 'a_001').",
    "bounds": "AABB of every node of the glb (Godot). model_bounds = only the model nodes (the sparkle burst area).",
    "spot": "the brief's Godot spot of the part; station_id = the repair station in data/stations_repairs.json that opens its mini-game.",
    "special": "'' normal swap; 'door_901' = see `door` (T12); 'dust' = see `dust` (T11).",
    "door_leaves": "T12: the nodes that slide with each leaf of door 901 (L slides -x, R +x).",
    "door": "T12: the exit-tunnel inner door (EnvironmentCollision door 901). Its intact leaves are not map objects: EnvironmentCollision "
            "cuts them out of SFX_tunnel_inside (environment.glb) at run time as the Node3D/MeshInstance3D nodes named in "
            "hide_env_nodes (siblings of SFX_tunnel_inside). While broken, hide those and show the glb's leaves; to slide a broken leaf, move "
            "its node along slide_axis by slide_m * open_amount from its rest transform (same as DoorController: left -1.75 m, right +1.75 m "
            "on Godot x). The seal nodes are children of their leaf and move with it. alarm/vapour are effects; light = the red alarm glow "
            "of the source render (optional, add an OmniLight3D there if wanted).",
    "dust": "T11: the hangar objects keep their meshes; while broken set the instance uniform `dust` (colony_surface.gdshader, "
            "instance uniform float dust) of every MeshInstance3D of the Hangar area to broken_value, and back to its fixed value afterwards "
            "(the manifest object's dust: 0.55 for the Hangar, hb_rover 1.0). broken_value 3.0 is the source blend's value; the "
            "shader clamps dust x surface mask to 0..1, so 3.0 = upward faces fully covered. The dust mesh hg_dust__broken (drifts, floor "
            "layer, boot prints) is cut into a 12 x 2 grid of patch nodes hg_dust__broken_r<row>c<col> (dust_nodes; rows along Godot z, "
            "columns along x over dust_region, the same grid HangarDust.area_of uses), shown only while broken, hidden area by area.",
}


def load_reports():
    out = {}
    for p in PARTS:
        rp = REPORTS / ("%s_export.json" % p["key"])
        rep = json.loads(rp.read_text(encoding="utf-8"))
        if not rep.get("ok"):
            raise SystemExit("export of %s failed: %s" % (p["key"], rep.get("error")))
        out[p["key"]] = rep
    return out


def add_palette(reports):
    path = PROJ / "data" / "palette.json"
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)
    added = []
    for rep in reports.values():
        for role, rec in rep["palette"].items():
            ours = role in data["roles"] and str(data["roles"][role].get("note") or "").startswith(("broken-part role", "alias of"))
            if role not in data["roles"] or (ours and data["roles"][role] != rec):     # new, or one of ours re-exported
                if not role.startswith("bp_"):
                    raise SystemExit("role %s is not in the colony palette and has no bp_ alias" % role)
                data["roles"][role] = rec
                added.append(role)
    if added:
        path.write_text(json.dumps(data, indent=1), encoding="utf-8", newline="\n")
    return sorted(added), data


def write_materials(palette, roles):
    new_roles = sorted(r for r in palette["roles"] if r.startswith("bp_"))
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        (t / "data").mkdir()
        (t / "data" / "palette.json").write_text(json.dumps(palette), encoding="utf-8")
        shutil.copy(PROJ / "data" / "lighting_preset.json", t / "data" / "lighting_preset.json")
        subprocess.run([sys.executable, "-I", str(PROJ / "tools" / "gen_materials.py"), str(t)], check=True)
        written = []
        for role in new_roles:
            if role not in roles:
                continue                           # bp_pipe / bp_steel / bp_chrome belong to the map, never rewritten here
            src = (t / "materials" / "colony" / ("%s.tres" % role)).read_text(encoding="utf-8")
            for k, v in MAT_OVERRIDES.get(role, {}).items():
                lines = src.splitlines()
                lines = [("shader_parameter/%s = %s" % (k, v)) if ln.startswith("shader_parameter/%s = " % k) else ln for ln in lines]
                src = "\n".join(lines) + "\n"
            (PROJ / "materials" / "colony" / ("%s.tres" % role)).write_text(src.replace("\r\n", "\n"), encoding="utf-8", newline="\n")
            written.append(role)
    return written


IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/broken_parts/{key}.glb"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=false
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=0
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path="res://assets/broken_parts/broken_part_post_import.gd"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=0
"""


def write_imports():
    made = []
    for p in PARTS:
        f = PROJ / "assets" / "broken_parts" / ("%s.glb.import" % p["key"])
        if not f.exists():
            f.write_text(IMPORT.format(key=p["key"]), encoding="utf-8", newline="\n")
            made.append(f.name)
    return made


def union(nodes):
    lo = [min(n["aabb_min"][i] for n in nodes) for i in range(3)]
    hi = [max(n["aabb_max"][i] for n in nodes) for i in range(3)]
    return {"center": [round((lo[i] + hi[i]) / 2, 4) for i in range(3)], "size": [round(hi[i] - lo[i], 4) for i in range(3)]}


def build_json(reports):
    manifest = json.loads((PROJ / "data" / "colony_manifest.json").read_text(encoding="utf-8"))
    parts = []
    for p in PARTS:
        rep = reports[p["key"]]
        nodes = rep["nodes"]
        rec = {"task_id": p["task_id"], "part": p["part"], "glb": "res://assets/broken_parts/%s.glb" % p["key"], "zone": p["zone"],
               "room_id": ROOM_OF[p["task_id"]], "station_id": "repair_" + p["task_id"].lower(),
               "hide_objects": p["hide_objects"], "hide_nodes": [n.replace(".", "_") for n in p["hide_objects"]],
               "effect_nodes": [n["name"] for n in nodes if n["kind"] == "effect"],
               "model_nodes": [n["name"] for n in nodes if n["kind"] == "model"],
               "bounds": union(nodes), "model_bounds": union([n for n in nodes if n["kind"] != "effect"] or nodes),
               "spot": p["spot"], "prompt": p["prompt"], "special": p["special"],
               "nodes": [{k: n[k] for k in ("name", "kind", "parent", "source_object", "aabb_min", "aabb_max", "tris")} for n in nodes],
               "source_blend": rep["source"]["blend"], "source_sha256": rep["source"]["sha256"]}
        if p["special"] == "door_901":
            by = {n["name"]: n for n in nodes}

            def leaf(side, slide):
                n = by["tunnel_door_inner_leaf_%s__broken" % side]
                return {"node": n["name"], "seal_node": "tunnel_door_inner_seal_%s__broken" % side, "rest_origin": n["origin_godot"],
                        "intact_rest_x": 21.1 if side == "L" else 22.9, "slide_axis": [1, 0, 0], "slide_m": slide,
                        "intact_node": "TunnelDoorInner_%s" % side}
            rec["door"] = {"door_id": 901, "env_object": "SFX_tunnel_inside", "hide_env_nodes": ["TunnelDoorInner_L", "TunnelDoorInner_R"],
                           "left": leaf("L", -1.75), "right": leaf("R", 1.75),
                           "broken_pose": "left leaf stops 12 cm short of the centre (rest x 20.98, intact 21.1); right leaf is jammed 30 cm "
                                          "open and tilted 4 deg off its floor guide (rest x 23.2, intact 22.9): a 0.4-0.6 m gap at the centre",
                           "alarm_node": "tunnel_door_inner_alarm__broken", "vapour_node": "air_leak_vfx__broken", "light": rep.get("lights", [None])[0]}
            rec["door_leaves"] = {"L": ["tunnel_door_inner_leaf_L__broken"], "R": ["tunnel_door_inner_leaf_R__broken"]}
        if p["special"] == "dust":
            hangar = [o for o in manifest["objects"] if o["area"] == "Hangar"]
            rec["dust"] = {"shader": "res://materials/colony_surface.gdshader", "instance_uniform": "dust", "area": "Hangar", "objects": len(hangar),
                           "broken_value": DUST_BROKEN, "fixed_value": 0.55,
                           "fixed_exceptions": {o["name"]: o["dust"] for o in hangar if o.get("dust") != 0.55},
                           "dust_mesh_node": "hg_dust__broken",
                           "grid": {"cols": rep["grid"]["cols"], "rows": rep["grid"]["rows"]},
                           "source": "BP10_hangar_dust.blend Broken objects: dust 3.0, dust_map 0.55 (the map value)"}
        if p["special"] == "dust":
            g = rep["grid"]["region_godot"]
            lo, hi = g["min"], g["max"]
            rec["dust_region"] = {"center": [round((lo[0] + hi[0]) / 2, 4), 2.0, round((lo[2] + hi[2]) / 2, 4)],
                                  "size": [round(hi[0] - lo[0], 4), 6.0, round(hi[2] - lo[2], 4)]}
            rec["dust_nodes"] = [x["node"] for x in rep["grid"]["patches"]]
        parts.append(rec)
    out = {"schema": 1, "_about": ABOUT, "parts": parts}
    (PROJ / "data" / "broken_parts.json").write_text(json.dumps(out, indent=1), encoding="utf-8", newline="\n")
    return parts


if __name__ == "__main__":
    reps = load_reports()
    added, pal = add_palette(reps)
    roles = sorted({r for rep in reps.values() for r in rep["palette"] if r.startswith("bp_") and r not in ("bp_pipe", "bp_steel", "bp_chrome")})
    mats = write_materials(pal, roles)
    imports = write_imports()
    parts = build_json(reps)
    print("palette roles added: %s" % added)
    print("materials written: %s" % mats)
    print("import files written: %s" % imports)
    print("data/broken_parts.json: %d parts" % len(parts))
