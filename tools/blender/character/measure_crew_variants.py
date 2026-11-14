"""Clearance checks for crew variants over the live clips (run after crew_variants.py, never saves).
  ... --python run_logged.py -- <log> measure_crew_variants.py <out.json>
Hair vs flight-suit body (signed: negative = inside), arms inside torso/legs and minimum foot gap at Feminine 0 and 1.
"""
import bpy, sys, json, bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

OUT = sys.argv[sys.argv.index("--") + 1:][0]
sc = bpy.context.scene
ARM = bpy.data.objects["Armature"]
OB = bpy.data.objects
for t in ARM.animation_data.nla_tracks: t.mute = True
tracks = {t.name: t.strips[0].action.name for t in ARM.animation_data.nla_tracks if t.strips}

def set_action(name):
    act = bpy.data.actions[name]
    ARM.animation_data.action = act
    if hasattr(ARM.animation_data, "action_slot") and act.slots:
        ARM.animation_data.action_slot = act.slots[0]
    return act

def fem(v):
    for o in OB:
        if o.type == 'MESH' and o.data.shape_keys and "Feminine" in o.data.shape_keys.key_blocks:
            o.data.shape_keys.key_blocks["Feminine"].value = v

def evald(names, vfilter=None):
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    for n in names:
        e = OB[n].evaluated_get(dg); me = e.to_mesh()
        tmp = bmesh.new(); tmp.from_mesh(me); tmp.transform(e.matrix_world)
        if vfilter:
            vf = vfilter(OB[n])
            bmesh.ops.delete(tmp, geom=[f for f in tmp.faces if not all(vf(v.index) for v in f.verts)], context='FACES')
        m2 = bpy.data.meshes.new("_t"); tmp.to_mesh(m2); tmp.free(); bm.from_mesh(m2); bpy.data.meshes.remove(m2)
        e.to_mesh_clear()
    return bm

def signed_min(points, bvh):
    """(min unsigned distance, count of points clearly inside). Thin closed trim shells make signed tests noisy."""
    best, inside = 9.0, 0
    for p in points:
        loc, nrm, _, d = bvh.find_nearest(p, 0.3)
        if loc is None: continue
        if (p - loc).dot(nrm) < 0 and d > 0.004 and d < 0.03: inside += 1
        best = min(best, d)
    return round(best, 4), inside

def group_filter(names):
    def mk(ob):
        idx = {g.index for g in ob.vertex_groups if g.name in names}
        def f(i):
            gs = ob.data.vertices[i].groups
            tot = sum(g.weight for g in gs) or 1
            return sum(g.weight for g in gs if g.group in idx) / tot > 0.5
        return f
    return mk

ARMB = {"LowerArmL", "HandL", "LowerArmR", "HandR"}
res = {}
for clip in ("idle", "walk", "sprint", "jump_start", "jump", "land"):
    act = set_action(tracks[clip])
    last = int(round(act.frame_range[1]))
    r = {}
    for f in range(0, last + 1, 2):
        sc.frame_set(f)
        for fv in (0.0, 1.0):
            fem(fv)
            body = evald(["Body_Torso", "Body_Arms"])
            bvh = BVHTree.FromBMesh(body)
            for h in ("Hair_Ponytail", "Hair_Bob", "Hair_Curly"):
                hb = evald([h]); d, ins = signed_min([v.co for v in hb.verts], bvh); hb.free()
                k = f"{h}_F{int(fv)}"
                cur = r.get(k, [9, 0, None])
                r[k] = [min(cur[0], d), max(cur[1], ins), f if d < cur[0] else cur[2]]
            body.free()
            torso = evald(["Body_Torso", "Body_Legs"]); bvt = BVHTree.FromBMesh(torso); torso.free()
            fore = evald(["Body_Arms"], group_filter(ARMB))
            d, ins = signed_min([v.co for v in fore.verts], bvt); fore.free()
            k = f"forearm_vs_torso_F{int(fv)}"; cur = r.get(k, [9, 0, None])
            r[k] = [min(cur[0], d), max(cur[1], ins), f if d < cur[0] else cur[2]]
            fl = evald(["Body_Legs"], group_filter({"FootL", "ToesL"})); fr = evald(["Body_Legs"], group_filter({"FootR", "ToesR"}))
            bvr = BVHTree.FromBMesh(fr)
            ds = [bvr.find_nearest(v.co, 2.0)[3] for v in fl.verts]
            ds = [d for d in ds if d is not None]
            gap = min(ds) if ds else -1.0; r["foot_verts"] = [len(fl.verts), len(fr.verts)]; fl.free(); fr.free()
            k = f"foot_gap_F{int(fv)}"; r[k] = round(min(r.get(k, 9), gap), 4)
            # head / inner hair / beard poking out of the helmet (helmet space)
            hb = ARM.data.bones["Head"]
            HC = (hb.head_local + hb.tail_local) / 2 + Vector((0, -0.005, -0.015))
            hel = OB["Suit_Helmet"]; gname = hel.vertex_groups[0].name
            pbm = ARM.pose.bones[gname]
            Minv = (pbm.matrix @ ARM.data.bones[gname].matrix_local.inverted()).inverted()
            HRm = max((v.co - HC).length for v in hel.data.vertices if v.co.z > HC.z + 0.05 and abs(v.co.x) < 0.1)
            zedge = HC.z - 0.85 * HRm   # sphere bottom edge (the neck ring below it flares out)
            dg = bpy.context.evaluated_depsgraph_get()
            for n in ["Body_Head", "Hair_Beard"] + [o.name for o in OB if o.name.startswith("HairIn_")]:
                e = OB[n].evaluated_get(dg); me = e.to_mesh()
                worst = -9.0
                for v in me.vertices:
                    q = Minv @ v.co
                    if q.z > zedge + 0.006:
                        worst = max(worst, (q - HC).length - 0.965 * HRm)
                e.to_mesh_clear()
                k = f"helmet_poke_{n}_F{int(fv)}"; r[k] = round(max(r.get(k, -9), worst), 4)
            if fv == 0.0:
                ids = [o.name for o in OB if o.name.startswith("Ident_")]
                ib = evald(ids); bvi = BVHTree.FromBMesh(ib); ib.free()
                sa = evald(["Suit_Arms"])
                dmin = min(bvi.find_nearest(v.co, 1.0)[3] or 9 for v in sa.verts); sa.free()
                r["ident_vs_suit_arms_min"] = round(min(r.get("ident_vs_suit_arms_min", 9), dmin), 4)
    res[clip] = r
fem(0.0)
ARM.animation_data.action = None
for pb in ARM.pose.bones: pb.matrix_basis = Matrix.Identity(4)
json.dump(res, open(OUT, "w"), indent=1)
print(json.dumps(res, indent=1))
