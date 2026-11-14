"""Builds the v5 live clips (judge round 1 fixes) on top of the retargeted candidates in crew_v2.blend, then exports
astronaut.glb. Pose-level edits through anim_v5_lib (FK + two-bone leg IK on ankle targets, re-pinned to the floor).

  blender -b --factory-startup --disable-autoexec crew_v2.blend --python run_logged.py -- <log> anim_v5_build.py
          <out.glb> <report.json> [--save] [--render <stills_dir>] [--only walk,sprint,...]

Clips (new actions *_v5, put on the live tracks; every older action and candidate track is kept):
  idle_v5        idle + ~1 cm breathing, +-1.5 cm weight shift, helmet look-arounds; stance narrowed to a 0.20 m gap
  walk_v5        walk (Mixamo) with stride x1.30, ankle gap 0.17, knees forward, toe-out <= 8 deg, softer arms,
                 spine/head posture and secondary motion (pelvis roll, lateral shift, chest yaw, clavicle roll, hip bob,
                 wrist lag, upper-spine lag)
  sprint_v5      sprint_mx_medium with flight phases stretched (17 -> 20 frames), +4 cm hip arc in flight, 8 deg lean,
                 ankle gap 0.15, chest/pelvis/shoulder motion, 90 deg elbows, 13.5 deg abduction, upper-spine lag
  jump_start_v5  jump_start_q frames 1-7, arms up (35 abd / 30 fwd) at the start, head up, tuck halved
  jump_v5        hand-keyed 31-frame non-looping arc driven by the game from vertical velocity: early rise 0-8,
                 f8 == jump_start's last frame (first shown at ~27%), apex float 12-18 (0.5 = ledge walk-off entry),
                 fall/reach 24-26, held 26-30
  land_v5        16 frames (0.5 s): contact 0, lowest 4 (hips 0.86), overshoot 10, idle frame 0 from 12; feet fixed, gap 0.20
Walk legs: stance feet flattened, sat on the floor and foot-locked (ball moves back at WALK_SPEED), trailing heel rises
about the ball when the leg cannot reach, hips follow a bob curve capped by leg reach; swing feet lifted clear.
"""
import bpy, sys, json, os, math
from mathutils import Matrix, Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
GLB, REPORT = argv[0], argv[1]
SAVE = "--save" in argv
RENDER = argv[argv.index("--render") + 1] if "--render" in argv else None
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
HERE = os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", "..", "tools", "blender", "character")
L = {}
exec(compile(open(os.path.normpath(os.path.join(HERE, "anim_v5_lib.py")), encoding="utf-8").read(), "anim_v5_lib.py", "exec"), L)
globals().update({k: v for k, v in L.items() if not k.startswith("__")})

REPORTS = {}
GAP_IDLE = 0.20

def key_frames(name, snaps):
    """Keys a list of basis snapshots into a fresh action called name (replacing an older one of that name)."""
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    set_action(act)
    prev = {}
    for f, snap in enumerate(snaps):
        for pb in ARM.pose.bones:
            q, loc = snap[pb.name]
            q = q.copy()
            if pb.name in prev and prev[pb.name].dot(q) < 0:
                q.negate()
            prev[pb.name] = q.copy()
            pb.rotation_quaternion = q; pb.location = loc
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if pb.parent is None:
                pb.keyframe_insert("location", frame=f)
    set_action(None)
    act.use_fake_user = True
    return act

def solve_pinned(p, knee_forward=0.0, pin=True):
    solve(p, knee_forward)
    if pin:
        dz = floor_gap()
        shift_z(p, dz); solve(p, knee_forward)
    return snapshot()

def gait_phase(poses):
    """phi per frame: cos(phi) ~ how far the left foot is ahead of the right (phi = 0 at left foot forward)."""
    n = len(poses)
    s = [(p.ank["R"].y - p.hip.y) - (p.ank["L"].y - p.hip.y) for p in poses]
    c = sum(s[i] * math.cos(2 * math.pi * i / n) for i in range(n)); d = sum(s[i] * math.sin(2 * math.pi * i / n) for i in range(n))
    phi0 = math.atan2(d, c)
    return [2 * math.pi * i / n - phi0 for i in range(n)]

def ball_pos(p, s):
    return p.ank[s] + p.W["Foot" + s] @ TOE_LOCAL[s]

def lowest_by_side():
    """Lowest leg-mesh point on each side of the body (x > 0 is the left leg)."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    z = {"L": 1e9, "R": 1e9}
    for o in LEG_MESHES:
        e = o.evaluated_get(dg); me = e.to_mesh()
        mw = e.matrix_world
        for v in me.vertices:
            w = mw @ v.co
            s = "L" if w.x > ARM.pose.bones["Hips"].head.x else "R"
            if w.z < z[s]:
                z[s] = w.z
        e.to_mesh_clear()
    return z

HZ = {s: (HEAD["Foot" + s].z, HEAD["Toes" + s].z) for s in SIDES}   # rest heel/ankle and ball heights (flat foot)

def contact_h(p, s):
    """Height of a foot's lower contact point above the floor (ankle/heel or ball, from bones)."""
    return min(p.ank[s].z - HZ[s][0], ball_pos(p, s).z - HZ[s][1])

def flat_foot(p, s):
    """The foot and toe rotations flattened onto the floor, keeping the foot's heading."""
    cur = p.W["Foot" + s] @ TOE_LOCAL[s]
    rest = rot3(REST["Foot" + s]) @ TOE_LOCAL[s]
    yaw = math.atan2(cur.y, cur.x) - math.atan2(rest.y, rest.x)
    R = Matrix.Rotation(yaw, 3, 'Z')
    return R @ rot3(REST["Foot" + s]), R @ rot3(REST["Toes" + s])

def gait_stance(base):
    n = len(base)
    bz = {s: [ball_pos(p, s).z for p in base] for s in SIDES}
    by = {s: [ball_pos(p, s).y for p in base] for s in SIDES}
    return {s: [bz[s][i] < HEAD["Toes" + s].z + 0.04 and by[s][(i + 2) % n] - by[s][(i - 2) % n] > 0 for i in range(n)]
            for s in SIDES}

def runs_of(mask, value=True):
    n = len(mask)
    if all(m == value for m in mask):
        return [list(range(n))]
    start = next(i for i in range(n) if mask[i] == value and mask[i - 1] != value)
    runs = []
    for k in range(n):
        j = (start + k) % n
        if mask[j] == value:
            if runs and (runs[-1][-1] + 1) % n == j:
                runs[-1].append(j)
            else:
                runs.append([j])
    return runs

def trim_stance(stance, max_len):
    """Shortens each stance run to max_len frames (trimming both ends): a faster walk spends less time on each foot."""
    out = {}
    for s, st in stance.items():
        st = list(st)
        for r in runs_of(st):
            extra = len(r) - max_len
            if extra > 0:                           # mostly from toe-off, so touch-down stays where the source has it
                head = extra // 3
                for j in r[:head] + r[len(r) - (extra - head):]:
                    st[j] = False
        out[s] = st
    return out

def plant_walk(poses, base, tag, clearance=0.015, lift=0.05, speed=None, stance=None):
    """Walk feet: stance feet flatten toward the floor through mid-stance, sit on it (bone contact height 0) and their
    ball moves backward at one constant speed per stance; swing feet rise on a sine arc and keep `clearance`."""
    n = len(poses)
    stance = stance or gait_stance(base)
    speeds, info = [], {}
    for s in SIDES:
        st = stance[s]
        info[s] = [len(r) for r in runs_of(st)]
        for r in runs_of(st):
            m = len(r)
            for k, j in enumerate(r):                    # flatten: heel strike -> flat -> heel rising
                w = math.sin(math.pi * (k + 0.5) / m) ** 0.6
                fF, fT = flat_foot(poses[j], s)
                poses[j].W["Foot" + s] = poses[j].W["Foot" + s].to_quaternion().slerp(fF.to_quaternion(), w).to_matrix()
                poses[j].W["Toes" + s] = poses[j].W["Toes" + s].to_quaternion().slerp(fT.to_quaternion(), w).to_matrix()
            ys = [ball_pos(poses[j], s).y for j in r]; xs = [ball_pos(poses[j], s).x for j in r]
            ks = list(range(m)); kb = sum(ks) / m; yb = sum(ys) / m
            slope = sum((k - kb) * (y - yb) for k, y in zip(ks, ys)) / max(1e-9, sum((k - kb) ** 2 for k in ks))
            if speed is not None:
                slope = speed / FPS
            speeds.append(slope * FPS)
            x0 = sum(xs) / m
            for k, j in enumerate(r):
                p = poses[j]
                d = Vector((x0, yb + slope * (k - kb), 0)) - Vector((ball_pos(p, s).x, ball_pos(p, s).y, 0))
                p.ank[s] = p.ank[s] + d; p.knee[s] = p.knee[s] + d
                dz = -contact_h(p, s)                    # sit exactly on the floor
                p.ank[s].z += dz; p.knee[s].z += dz
        for r in runs_of(st, False):
            m = len(r)
            for k, j in enumerate(r):
                p = poses[j]
                h = lift * math.sin(math.pi * (k + 1) / (m + 1))
                p.ank[s].z += h; p.knee[s].z += h
                c = contact_h(p, s)
                if c < clearance:
                    p.ank[s].z += clearance - c; p.knee[s].z += clearance - c
    REPORTS.setdefault(tag, {})["stance_runs_frames"] = info
    REPORTS[tag]["locked_stance_speeds_m_s"] = [round(v, 3) for v in speeds]

def lock_feet(poses, base, tag, swing_lift=0.0, speed=None):
    """Foot locking for a cyclic gait. Stance = frames where a foot's ball is within 12 mm of its lowest and not
    above the other foot's. Over each stance run the ball moves backward at one constant speed (least-squares fit
    to that run) with a constant sideways position; the ankle target follows from the final foot rotation."""
    n = len(poses)
    bz = {s: [ball_pos(p, s).z for p in base] for s in SIDES}
    by = {s: [ball_pos(p, s).y for p in base] for s in SIDES}
    # stance: ball low and travelling backward (+Y) over a +-2 frame window (the source walk wobbles mid-stance)
    stance = {s: [bz[s][i] < HEAD["Toes" + s].z + 0.04 and by[s][(i + 2) % n] - by[s][(i - 2) % n] > 0 for i in range(n)]
              for s in SIDES}
    speeds = []
    info = {}
    for s in SIDES:
        st = stance[s]
        if all(st) or not any(st):
            continue
        start = next(i for i in range(n) if st[i] and not st[i - 1])
        runs, i = [], start
        for k in range(n):
            j = (start + k) % n
            if st[j] and (not runs or not st[(j - 1) % n]):
                runs.append([j])
            elif st[j]:
                runs[-1].append(j)
        info[s] = [len(r) for r in runs]
        for r in runs:
            if len(r) < 2:
                continue
            ys = [ball_pos(poses[j], s).y for j in r]
            xs = [ball_pos(poses[j], s).x for j in r]
            m = len(r); ks = list(range(m))
            kb = sum(ks) / m; yb = sum(ys) / m
            slope = sum((k - kb) * (y - yb) for k, y in zip(ks, ys)) / max(1e-9, sum((k - kb) ** 2 for k in ks))
            if speed is not None:
                slope = speed / FPS
            speeds.append(slope * FPS)
            x0 = sum(xs) / m
            ds = []
            for k, j in enumerate(r):
                cur = ball_pos(poses[j], s)
                ds.append(Vector((x0, yb + slope * (k - kb), cur.z)) - cur)
            # taper the correction into the two swing frames on each side, so lift-off and touch-down do not pop
            extra = [((r[0] - 2) % n, ds[0] / 3), ((r[0] - 1) % n, ds[0] * 2 / 3),
                     ((r[-1] + 1) % n, ds[-1] * 2 / 3), ((r[-1] + 2) % n, ds[-1] / 3)]
            for j, d in list(zip(r, ds)) + [(j, d) for j, d in extra if not st[j]]:
                d = Vector((d.x, d.y, 0.0))
                poses[j].ank[s] = poses[j].ank[s] + d; poses[j].knee[s] = poses[j].knee[s] + d
        # swing clearance: the source walk's swing foot skims the floor (and can dip below the planted one, which the
        # per-frame floor pin then puts on the ground); lift it on a sine arc over each swing run
        if swing_lift > 0:
            sw = [j for j in range(n) if not st[j]]
            runs_sw = []
            for j in sorted(sw, key=lambda j: (j - start) % n):
                if runs_sw and (runs_sw[-1][-1] + 1) % n == j:
                    runs_sw[-1].append(j)
                else:
                    runs_sw.append([j])
            for r in runs_sw:
                m = len(r)
                for k, j in enumerate(r):
                    h = swing_lift * math.sin(math.pi * (k + 1) / (m + 1))
                    poses[j].ank[s] = poses[j].ank[s] + Vector((0, 0, h)); poses[j].knee[s] = poses[j].knee[s] + Vector((0, 0, h))
    REPORTS.setdefault(tag, {})["stance_runs_frames"] = info
    REPORTS[tag]["locked_stance_speeds_m_s"] = [round(v, 3) for v in speeds]

def set_gap(p, mean_x, gap, var):
    for s in SIDES:
        rel = p.ank[s] - p.hip
        nx = SGN[s] * gap / 2 + (rel.x - mean_x[s]) * var
        dx = nx - rel.x
        p.ank[s].x += dx; p.knee[s].x += dx

def arm_secondary(p, phi, abd, elbow_fn, wrist):
    for s in SIDES:
        set_abduction(p, s, abd)
    for s in SIDES:
        a, flex, e = arm_angles(p, s)
        set_elbow(p, s, elbow_fn(s, flex))
    rotate_subtree(p, "HandL", Rx(wrist * math.sin(phi)))
    rotate_subtree(p, "HandR", Rx(-wrist * math.sin(phi)))

# ================================================================== idle
def build_idle():
    src = bpy.data.actions["idle"]
    n = 120
    T = n
    base0 = eval_action(src, 0)
    hipz = base0.hip.z - 0.012          # a little knee slack so the weight shift does not lock the legs
    snaps = []
    for i in range(n):
        p = eval_action(src, i)
        t = i / T
        # stance: ankles fixed at a 0.20 m gap under the hips' rest position, feet flat as in the source idle
        for s in SIDES:
            p.ank[s] = Vector((SGN[s] * GAP_IDLE / 2, base0.ank[s].y, base0.ank[s].z))
            p.knee[s] = Vector((SGN[s] * GAP_IDLE / 2, base0.ank[s].y - 0.15, (base0.ank[s].z + hipz) / 2))
        shift = 0.015 * math.sin(2 * math.pi * t)
        p.hip = Vector((base0.hip.x + shift, base0.hip.y, hipz))
        set_roll(p, "Hips", 1.5 * math.sin(2 * math.pi * t), only=True)
        b = 0.5 - 0.5 * math.cos(4 * math.pi * t)          # two breaths per 4 s loop
        rotate_subtree(p, "Chest", Rx(-1.2 * b))
        rotate_subtree(p, "ShoulderL", Ry(-4.0 * b)); rotate_subtree(p, "ShoulderR", Ry(4.0 * b))
        # helmet look-arounds: left at ~1.1 s, right at ~2.7 s (sin^2 windows, zero at the loop ends)
        def bump(c, w):
            x = (t * 4.0 - c) / w
            return math.cos(x * math.pi / 2) ** 2 if abs(x) < 1 else 0.0
        yaw = 12 * bump(1.1, 0.75) - 9 * bump(2.7, 0.7)
        pitch = -3 * bump(2.7, 0.7) + 2 * bump(1.1, 0.75)
        rotate_subtree(p, "Neck", Rz(yaw * 0.4)); rotate_subtree(p, "Head", Rz(yaw * 0.6) @ Rx(pitch))
        snaps.append(solve_pinned(p, knee_forward=0.8))
    snaps.append(snaps[0])
    return key_frames("idle_v5", snaps), False

# ================================================================== walk
WALK_SPEED = 2.0            # planted-foot speed (m/s at speed 1): the source walk's 1.545 x 1.30 stride
WALK_STANCE_FRAMES = 18     # of 32: the source's 19/17-frame stances, the longer one trimmed so a foot is always down

def build_walk():
    src = bpy.data.actions["walk"]
    n = 32
    base = [eval_action(src, i) for i in range(n)]
    phis = gait_phase(base)
    mean_y = {s: sum((p.ank[s] - p.hip).y for p in base) / n for s in SIDES}
    mean_x = {s: sum((p.ank[s] - p.hip).x for p in base) / n for s in SIDES}
    # toe-out: one constant turn per foot, from its flat-foot frames, so planted feet never twist
    amin = {s: min(p.ank[s].z for p in base) for s in SIDES}
    toe = {s: [foot_out_deg(p, s) for p in base if p.ank[s].z < amin[s] + 0.015] for s in SIDES}
    turn = {s: (3.0 - sum(toe[s]) / len(toe[s])) for s in SIDES}
    REPORTS.setdefault("walk_v5", {})["toe_out_source_deg"] = {s: [round(min(toe[s]), 1), round(max(toe[s]), 1)] for s in SIDES}
    flexmax = max(max(arm_angles(p, s)[1] for s in SIDES) for p in base)
    hip_mean = sum(p.hip.z for p in base) / n
    poses = []
    for i, p0 in enumerate(base):
        p = p0.copy(); phi = phis[i]
        for s in SIDES:                      # stride x1.30 about each foot's mean fore-aft position
            rel = p.ank[s] - p.hip
            dy = (mean_y[s] + (rel.y - mean_y[s]) * 1.30) - rel.y
            p.ank[s].y += dy; p.knee[s].y += dy
        set_gap(p, mean_x, 0.17, 0.2)
        for s in SIDES:
            turn_foot(p, s, turn[s])
        # pelvis: roll toward the swing side, sway over the stance foot, bob (high at mid-stance); feet stay put
        p.hip = Vector((p.hip.x + 0.02 * math.sin(phi), p.hip.y, hip_mean - 0.015 * math.cos(2 * phi)))
        set_roll(p, "Hips", 3.0 * math.sin(phi), only=True)
        rotate_subtree(p, "Spine", Rx(6.0))
        set_yaw(p, "Chest", 6.0 * math.cos(phi))
        rotate_subtree(p, "Chest", Rx(1.5 * math.sin(2 * phi)), only=True)      # upper spine / backpack lag
        rotate_subtree(p, "ShoulderL", Ry(3.0 * math.cos(phi))); rotate_subtree(p, "ShoulderR", Ry(3.0 * math.cos(phi)))
        arm_secondary(p, phi, 11.0, lambda s, flex: 15.0 + 10.0 * max(0.0, flex / flexmax), 8.0)
        rotate_subtree(p, "Head", Rx(-10.0))
        rotate_subtree(p, "Head", Rz(-0.7 * head_yaw_deg(p)))
        poses.append(p)
    stance = trim_stance(gait_stance(base), WALK_STANCE_FRAMES)
    plant_walk(poses, base, "walk_v5", clearance=0.015, lift=0.04, speed=WALK_SPEED, stance=stance)
    # hips: the bob curve, capped so each stance leg reaches its planted foot (a 1.3x stride needs the hips lower at
    # double support); then smoothed around the loop so the cap does not kink
    caps, heel_lift = [], []
    for i, p in enumerate(poses):
        pos = fk_positions(p)
        cap = p.hip.z
        for s in SIDES:
            if not stance[s][i]:
                continue
            off = pos["UpperLeg" + s] - p.hip
            hj = p.hip + off
            reach = (L1[s] + L2[s]) * 0.985
            if (p.ank[s] - hj).length <= reach:
                continue
            if p.ank[s].y > hj.y:
                # trailing foot: raise the heel about the ball of the foot (toes stay flat) until the leg reaches
                b = ball_pos(p, s)
                lo, hi = 0.0, 55.0
                for _ in range(24):
                    mid = (lo + hi) / 2
                    if (b + Rx(mid) @ (p.ank[s] - b) - hj).length > reach:
                        lo = mid
                    else:
                        hi = mid
                R = Rx(hi)
                na = b + R @ (p.ank[s] - b)
                p.knee[s] = p.knee[s] + (na - p.ank[s]); p.ank[s] = na
                p.W["Foot" + s] = R @ p.W["Foot" + s]
                heel_lift.append(round(hi, 1))
            if (p.ank[s] - hj).length > reach:
                # still out of reach (leading foot, or heel lift at its limit): lower the hips just enough
                # leading foot: lower the hips just enough
                hj_xy = Vector((hj.x, hj.y))
                dxy = (Vector((p.ank[s].x, p.ank[s].y)) - hj_xy).length
                cap = min(cap, p.ank[s].z + math.sqrt(max(0.0, reach ** 2 - dxy ** 2)) - off.z)
        caps.append(cap)
    REPORTS["walk_v5"]["heel_lift_deg_max"] = max(heel_lift) if heel_lift else 0.0
    sm = [min(caps[i], (caps[(i - 1) % n] + 2 * caps[i] + caps[(i + 1) % n]) / 4) for i in range(n)]
    snaps, pen = [], []
    for i, p in enumerate(poses):
        p.hip.z = sm[i]
        # mesh contact: the boot's real lowest point, per side, onto the floor (stance) or clear of it (swing)
        for _ in range(3):
            solve(p, 0.7)
            low = lowest_by_side()
            for s in SIDES:
                d = low[s] - REST_MIN
                if stance[s][i]:
                    p.ank[s].z -= d; p.knee[s].z -= d
                elif d < 0.01:
                    p.ank[s].z += 0.01 - d; p.knee[s].z += 0.01 - d
        # a stance foot that still floats is out of the leg's reach: drop the hips by that much
        solve(p, 0.7)
        low = lowest_by_side()
        lift_needed = max([low[s] - REST_MIN for s in SIDES if stance[s][i]] or [0.0])
        if lift_needed > 0.002:
            p.hip.z -= lift_needed
        solve(p, 0.7)
        g = floor_gap()
        if g > 0:                                    # only ever lift out of the floor; never pull feet down
            shift_z(p, g); solve(p, 0.7)
        pen.append(round(g * 1000, 1))
        snaps.append(snapshot())
    REPORTS["walk_v5"]["floor_correction_mm"] = [min(pen), max(pen)]
    REPORTS["walk_v5"]["floor_gap_mm_per_frame"] = pen
    REPORTS["walk_v5"]["stance_mask"] = {s: "".join("S" if x else "." for x in stance[s]) for s in SIDES}
    snaps.append(snaps[0])
    return key_frames("walk_v5", snaps), True

# ================================================================== sprint
SPRINT_SPEED = 4.2          # planted-foot speed (m/s at speed 1): the mean of the two fitted stance speeds (4.03, 4.34)
SPRINT_FLIGHT = {3, 4, 5, 11, 12, 13}   # sprint_mx_medium frames i..i+1 with both feet off the ground in the source

def build_sprint():
    src = bpy.data.actions["sprint_mx_medium"]
    n_src, n_out = 17, 20
    k = (n_out - (n_src - len(SPRINT_FLIGHT))) / len(SPRINT_FLIGHT)
    cum = [0.0]
    for i in range(n_src):
        cum.append(cum[-1] + (k if i in SPRINT_FLIGHT else 1.0))
    times, flight_u = [], []
    for j in range(n_out):
        c = j * cum[-1] / n_out
        i = max(ii for ii in range(n_src) if cum[ii] <= c + 1e-9)
        w = k if i in SPRINT_FLIGHT else 1.0
        times.append(i + (c - cum[i]) / w)
        flight_u.append(i in SPRINT_FLIGHT)
    base = [eval_action(src, t) for t in times]
    phis = gait_phase(base)
    mean_x = {s: sum((p.ank[s] - p.hip).x for p in base) / n_out for s in SIDES}
    lean = sum(trunk_pitch_deg(p) for p in base) / n_out
    REPORTS.setdefault("sprint_v5", {}).update({"source_times": [round(t, 2) for t in times], "flight_stretch": round(k, 3),
                                                 "source_trunk_pitch_mean_deg": round(lean, 1)})
    poses = []
    for j, p0 in enumerate(base):
        p = p0.copy(); phi = phis[j]
        set_gap(p, mean_x, 0.15, 0.45)
        p.hip = p.hip + Vector((0.025 * math.sin(phi), 0, 0))
        set_roll(p, "Hips", 4.0 * math.sin(phi), only=True)
        rotate_subtree(p, "Spine", Rx(8.0 - lean))
        set_yaw(p, "Chest", 10.0 * math.cos(phi))
        rotate_subtree(p, "Chest", Rx(3.0 * math.sin(2 * phi)), only=True)
        rotate_subtree(p, "ShoulderL", Ry(5.0 * math.cos(phi))); rotate_subtree(p, "ShoulderR", Ry(5.0 * math.cos(phi)))
        for s in SIDES:
            set_abduction(p, s, 13.5)
            set_forearm(p, s, 90.0, inward=0.12, up=0.35)
        rotate_subtree(p, "HandL", Rx(6.0 * math.sin(phi))); rotate_subtree(p, "HandR", Rx(-6.0 * math.sin(phi)))
        set_head_pitch(p, 3.0)
        rotate_subtree(p, "Head", Rz(-0.6 * head_yaw_deg(p)))
        poses.append(p)
    lock_feet(poses, base, "sprint_v5", speed=SPRINT_SPEED)
    # stance frames pinned; flight frames ride between the neighbouring stance heights plus a 4 cm arc
    dz = []
    for j, p in enumerate(poses):
        solve(p, 0.5); dz.append(floor_gap())
    runs, j = [], 0
    while j < n_out:
        if flight_u[j]:
            a = j
            while j < n_out and flight_u[j]:
                j += 1
            runs.append((a, j - 1))
        else:
            j += 1
    flight_dz = {}
    for a, b in runs:
        before, after = dz[(a - 1) % n_out], dz[(b + 1) % n_out]
        m = b - a + 2
        for jj in range(a, b + 1):
            u = (jj - a + 1) / m
            flight_dz[jj] = max(dz[jj], before + (after - before) * u + 0.04 * math.sin(math.pi * u))
    snaps = []
    for j, p in enumerate(poses):
        shift_z(p, flight_dz.get(j, dz[j]))
        solve(p, 0.5)
        snaps.append(snapshot())
    snaps.append(snaps[0])
    return key_frames("sprint_v5", snaps), True

# ================================================================== jump start
def rest_ankle_rel(s, gap):
    r = HEAD["Foot" + s] - HEAD["Hips"]
    return Vector((SGN[s] * gap / 2, r.y, r.z))

def build_jump_start(tuck=0.38):
    src = bpy.data.actions["jump_start_q"]
    keys = list(range(1, 8))
    wts = [1.0, 1.0, 0.6, 0.3, 0.1, 0.0, 0.0]
    snaps, poses = [], []
    for j, t in enumerate(keys):
        p = eval_action(src, t)
        for s in SIDES:
            rr = rest_ankle_rel(s, GAP_IDLE)
            rel = p.ank[s] - p.hip
            nrel = rr + (rel - rr) * tuck
            kn = p.knee[s] - p.hip
            p.knee[s] = p.hip + kn * (0.5 + 0.5 * tuck) + Vector((0, -0.05, 0)); p.ank[s] = p.hip + nrel
            p.knee[s].x = p.hip.x + SGN[s] * GAP_IDLE / 2
        if wts[j] > 0:
            C = p.W["Chest"] @ rot3(REST["Chest"]).inverted()
            for s in SIDES:
                a, b = math.radians(35), math.radians(30)
                d = Vector((SGN[s] * math.sin(a), -math.sin(b), -math.sqrt(max(0.0, 1 - math.sin(a) ** 2 - math.sin(b) ** 2))))
                aim_upper_arm(p, s, C @ d, wts[j])
                e = arm_angles(p, s)[2]
                set_forearm(p, s, e + (25.0 - e) * wts[j], inward=0.1, up=0.0)
        set_head_pitch(p, 5.0 + (-6.0 - 5.0) * (j / (len(keys) - 1)))   # up at push-off, level into the float
        solve(p, 0.6)
        g = floor_gap()
        if g > 0:
            shift_z(p, g); solve(p, 0.6)
        snaps.append(snapshot()); poses.append(read_pose())
    return key_frames("jump_start_v5", snaps), False

# ================================================================== jump (non-looping arc)
def build_jump():
    js = bpy.data.actions["jump_start_v5"]
    K0 = eval_action(js, 6)
    jq = bpy.data.actions["jump_q"]
    rest_hip_z = REST["Hips"].translation.z
    def apex(t, abd, flex, roll, lz, rz):
        p = eval_action(jq, t)
        lift = p.hip.z - rest_hip_z
        shift_z(p, -lift)                                  # hip offset 0: no lift over the origin
        for s, z in (("L", lz), ("R", rz)):
            rel = p.ank[s] - p.hip
            p.ank[s] = p.hip + Vector((SGN[s] * GAP_IDLE / 2, rel.y, max(rel.z, z)))
            p.knee[s] = p.hip + Vector((SGN[s] * GAP_IDLE / 2, -0.25, (max(rel.z, z)) * 0.45))
        C = p.W["Chest"] @ rot3(REST["Chest"]).inverted()
        for s in SIDES:
            a, b = math.radians(abd), math.radians(flex)
            d = Vector((SGN[s] * math.sin(a), -math.sin(b), -math.sqrt(max(0.0, 1 - math.sin(a) ** 2 - math.sin(b) ** 2))))
            aim_upper_arm(p, s, C @ d)
            set_elbow(p, s, 30.0)
        set_roll(p, "Chest", roll)
        set_head_pitch(p, -6.0)                           # jump_q looks at its feet; bring the helmet up
        return p
    A1 = apex(0, 44, 8, -2.0, -0.56, -0.62)
    A2 = apex(25, 48, 4, 0.0, -0.54, -0.60)
    A3 = apex(50, 42, 10, 2.0, -0.58, -0.64)
    def fall(abd, flex, bend):
        p = A3.copy()
        reach = (L1["L"] + L2["L"]) * bend
        for s in SIDES:
            hj = HEAD["UpperLeg" + s] - HEAD["Hips"]
            ax = SGN[s] * GAP_IDLE / 2
            dz = -math.sqrt(max(0.0, reach ** 2 - (ax - hj.x) ** 2 - 0.03 ** 2)) + hj.z
            p.ank[s] = p.hip + Vector((ax, -0.03, dz))
            p.knee[s] = p.hip + Vector((ax, -0.12, dz * 0.5))
            p.W["Foot" + s] = rot3(REST["Foot" + s]).copy(); p.W["Toes" + s] = rot3(REST["Toes" + s]).copy()
        C = p.W["Chest"] @ rot3(REST["Chest"]).inverted()
        for s in SIDES:
            a, b = math.radians(abd), math.radians(flex)
            d = Vector((SGN[s] * math.sin(a), -math.sin(b), -math.sqrt(max(0.0, 1 - math.sin(a) ** 2 - math.sin(b) ** 2))))
            aim_upper_arm(p, s, C @ d)
            set_elbow(p, s, 25.0)
        set_roll(p, "Chest", 0.0)
        rotate_subtree(p, "Chest", Rx(6.0))
        set_head_pitch(p, -11.0)
        return p
    F1 = fall(32, 16, 0.97)
    F2 = fall(28, 12, 0.975)
    REPORTS.setdefault("jump_v5", {})["apex_hip_lift_removed_m"] = round(eval_action(jq, 0).hip.z - rest_hip_z, 3)
    # Game timing: t = (v0 - vy) / (2 v0) x length, so after jump_start (~0.2-0.25 s of the rise) the clip is first
    # shown at ~27% (f8): f8 == jump_start's last frame, f0-f8 an earlier rise (jump_start's push-off frame easing
    # into it), apex 0.5 (f15) for ledge walk-offs, fall pose held from 0.85 (f26) because playback stops 0.05 s early.
    R0 = eval_action(js, 2)
    segs = [(0, 8, R0, K0, "ease"), (8, 12, K0, A1, "ease"), (12, 15, A1, A2, "lin"), (15, 18, A2, A3, "lin"),
            (18, 24, A3, F1, "ease"), (24, 26, F1, F2, "ease"), (26, 30, F2, F2, "lin")]
    snaps = []
    for f in range(31):
        for a, b, Pa, Pb, kind in segs:
            if a <= f <= b:
                u = (f - a) / (b - a)
                w = smooth(u) if kind == "ease" else u
                p = lerp_pose(Pa, Pb, w)
                break
        # backpack / upper-spine lag: chest tips forward after take-off, back as the fall starts; zero at f8 and f26+
        if 8 < f < 18:
            lag = 1.5 * math.sin(math.pi * (f - 8) / 10)
        elif 18 <= f < 26:
            lag = -2.0 * math.sin(math.pi * (f - 18) / 8)
        else:
            lag = 0.0
        rotate_subtree(p, "Chest", Rx(lag), only=True)
        solve(p, 0.6)
        snaps.append(snapshot())
    return key_frames("jump_v5", snaps), False

# ================================================================== land
def build_land():
    idle = bpy.data.actions["idle_v5"]
    I0 = eval_action(idle, 0)
    I0snap = snapshot()
    J = eval_action(bpy.data.actions["jump_v5"], 30)
    idle_hip = I0.hip.copy()
    zkeys = [(0, None), (4, 0.86), (8, idle_hip.z - 0.02), (10, idle_hip.z), (12, idle_hip.z)]
    pkeys = [(0, 3.0), (4, 15.0), (8, 4.0), (10, -1.5), (12, 0.0)]
    idle_head = math.degrees(math.asin(max(-1, min(1, forward(I0, "Head").z))))
    def interp(keys, f):
        for (a, va), (b, vb) in zip(keys, keys[1:]):
            if a <= f <= b:
                return va + (vb - va) * smooth((f - a) / (b - a))
        return keys[-1][1]
    # contact height: the fall pose's legs on the floor at the idle foot positions
    c = J.copy()
    for s in SIDES:
        rel = J.ank[s] - J.hip
        c.ank[s] = Vector((I0.ank[s].x, I0.ank[s].y, I0.ank[s].z))
        c.hip = Vector((idle_hip.x, idle_hip.y, I0.ank[s].z - rel.z))
    z0 = c.hip.z
    zkeys[0] = (0, z0)
    snaps = []
    for f in range(16):
        if f >= 12:
            snaps.append(I0snap); continue
        e = smooth(f / 12.0)
        p = lerp_pose(J, I0, e)
        crouch = max(0.0, (idle_hip.z - interp(zkeys, f)) / (idle_hip.z - 0.86))
        p.hip = Vector((idle_hip.x, idle_hip.y + 0.05 * crouch, interp(zkeys, f)))
        for s in SIDES:
            p.ank[s] = I0.ank[s].copy()
            p.knee[s] = Vector((I0.ank[s].x, I0.ank[s].y - 0.2, (p.hip.z + I0.ank[s].z) / 2))
            p.W["Foot" + s] = I0.W["Foot" + s].copy(); p.W["Toes" + s] = I0.W["Toes" + s].copy()
        pitch = interp(pkeys, f)
        rotate_subtree(p, "Spine", Rx(pitch))
        set_head_pitch(p, -6.0 + (idle_head + 6.0) * e)
        solve(p, 0.9)
        snaps.append(snapshot())
    return key_frames("land_v5", snaps), False

# ================================================================== run
BUILD = [("idle", build_idle), ("walk", build_walk), ("sprint", build_sprint), ("jump_start", build_jump_start),
         ("jump", build_jump), ("land", build_land)]
built = {}
for live, fn in BUILD:
    if ONLY and live not in ONLY and f"{live}_v5" not in bpy.data.actions:
        continue
    if ONLY and live not in ONLY:
        built[live] = (bpy.data.actions[f"{live}_v5"], live in ("idle", "walk", "sprint")); continue
    built[live] = fn()

def put_on_track(track_name, act, last):
    track = next((t for t in ARM.animation_data.nla_tracks if t.name == track_name), None)
    if track is None:
        track = ARM.animation_data.nla_tracks.new(); track.name = track_name
    for s in list(track.strips):
        track.strips.remove(s)
    strip = track.strips.new(track_name, 0, act)
    strip.frame_end = max(last, 1)

for live, (act, loop) in built.items():
    last = int(round(act.frame_range[1]))
    put_on_track(live, act, last)
for a in ("idle", "walk", "jump_q", "jump_start_q", "land_q", "sprint_mx_medium"):
    if a in bpy.data.actions:
        bpy.data.actions[a].use_fake_user = True

# ---------------------------------------------------------------- measure
for live, (act, loop) in built.items():
    frames = int(round(act.frame_range[1])) + 1
    R, rows = measure(act, frames, loop)
    R["action"] = act.name
    R.update(REPORTS.get(act.name, {}))
    REPORTS[act.name] = R
set_action(None)
for pb in ARM.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)

# ---------------------------------------------------------------- export (same settings as build_character.py)
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

# ---------------------------------------------------------------- stills
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
    for clip, act, last, nshots in clips:
        set_action(act)
        frames = sorted({round(last * i / (nshots - 1)) for i in range(nshots)})
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
    set_action(None)
    for pb in ARM.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)

if RENDER:
    render_stills(RENDER, [(live, act, int(round(act.frame_range[1])), 8 if live in ("jump", "idle") else 7)
                           for live, (act, loop) in built.items()])

json.dump({"glb": GLB, "clips": REPORTS, "glb_animations": rows, "saved_blend": SAVE,
           "live_tracks": {t.name: t.strips[0].action.name for t in ARM.animation_data.nla_tracks if t.strips}},
          open(REPORT, "w"), indent=1)

if SAVE:
    for tr in ARM.animation_data.nla_tracks:
        tr.mute = True
    set_action(None)
    SCENE.frame_set(0)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_mainfile()

