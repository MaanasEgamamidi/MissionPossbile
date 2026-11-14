"""Retargets a Mixamo walk (FBX, skeleton only) onto the astronaut rig and re-exports astronaut.glb.

Run headless:
  blender -b --factory-startup --disable-autoexec <astronaut.blend> --python retarget_mixamo_walk.py -- <walk.fbx> <out.glb> <report.json> [--save]

Method: per bone, the target follows the source bone's world-space rotation, after a rest-pose correction that
turns the target's rest direction onto the source's rest direction (Mixamo is a T-pose, the astronaut is not).
Root motion is removed (the game moves the capsule); the hips height is then set per frame so the lowest
point of the legs and boots sits at the rest-pose height (feet stay on the ground, no sinking).
The result replaces the clip called 'walk'; every other clip is left as it was.
"""
import bpy, sys, json
from mathutils import Matrix, Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
FBX, GLB, REPORT = argv[0], argv[1], argv[2]
SAVE = "--save" in argv
R = {"fbx": FBX, "glb": GLB}

ARM = bpy.data.objects["Armature"]
SCENE = bpy.context.scene
LEG_MESHES = [bpy.data.objects[n] for n in ("Body_Legs", "Suit_Legs") if n in bpy.data.objects]

MAP = {  # astronaut bone <- mixamo bone (prefix stripped)
    "Hips": "Hips", "Spine": "Spine1", "Chest": "Spine2", "Neck": "Neck", "Head": "Head",
    "ShoulderL": "LeftShoulder", "UpperArmL": "LeftArm", "LowerArmL": "LeftForeArm", "HandL": "LeftHand",
    "ShoulderR": "RightShoulder", "UpperArmR": "RightArm", "LowerArmR": "RightForeArm", "HandR": "RightHand",
    "UpperLegL": "LeftUpLeg", "LowerLegL": "LeftLeg", "FootL": "LeftFoot", "ToesL": "LeftToeBase",
    "UpperLegR": "RightUpLeg", "LowerLegR": "RightLeg", "FootR": "RightFoot", "ToesR": "RightToeBase",
}

# ---------------------------------------------------------------- import the source
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=FBX)
SRC = [o for o in bpy.data.objects if o not in before and o.type == 'ARMATURE'][0]
prefix = SRC.data.bones[0].name.split(":")[0] + ":" if ":" in SRC.data.bones[0].name else ""
src_action = SRC.animation_data.action
f0, f1 = int(round(src_action.frame_range[0])), int(round(src_action.frame_range[1]))
R["source_frames"] = [f0, f1]

def src_bone(name):
    return SRC.pose.bones[prefix + name]

def rot3(m):
    return m.to_3x3().normalized()

# rest data, world space
src_rest = {t: rot3(SRC.matrix_world @ SRC.data.bones[prefix + s].matrix_local) for t, s in MAP.items()}
tgt_rest = {b.name: b.matrix_local.copy() for b in ARM.data.bones}  # armature object is identity
correction = {}
for t, s in MAP.items():
    sb = SRC.data.bones[prefix + s]
    s_dir = (rot3(SRC.matrix_world) @ (sb.tail_local - sb.head_local)).normalized()
    tb = ARM.data.bones[t]
    t_dir = (tb.tail_local - tb.head_local).normalized()
    q = t_dir.rotation_difference(s_dir).to_matrix()
    # target rest rotation turned to point like the source rest bone
    correction[t] = src_rest[t].inverted() @ q @ rot3(tgt_rest[t])

# ---------------------------------------------------------------- sample the source
frames = list(range(f0, f1 + 1))
# Mixamo cycles repeat the first pose on the last frame; drop it so the loop does not stutter.
SCENE.frame_set(f0); first = {s: rot3(SRC.matrix_world @ src_bone(s).matrix) for s in MAP.values()}
SCENE.frame_set(f1); last = {s: rot3(SRC.matrix_world @ src_bone(s).matrix) for s in MAP.values()}
def _ang(a, b):
    x = a.to_quaternion().rotation_difference(b.to_quaternion()).angle
    return min(x, 6.283185307 - x)
dup = max(_ang(first[s], last[s]) for s in MAP.values())
R["last_frame_vs_first_deg"] = round(dup * 57.2958, 2)
if dup < 0.06:
    frames = frames[:-1]
samples = []
src_legs = []   # per frame, per side: (knee, ankle) relative to the source hips, in source metres
for f in frames:
    SCENE.frame_set(f)
    world = {t: rot3(SRC.matrix_world @ src_bone(s).matrix) for t, s in MAP.items()}
    hips = SRC.matrix_world @ src_bone("Hips").head
    samples.append((world, hips.copy()))
    legs = {}
    for side, s in (("L", "Left"), ("R", "Right")):
        knee = SRC.matrix_world @ src_bone(s + "Leg").head
        ankle = SRC.matrix_world @ src_bone(s + "Foot").head
        legs[side] = (knee - hips, ankle - hips)
    src_legs.append(legs)
SCENE.frame_set(f0)
R["source_left_ankle_x"] = round(src_legs[0]["L"][1].x, 3)  # same sign as the rig's left (+x) means no mirroring

# remove forward drift (root motion) as a straight line across the cycle, keep the small residual surge
n = len(samples)
h0 = samples[0][1]
stride = (samples[-1][1] - h0) * (n / max(n - 1, 1))  # displacement over one full cycle
R["root_motion_per_cycle_m"] = [round(v, 3) for v in stride]
R["source_speed_m_s"] = round(Vector((stride.x, stride.y)).length / (n / SCENE.render.fps), 3)
hip_scale = tgt_rest["Hips"].translation.z / h0.z if h0.z > 0.1 else 1.0

# ---------------------------------------------------------------- write the target action
old = bpy.data.actions.get("walk")
act = bpy.data.actions.new("walk_mixamo")
ARM.animation_data.action = act
for tr in ARM.animation_data.nla_tracks:
    tr.mute = True
order = [b for b in ARM.data.bones]  # data.bones is parent-before-child
for pb in ARM.pose.bones:
    pb.rotation_mode = 'QUATERNION'

# Leg placement. The rig's hip joints sit 0.24 m out from the centre line, much wider than Mixamo's, so copying the
# leg rotations alone hangs the feet about half a metre apart. Instead each ankle goes where the source ankle is
# relative to the source hips (scaled to this rig) and the thigh and shin reach it with two-bone IK, bending the knee
# the way the source knee bends. Feet and toes keep the retargeted rotations.
NARROW = "--wide" not in argv

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

HEAD = {b.name: b.head_local.copy() for b in ARM.data.bones}

def leg_ik(side, hj, hip_pos, legs):
    knee_rel, ankle_rel = legs[side]
    ankle = hip_pos + ankle_rel * hip_scale
    knee_src = hip_pos + knee_rel * hip_scale
    pole = knee_src - (hj + ankle) * 0.5
    l1 = (HEAD["LowerLeg" + side] - HEAD["UpperLeg" + side]).length
    l2 = (HEAD["Foot" + side] - HEAD["LowerLeg" + side]).length
    knee, ankle = two_bone(hj, ankle, l1, l2, pole)
    fwd = Vector((0, -1, 0))
    r_thigh = frame_of(knee - hj, pole) @ frame_of(HEAD["LowerLeg" + side] - HEAD["UpperLeg" + side], fwd).transposed()
    r_shin = frame_of(ankle - knee, pole) @ frame_of(HEAD["Foot" + side] - HEAD["LowerLeg" + side], fwd).transposed()
    return r_thigh @ rot3(tgt_rest["UpperLeg" + side]), r_shin @ rot3(tgt_rest["LowerLeg" + side])

def pose_frame(i, world, hip_pos, legs=None):
    """Sets matrix_basis of every bone from desired world rotations; returns the posed bone matrices."""
    pose_mat = {}
    override = {}
    for b in order:
        pb = ARM.pose.bones[b.name]
        rest = tgt_rest[b.name]
        if b.parent is None:
            parent_pose = Matrix.Identity(4); rel = rest
        else:
            parent_pose = pose_mat[b.parent.name]; rel = tgt_rest[b.parent.name].inverted() @ rest
        inherited = parent_pose @ rel
        if NARROW and legs is not None and b.name in ("UpperLegL", "UpperLegR"):
            side = b.name[-1]
            override["UpperLeg" + side], override["LowerLeg" + side] = leg_ik(side, inherited.translation.copy(), hip_pos, legs)
        if b.name in override:
            r = override[b.name]
            m = Matrix.Translation(inherited.translation) @ r.to_4x4()
        elif b.name in world:
            r = (world[b.name] @ correction[b.name])
            m = Matrix.Translation(inherited.translation) @ r.to_4x4()
        else:
            m = inherited  # HandAnchor*: follows its parent
        if b.parent is None:
            m = Matrix.Translation(hip_pos) @ rot3(m).to_4x4()
        basis = inherited.inverted() @ m
        loc, q, _ = basis.decompose()
        pb.rotation_quaternion = q
        pb.location = loc if b.parent is None else Vector()
        pb.scale = Vector((1, 1, 1))
        pose_mat[b.name] = inherited @ Matrix.Translation(pb.location) @ q.to_matrix().to_4x4()
    return pose_mat

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

# rest-pose floor height
for pb in ARM.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
rest_min = lowest_leg_z()
R["rest_lowest_z"] = round(rest_min, 4)

prev_q = {}
residual_min = []
foot_gap = []
for i, (world, hips) in enumerate(samples):
    frame = i
    drift = h0 + stride * (i / n)
    off = hips - drift
    hip_pos = Vector((off.x * hip_scale, off.y * hip_scale, hips.z * hip_scale))
    pose_frame(i, world, hip_pos, src_legs[i])
    bpy.context.view_layer.update()
    low = lowest_leg_z()
    hip_pos.z += rest_min - low
    pm = pose_frame(i, world, hip_pos, src_legs[i])
    foot_gap.append((pm["FootL"].translation - pm["FootR"].translation).x)
    bpy.context.view_layer.update()
    residual_min.append(lowest_leg_z() - rest_min)
    for pb in ARM.pose.bones:
        q = pb.rotation_quaternion.copy()
        if pb.name in prev_q and prev_q[pb.name].dot(q) < 0:
            q.negate(); pb.rotation_quaternion = q
        prev_q[pb.name] = q.copy()
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if pb.parent is None:
            pb.keyframe_insert("location", frame=frame)
# close the loop: key the first pose again one frame after the end
SCENE.frame_set(0)  # the action now gives the first pose back
for pb in ARM.pose.bones:
    q = pb.rotation_quaternion.copy()
    if pb.name in prev_q and prev_q[pb.name].dot(q) < 0:
        q.negate(); pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion", frame=n)
    if pb.parent is None:
        pb.keyframe_insert("location", frame=n)
R["frames"] = n
R["seconds"] = round(n / SCENE.render.fps, 4)
R["ankle_gap_m"] = [round(min(foot_gap), 3), round(max(foot_gap), 3)]
R["narrow_legs"] = NARROW
R["foot_min_residual_mm"] = [round(min(residual_min) * 1000, 2), round(max(residual_min) * 1000, 2)]

# ---------------------------------------------------------------- swap the clip
ARM.animation_data.action = None
walk_track = next(t for t in ARM.animation_data.nla_tracks if t.name == "walk")
for s in list(walk_track.strips):
    walk_track.strips.remove(s)
if old is not None:
    old.name = "walk_procedural_old"
act.name = "walk"
strip = walk_track.strips.new("walk", 0, act)
strip.frame_end = n
for pb in ARM.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)

# remove the imported source
for o in [o for o in bpy.data.objects if o not in before]:
    bpy.data.objects.remove(o, do_unlink=True)
if old is not None:
    old.use_fake_user = False

# ---------------------------------------------------------------- save + export (same settings as build_character.py)
if SAVE:
    for tr in ARM.animation_data.nla_tracks:
        tr.mute = True
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_mainfile()
for tr in ARM.animation_data.nla_tracks:
    tr.mute = False
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
raw = open(GLB, "rb").read()
size = struct.unpack_from('<I', raw, 12)[0]
gltf = json.loads(raw[20:20 + size])
rows = []
for a in gltf.get('animations', []):
    ins = [gltf['accessors'][s['input']] for s in a['samplers']]
    rows.append({'name': a.get('name'), 'seconds': round(max(i['max'][0] for i in ins) - min(i['min'][0] for i in ins), 4)})
R["glb_animations"] = rows
R["glb_bytes"] = len(raw)
R["saved_blend"] = SAVE
open(REPORT, "w").write(json.dumps(R, indent=1))
