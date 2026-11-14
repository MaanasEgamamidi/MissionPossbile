"""Generate the external Godot materials from data/palette.json (written by the Blender export) and the lighting preset.
  py -I tools/gen_materials.py [project_dir]
One material per palette role in materials/colony/<role>.tres. Re-run after changing the preset or the palette.

Each role gets the shader of its Blender material class, with the class parameters gc_mat._surface reads:
  glow -> colony_glow      screen -> colony_screen      glass / water / any see-through role -> colony_glass
  terrain -> colony_terrain      decals -> alpha-blended StandardMaterial3D      everything else -> colony_surface
Colours in a .tres are sRGB; the palette stores linear values, so they are converted here.
Emission strengths follow gc_mat._emissive (max(emit, 1) x 2.2 for lamps, x 1.6 for screens) times the preset scales,
which are visual fits to the reference renders, not physical conversions."""
import json
import sys
from pathlib import Path

proj = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
data = json.loads((proj / "data" / "palette.json").read_text(encoding="utf-8"))
pal = data["roles"]
preset = json.loads((proj / "data" / "lighting_preset.json").read_text(encoding="utf-8"))
mp = preset["materials"]
out = proj / "materials" / "colony"
out.mkdir(parents=True, exist_ok=True)
for old in out.glob("*.tres"):
    old.unlink()

CLASS_ID = {"paint": 1, "plastic": 2, "floor": 2, "rubber": 2, "leather": 2, "ceramic": 2, "metal": 3, "fabric": 4, "wood": 5, "leaf": 6,
            "soil": 7, "rock": 7, "foam": 7, "solar": 8}


def srgb(v):
    v = max(0.0, min(1.0, v))
    return v * 12.92 if v <= 0.0031308 else 1.055 * (v ** (1 / 2.4)) - 0.055


def col(lin):
    return "Color(%s, %s, %s, 1)" % tuple(fmt(srgb(c)) for c in lin[:3])


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    return f"{float(v):.5f}".rstrip("0").rstrip(".")


def shader_material(role, shader, params):
    lines = ['[gd_resource type="ShaderMaterial" load_steps=2 format=3]', "", f'[ext_resource type="Shader" path="res://materials/{shader}.gdshader" id="1"]', "",
             "[resource]", f'resource_name = "{role}"', 'shader = ExtResource("1")']
    for k, v in params.items():
        lines.append(f"shader_parameter/{k} = {v if isinstance(v, str) else fmt(v)}")
    return "\n".join(lines) + "\n"


stats = {}
dust_lin = data.get("dust_linear", [0.36, 0.165, 0.075])
for role, p in pal.items():
    over = mp.get("overrides", {}).get(role, {})
    cls = p.get("mat_class")
    a = over.get("alpha", p.get("alpha"))
    base = over.get("albedo_linear") or p.get("base_linear") or p["rgb_linear"]
    glow_col = p["rgb_linear"]                      # unclamped palette colour for emitters
    emit = float(p.get("emission") or 0.0)
    kind = "surface"
    if cls == "terrain":
        kind = "terrain"
        text = shader_material(role, "colony_terrain", {"detail_gain": float(mp.get("terrain_detail_gain", 1.0)), "bump_gain": float(mp.get("terrain_bump_gain", 1.0))})
    elif cls == "decal":
        kind = "decal"
        text = "\n".join(['[gd_resource type="StandardMaterial3D" format=3]', "", "[resource]", f'resource_name = "{role}"', "transparency = 1",
                          "albedo_color = Color(%s, %s, %s, %s)" % (*[fmt(srgb(c)) for c in base[:3]], fmt(float(a if a is not None else 0.55))),
                          f"roughness = {fmt(float(p['roughness']))}"]) + "\n"
    elif cls == "glow":
        kind = "glow"
        text = shader_material(role, "colony_glow", {"emission": col(glow_col),
                                                      "emission_energy": max(emit, 1.0) * 2.2 * float(p.get("emit_k", 1.0)) * float(mp.get("glow_emission_scale", 1.0))})
    elif cls == "screen":
        kind = "screen"
        text = shader_material(role, "colony_screen", {"emission": col(glow_col),
                                                        "emission_energy": max(emit, 1.0) * 1.6 * float(p.get("emit_k", 1.0)) * float(mp.get("screen_emission_scale", 1.0))})
    elif a is not None or cls in ("glass", "water"):
        kind = "glass"
        tint = float(p.get("tint", 1.0))
        c = [1.0 - (1.0 - v) * tint * 0.6 for v in p["rgb_linear"]]          # gc_mat._glass base colour
        if over.get("albedo_linear"):
            c = over["albedo_linear"]
        text = shader_material(role, "colony_glass", {"albedo": col(c), "opacity": float(a if a is not None else 0.2),
                                                       "roughness": float(over.get("roughness", mp.get("glass_roughness", 0.03))),
                                                       "edge_opacity": float(over.get("edge_opacity", mp.get("glass_edge_opacity", 0.85))),
                                                       "dust_k": float(p.get("dust_k", 0.6)), "dust_color": col(dust_lin)})
    else:
        params = {"albedo": col(base), "roughness": float(over.get("roughness", p.get("rough0", p["roughness"]))), "metallic": float(p.get("metal0", 0.0)),
                  "specular": float(over.get("specular", mp.get("specular", 0.5))), "class_id": int(CLASS_ID.get(cls, 0)),
                  "var": float(p.get("var", 0.05)), "wear": float(p.get("wear", 0.0)), "grime": float(p.get("grime", 0.0)), "bump": float(p.get("bump", 0.01)),
                  "bscale": float(p.get("bscale", 300.0)), "coat": float(p.get("coat", 0.0)), "edge_color": col(p.get("edge_color", [0.55, 0.56, 0.57])),
                  "edge_metal": float(p.get("edge_metal", 1.0)), "edge_rough": float(p.get("edge_rough", 0.35)),
                  "dust_k": float(over.get("dust_k", p.get("dust_k", 1.0))), "dust_color": col(dust_lin), "dust_roughness": float(data.get("dust_roughness", 0.93)),
                  "dust_gain": float(mp.get("dust_gain", 1.0)), "grime_gain": float(mp.get("grime_gain", 1.0)), "bump_gain": float(mp.get("bump_gain", 1.0))}
        if emit > 0:
            params["emission"] = col(glow_col)
            params["emission_energy"] = emit * float(mp.get("emission_scale", 1.0))
        text = shader_material(role, "colony_surface", params)
    (out / f"{role}.tres").write_text(text, encoding="utf-8")
    stats[kind] = stats.get(kind, 0) + 1
print(f"wrote {sum(stats.values())} materials to {out}  {stats}")
