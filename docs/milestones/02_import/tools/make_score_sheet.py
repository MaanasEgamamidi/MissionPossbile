"""Build score_sheet.csv / score_sheet.json / camera_pairs.json for Prompt 02 from the reviewer's rubric scores and the
image metrics of each pass. Run:  py -I make_score_sheet.py
Rubric (visual review, not a physical percentage): brightness and contrast 30, colour and white balance 25,
shadows and contact 25, reflections and transmission 15, atmosphere and haze 5."""
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
PAIRS = HERE / "evidence" / "pairs"
PROJ = Path(r"G:\nasa app\mars_colony_godot")

# reviewer: Claude (executor), 2026-11-11, from the side-by-side sheets in evidence/pairs/sheets_pass3.
# (B, C, S, R, A), mismatch categories, likely cause, remaining work
FINAL = {
    "Shot_01_MedBay": ((24, 21, 15, 9, 4), "contact shadows; emissive panels", "Flat room ambient instead of bounced light; only 3 shadowed fixtures per zone; one equipment panel glows as a flat white rectangle.", "Per-fixture shadows or baked AO on static furniture; texture or dim the glowing panel."),
    "Shot_02_MessHall": ((25, 20, 15, 10, 4), "wall hot spots; floor dust colour", "Spot cones show as hot spots on walls near sconces; shader dust is rustier and patchier than the reference at low dust values; notice board is a flat glowing colour.", "Tune spot cone falloff per fixture type; fit dust response at dust < 0.2; give screens and boards real content."),
    "Shot_03_RecKitchen": ((25, 20, 15, 10, 4), "emissive board; contact shadows", "Wall board glows as a flat yellow rectangle where the reference shows a pin board; weak contact shadows under furniture.", "Screen and board content textures; contact shadows."),
    "Shot_04_CrewCorridor": ((26, 20, 17, 10, 4), "floor colour", "Floor dust is redder and higher contrast than the reference.", "Fit dust colour and patch contrast."),
    "Shot_05_Hangar": ((22, 20, 13, 9, 3), "ceiling brightness; contact shadows", "Open metal deck and beams read lighter than the reference, where the deck sits above the fixtures and receives only bounce; many small shadows under the rover and tools are missing.", "Reduce ambient on surfaces above the fixture plane or add ceiling occlusion; more shadowed fixtures in this room."),
    "Shot_06_Airlock": ((23, 19, 14, 9, 3), "floor dust pattern; glazing", "Dust pattern and colour on the floor plates differ from the procedural reference; door windows show no reflection.", "Fit dust; reflective glazing material for door windows."),
    "Shot_07_PowerRoom": ((20, 18, 13, 8, 3), "exposure +0.30 EV; ceiling; screens", "Ducts and deck too light; screens are flat yellow and cyan rectangles where the reference shows dense dark displays.", "Ceiling occlusion; screen content; check the room's large AreaLight3D panels against its spot fixtures."),
    "Shot_08_LifeSupport": ((24, 20, 14, 9, 4), "ceiling brightness; contact shadows", "Same open-deck ceiling effect as the hangar, milder.", "As hangar."),
    "Shot_09_Command": ((22, 17, 14, 8, 3), "screens; floor colour", "Wall and desk screens are flat blue and teal; floor shows rust dust where the reference floor is cool grey; room slightly bright (+0.18 EV).", "Screen content; per-material dust response for this floor finish."),
    "Shot_10_EastQuarters": ((25, 19, 15, 10, 4), "floor saturation; partition colour", "Floor more saturated orange; folding partition reads dark grey instead of olive-brown fabric.", "Check the partition's palette role against its render material; saturation fit."),
    "Shot_11_Greenhouse": ((24, 20, 13, 9, 3), "ceiling shadows; plant detail", "Reference shows soft shadows cast on the ceiling around the grow-light housings and under racks; game-detail plants are simple shapes.", "Shadowed grow lights; crop detail level is a Prompt 08 and 13 topic."),
    "Shot_12_WestBunk": ((25, 19, 15, 10, 4), "floor dust", "Floor dust heavier and redder than the reference.", "Fit dust."),
    "Shot_13_Exterior_Airlock": ((22, 17, 13, 6, 2), "ground detail; hall glass; haze", "Reference ground has render-only gravel, tyre tracks and their micro-shadows; hall glass in the reference is see-through with a lit interior, in Godot it is near-black smoked alpha; no atmospheric haze volume.", "Ground detail (decals or a terrain shader using the three unused colour attributes); refractive or reflective glass; a haze solution that does not brighten the distance."),
    "Shot_14_Exterior_Wide": ((24, 19, 15, 8, 2), "haze; glass reflections", "No haze; hall and dome glass lack sky reflections; slightly bluer than the reference (B/G +16 %).", "Haze; reflection on glass; outdoor white balance."),
    "Shot_15_GardenDome": ((23, 18, 14, 7, 2), "dome glass and frame; lamp bloom", "Game-detail dome struts are thicker and lighter; glass is clearer than the tinted reference glass; the interior lamp blooms larger.", "Dome glass tint and reflection; glow threshold."),
}
# views actually reviewed in earlier passes
EARLIER = {
    "pass0_baseline": {"Shot_02_MessHall": (18, 17, 12, 8, 4), "Shot_05_Hangar": (15, 16, 11, 8, 3), "Shot_11_Greenhouse": (19, 18, 11, 8, 3), "Shot_14_Exterior_Wide": (10, 13, 13, 4, 2)},
    "pass1": {"Shot_04_CrewCorridor": (22, 14, 14, 9, 4), "Shot_07_PowerRoom": (17, 16, 12, 8, 3), "Shot_06_Airlock": (17, 15, 12, 8, 3), "Shot_13_Exterior_Airlock": (18, 13, 12, 4, 2)},
}


def metrics(tag):
    p = PAIRS / f"metrics_{tag}.json"
    if not p.exists():
        return {}, {}
    d = json.loads(p.read_text(encoding="utf-8"))
    return {r["camera"]: r for r in d["pairs"] if r.get("status") == "ok"}, d["summary"]


tags = ["pass0_baseline", "pass1", "pass2", "pass3"]
M = {t: metrics(t) for t in tags}
cap = json.loads((PAIRS / "pass3" / "capture_report.json").read_text(encoding="utf-8"))
gpu = {v["camera"]: v for v in cap["views"]}
manifest = json.loads((PROJ / "data" / "colony_manifest.json").read_text(encoding="utf-8"))
cams = {c["name"]: c for c in manifest["cameras"]}
preset = json.loads((PROJ / "data" / "lighting_preset.json").read_text(encoding="utf-8"))

rows = []
for cam, (sc, cat, cause, todo) in FINAL.items():
    row = {"camera": cam, "brightness_contrast_30": sc[0], "colour_wb_25": sc[1], "shadows_contact_25": sc[2], "reflections_transmission_15": sc[3], "atmosphere_haze_5": sc[4],
           "rubric_total_100": sum(sc), "meets_95": sum(sc) >= 95, "mismatch": cat, "likely_cause": cause, "remaining_work": todo}
    for t in tags:
        m = M[t][0].get(cam, {})
        row[f"ssim_{t}"] = m.get("ssim")
        row[f"ev_diff_{t}"] = m.get("ev_diff")
        row[f"de76_{t}"] = m.get("de76_mean")
    m3 = M["pass3"][0].get(cam, {})
    row["rg_shift_pass3"] = m3.get("rg_shift")
    row["bg_shift_pass3"] = m3.get("bg_shift")
    row["gpu_ms_1080p"] = gpu.get(cam, {}).get("render_gpu_ms")
    for t, d in EARLIER.items():
        if cam in d:
            row[f"rubric_{t}"] = sum(d[cam])
    rows.append(row)

keys = []
for r in rows:
    for k in r:
        if k not in keys:
            keys.append(k)
with open(HERE / "score_sheet.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=keys)
    w.writeheader()
    for r in rows:
        w.writerow(r)
summary = {
    "reviewer": "Claude (executor). Owner review pending.", "review_date": "2026-11-11",
    "what_was_scored": "Godot captures of lighting pass 3 against the 2026-11-08 Cycles beauty shots of the CURRENT map. Scores were given from the sheets captured before the fixture-ownership fix; the final recapture differs by at most 0.008 SSIM and 0.08 EV per view.",
    "rubric_is": "a visual rubric score out of 100, not a measured physical percentage",
    "views": len(rows), "views_at_or_above_95": sum(1 for r in rows if r["meets_95"]),
    "rubric_mean": round(sum(r["rubric_total_100"] for r in rows) / len(rows), 1), "rubric_min": min(r["rubric_total_100"] for r in rows), "rubric_max": max(r["rubric_total_100"] for r in rows),
    "metric_summaries": {t: M[t][1] for t in tags},
    "gpu_ms_1080p_msaa4": {"mean": round(sum(v["render_gpu_ms"] for v in cap["views"]) / len(cap["views"]), 2), "max": max(v["render_gpu_ms"] for v in cap["views"]),
                           "views_over_16_7_ms": sum(1 for v in cap["views"] if v["render_gpu_ms"] > 16.7), "adapter": cap["adapter"],
                           "note": "Viewport render time reported by the engine during capture in an off-screen 1920x1080 viewport. Not a gameplay frame-rate measurement."},
}
(HERE / "score_sheet.json").write_text(json.dumps({"summary": summary, "views": rows, "earlier_pass_rubric": EARLIER}, indent=1), encoding="utf-8")

pairs = []
for cam in FINAL:
    c = cams[cam]
    pairs.append({
        "camera": cam, "blender_matrix_world": c["matrix_world"], "lens_mm": c["lens"], "sensor_width_mm": c["sensor_width"], "sensor_fit": c["sensor_fit"],
        "horizontal_fov_rad": c["angle_x"], "clip_start_m": c["clip_start"], "clip_end_m": c["clip_end"],
        "reference": {"file": f"grand_colony_drive/beauty_shots_cycles_1080p.zip:{cam}.png", "renderer": "Cycles (Blender 5.2 era file, rendered 2026-11-08)", "resolution": [1920, 1080],
                      "view_transform": "AgX", "look": "AgX - Punchy", "exposure_ev": -0.45, "compositor": "as saved in the scene (bloom, dispersion, colour balance, vignette); its on/off state was not recorded with the renders",
                      "geometry": "render detail level, procedural materials", "state": "day, all fixtures powered", "historical": True},
        "godot": {"file": f"docs/milestones/02_import/evidence/pairs/pass3/{cam}.png", "engine": cap["godot"], "adapter": cap["adapter"], "resolution": cap["size"], "msaa": "4x",
                  "frames_before_capture": cap["frames_per_view"], "ui_and_debug_overlays": "none (off-screen SubViewport)", "tonemap": "AgX", "exposure": round(2 ** preset["tonemap"]["exposure_ev"] * preset["tonemap"]["exposure_trim"], 4),
                  "preset": preset["name"], "pass": preset["pass"], "geometry": "game detail level, flat palette materials with shader dust", "state": "day, all fixtures powered",
                  "render_gpu_ms": gpu.get(cam, {}).get("render_gpu_ms"), "draw_calls": gpu.get(cam, {}).get("draw_calls")},
        "sheet": f"docs/milestones/02_import/evidence/pairs/sheets_pass3/{cam}.jpg",
    })
(HERE / "camera_pairs.json").write_text(json.dumps({"note": "Rehearsal pairs on the CURRENT map. The improved map has not been supplied; these are not acceptance pairs.", "pairs": pairs}, indent=1), encoding="utf-8")

print(json.dumps({k: summary[k] for k in ("views", "views_at_or_above_95", "rubric_mean", "rubric_min", "rubric_max", "gpu_ms_1080p_msaa4")}))
for t in tags:
    print(t, M[t][1].get("mean_ssim"), M[t][1].get("mean_abs_ev"), M[t][1].get("mean_de76"))
print("| View | B/30 | C/25 | S/25 | R/15 | A/5 | Total | SSIM p0 to p3 | EV diff p0 to p3 | dE76 p0 to p3 | GPU ms |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | ---: |")
for r in rows:
    print(f"| {r['camera'][5:]} | {r['brightness_contrast_30']} | {r['colour_wb_25']} | {r['shadows_contact_25']} | {r['reflections_transmission_15']} | {r['atmosphere_haze_5']} | **{r['rubric_total_100']}** | "
          f"{r['ssim_pass0_baseline']:.3f} to {r['ssim_pass3']:.3f} | {r['ev_diff_pass0_baseline']:+.2f} to {r['ev_diff_pass3']:+.2f} | {r['de76_pass0_baseline']:.1f} to {r['de76_pass3']:.1f} | {r['gpu_ms_1080p']} |")
