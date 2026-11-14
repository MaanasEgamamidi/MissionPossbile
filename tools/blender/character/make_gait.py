"""Hand-built walk (and run) cycles for the crew rig, keyed bone by bone from a small set of gait parameters.

Replaces the retargeted Mixamo walk. The rig's hip joints sit 0.24 m out from the centre line, so any clip that hangs
the legs straight down from the hips (as the Mixamo retarget did) puts the feet about half a metre apart. Here the feet
are placed first, close to the centre line, and the legs reach them with two-bone IK.

Run inside Blender with crew_v2.blend open (MCP or headless):
    ns = {"__name__": "gait"}; exec(open(path).read(), ns)
    ns["build"]("walk", ns["WALK"]); ns["build"]("sprint", ns["RUN"]); ns["export"](glb_path, save=True)
Each clip replaces the NLA track of the same name; the old action is kept as <name>_old.
"""
import bpy, math
from mathutils import Matrix, Vector

FPS = 24  # not used for timing: clips play at the scene frame rate (30 once a Mixamo FBX has been imported)

# ------------------------------------------------------------------ parameters
WALK = dict(
    frames=16,            # one full cycle (two steps); 0.667 s at 24 fps
    stance=0.56,          # fraction of the cycle a foot is on the ground (> 0.5: both feet down briefly = a walk)
    half_travel=0.30,     # stance foot runs from 0.30 m in front of the hips to 0.30 m behind
    foot_x=0.12,          # ankle distance from the centre line (the rest pose has 0.144..0.185)
    lift=0.11,            # swing foot clearance at mid swing
    hip_z=0.965,          # wanted hips height (rest 0.94); lowered wherever the planted foot needs it
    bob=0.015,            # extra hips drop at the moment of foot contact
    sway=0.022,           # hips shift over the stance foot
    pelvis_yaw=6.0,       # degrees, the leading hip goes forward
    chest_yaw=-5.0,       # degrees, shoulders turn against the hips
    lean=3.0,             # degrees forward
    arm_swing=20.0,       # degrees each way at the shoulder
    arm_in=9.0,           # degrees the arms come in from the A-pose
    elbow=8.0,            # degrees of extra elbow bend, more on the forward swing
    heel_up=28.0,         # degrees of heel lift at toe-off
    toe_up=12.0,          # degrees of toes-up at heel strike
)
RUN = dict(WALK, frames=14, stance=0.38, half_travel=0.36, lift=0.22, hip_z=0.95, bob=-0.03, sway=0.015,
           pelvis_yaw=8.0, chest_yaw=-8.0, lean=8.0, arm_swing=34.0, elbow=75.0, heel_up=35.0, toe_up=10.0)


def ground_speed(p):
    """Metres per second the clip covers when played at speed 1 (at the scene's frame rate, which the export uses)."""
    t = p["frames"] / bpy.context.scene.render.fps
    return 2 * p["half_travel"] / (p["stance"] * t)


# ------------------------------------------------------------------ helpers
def rx(a): return Matrix.Rotation(a, 3, 'X')
def ry(a): return Matrix.Rotation(a, 3, 'Y')
def rz(a): return Matrix.Rotation(a, 3, 'Z')
def rot3(m): return m.to_3x3().normalized()
def smooth(u): return u * u * (3 - 2 * u)


def frame_of(x, y):
    """Orthonormal frame whose first axis is x and second is y made perpendicular to x."""
    x = x.normalized()
    y = (y - x * y.dot(x)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()


def two_bone(h, a, l1, l2, pole):
    """Knee position for hip h, ankle target a, bone lengths, bending towards pole."""
    d_vec = a - h
    d = min(d_vec.length, (l1 + l2) * 0.999)
    u = d_vec.normalized()
    along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    up = math.sqrt(max(l1 * l1 - along * along, 0.0))
    v = (pole - u * pole.dot(u)).normalized()
    return h + u * along + v * up, h + u * d


def foot_path(q, p):
    """Ankle offset (y, z) and foot pitch for a foot at cycle phase q (0 = heel strike). Forward is -Y."""
    s, h = p["stance"], p["half_travel"]
    if q < s:
        u = q / s
        y = -h + 2 * h * u                       # front to back under the body
        pitch = 0.0
        if u < 0.15:                             # heel strike: toes still up, settling
            pitch = -math.radians(p["toe_up"]) * (1 - u / 0.15)
        elif u > 0.7:                            # toe-off: heel rises about the toes
            pitch = math.radians(p["heel_up"]) * smooth((u - 0.7) / 0.3)
        return y, 0.0, pitch
    u = (q - s) / (1 - s)
    y = h - 2 * h * smooth(u)                    # swing back to front
    z = p["lift"] * math.sin(math.pi * min(1.0, u * 1.12))   # highest a little before mid swing, down just before contact
    pitch = math.radians(p["heel_up"]) * max(0.0, 1 - u / 0.35) - math.radians(p["toe_up"]) * smooth(max(0.0, (u - 0.6) / 0.4))
    return y, z, pitch


# ------------------------------------------------------------------ build one clip
def build(clip, p):
    arm = bpy.data.objects["Armature"]
    bones = arm.data.bones
    rest = {b.name: b.matrix_local.copy() for b in bones}
    rrot = {n: rot3(m) for n, m in rest.items()}
    order = list(bones)
    head = {b.name: b.head_local.copy() for b in bones}
    tail = {b.name: b.tail_local.copy() for b in bones}
    n = p["frames"]
    report = {"clip": clip, "frames": n, "seconds": round(n / bpy.context.scene.render.fps, 4), "ground_speed": round(ground_speed(p), 3), "foot_gap": []}

    old = bpy.data.actions.get(clip)
    act = bpy.data.actions.new(clip + "_new")
    arm.animation_data.action = act
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'

    def pose_frame(world, hip_pos):
        pose_mat = {}
        for b in order:
            pb = arm.pose.bones[b.name]
            r = rest[b.name]
            if b.parent is None:
                parent_pose, rel = Matrix.Identity(4), r
            else:
                parent_pose, rel = pose_mat[b.parent.name], rest[b.parent.name].inverted() @ r
            inherited = parent_pose @ rel
            if b.name in world:
                m = Matrix.Translation(inherited.translation) @ world[b.name].to_4x4()
            else:
                m = inherited
            if b.parent is None:
                m = Matrix.Translation(hip_pos) @ rot3(m).to_4x4()
            loc, q, _ = (inherited.inverted() @ m).decompose()
            pb.rotation_quaternion = q
            pb.location = loc if b.parent is None else Vector()
            pb.scale = Vector((1, 1, 1))
            pose_mat[b.name] = inherited @ Matrix.Translation(pb.location) @ q.to_matrix().to_4x4()
        return pose_mat

    prev = {}
    for f in range(n + 1):
        ph = (f % n) / n
        c = math.cos(2 * math.pi * ph)            # +1 when the left foot strikes, -1 when the right does
        yaw = -math.radians(p["pelvis_yaw"]) * c
        lean = math.radians(p["lean"])
        # ---- feet first
        targets, pitches = {}, {}
        for side, sx, q in (("L", 1, ph), ("R", -1, (ph + 0.5) % 1)):
            y, z, pitch = foot_path(q, p)
            ankle_rest = head["Foot" + side]
            a = Vector((sx * p["foot_x"], y, ankle_rest.z + z))
            if pitch > 0:  # heel up: turn about the toe joint so the toes stay planted
                toe = a + (head["Toes" + side] - ankle_rest)
                a = toe + rx(pitch) @ (ankle_rest - head["Toes" + side])
            targets[side], pitches[side] = a, pitch
        # ---- hips: height limited so the planted foot can be reached, sway over the stance foot
        stance_l = ph < p["stance"]
        z_hip = p["hip_z"] - p["bob"] * (0.5 + 0.5 * math.cos(4 * math.pi * ph))
        hips_rot = rz(yaw) @ rx(lean * 0.5)
        hip_pos = Vector((p["sway"] * math.cos(2 * math.pi * (ph - p["stance"] / 2)), 0.0, z_hip))  # over the left foot mid-stance
        for side in ("L", "R"):
            ql = ph if side == "L" else (ph + 0.5) % 1
            if ql < p["stance"]:
                leg = (head["Foot" + side] - head["LowerLeg" + side]).length + (head["LowerLeg" + side] - head["UpperLeg" + side]).length
                hj_off = hips_rot @ (head["UpperLeg" + side] - head["Hips"])
                hor = Vector((targets[side].x - hj_off.x - hip_pos.x, targets[side].y - hj_off.y, 0)).length
                reach = math.sqrt(max((leg * 0.997) ** 2 - hor * hor, 0.0)) + targets[side].z - hj_off.z
                hip_pos.z = min(hip_pos.z, reach)
        world = {}
        world["Hips"] = hips_rot @ rrot["Hips"]
        spine_d = rz(yaw * 0.4) @ rx(lean)
        chest_d = rz(-math.radians(p["chest_yaw"]) * c) @ rx(lean * 1.1)   # turns against the pelvis
        world["Spine"] = spine_d @ rrot["Spine"]
        world["Chest"] = chest_d @ rrot["Chest"]
        world["Neck"] = rx(lean * 0.4) @ rrot["Neck"]
        world["Head"] = rx(-lean * 0.3) @ rrot["Head"]      # eyes stay level
        for side, sx in (("L", 1), ("R", -1)):
            world["Shoulder" + side] = chest_d @ rrot["Shoulder" + side]
            swing = math.radians(p["arm_swing"]) * (c if side == "L" else -c)   # + = back: left arm back while the left foot leads
            upper_d = chest_d @ rx(swing) @ ry(math.radians(p["arm_in"]) * sx)
            world["UpperArm" + side] = upper_d @ rrot["UpperArm" + side]
            fwd = max(0.0, -swing) / max(math.radians(p["arm_swing"]), 1e-6)   # 0..1, more bend on the forward swing
            bend = math.radians(p["elbow"]) * (0.7 + 0.6 * fwd)
            lower_d = upper_d @ rx(-bend)
            world["LowerArm" + side] = lower_d @ rrot["LowerArm" + side]
            world["Hand" + side] = lower_d @ rrot["Hand" + side]
        # ---- legs: two-bone IK onto the foot targets, knees towards the facing direction
        forward = rz(yaw * 0.5) @ Vector((0, -1, 0))
        for side in ("L", "R"):
            hj = hip_pos + hips_rot @ (head["UpperLeg" + side] - head["Hips"])
            l1 = (head["LowerLeg" + side] - head["UpperLeg" + side]).length
            l2 = (head["Foot" + side] - head["LowerLeg" + side]).length
            knee, ankle = two_bone(hj, targets[side], l1, l2, forward)
            pole_rest = Vector((0, -1, 0))
            r_thigh = frame_of(knee - hj, forward) @ frame_of(head["LowerLeg" + side] - head["UpperLeg" + side], pole_rest).transposed()
            r_shin = frame_of(ankle - knee, forward) @ frame_of(head["Foot" + side] - head["LowerLeg" + side], pole_rest).transposed()
            world["UpperLeg" + side] = r_thigh @ rrot["UpperLeg" + side]
            world["LowerLeg" + side] = r_shin @ rrot["LowerLeg" + side]
            foot_d = rx(pitches[side])
            world["Foot" + side] = foot_d @ rrot["Foot" + side]
            world["Toes" + side] = (Matrix.Identity(3) if pitches[side] > 0 else foot_d) @ rrot["Toes" + side]
        pm = pose_frame(world, hip_pos)
        if f < n:
            report["foot_gap"].append(round((pm["FootL"].translation - pm["FootR"].translation).x, 3))
        for pb in arm.pose.bones:
            qq = pb.rotation_quaternion.copy()
            if pb.name in prev and prev[pb.name].dot(qq) < 0:
                qq.negate(); pb.rotation_quaternion = qq
            prev[pb.name] = qq.copy()
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if pb.parent is None:
                pb.keyframe_insert("location", frame=f)

    # swap into the NLA track
    arm.animation_data.action = None
    track = next(t for t in arm.animation_data.nla_tracks if t.name == clip)
    for s in list(track.strips):
        track.strips.remove(s)
    if old is not None:
        old.name = clip + "_old"
        old.use_fake_user = True
    act.name = clip
    strip = track.strips.new(clip, 0, act)
    strip.frame_end = n
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    report["foot_gap_range"] = [min(report["foot_gap"]), max(report["foot_gap"])]
    del report["foot_gap"]
    return report


def export(glb, save=False):
    arm = bpy.data.objects["Armature"]
    if save:
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_mainfile()
    for tr in arm.animation_data.nla_tracks:
        tr.mute = False
    # old clips are kept for reference in the .blend, never exported
    for a in bpy.data.actions:
        if a.name.endswith("_old"):
            a.use_fake_user = True
    for o in bpy.context.view_layer.objects:
        o.select_set(o == arm or o.parent == arm)
    bpy.context.view_layer.objects.active = arm
    props = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kw = dict(filepath=glb, export_format='GLB', use_selection=True, export_yup=True, export_animations=True,
              export_skins=True, export_materials='EXPORT', export_apply=False, export_frame_range=False,
              export_force_sampling=True, export_animation_mode='NLA_TRACKS', export_anim_slide_to_zero=True,
              export_def_bones=False, export_extra_animations=False, export_all_influences=False)
    bpy.ops.export_scene.gltf(**{k: v for k, v in kw.items() if k in props})
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    return glb

