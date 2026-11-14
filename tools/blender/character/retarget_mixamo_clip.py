"""Retargets clips from Mixamo (FBX, skeleton only) or the Quaternius Universal Animation Library (glb, UE-mannequin bone
names) onto the astronaut rig, writes them as named NLA clips and re-exports astronaut.glb. Generalises
retarget_mixamo_walk.py: same rest-pose correction (world rotations copied after turning the target rest direction onto
the source rest direction) and the same narrow-feet leg IK (the rig's hip joints sit 0.24 m out, so the ankles are
placed from the source ankle-vs-hips offset and thigh + shin reach them with two-bone IK).

Run headless:
  blender -b --factory-startup --disable-autoexec <crew_v2.blend> --python retarget_mixamo_clip.py -- <jobs.json> <out.glb>
          [--save] [--render <stills_dir>]

jobs.json = {"copies": [{"from": action, "target": track}], "clips": [job, ...]}; each job:
  source   FBX or glb path;  action  (glb only) action name inside the file
  target   clip (NLA track) to write; the action gets the same name; the track is created if missing
  live     optional list of live track names that should play this clip too (e.g. ["sprint"])
  old_names  {track: name}: an existing action called <track> is renamed to this and kept with a fake user
  report   JSON report path
  mode     "loop"  cycle: root motion removed as a straight line, loop closed (last key = first pose)
           "once"  one-shot: hips follow the source relative to the standing frame
           "air"   loop held over the origin: hips at rest height, source vertical hip travel removed
  vertical "pin" (lowest leg point on the floor every frame; default for loop/once) | "pin_first" (constant offset that
           puts frame 0 on the floor, then the source's own vertical motion: for clips whose feet leave the ground)
           | "pin_up" (like pin_first but never below the floor) | "rest" (hips at rest height; default for air)
  clearance       air only: lift the whole loop just enough that the lowest foot stays this far above the origin
  upper    0..1, how much of the source's upper-body pose to keep (rest is the standing pose); stand_action picks
           another action of the same file for that standing pose
  x_offset source metres each ankle/knee is pushed outward (gaits whose feet cross the midline)
  start, end      source frames (scene frames, 30 fps after import) used, inclusive; loops default to the whole action
                  and drop a last frame that repeats the first
  speed    source frames advanced per output frame (time compression, default 1)
  pingpong [a,b], period   air only: seamless loop easing a->b->a over `period` output frames (cosine timing)
  legs     0..1, how much of the source's leg bend to keep: ankles/knees blended toward the standing offset (tuck depth
           in the air, squat depth on landing). Default 1.
  stand_frame     source frame used as the standing reference for `legs` and the hips' horizontal offset (default start
                  of the action)
  x_scale  stance width: scales sideways ankle/knee offsets (and the hips' sideways sway for "once")
  deyaw    "upper" (hips and everything above turn back to yaw_ref_deg; planted feet do not slide) | "all" | ""
  yaw_ref_deg     pelvis heading to turn back to (default: the standing frame's)
  blend_to_idle   one-shots: the last N frames ease into the idle clip's first pose (feet re-pinned)
  rm_speed_m_s    in-place sources: the root-motion speed measured on the source (m/s); scaled to the rig in the report
Speeds: clip_ground_speed_m_s is the source speed scaled to the rig; measured_ball_speed_m_s is the planted foot's
speed measured on the retargeted pose (what the game's *_CLIP_SPEED constants mean).
"""
import bpy, sys, json, math, os
from mathutils import Matrix, Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
JOBS, GLB = argv[0], argv[1]
SAVE = "--save" in argv
RENDER = argv[argv.index("--render") + 1] if "--render" in argv else None
SPEC = json.load(open(JOBS, encoding="utf-8-sig"))
jobs = SPEC.get("clips", [])

ARM = bpy.data.objects["Armature"]
SCENE = bpy.context.scene
LEG_MESHES = [bpy.data.objects[n] for n in ("Body_Legs", "Suit_Legs") if n in bpy.data.objects]
FPS = SCENE.render.fps

MAP_MIXAMO = {  # astronaut bone <- mixamo bone (prefix stripped)
    "Hips": "Hips", "Spine": "Spine1", "Chest": "Spine2", "Neck": "Neck", "Head": "Head",
    "ShoulderL": "LeftShoulder", "UpperArmL": "LeftArm", "LowerArmL": "LeftForeArm", "HandL": "LeftHand",
    "ShoulderR": "RightShoulder", "UpperArmR": "RightArm", "LowerArmR": "RightForeArm", "HandR": "RightHand",
    "UpperLegL": "LeftUpLeg", "LowerLegL": "LeftLeg", "FootL": "LeftFoot", "ToesL": "LeftToeBase",
    "UpperLegR": "RightUpLeg", "LowerLegR": "RightLeg", "FootR": "RightFoot", "ToesR": "RightToeBase",
}
MAP_UE = {  # astronaut bone <- Quaternius UAL / UE mannequin bone
    "Hips": "pelvis", "Spine": "spine_02", "Chest": "spine_03", "Neck": "neck_01", "Head": "Head",
    "ShoulderL": "clavicle_l", "UpperArmL": "upperarm_l", "LowerArmL": "lowerarm_l", "HandL": "hand_l",
    "ShoulderR": "clavicle_r", "UpperArmR": "upperarm_r", "LowerArmR": "lowerarm_r", "HandR": "hand_r",
    "UpperLegL": "thigh_l", "LowerLegL": "calf_l", "FootL": "foot_l", "ToesL": "ball_l",
    "UpperLegR": "thigh_r", "LowerLegR": "calf_r", "FootR": "foot_r", "ToesR": "ball_r",
}
LEGSET = {"UpperLegL", "LowerLegL", "FootL", "ToesL", "UpperLegR", "LowerLegR", "FootR", "ToesR"}

def rot3(m):
    return m.to_3x3().normalized()

def set_action(obj, action):
    if obj.animation_data is None:
        obj.animation_data_create()
    obj.animation_data.action = action
    if action is not None and hasattr(obj.animation_data, "action_slot") and action.slots:
        obj.animation_data.action_slot = action.slots[0]

ORIG_ACTIONS = set(bpy.data.actions)
tgt_rest = {b.name: b.matrix_local.copy() for b in ARM.data.bones}  # armature object is identity
HEAD = {b.name: b.head_local.copy() for b in ARM.data.bones}
order = [b for b in ARM.data.bones]  # parent-before-child
for pb in ARM.pose.bones:
    pb.rotation_mode = 'QUATERNION'
TGT_LEG = (HEAD["LowerLegL"] - HEAD["UpperLegL"]).length + (HEAD["FootL"] - HEAD["LowerLegL"]).length

for tr in ARM.animation_data.nla_tracks:
    tr.mute = True
set_action(ARM, bpy.data.actions["idle"])
SCENE.frame_set(0)
IDLE = {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in ARM.pose.bones}
set_action(ARM, None)

def lowest_leg_z():
    dg = bpy.context.evaluated_depsgraph_get()
    z = 1e9
    for o in LEG_MESHES:
        e = o.evaluated_get(dg); me = e.to_mesh()
        mw = e.matrix_world
        for v in me.vertices:
            z = min(z, (mw @ v.co).z)
        e.to_mesh_clear()
    return z

for pb in ARM.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
REST_MIN = lowest_leg_z()

def frame_of(x, y):
    x = x.normalized()
    y = (y - x * y.dot(x)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()

def two_bone(h, a, l1, l2, pole):
    d_vec = a - h
    d = min(d_vec.length, (l1 + l2) * 0.999)
    u = d_vec.normalized()
    along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    up = max(l1 * l1 - along * along, 0.0) ** 0.5
    v = pole - u * pole.dot(u)
    v = v.normalized() if v.length > 1e-6 else Vector((0, -1, 0))
    return h + u * along + v * up, h + u * d

# ---------------------------------------------------------------- sources (each file imported once)
SOURCES = {}
def load_source(path):
    if path in SOURCES:
        return SOURCES[path]
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    SCENE.render.fps = FPS  # importers may change it; the clips are keyed at the crew scene's rate
    new_o = [o for o in bpy.data.objects if o not in before_o]
    src = [o for o in new_o if o.type == 'ARMATURE'][0]
    names = {b.name for b in src.data.bones}
    if "pelvis" in names:
        smap, prefix = MAP_UE, ""
    else:
        prefix = src.data.bones[0].name.split(":")[0] + ":" if ":" in src.data.bones[0].name else ""
        smap = MAP_MIXAMO
    if src.animation_data:
        for t in src.animation_data.nla_tracks:
            t.mute = True
    for o in new_o:
        if o.type != 'ARMATURE':
            o.hide_render = True
    SOURCES[path] = dict(obj=src, smap=smap, prefix=prefix, new_o=new_o,
                         new_a=[a for a in bpy.data.actions if a not in before_a],
                         action=src.animation_data.action if src.animation_data else None)
    return SOURCES[path]

def run_job(job):
    R = {k: job[k] for k in job if k not in ("report",)}
    R["glb"] = GLB
    mode = job["mode"]
    S = load_source(job["source"])
    SRC, smap, prefix = S["obj"], S["smap"], S["prefix"]
    act_src = bpy.data.actions[job["action"]] if job.get("action") else S["action"]
    set_action(SRC, act_src)
    F0, F1 = act_src.frame_range[0], act_src.frame_range[1]
    R["source_action"] = act_src.name
    R["source_action_frames"] = [round(F0, 2), round(F1, 2)]
    R["scene_fps"] = SCENE.render.fps
    sb = lambda t: SRC.pose.bones[prefix + smap[t]]
    mw = SRC.matrix_world

    src_rest = {t: rot3(mw @ SRC.data.bones[prefix + s].matrix_local) for t, s in smap.items()}
    correction = {}
    for t, s in smap.items():
        b = SRC.data.bones[prefix + s]
        s_dir = (rot3(mw) @ (b.tail_local - b.head_local)).normalized()
        tb = ARM.data.bones[t]
        t_dir = (tb.tail_local - tb.head_local).normalized()
        correction[t] = src_rest[t].inverted() @ t_dir.rotation_difference(s_dir).to_matrix() @ rot3(tgt_rest[t])

    def bh(t):
        return mw @ SRC.data.bones[prefix + smap[t]].head_local
    src_leg = ((bh("LowerLegL") - bh("UpperLegL")).length + (bh("FootL") - bh("LowerLegL")).length
               + (bh("LowerLegR") - bh("UpperLegR")).length + (bh("FootR") - bh("LowerLegR")).length) / 2
    scale = TGT_LEG / src_leg
    R["scale"] = round(scale, 4)

    def sample(f):
        fi = int(math.floor(f)); SCENE.frame_set(fi, subframe=f - fi)
        world = {t: rot3(mw @ sb(t).matrix) for t in smap}
        hips = mw @ sb("Hips").head
        legs = {s: ((mw @ sb("LowerLeg" + s).head) - hips, (mw @ sb("Foot" + s).head) - hips) for s in ("L", "R")}
        v = (mw @ sb("UpperLegR").head) - (mw @ sb("UpperLegL").head)
        return world, hips.copy(), legs, math.atan2(-v.y, -v.x)  # pelvis heading, 0 = facing -Y

    stand_f = job.get("stand_frame", F0)
    if job.get("stand_action"):
        set_action(SRC, bpy.data.actions[job["stand_action"]])
    stand_world, hips_ref, legs_stand, yaw_stand = sample(stand_f)
    set_action(SRC, act_src)
    deyaw = job.get("deyaw", "")
    yaw_ref = math.radians(job["yaw_ref_deg"]) if "yaw_ref_deg" in job else yaw_stand
    xs = job.get("x_scale", 1.0)
    xo = job.get("x_offset", 0.0)  # source metres each ankle/knee is pushed outward (for gaits whose feet cross the midline)
    leg_amt = job.get("legs", 1.0)
    upper_amt = job.get("upper", 1.0)  # 0..1: how much of the source's upper-body pose to keep vs the standing pose
    if deyaw:
        rzs = Matrix.Rotation(-(yaw_stand - yaw_ref), 3, 'Z')
        stand_world = {t: (rzs @ r if t not in LEGSET else r) for t, r in stand_world.items()}

    def fix(smp):
        world, hips, legs, yaw = smp
        if deyaw:
            rz = Matrix.Rotation(-(yaw - yaw_ref), 3, 'Z')
            world = {t: (rz @ r if (deyaw == "all" or t not in LEGSET) else r) for t, r in world.items()}
            if deyaw == "all":
                legs = {s: (rz @ k, rz @ a) for s, (k, a) in legs.items()}
        if upper_amt != 1.0:
            world = {t: (stand_world[t].to_quaternion().slerp(r.to_quaternion(), upper_amt).to_matrix()
                         if t not in LEGSET else r) for t, r in world.items()}
        if leg_amt != 1.0:
            legs = {s: (legs_stand[s][0].lerp(k, leg_amt), legs_stand[s][1].lerp(a, leg_amt)) for s, (k, a) in legs.items()}
        if xs != 1.0:
            legs = {s: (Vector((k.x * xs, k.y, k.z)), Vector((a.x * xs, a.y, a.z))) for s, (k, a) in legs.items()}
        if xo:
            legs = {s: (k + Vector((xo if s == "L" else -xo, 0, 0)), a + Vector((xo if s == "L" else -xo, 0, 0)))
                    for s, (k, a) in legs.items()}
        return world, hips, legs, yaw

    # ---- source times
    spd = job.get("speed", 1.0)
    if mode == "air" and "pingpong" in job:
        a, b = job["pingpong"]; P = job.get("period", 36)
        times = [a + (b - a) * (0.5 - 0.5 * math.cos(2 * math.pi * t / P)) for t in range(P)]
    else:
        start, end = job.get("start", F0), job.get("end", F1)
        times = []
        t = start
        while t <= end + 1e-6:
            times.append(t); t += spd
        if mode in ("loop", "air"):
            w0, w1 = sample(start)[0], sample(end)[0]
            dup = max(min(x, 6.283185 - x) for x in (w0[k].to_quaternion().rotation_difference(w1[k].to_quaternion()).angle for k in smap))
            R["last_frame_vs_first_deg"] = round(dup * 57.2958, 2)
            if dup < 0.06:
                times = times[:-1]
    R["source_times"] = [round(t, 2) for t in times]
    raw = [sample(t) for t in times]
    samples = [fix(s) for s in raw]
    n = len(samples)
    R["pelvis_yaw_deg_vs_ref"] = [round(math.degrees(s[3] - yaw_ref), 1) for s in raw[::max(1, n // 12)]]

    stride = Vector()
    if mode == "loop":
        stride = (samples[-1][1] - samples[0][1]) * (n / max(n - 1, 1))
        R["root_motion_per_cycle_m"] = [round(v, 3) for v in stride]
        cyc = n / FPS
        if "rm_speed_m_s" in job:
            R["source_speed_m_s"] = job["rm_speed_m_s"]
        else:
            R["source_speed_m_s"] = round(Vector((stride.x, stride.y)).length / cyc, 3)
        R["clip_ground_speed_m_s"] = round(R["source_speed_m_s"] * scale, 3)

    def leg_ik(side, hj, hip_pos, legs):
        knee_rel, ankle_rel = legs[side]
        ankle = hip_pos + ankle_rel * scale
        knee_src = hip_pos + knee_rel * scale
        pole = knee_src - (hj + ankle) * 0.5
        l1 = (HEAD["LowerLeg" + side] - HEAD["UpperLeg" + side]).length
        l2 = (HEAD["Foot" + side] - HEAD["LowerLeg" + side]).length
        knee, ankle = two_bone(hj, ankle, l1, l2, pole)
        fwd = Vector((0, -1, 0))
        r_thigh = frame_of(knee - hj, pole) @ frame_of(HEAD["LowerLeg" + side] - HEAD["UpperLeg" + side], fwd).transposed()
        r_shin = frame_of(ankle - knee, pole) @ frame_of(HEAD["Foot" + side] - HEAD["LowerLeg" + side], fwd).transposed()
        return r_thigh @ rot3(tgt_rest["UpperLeg" + side]), r_shin @ rot3(tgt_rest["LowerLeg" + side])

    def pose_frame(world, hip_pos, legs):
        pose_mat = {}; override = {}
        for b in order:
            pb = ARM.pose.bones[b.name]
            rest = tgt_rest[b.name]
            if b.parent is None:
                parent_pose = Matrix.Identity(4); rel = rest
            else:
                parent_pose = pose_mat[b.parent.name]; rel = tgt_rest[b.parent.name].inverted() @ rest
            inherited = parent_pose @ rel
            if b.name in ("UpperLegL", "UpperLegR"):
                side = b.name[-1]
                override["UpperLeg" + side], override["LowerLeg" + side] = leg_ik(side, inherited.translation.copy(), hip_pos, legs)
            if b.name in override:
                m = Matrix.Translation(inherited.translation) @ override[b.name].to_4x4()
            elif b.name in world:
                m = Matrix.Translation(inherited.translation) @ (world[b.name] @ correction[b.name]).to_4x4()
            else:
                m = inherited
            if b.parent is None:
                m = Matrix.Translation(hip_pos) @ rot3(m).to_4x4()
            loc, q, _ = (inherited.inverted() @ m).decompose()
            pb.rotation_quaternion = q
            pb.location = loc if b.parent is None else Vector()
            pb.scale = Vector((1, 1, 1))
            pose_mat[b.name] = inherited @ Matrix.Translation(pb.location) @ q.to_matrix().to_4x4()

    hips_pb = ARM.pose.bones["Hips"]
    hips_rest_inv = rot3(tgt_rest["Hips"]).inverted()
    vertical = job.get("vertical", "rest" if mode == "air" else "pin")

    def lift(dz):
        hips_pb.location = hips_pb.location + hips_rest_inv @ Vector((0, 0, dz))

    def floor_gap():
        bpy.context.view_layer.update()
        return REST_MIN - lowest_leg_z()

    set_action(ARM, None)
    basis = []
    first_dz = None
    for i, (world, hips, legs, _y) in enumerate(samples):
        if mode == "loop":
            off = hips - (samples[0][1] + stride * (i / n))
            hip_pos = Vector((off.x * scale, off.y * scale, hips.z * scale))
        elif mode == "once":
            off = hips - hips_ref
            hip_pos = Vector((off.x * scale * xs, off.y * scale, hips.z * scale))
        else:
            hip_pos = Vector((0, 0, tgt_rest["Hips"].translation.z))
        pose_frame(world, hip_pos, legs)
        if vertical == "pin":
            lift(floor_gap())
        elif vertical in ("pin_first", "pin_up"):
            g = floor_gap()
            if first_dz is None:
                first_dz = g
            # pin_up: the source's own rise, but never below the floor (a straightening push-off leg)
            lift(max(g, first_dz) if vertical == "pin_up" else first_dz)
        basis.append({pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in ARM.pose.bones})

    # airborne loops: if a hanging foot would reach below the character origin, lift the whole loop just enough to
    # keep `clearance` metres under it (walking off a ledge enters this clip with the capsule still on the floor)
    if vertical == "rest" and "clearance" in job:
        lows = []
        for bdict in basis:
            for pb in ARM.pose.bones:
                pb.rotation_quaternion, pb.location = bdict[pb.name]
            bpy.context.view_layer.update()
            lows.append(lowest_leg_z() - REST_MIN)
        up = max(0.0, job["clearance"] - min(lows))
        R["air_lift_m"] = round(up, 3)
        if up > 0:
            d = hips_rest_inv @ Vector((0, 0, up))
            for bdict in basis:
                q, loc = bdict["Hips"]; bdict["Hips"] = (q, loc + d)

    k = job.get("blend_to_idle", 0) if mode == "once" else 0
    for j in range(k):
        i = n - k + j
        w = (j + 1) / k; w = w * w * (3 - 2 * w)
        for pb in ARM.pose.bones:
            q, loc = basis[i][pb.name]; qi, li = IDLE[pb.name]
            if q.dot(qi) < 0: qi = -qi
            pb.rotation_quaternion = q.slerp(qi, w); pb.location = loc.lerp(li, w)
        if vertical in ("pin", "pin_first", "pin_up"):
            lift(floor_gap())
        basis[i] = {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in ARM.pose.bones}

    # ---- key, measuring as we go
    act = bpy.data.actions.new(job["target"] + "__new")
    set_action(ARM, act)
    prev_q = {}
    gap, resid, hipz, balls = [], [], [], []
    keys = basis + ([basis[0]] if mode in ("loop", "air") else [])
    for f, bdict in enumerate(keys):
        for pb in ARM.pose.bones:
            q, loc = bdict[pb.name]
            q = q.copy()
            if pb.name in prev_q and prev_q[pb.name].dot(q) < 0:
                q.negate()
            prev_q[pb.name] = q.copy()
            pb.rotation_quaternion = q; pb.location = loc
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if pb.parent is None:
                pb.keyframe_insert("location", frame=f)
        if f < n:
            bpy.context.view_layer.update()
            fl, fr = ARM.pose.bones["FootL"].head, ARM.pose.bones["FootR"].head
            gap.append(fl.x - fr.x); hipz.append(hips_pb.head.z)
            resid.append(lowest_leg_z() - REST_MIN)
            balls.append((ARM.pose.bones["ToesL"].head.copy(), ARM.pose.bones["ToesR"].head.copy()))
    last = len(keys) - 1
    R["frames_keyed"] = len(keys)
    R["seconds"] = round(last / FPS, 4)
    R["ankle_gap_m"] = [round(min(gap), 3), round(max(gap), 3)]
    R["hips_z_m"] = [round(min(hipz), 3), round(max(hipz), 3)]
    R["lowest_leg_above_floor_mm"] = [round(min(resid) * 1000, 1), round(max(resid) * 1000, 1)]
    if mode == "loop":
        # planted-foot speed on the retargeted pose: ball of the foot while it is within 2 cm of its lowest height
        v = []
        zmin = min(min(bb[0].z, bb[1].z) for bb in balls)
        for s in (0, 1):
            for i in range(n):
                a, b = balls[i][s], balls[(i + 1) % n][s]
                if a.z < zmin + 0.012 and b.z < zmin + 0.012:
                    v.append(abs(b.y - a.y) * FPS)
        v.sort()
        R["measured_ball_speed_m_s"] = round(v[len(v) // 2], 3) if v else None
        R["planted_samples"] = len(v)
    # foot sliding check: per-frame movement of a planted ball of the foot (within 12 mm of the floor in both frames);
    # sideways for every clip, and along the walk direction too for one-shots (loops slide backwards on purpose)
    zmin = min(min(bb[0].z, bb[1].z) for bb in balls)
    side, fwd = [], []
    for s in (0, 1):
        for i in range(n - 1):
            a, b = balls[i][s], balls[i + 1][s]
            if a.z < zmin + 0.012 and b.z < zmin + 0.012:
                side.append(abs(b.x - a.x)); fwd.append(abs(b.y - a.y))
    R["planted_ball_sideways_mm_per_frame_max"] = round(max(side) * 1000, 1) if side else None
    if mode == "once":
        R["planted_ball_forward_mm_per_frame_max"] = round(max(fwd) * 1000, 1) if fwd else None
    set_action(ARM, None)
    put_on_track(job["target"], act, last)
    for live in job.get("live", []):
        put_on_track(live, act, last, job.get("old_names", {}).get(live))
    for pb in ARM.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    return R

def put_on_track(track_name, act, last, old_name=None):
    track = next((t for t in ARM.animation_data.nla_tracks if t.name == track_name), None)
    if track is None:
        track = ARM.animation_data.nla_tracks.new(); track.name = track_name
    for s in list(track.strips):
        track.strips.remove(s)
    old = bpy.data.actions.get(track_name)
    if old is not None and old != act:
        old.name = old_name or (track_name + "_old")
        old.use_fake_user = True
    if act.name.endswith("__new"):
        act.name = track_name
    strip = track.strips.new(track_name, 0, act)
    strip.frame_end = max(last, 1)
    track.mute = True

# ---------------------------------------------------------------- copies of existing clips under new names
for c in SPEC.get("copies", []):
    a = bpy.data.actions[c["from"]]
    src_strip = next(s for t in ARM.animation_data.nla_tracks if t.name == c["from"] for s in t.strips)
    put_on_track(c["target"], a, src_strip.frame_end)

reports = []
for job in jobs:
    for tr in ARM.animation_data.nla_tracks:
        tr.mute = True
    reports.append((job, run_job(job)))
SCENE.frame_set(0)
# drop the imported sources and the actions that came with them
for S in SOURCES.values():
    for o in S["new_o"]:
        d = o.data
        bpy.data.objects.remove(o, do_unlink=True)
    for a in S["new_a"]:  # the FBX importer gives its actions a fake user, so remove them explicitly
        if a.name in bpy.data.actions:
            bpy.data.actions.remove(a)
for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.cameras, bpy.data.lights, bpy.data.images):
    for d in list(coll):
        if d.users == 0 and not d.use_fake_user:
            coll.remove(d)

# ---------------------------------------------------------------- export (same settings as build_character.py)
for tr in ARM.animation_data.nla_tracks:
    tr.mute = False
set_action(ARM, None)
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    if o == ARM or o.parent == ARM:
        o.select_set(True)
bpy.context.view_layer.objects.active = ARM
props = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
kw = dict(filepath=GLB, export_format='GLB', use_selection=True, export_yup=True, export_animations=True,
          export_skins=True, export_materials='EXPORT', export_apply=False, export_frame_range=False,
          export_force_sampling=True, export_animation_mode='NLA_TRACKS', export_anim_slide_to_zero=True,
          export_def_bones=False, export_extra_animations=False, export_all_influences=False)
bpy.ops.export_scene.gltf(**{k: v for k, v in kw.items() if k in props})

import struct
raw_glb = open(GLB, "rb").read()
size = struct.unpack_from('<I', raw_glb, 12)[0]
gltf = json.loads(raw_glb[20:20 + size])
rows = []
for a in gltf.get('animations', []):
    ins = [gltf['accessors'][s['input']] for s in a['samplers']]
    rows.append({'name': a.get('name'), 'seconds': round(max(i['max'][0] for i in ins) - min(i['min'][0] for i in ins), 4)})

# ---------------------------------------------------------------- optional stills for contact sheets
def render_stills(out_dir, clips):
    os.makedirs(out_dir, exist_ok=True)
    for tr in ARM.animation_data.nla_tracks:
        tr.mute = True
    sc = SCENE
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_shadows = False
    sc.render.resolution_x, sc.render.resolution_y = 300, 440
    old_cam = sc.camera
    cam = bpy.data.objects.new("_sheet_cam", bpy.data.cameras.new("_sheet_cam")); sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.3
    me = bpy.data.meshes.new("_sheet_floor")
    me.from_pydata([(-1.1, -1.1, 0), (1.1, -1.1, 0), (1.1, 1.1, 0), (-1.1, 1.1, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("_sheet_floor", me); sc.collection.objects.link(floor)
    fm = bpy.data.materials.new("_sheet_floor"); fm.diffuse_color = (0.12, 0.13, 0.15, 1); me.materials.append(fm)
    sc.camera = cam
    for clip, action_name, last, oneshot in clips:
        set_action(ARM, bpy.data.actions[action_name])
        nshots = 6
        frames = sorted({round(last * i / (nshots - 1)) for i in range(nshots)}) if oneshot else sorted({round(last * i / nshots) for i in range(nshots)})
        for suited in (True, False):
            for o in bpy.data.objects:
                if o.type == 'MESH' and not o.name.startswith("_sheet"):
                    if o.name.startswith("Suit"):
                        o.hide_render = not suited
                    elif o.name in ("Body_Torso", "Body_Arms", "Body_Legs"):
                        o.hide_render = suited
            for view, ang in (("front", 0), ("side", 90), ("back", 180)):
                if not suited and view != "side":
                    continue
                for f in frames:
                    sc.frame_set(f)
                    a = math.radians(ang)
                    cam.location = Vector((math.sin(a) * 6, -math.cos(a) * 6, 0.95))
                    cam.rotation_euler = (math.pi / 2, 0, a)
                    sc.render.filepath = os.path.join(out_dir, f"{clip}_{view}_{'suit' if suited else 'body'}_{f:03d}.png")
                    bpy.ops.render.render(write_still=True)
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.hide_render = False
    cd = cam.data
    bpy.data.objects.remove(cam, do_unlink=True); bpy.data.cameras.remove(cd)
    bpy.data.objects.remove(floor, do_unlink=True); bpy.data.meshes.remove(me); bpy.data.materials.remove(fm)
    sc.camera = old_cam
    set_action(ARM, None)
    for pb in ARM.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)

if RENDER:
    clips = [(j["target"], j["target"], r["frames_keyed"] - 1, j["mode"] == "once") for j, r in reports if j.get("sheet", True)]
    for c in SPEC.get("copies", []):
        if c.get("sheet", False):
            st = next(s for t in ARM.animation_data.nla_tracks if t.name == c["target"] for s in t.strips)
            clips.append((c["target"], st.action.name, st.frame_end, False))
    render_stills(RENDER, [(c, a, int(round(l)), o) for c, a, l, o in clips])

for job, rep in reports:
    rep["glb_animations"] = rows
    rep["glb_bytes"] = len(raw_glb)
    rep["saved_blend"] = SAVE
    if job.get("report"):
        open(job["report"], "w").write(json.dumps(rep, indent=1))
if SPEC.get("summary"):
    summ = {"glb": GLB, "glb_animations": rows, "live": {}, "candidates": {}}
    for t in ARM.animation_data.nla_tracks:
        if t.strips:
            summ["live" if t.strips[0].action.name != t.name else "candidates"][t.name] = t.strips[0].action.name
    summ["candidates"] = {}
    for job, rep in reports:
        summ["candidates"][job["target"]] = {k: rep.get(k) for k in (
            "source", "source_action", "mode", "source_times", "frames_keyed", "seconds", "source_speed_m_s", "scale",
            "clip_ground_speed_m_s", "measured_ball_speed_m_s", "ankle_gap_m", "hips_z_m", "lowest_leg_above_floor_mm",
            "live", "notes")}
        summ["candidates"][job["target"]]["source_times"] = [rep["source_times"][0], rep["source_times"][-1]]
    for c in SPEC.get("copies", []):
        summ["candidates"].setdefault(c["target"], {"copy_of": c["from"], **c.get("info", {})})
    summ["live_tracks"] = {t.name: t.strips[0].action.name for t in ARM.animation_data.nla_tracks if t.strips}
    open(SPEC["summary"], "w").write(json.dumps(summ, indent=1))

if SAVE:
    for tr in ARM.animation_data.nla_tracks:
        tr.mute = True
    set_action(ARM, None)
    SCENE.frame_set(0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_mainfile()
