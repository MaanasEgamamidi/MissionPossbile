"""Pose-level animation layer for the crew rig (Blender). Used by anim_v5_build.py; exec() it inside Blender.

A Pose is the rig described in armature space: W[bone] world 3x3 rotation for every bone, hip (Hips head position),
ank[side] ankle targets, knee[side] knee positions (the knee bend direction comes from them) . solve() turns a Pose
into pose-bone basis values: plain FK for every bone except thigh and shin, which reach the ankle target with the
same two-bone IK as retarget_mixamo_walk.py (the rig's hip joints sit 0.24 m out, so the legs are always placed by
ankle target, never by copied rotations).
Axes: the character faces -Y, its left is +X, up is +Z.
"""
import bpy, math
from mathutils import Matrix, Vector, Quaternion

ARM = bpy.data.objects["Armature"]
SCENE = bpy.context.scene
FPS = SCENE.render.fps
LEG_MESHES = [bpy.data.objects[n] for n in ("Body_Legs", "Suit_Legs") if n in bpy.data.objects]
REST = {b.name: b.matrix_local.copy() for b in ARM.data.bones}
HEAD = {b.name: b.head_local.copy() for b in ARM.data.bones}
ORDER = [b for b in ARM.data.bones]
LEGS = {"UpperLegL", "LowerLegL", "FootL", "ToesL", "UpperLegR", "LowerLegR", "FootR", "ToesR"}
SIDES = ("L", "R")
SGN = {"L": 1.0, "R": -1.0}
for pb in ARM.pose.bones:
    pb.rotation_mode = 'QUATERNION'

def rot3(m):
    return m.to_3x3().normalized()

def children_of(name):
    out = []
    def rec(b):
        for c in b.children:
            if c.name not in LEGS:
                out.append(c.name); rec(c)
    rec(ARM.data.bones[name])
    return out

SUBTREE = {b.name: [b.name] + children_of(b.name) for b in ARM.data.bones}

def set_action(action):
    if ARM.animation_data is None:
        ARM.animation_data_create()
    for t in ARM.animation_data.nla_tracks:
        t.mute = True
    ARM.animation_data.action = action
    if action is not None and hasattr(ARM.animation_data, "action_slot") and action.slots:
        ARM.animation_data.action_slot = action.slots[0]

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

class Pose:
    def __init__(self):
        self.W = {}; self.hip = Vector(); self.ank = {}; self.knee = {}
    def copy(self):
        p = Pose(); p.W = {k: v.copy() for k, v in self.W.items()}; p.hip = self.hip.copy()
        p.ank = {k: v.copy() for k, v in self.ank.items()}; p.knee = {k: v.copy() for k, v in self.knee.items()}
        return p

def read_pose():
    """The current pose bones as a Pose."""
    bpy.context.view_layer.update()
    p = Pose()
    for pb in ARM.pose.bones:
        p.W[pb.name] = rot3(pb.matrix)
    pbs = ARM.pose.bones
    p.hip = pbs["Hips"].head.copy()
    for s in SIDES:
        p.ank[s] = pbs["Foot" + s].head.copy(); p.knee[s] = pbs["LowerLeg" + s].head.copy()
    return p

def eval_action(action, t):
    set_action(action)
    fi = int(math.floor(t)); SCENE.frame_set(fi, subframe=t - fi)
    return read_pose()

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

L1 = {s: (HEAD["LowerLeg" + s] - HEAD["UpperLeg" + s]).length for s in SIDES}
L2 = {s: (HEAD["Foot" + s] - HEAD["LowerLeg" + s]).length for s in SIDES}

def solve(p, knee_forward=0.0):
    """Writes p into the pose bones (basis). knee_forward 0..1 turns each knee's bend direction toward straight ahead."""
    pose_mat = {}
    pbs = ARM.pose.bones
    for b in ORDER:
        pb = pbs[b.name]; rest = REST[b.name]
        if b.parent is None:
            inherited = rest.copy()
        else:
            inherited = pose_mat[b.parent.name] @ (REST[b.parent.name].inverted() @ rest)
        name = b.name
        if name.startswith("UpperLeg") or name.startswith("LowerLeg"):
            s = name[-1]
            if name.startswith("UpperLeg"):
                hj = inherited.translation.copy()
                ank = p.ank[s]
                pole = p.knee[s] - (hj + ank) * 0.5
                if knee_forward > 0:
                    pole = pole.normalized().lerp(Vector((0, -1, 0)), knee_forward)
                knee, ank2 = two_bone(hj, ank, L1[s], L2[s], pole)
                fwd = Vector((0, -1, 0))
                p._thigh = frame_of(knee - hj, pole) @ frame_of(HEAD["LowerLeg" + s] - HEAD["UpperLeg" + s], fwd).transposed() @ rot3(REST["UpperLeg" + s])
                p._shin = frame_of(ank2 - knee, pole) @ frame_of(HEAD["Foot" + s] - HEAD["LowerLeg" + s], fwd).transposed() @ rot3(REST["LowerLeg" + s])
                r = p._thigh
            else:
                r = p._shin
        else:
            r = p.W[name]
        m = Matrix.Translation(inherited.translation) @ r.to_4x4()
        if b.parent is None:
            m = Matrix.Translation(p.hip) @ r.to_4x4()
        loc, q, _ = (inherited.inverted() @ m).decompose()
        pb.rotation_quaternion = q
        pb.location = loc if b.parent is None else Vector()
        pb.scale = Vector((1, 1, 1))
        pose_mat[name] = inherited @ Matrix.Translation(pb.location) @ q.to_matrix().to_4x4()

def floor_gap():
    bpy.context.view_layer.update()
    return REST_MIN - lowest_leg_z()

def shift_z(p, dz):
    p.hip = p.hip + Vector((0, 0, dz))
    for s in SIDES:
        p.ank[s] = p.ank[s] + Vector((0, 0, dz)); p.knee[s] = p.knee[s] + Vector((0, 0, dz))

def snapshot():
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in ARM.pose.bones}

def apply_snapshot(snap):
    for pb in ARM.pose.bones:
        pb.rotation_quaternion, pb.location = snap[pb.name][0].copy(), snap[pb.name][1].copy()

# ---------------------------------------------------------------- edits
def rotate_subtree(p, bone, R, only=False):
    for n in ([bone] if only else SUBTREE[bone]):
        p.W[n] = R @ p.W[n]

def Rx(deg): return Matrix.Rotation(math.radians(deg), 3, 'X')
def Ry(deg): return Matrix.Rotation(math.radians(deg), 3, 'Y')
def Rz(deg): return Matrix.Rotation(math.radians(deg), 3, 'Z')

def local_axis(bone, world_axis):
    """The bone-local vector that points along world_axis in the rest pose."""
    return rot3(REST[bone]).inverted() @ Vector(world_axis)

AX = {b.name: {"x": local_axis(b.name, (1, 0, 0)), "fwd": local_axis(b.name, (0, -1, 0)), "up": local_axis(b.name, (0, 0, 1))}
      for b in ARM.data.bones}

def lateral(p, bone):
    return (p.W[bone] @ AX[bone]["x"]).normalized()

def forward(p, bone):
    return (p.W[bone] @ AX[bone]["fwd"]).normalized()

def yaw_deg(p, bone):
    v = lateral(p, bone); return math.degrees(math.atan2(v.y, v.x))

def roll_deg(p, bone):
    """+ when the bone's left (+X) side is up."""
    return math.degrees(math.asin(max(-1, min(1, lateral(p, bone).z))))

def head_yaw_deg(p):
    f = forward(p, "Head"); return math.degrees(math.atan2(f.x, -f.y))

def set_yaw(p, bone, deg, only=False):
    rotate_subtree(p, bone, Rz(deg - yaw_deg(p, bone)), only)

def set_roll(p, bone, deg, only=False):
    rotate_subtree(p, bone, Ry(-(deg - roll_deg(p, bone))), only)

def trunk_pitch_deg(p):
    """Forward lean of hips->neck from vertical (+ = leaning forward)."""
    pos = fk_positions(p)
    v = pos["Neck"] - pos["Hips"]
    return math.degrees(math.atan2(-v.y, v.z))

def fk_positions(p):
    """Bone head positions of a Pose without touching the scene (legs from the last solve are ignored)."""
    out = {}; mats = {}
    for b in ORDER:
        rest = REST[b.name]
        if b.parent is None:
            m = Matrix.Translation(p.hip) @ p.W[b.name].to_4x4()
        else:
            inh = mats[b.parent.name] @ (REST[b.parent.name].inverted() @ rest)
            m = Matrix.Translation(inh.translation) @ p.W[b.name].to_4x4()
        mats[b.name] = m; out[b.name] = m.translation.copy()
    return out

def arm_vectors(p, s):
    pos = fk_positions(p)
    u = (pos["LowerArm" + s] - pos["UpperArm" + s]).normalized()
    f = (pos["Hand" + s] - pos["LowerArm" + s]).normalized()
    return u, f, pos

def arm_angles(p, s):
    """(abduction deg, forward flexion deg, elbow flex deg) of one arm, in the body's (chest) frame."""
    u, f, _ = arm_vectors(p, s)
    C = p.W["Chest"] @ rot3(REST["Chest"]).inverted()   # chest rotation relative to rest (world-axis frame)
    ul = C.inverted() @ u
    abd = math.degrees(math.asin(max(-1, min(1, ul.x * SGN[s]))))
    flex = math.degrees(math.asin(max(-1, min(1, -ul.y))))
    elbow = math.degrees(u.angle(f))
    return abd, flex, elbow

def set_abduction(p, s, deg):
    abd, _, _ = arm_angles(p, s)
    u, _, _ = arm_vectors(p, s)
    C = p.W["Chest"] @ rot3(REST["Chest"]).inverted()
    axis = C @ Vector((0, 1, 0))            # body forward-back axis
    # rotating about +Y moves a hanging arm toward -X; left arm abducts toward +X
    ang = -(deg - abd) * SGN[s]
    rotate_subtree(p, "UpperArm" + s, Matrix.Rotation(math.radians(ang), 3, axis))

def set_elbow(p, s, deg):
    u, f, _ = arm_vectors(p, s)
    cur = math.degrees(u.angle(f))
    n = u.cross(f)
    if n.length < 0.05:
        n = f.cross(Vector((0, -1, 0)))
    rotate_subtree(p, "LowerArm" + s, Matrix.Rotation(math.radians(deg - cur), 3, n.normalized()))

def aim_upper_arm(p, s, target_dir, w=1.0):
    u, _, _ = arm_vectors(p, s)
    q = u.rotation_difference(target_dir.normalized())
    q = Quaternion().slerp(q, w)
    rotate_subtree(p, "UpperArm" + s, q.to_matrix())

TOE_LOCAL = {s: rot3(REST["Foot" + s]).inverted() @ (HEAD["Toes" + s] - HEAD["Foot" + s]) for s in SIDES}

def _raw_out(W, s):
    v = W @ TOE_LOCAL[s]
    return math.degrees(math.atan2(v.x * SGN[s], -v.y))

REST_OUT = {s: _raw_out(rot3(REST["Foot" + s]), s) for s in SIDES}   # the rig's rest feet (= idle) count as 0

def foot_out_deg(p, s):
    """Toe-out of one foot relative to the rest/idle foot, seen from above, + = toes turned outward."""
    return _raw_out(p.W["Foot" + s], s) - REST_OUT[s]

def set_head_pitch(p, deg):
    """Absolute helmet pitch: + looks up (forward axis of the head above horizontal)."""
    cur = math.degrees(math.asin(max(-1, min(1, forward(p, "Head").z))))
    rotate_subtree(p, "Head", Rx(cur - deg))

def set_forearm(p, s, elbow_deg, inward=0.15, up=0.25):
    """Bends the elbow to elbow_deg with the forearm swung into the walking direction (not across the chest)."""
    u, f, _ = arm_vectors(p, s)
    C = p.W["Chest"] @ rot3(REST["Chest"]).inverted()
    d = C @ Vector((-SGN[s] * inward, -1.0, up))
    perp = (d - u * d.dot(u)).normalized()
    a = math.radians(elbow_deg)
    target = (u * math.cos(a) + perp * math.sin(a)).normalized()
    rotate_subtree(p, "LowerArm" + s, f.rotation_difference(target).to_matrix())

def turn_foot(p, s, deg_out):
    """Turns a foot (and toes) about vertical so its toe-out grows by deg_out."""
    R = Rz(deg_out * SGN[s])
    p.W["Foot" + s] = R @ p.W["Foot" + s]; p.W["Toes" + s] = R @ p.W["Toes" + s]

def lerp_pose(a, b, w):
    p = Pose()
    for k in a.W:
        p.W[k] = a.W[k].to_quaternion().slerp(b.W[k].to_quaternion(), w).to_matrix()
    p.hip = a.hip.lerp(b.hip, w)
    for s in SIDES:
        p.ank[s] = a.ank[s].lerp(b.ank[s], w); p.knee[s] = a.knee[s].lerp(b.knee[s], w)
    return p

def smooth(x):
    x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)

# ---------------------------------------------------------------- measuring a finished action
def measure(action, frames, loop, speed_dir=-1):
    """Per-clip numbers: ankle gap, hips height, knee/toe angles, arm angles, planted-foot speed and drift."""
    rows = []
    for f in range(frames):
        p = eval_action(action, f)
        pbs = ARM.pose.bones
        bpy.context.view_layer.update()
        balls = {s: pbs["Toes" + s].head.copy() for s in SIDES}
        heels = {s: pbs["Foot" + s].head.copy() for s in SIDES}
        knees = {s: pbs["LowerLeg" + s].head.copy() for s in SIDES}
        hj = {s: pbs["UpperLeg" + s].head.copy() for s in SIDES}
        knee_out = {}
        thigh = max(math.degrees((knees[s] - hj[s]).angle(Vector((0, 0, -1)))) for s in SIDES)
        kflex = max(math.degrees((knees[s] - hj[s]).angle(heels[s] - knees[s])) for s in SIDES)
        for s in SIDES:
            bend = math.degrees((knees[s] - hj[s]).angle(heels[s] - knees[s]))
            mid = (hj[s] + heels[s]) * 0.5
            d = knees[s] - mid
            # bend direction only means something once the knee is bent
            knee_out[s] = math.degrees(math.atan2(d.x * SGN[s], -d.y)) if bend > 15 else None
        arms = {s: arm_angles(p, s) for s in SIDES}
        hands = {s: pbs["Hand" + s].head.copy() for s in SIDES}
        rows.append(dict(f=f, gap=heels["L"].x - heels["R"].x, hipz=pbs["Hips"].head.z, hip=pbs["Hips"].head.copy(),
                         balls=balls, heels=heels, knee_out=knee_out, toe_out={s: foot_out_deg(p, s) for s in SIDES},
                         pitch={s: math.degrees((p.W["Foot" + s] @ TOE_LOCAL[s]).angle(rot3(REST["Foot" + s]) @ TOE_LOCAL[s]))
                                for s in SIDES},
                         arms=arms, hands=hands, trunk=trunk_pitch_deg(p), chest_yaw=yaw_deg(p, "Chest"),
                         pelvis_roll=roll_deg(p, "Hips"), head_pitch=math.degrees(math.asin(max(-1, min(1, forward(p, "Head").z)))),
                         navel_z=pbs["Spine"].head.z, low=lowest_leg_z() - REST_MIN, thigh=thigh, kflex=kflex,
                         hand_head=min((hands[s] - pbs["Head"].head).length for s in SIDES),
                         hand_back=max(hands[s].y - pbs["Chest"].head.y for s in SIDES)))
    R = {"frames": frames, "seconds": round((frames - 1) / FPS, 4)}
    rng = lambda key: [round(min(r[key] for r in rows), 3), round(max(r[key] for r in rows), 3)]
    R["ankle_gap_m"] = rng("gap"); R["hips_z_m"] = rng("hipz"); R["trunk_pitch_deg"] = rng("trunk")
    R["thigh_from_vertical_max_deg"] = round(max(r["thigh"] for r in rows), 1)
    R["knee_flex_max_deg"] = round(max(r["kflex"] for r in rows), 1)
    R["hand_to_head_min_m"] = round(min(r["hand_head"] for r in rows), 3)
    R["hand_behind_chest_max_m"] = round(max(r["hand_back"] for r in rows), 3)
    R["chest_yaw_deg"] = rng("chest_yaw"); R["pelvis_roll_deg"] = rng("pelvis_roll"); R["head_pitch_deg"] = rng("head_pitch")
    R["lowest_leg_above_floor_mm"] = [round(min(r["low"] for r in rows) * 1000, 1), round(max(r["low"] for r in rows) * 1000, 1)]
    ko = [v for r in rows for v in r["knee_out"].values() if v is not None]
    R["knee_out_deg_when_bent"] = [round(min(ko), 1), round(max(ko), 1)] if ko else None
    # toe-out only where the foot is near flat on the floor (ankle within 15 mm of its lowest)
    amin = {s: min(r["heels"][s].z for r in rows) for s in SIDES}
    # (skipping feet pitched over 50 deg, whose heading is undefined)
    to = [r["toe_out"][s] for r in rows for s in SIDES if r["heels"][s].z < amin[s] + 0.015 and r["pitch"][s] < 50]
    R["toe_out_deg_planted"] = [round(min(to), 1), round(max(to), 1)] if to else None
    for i, k in enumerate(("abduction", "arm_flex", "elbow_flex")):
        R[k + "_deg"] = [round(min(min(r["arms"][s][i] for s in SIDES) for r in rows), 1),
                         round(max(max(r["arms"][s][i] for s in SIDES) for r in rows), 1)]
    R["hand_above_navel_max_m"] = round(max(max(r["hands"][s].z - r["navel_z"] for s in SIDES) for r in rows), 3)
    R["hand_ahead_of_hips_max_m"] = round(max(max(-(r["hands"][s].y - r["hip"].y) for s in SIDES) for r in rows), 3)
    # planted foot, two consecutive frames: the ankle within 8 mm of its rest height (heel/flat foot down) or else
    # the ball of the foot within 8 mm of its rest height (rolling over the toes); drift is measured on that point
    vy, drift_side = [], []
    n = len(rows)
    hz = {s: (HEAD["Foot" + s].z, HEAD["Toes" + s].z) for s in SIDES}
    def contact(r, s):  # how far the foot's lower contact point (heel/ankle or ball) is above its rest height
        return min(r["heels"][s].z - hz[s][0], r["balls"][s].z - hz[s][1])
    for s in SIDES:
        o = "R" if s == "L" else "L"
        for i in range(n - 1):
            ra, rb = rows[i], rows[i + 1]
            # the planted foot is the lower one (a low swing foot passing a planted one is not "planted")
            if any(contact(r, s) > contact(r, o) + 0.002 for r in (ra, rb)):
                continue
            # the ball of the foot when it is down (flat foot or heel rising), else the heel (heel strike)
            if all(r["balls"][s].z < hz[s][1] + 0.008 for r in (ra, rb)):
                a, b = ra["balls"][s], rb["balls"][s]
            elif all(r["heels"][s].z < hz[s][0] + 0.008 for r in (ra, rb)):
                a, b = ra["heels"][s], rb["heels"][s]
            else:
                continue
            vy.append((b.y - a.y) * FPS); drift_side.append(abs(b.x - a.x))
    if vy:
        vs = sorted(vy); v = vs[len(vs) // 2]
        R["planted_ball_speed_m_s"] = round(abs(v), 3) if loop else None
        ref = v if loop else 0.0
        R["stance_drift_mm_per_frame_max"] = round(max(max(abs((x - ref) / FPS) for x in vy), max(drift_side)) * 1000, 1)
        R["planted_samples"] = len(vy)
    return R, rows
