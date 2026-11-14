"""Read-only audit of the .blend currently open in Blender (Prompt 01 evidence).

Run inside Blender (background or live). It never saves the .blend; it only writes a JSON
report to OUT_DIR. Entry point: audit(out_dir, label) -> compact summary dict.
"""
import bpy
import json
import math
import os
import re
from collections import Counter, defaultdict

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None


def r3(v, n=4):
    return [round(float(x), n) for x in v]


def safe(fn, default=None):
    try:
        return fn()
    except Exception as e:  # report instead of failing the whole audit
        return {"_error": f"{type(e).__name__}: {e}"} if default is None else default


CATS = {
    "rover_vehicle": r"rover|chassis|wheel|buggy|vehicle|truck|cart|tire|tyre",
    "human_body": r"human|person|people|crew|survivor|body|man|woman|head|hand|torso|leg|arm_|astronaut",
    "suit": r"suit|helmet|visor|glove|boot|eva|backpack|plss",
    "spaceship": r"ship|shuttle|lander|orbiter|rocket|spacecraft|booster|capsule|ex_lander",
    "crops_plants": r"tomato|lettuce|plant|crop|leaf|vine|seedling|tray|hydro|grow",
    "energy": r"solar|panel|battery|reactor|generator|tracker|cleaner",
    "life_support": r"oxygen|o2|co2|electroly|moxie|water|tank|scrubber|pump|recycl",
    "comms": r"antenna|dish|radio|comm|relay|mast",
    "doors_glass": r"door|airlock|glass|dome|window|hatch",
    "terrain_rock": r"terrain|rock|boulder|dune|ground|mountain|crater|regolith",
    "salvage_fab": r"salvage|crate|scrap|wreck|crash|debris|fabricat|printer|workbench|lathe",
    "science": r"sample|lab|microscope|spectro|instrument|drill|core|analy",
}


def mesh_stats(me):
    nv = len(me.vertices)
    npoly = len(me.polygons)
    tris = 0
    if npoly:
        if np is not None:
            arr = np.empty(npoly, dtype=np.int32)
            me.polygons.foreach_get("loop_total", arr)
            tris = int((arr - 2).sum())
        else:
            tris = sum(p.loop_total - 2 for p in me.polygons)
    return nv, npoly, tris


def action_info(act):
    info = {"name": act.name, "users": act.users}
    info["frame_range"] = safe(lambda: r3(act.frame_range, 2), [])
    n = 0
    paths = Counter()
    try:
        fcs = []
        if hasattr(act, "layers") and len(act.layers):
            for layer in act.layers:
                for strip in layer.strips:
                    for cb in getattr(strip, "channelbags", []):
                        fcs.extend(cb.fcurves)
            info["slots"] = [s.name_display if hasattr(s, "name_display") else s.name for s in getattr(act, "slots", [])]
        elif hasattr(act, "fcurves"):
            fcs = list(act.fcurves)
        n = len(fcs)
        for fc in fcs:
            m = re.match(r'pose\.bones\["([^"]+)"\]', fc.data_path)
            paths["bone" if m else fc.data_path.split(".")[-1]] += 1
    except Exception as e:
        info["_error"] = str(e)
    info["fcurves"] = n
    info["path_kinds"] = dict(paths.most_common(8))
    return info


def material_info(mat):
    d = {"name": mat.name, "users": mat.users}
    nt = mat.node_tree
    kinds = Counter()
    if nt:
        for n in nt.nodes:
            kinds[n.bl_idname] += 1
        d["nodes"] = len(nt.nodes)
        d["node_kinds"] = dict(kinds)
        d["image_nodes"] = [n.image.name for n in nt.nodes if n.bl_idname == "ShaderNodeTexImage" and n.image]
        d["procedural_tex_nodes"] = sum(v for k, v in kinds.items() if k.startswith("ShaderNodeTex") and k not in ("ShaderNodeTexImage", "ShaderNodeTexCoord", "ShaderNodeTexEnvironment"))
        d["uses_vertex_color"] = any(k in kinds for k in ("ShaderNodeVertexColor", "ShaderNodeAttribute"))
        pb = next((n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if pb:
            def val(name):
                s = pb.inputs.get(name)
                if s is None:
                    return None
                linked = s.is_linked
                try:
                    v = s.default_value
                    v = r3(v) if hasattr(v, "__len__") else round(float(v), 4)
                except Exception:
                    v = None
                return {"v": v, "linked": linked}
            d["principled"] = {k: val(k) for k in ("Base Color", "Metallic", "Roughness", "IOR", "Alpha", "Transmission Weight", "Emission Color", "Emission Strength", "Coat Weight", "Normal")}
        d["has_volume"] = any(k.startswith("ShaderNodeVolume") or k == "ShaderNodeVolumePrincipled" for k in kinds)
        d["has_emission_node"] = "ShaderNodeEmission" in kinds
        d["has_glass_like"] = any(k in kinds for k in ("ShaderNodeBsdfGlass", "ShaderNodeBsdfTransparent", "ShaderNodeBsdfRefraction"))
    for attr in ("surface_render_method", "blend_method", "use_backface_culling", "use_transparency_overlap", "displacement_method"):
        if hasattr(mat, attr):
            d[attr] = safe(lambda a=attr: str(getattr(mat, a)), "")
    return d


def world_info(w):
    d = {"name": w.name}
    nt = w.node_tree
    if nt:
        d["node_kinds"] = dict(Counter(n.bl_idname for n in nt.nodes))
        for n in nt.nodes:
            if n.bl_idname == "ShaderNodeTexSky":
                d["sky"] = {a: safe(lambda a=a: (round(getattr(n, a), 4) if isinstance(getattr(n, a), float) else str(getattr(n, a))), "")
                            for a in ("sky_type", "sun_elevation", "sun_rotation", "sun_intensity", "sun_size", "altitude", "air_density", "aerosol_density", "dust_density", "ozone_density") if hasattr(n, a)}
            if n.bl_idname == "ShaderNodeBackground":
                d.setdefault("backgrounds", []).append({"strength": safe(lambda: round(n.inputs["Strength"].default_value, 4), None),
                                                        "strength_linked": n.inputs["Strength"].is_linked,
                                                        "color": safe(lambda: r3(n.inputs["Color"].default_value), None),
                                                        "color_linked": n.inputs["Color"].is_linked})
    return d


def scene_info(sc):
    r = sc.render
    vs = sc.view_settings
    d = {
        "name": sc.name,
        "objects": len(sc.objects),
        "engine": r.engine,
        "resolution": [r.resolution_x, r.resolution_y, r.resolution_percentage],
        "fps": r.fps,
        "frame_range": [sc.frame_start, sc.frame_end, sc.frame_current],
        "active_camera": sc.camera.name if sc.camera else None,
        "film_transparent": r.film_transparent,
        "units": {"system": sc.unit_settings.system, "scale_length": sc.unit_settings.scale_length, "length_unit": sc.unit_settings.length_unit},
        "color_management": {
            "display_device": sc.display_settings.display_device,
            "view_transform": vs.view_transform,
            "look": vs.look,
            "exposure": round(vs.exposure, 4),
            "gamma": round(vs.gamma, 4),
            "use_curve_mapping": vs.use_curve_mapping,
        },
        "world": sc.world.name if sc.world else None,
        "gravity": r3(sc.gravity),
        "view_layers": [vl.name for vl in sc.view_layers],
    }
    cy = getattr(sc, "cycles", None)
    if cy:
        d["cycles"] = {a: safe(lambda a=a: getattr(cy, a), None) for a in ("samples", "preview_samples", "use_denoising", "max_bounces", "device", "use_adaptive_sampling", "adaptive_threshold", "volume_bounces", "film_exposure")}
    ee = getattr(sc, "eevee", None)
    if ee:
        d["eevee"] = {a: safe(lambda a=a: getattr(ee, a), None) for a in ("taa_render_samples", "use_raytracing", "use_shadows", "use_volumetric_shadows", "volumetric_tile_size", "gi_diffuse_bounces", "use_gtao", "shadow_ray_count", "shadow_step_count") if hasattr(ee, a)}
    d["compositor_nodes"] = safe(lambda: dict(Counter(n.bl_idname for n in (getattr(sc, "compositing_node_group", None) or sc.node_tree).nodes)), {})
    d["markers"] = [(m.name, m.frame, m.camera.name if m.camera else None) for m in sc.timeline_markers]
    return d


def collection_tree(coll, depth, max_depth, mesh_tris):
    objs = list(coll.objects)
    all_objs = list(coll.all_objects)
    tris = 0
    for o in all_objs:
        if o.type == "MESH" and o.data:
            tris += mesh_tris.get(o.data.name, 0)
    d = {"name": coll.name, "direct_objects": len(objs), "all_objects": len(all_objs), "instanced_tris": tris,
         "hide_render": coll.hide_render, "hide_viewport": coll.hide_viewport}
    if depth < max_depth:
        kids = [collection_tree(c, depth + 1, max_depth, mesh_tris) for c in coll.children]
        if kids:
            d["children"] = kids
    else:
        if coll.children:
            d["children_count"] = len(coll.children)
    return d


def world_bbox(objs):
    lo = [1e18] * 3
    hi = [-1e18] * 3
    any_ = False
    for o in objs:
        if o.type not in ("MESH", "CURVE", "SURFACE", "FONT", "META"):
            continue
        try:
            mw = o.matrix_world
            for c in o.bound_box:
                p = mw @ __import__("mathutils").Vector(c)
                for i in range(3):
                    lo[i] = min(lo[i], p[i])
                    hi[i] = max(hi[i], p[i])
                any_ = True
        except Exception:
            pass
    if not any_:
        return None
    return {"min": r3(lo, 3), "max": r3(hi, 3), "size": r3([hi[i] - lo[i] for i in range(3)], 3)}


def audit(out_dir, label):
    D = bpy.data
    rep = {"label": label}
    rep["file"] = {
        "filepath": D.filepath,
        "bytes": os.path.getsize(D.filepath) if D.filepath and os.path.exists(D.filepath) else None,
        "saved_with_version": list(D.version),
        "opened_with": bpy.app.version_string,
        "opened_build": f"{bpy.app.build_hash.decode() if isinstance(bpy.app.build_hash, bytes) else bpy.app.build_hash} {bpy.app.build_date.decode() if isinstance(bpy.app.build_date, bytes) else bpy.app.build_date}",
        "background": bpy.app.background,
        "is_dirty_at_audit": D.is_dirty,
    }
    rep["counts"] = {k: len(getattr(D, k)) for k in ("scenes", "objects", "meshes", "curves", "materials", "textures", "images", "cameras", "lights", "armatures", "actions", "collections", "node_groups", "worlds", "libraries", "texts", "lightprobes", "volumes", "shape_keys", "grease_pencils") if hasattr(D, k)}
    rep["libraries"] = [(l.name, l.filepath) for l in D.libraries]
    rep["texts"] = [(t.name, len(t.as_string())) for t in D.texts]
    rep["scenes"] = [safe(lambda s=s: scene_info(s)) for s in D.scenes]
    rep["worlds"] = [safe(lambda w=w: world_info(w)) for w in D.worlds]

    for sc in D.scenes:
        safe(lambda sc=sc: sc.view_layers[0].update())

    # ---- meshes
    mesh_tris = {}
    mesh_rows = []
    tot_v = tot_p = tot_t = 0
    color_attr_meshes = 0
    uv_meshes = 0
    for me in D.meshes:
        nv, npoly, tris = mesh_stats(me)
        mesh_tris[me.name] = tris
        tot_v += nv
        tot_p += npoly
        tot_t += tris
        ca = [a.name for a in me.color_attributes] if hasattr(me, "color_attributes") else []
        if ca:
            color_attr_meshes += 1
        if len(me.uv_layers):
            uv_meshes += 1
        mesh_rows.append({"name": me.name, "verts": nv, "polys": npoly, "tris": tris, "users": me.users, "materials": len(me.materials),
                          "uv_layers": len(me.uv_layers), "color_attributes": ca})
    mesh_rows.sort(key=lambda m: -m["tris"])
    rep["mesh_totals"] = {"unique_meshes": len(D.meshes), "unique_verts": tot_v, "unique_polys": tot_p, "unique_tris": tot_t,
                          "meshes_with_color_attributes": color_attr_meshes, "meshes_with_uvs": uv_meshes}
    rep["meshes_top_by_tris"] = mesh_rows[:40]
    rep["meshes_with_color_attributes_sample"] = [m for m in mesh_rows if m["color_attributes"]][:40]

    # ---- objects
    types = Counter()
    mods = Counter()
    prop_keys = Counter()
    prefix = Counter()
    parented = 0
    inst_coll = 0
    inst_tris = 0
    mesh_users = Counter()
    hidden_render = 0
    skinned = []
    lod_like = Counter()
    scale_nonunit = 0
    neg_scale = 0
    for o in D.objects:
        types[o.type] += 1
        if o.parent:
            parented += 1
        if o.instance_type == "COLLECTION" and o.instance_collection:
            inst_coll += 1
        if o.hide_render:
            hidden_render += 1
        for m in o.modifiers:
            mods[m.type] += 1
            if m.type == "ARMATURE":
                skinned.append({"object": o.name, "armature": m.object.name if m.object else None, "vertex_groups": len(o.vertex_groups),
                                "tris": mesh_tris.get(o.data.name, 0) if o.data else 0})
        for k in o.keys():
            if k not in ("_RNA_UI",):
                prop_keys[k] += 1
        m = re.match(r"([A-Za-z]+[_\-.]?[A-Za-z]*)", o.name)
        if m:
            prefix[m.group(1)[:18]] += 1
        if re.search(r"(?i)lod\d|_lod|_game|_render|_hi$|_lo$|_low|_high", o.name):
            lod_like[re.search(r"(?i)lod\d|_lod|_game|_render|_hi$|_lo$|_low|_high", o.name).group(0).lower()] += 1
        if o.type == "MESH" and o.data:
            mesh_users[o.data.name] += 1
            inst_tris += mesh_tris.get(o.data.name, 0)
        s = o.scale
        if any(abs(abs(x) - 1.0) > 1e-4 for x in s):
            scale_nonunit += 1
        if s[0] * s[1] * s[2] < 0:
            neg_scale += 1
    shared = [(n, c, mesh_tris.get(n, 0)) for n, c in mesh_users.most_common(40) if c > 1]
    rep["objects"] = {
        "by_type": dict(types), "parented": parented, "collection_instances": inst_coll, "hidden_in_render": hidden_render,
        "modifiers": dict(mods), "custom_property_keys": dict(prop_keys.most_common(60)), "name_prefixes_top": dict(prefix.most_common(80)),
        "lod_like_name_tokens": dict(lod_like), "non_unit_scale_objects": scale_nonunit, "negative_scale_objects": neg_scale,
        "mesh_objects": types.get("MESH", 0), "mesh_objects_sharing_data": sum(c for _, c, _ in [(n, c, 0) for n, c in mesh_users.items() if c > 1]),
        "meshes_used_once": sum(1 for c in mesh_users.values() if c == 1), "meshes_shared": sum(1 for c in mesh_users.values() if c > 1),
        "instanced_scene_tris": inst_tris, "top_shared_meshes": shared,
    }
    rep["skinned_meshes"] = skinned

    # ---- armatures / animation
    rep["armatures"] = [{"name": a.name, "bones": len(a.bones), "users": a.users,
                         "objects": [o.name for o in D.objects if o.type == "ARMATURE" and o.data == a],
                         "bone_sample": [b.name for b in list(a.bones)[:24]]} for a in D.armatures]
    rep["actions"] = [action_info(a) for a in D.actions]
    rep["shape_keys"] = safe(lambda: [{"name": k.name, "blocks": len(k.key_blocks), "user": k.user.name if k.user else None} for k in D.shape_keys], [])
    rep["animated_objects"] = [o.name for o in D.objects if o.animation_data and o.animation_data.action][:80]

    # ---- cameras
    cams = []
    for o in D.objects:
        if o.type != "CAMERA":
            continue
        c = o.data
        mw = o.matrix_world
        fwd = mw.to_3x3() @ __import__("mathutils").Vector((0, 0, -1))
        eul = mw.to_euler("XYZ")
        row = {
            "name": o.name, "data": c.name, "scenes": [s.name for s in o.users_scene], "collections": [k.name for k in o.users_collection],
            "location": r3(mw.translation), "rotation_euler_xyz_deg": [round(math.degrees(a), 3) for a in eul], "forward": r3(fwd),
            "type": c.type, "lens_mm": round(c.lens, 3), "sensor_fit": c.sensor_fit, "sensor_width": round(c.sensor_width, 3), "sensor_height": round(c.sensor_height, 3),
            "angle_x_deg": round(math.degrees(c.angle_x), 3), "angle_y_deg": round(math.degrees(c.angle_y), 3),
            "clip": [round(c.clip_start, 4), round(c.clip_end, 2)], "shift": [round(c.shift_x, 4), round(c.shift_y, 4)],
            "dof": {"use": c.dof.use_dof, "fstop": round(c.dof.aperture_fstop, 3), "focus_distance": round(c.dof.focus_distance, 3)},
            "ortho_scale": round(c.ortho_scale, 3) if c.type == "ORTHO" else None,
            "animated": bool(o.animation_data and o.animation_data.action), "parent": o.parent.name if o.parent else None,
            "custom_props": {k: (o[k] if isinstance(o[k], (int, float, str)) else str(o[k])) for k in o.keys() if k != "_RNA_UI"},
            "matrix_world": [r3(rw, 5) for rw in mw],
        }
        cams.append(row)
    cams.sort(key=lambda c: c["name"])
    rep["cameras"] = cams

    # ---- lights
    lights = []
    ltypes = Counter()
    lenergy = defaultdict(float)
    for o in D.objects:
        if o.type != "LIGHT":
            continue
        l = o.data
        ltypes[l.type] += 1
        lenergy[l.type] += float(l.energy)
        row = {"name": o.name, "data": l.name, "type": l.type, "energy": round(float(l.energy), 4), "color": r3(l.color), "location": r3(o.matrix_world.translation, 3),
               "collections": [k.name for k in o.users_collection], "hide_render": o.hide_render, "use_shadow": getattr(l, "use_shadow", None),
               "data_users": l.users, "uses_nodes": bool(getattr(l, "use_nodes", False))}
        for a in ("shadow_soft_size", "spot_size", "spot_blend", "shape", "size", "size_y", "angle", "exposure", "temperature", "use_temperature", "normalize", "use_custom_distance", "cutoff_distance", "diffuse_factor", "specular_factor", "volume_factor"):
            if hasattr(l, a):
                v = safe(lambda a=a: getattr(l, a), None)
                row[a] = round(v, 4) if isinstance(v, float) else (v if isinstance(v, (int, bool, str)) or v is None else str(v))
        cp = {k: (o[k] if isinstance(o[k], (int, float, str)) else str(o[k])) for k in o.keys() if k != "_RNA_UI"}
        if cp:
            row["custom_props"] = cp
        lights.append(row)
    rep["lights_summary"] = {"by_type": dict(ltypes), "energy_sum_by_type": {k: round(v, 2) for k, v in lenergy.items()},
                             "unique_light_datablocks": len(D.lights), "light_objects": sum(ltypes.values()),
                             "by_collection": dict(Counter(c for row in lights for c in row["collections"]).most_common(60))}
    rep["lights"] = lights
    rep["lightprobes"] = safe(lambda: [{"name": o.name, "type": o.data.type, "location": r3(o.matrix_world.translation, 3), "scale": r3(o.scale, 3)} for o in D.objects if o.type == "LIGHT_PROBE"], [])

    # ---- materials / images
    mats = [safe(lambda m=m: material_info(m)) for m in D.materials]
    rep["materials"] = mats
    okm = [m for m in mats if isinstance(m, dict) and "_error" not in m]
    rep["materials_summary"] = {
        "count": len(mats),
        "with_image_textures": sum(1 for m in okm if m.get("image_nodes")),
        "with_procedural_texture_nodes": sum(1 for m in okm if m.get("procedural_tex_nodes")),
        "using_vertex_color_or_attribute": sum(1 for m in okm if m.get("uses_vertex_color")),
        "with_volume": sum(1 for m in okm if m.get("has_volume")),
        "transmissive_or_glass": [m["name"] for m in okm if m.get("has_glass_like") or ((m.get("principled") or {}).get("Transmission Weight") or {}).get("v") not in (None, 0.0) or ((m.get("principled") or {}).get("Transmission Weight") or {}).get("linked")][:80],
        "alpha_below_one": [m["name"] for m in okm if isinstance(((m.get("principled") or {}).get("Alpha") or {}).get("v"), float) and ((m.get("principled") or {}).get("Alpha") or {}).get("v") < 0.999][:80],
        "emissive": [m["name"] for m in okm if m.get("has_emission_node") or (isinstance(((m.get("principled") or {}).get("Emission Strength") or {}).get("v"), float) and ((m.get("principled") or {}).get("Emission Strength") or {}).get("v") > 0)][:200],
        "node_kind_totals": dict(sum((Counter(m.get("node_kinds", {})) for m in okm), Counter()).most_common(60)),
        "render_methods": dict(Counter(m.get("surface_render_method", m.get("blend_method", "?")) for m in okm)),
    }
    rep["images"] = [{"name": i.name, "size": list(i.size), "source": i.source, "filepath": i.filepath, "packed": bool(i.packed_file), "users": i.users,
                      "colorspace": safe(lambda i=i: i.colorspace_settings.name, "")} for i in D.images]
    rep["node_groups"] = [{"name": g.name, "type": g.bl_idname, "nodes": len(g.nodes), "users": g.users} for g in D.node_groups]
    rep["missing_files"] = safe(lambda: [i.filepath for i in D.images if i.source == "FILE" and not i.packed_file and i.filepath and not os.path.exists(bpy.path.abspath(i.filepath))], [])

    # ---- hierarchy / spatial
    trees = []
    for sc in D.scenes:
        trees.append({"scene": sc.name, "tree": safe(lambda sc=sc: collection_tree(sc.collection, 0, 3, mesh_tris))})
    rep["collection_trees"] = trees
    rep["scene_bbox"] = {sc.name: safe(lambda sc=sc: world_bbox(sc.objects)) for sc in D.scenes}
    top_boxes = {}
    for sc in D.scenes:
        for c in sc.collection.children:
            top_boxes[f"{sc.name}/{c.name}"] = safe(lambda c=c: world_bbox(c.all_objects))
            for c2 in c.children:
                top_boxes[f"{sc.name}/{c.name}/{c2.name}"] = safe(lambda c2=c2: world_bbox(c2.all_objects))
    rep["collection_bboxes"] = top_boxes

    # ---- category search (names of objects, their data and collections)
    cat = {}
    for key, pat in CATS.items():
        rx = re.compile(pat, re.I)
        hits = [o for o in D.objects if rx.search(o.name) or (o.data is not None and rx.search(o.data.name))]
        colls = [c for c in D.collections if rx.search(c.name)]
        tri = sum(mesh_tris.get(o.data.name, 0) for o in hits if o.type == "MESH" and o.data)
        roots = Counter()
        for o in hits:
            p = o
            while p.parent:
                p = p.parent
            roots[p.name] += 1
        cat[key] = {
            "pattern": pat, "object_hits": len(hits), "tris": tri, "types": dict(Counter(o.type for o in hits)),
            "collections": [(c.name, len(c.all_objects)) for c in colls][:40],
            "root_objects_top": roots.most_common(25),
            "sample_names": sorted({o.name for o in hits})[:40],
        }
    rep["category_search"] = cat

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, label + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=1, default=str)

    summary = {
        "report": path, "file": rep["file"], "counts": rep["counts"],
        "scenes": [(s.get("name"), s.get("objects"), s.get("engine"), s.get("active_camera"), s.get("color_management", {}).get("view_transform"), s.get("color_management", {}).get("exposure")) for s in rep["scenes"] if isinstance(s, dict)],
        "mesh_totals": rep["mesh_totals"], "objects_by_type": rep["objects"]["by_type"], "instanced_scene_tris": rep["objects"]["instanced_scene_tris"],
        "meshes_shared": rep["objects"]["meshes_shared"], "collection_instances": rep["objects"]["collection_instances"],
        "modifiers": rep["objects"]["modifiers"], "custom_property_keys": dict(list(rep["objects"]["custom_property_keys"].items())[:20]),
        "cameras": [c["name"] for c in cams][:80], "lights": rep["lights_summary"]["by_type"], "armatures": [(a["name"], a["bones"]) for a in rep["armatures"]],
        "actions": [(a["name"], a["fcurves"]) for a in rep["actions"]][:30], "skinned_meshes": len(skinned),
        "materials_summary": {k: (v if not isinstance(v, list) else len(v)) for k, v in rep["materials_summary"].items() if k != "node_kind_totals"},
        "images": len(rep["images"]), "missing_files": rep["missing_files"], "libraries": rep["libraries"],
        "category_hits": {k: (v["object_hits"], v["tris"]) for k, v in cat.items()},
        "is_dirty_after_audit": D.is_dirty,
    }
    with open(os.path.join(out_dir, label + ".summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=1, default=str)
    return summary


if __name__ == "__main__":
    import sys
    import traceback

    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[0::2], argv[1::2]))
    out_dir, label = opts["--out"], opts["--label"]
    os.makedirs(out_dir, exist_ok=True)
    try:
        audit(out_dir, label)
    except Exception:
        with open(os.path.join(out_dir, label + ".error.txt"), "w", encoding="utf-8") as f:
            f.write(traceback.format_exc())
