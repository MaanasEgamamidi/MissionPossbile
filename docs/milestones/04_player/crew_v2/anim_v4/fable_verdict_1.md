# Animation judge verdict, round 1 (Fable)

Inputs: 14 in-game posed sheets (`ingame/`), 3 gameplay sheets plus `_test_saves/diag/judge1/capture_log.txt`, `candidates_report.json`, 11 of 13 Blender sheets. Frame numbers are 30 fps clip frames unless prefixed `play_`.

## Game-side problems
1. Possible clip-start freeze: first two log samples after every clip change read `t=0.00` (~0.13 s apart). `jump_start` (0.267 s) appears never to advance; `play_033`/`053` show the frame-0 crouch in mid-air at y=0.30. Check for play() re-called during transitions or a seek(0) after the blend starts; could be logging lag — confirm before fixing.
2. Crouch plays in the air: launch is instant but `jump_start_mx` f0-f5 is a ground crouch.
3. Air pose is frozen: `jump_mx` is one source frame held 1.2 s; from behind it reads as a stiff A-pose doll.
4. Running landing slides: standing `land` plays at 3.84 m/s; then sprint restarts at scale 0.50 with ground 1.55 m/s (slow motion + foot slide).
5. Sprint clip chosen by key, not speed: sprint at scale 0.50-0.67 while ground speed is 0.3-2.7 m/s.
6. Stop slides: idle at 3.47 m/s.
7. Walk overdriven: suited 2.4 m/s on a 1.545 m/s clip = 1.55x (1.94x unsuited), ~2.9-3.6 steps/s, scurries.
8. Walk and sprint look the same from behind: fore-aft arm swing invisible from rear, almost no roll/sway/backpack motion.
9. Framing: feet cropped at the bottom; walk test area very dark.

## A. Winners
| Slot | Winner | Score | Others |
|---|---|---|---|
| Walk | walk_mixamo (with fixes) | 6 | walk_q 4 (frozen hands, marching, needs 2.4-3x); walk_q_formal 3 (robotic arms) |
| Sprint | sprint_mx_medium (with fixes) | 7 | sprint_q_jog 5 (crouched, 30° lean, wild arms, speed suspect); sprint_mx_standard 5 (hunched, wide); sprint_q 3 |
| Jump start | jump_start_q (trimmed) | 6 | jump_start_mx 3 |
| Jump (air) | none — build (section C) | | jump_q 5 (static, 10 cm pop); jump_mx 4 (one frozen frame) |
| Land | land_q (with fixes) | 6 | land_mx 4 |
No full hybrid; borrow only walk_q's constant 0.18 m ankle gap and slight forward lean.

## B. Fixes
### Walk = walk_mixamo (32 frames; contacts ~f5, f21; passing ~f12, f28)
1. Ankle gap 0.16-0.18 m all frames.
2. Knee poles straight ahead (≤5° out); knee centres ≤0.20 m apart at passing; kneecap over 2nd toe.
3. Toe-out ≤8° per foot.
4. Stride ×1.30 (step ~0.83→1.07 m), keep 1.067 s → clip ground speed ~2.0 m/s (1.2x suited, 1.5x unsuited). Lower hips 1.5-2 cm at contacts if legs hyperextend; re-measure from planted foot.
5. Upper-arm abduction 25° → 10-12°; hand-to-thigh clearance ≥3 cm at passing.
6. Elbows 15° constant flex + 10° extra on forward swing (peaks f5, f21); hand ≤ navel (shoulder flex ≤30°); back swing ≤20°.
7. Spine +6° forward pitch (over 2-3 bones) → net 3-4° forward.
8. Head +10° pitch up; counter-rotate head vs chest yaw at 70%.
9. Secondary: pelvis roll ±3° (drops on swing side), pelvis lateral ±2 cm toward stance foot; chest yaw ±6° opposing pelvis; clavicle roll ±3°; hip bob 3 cm (low at contact, high at passing); wrist lag 2 frames ±8° flop, fingers ~20° curl; backpack/upper-spine pitch lag ±1.5°, 2 frames behind hips.
10. Loop: f31→f0 velocity continuous; stance foot drift ≤5 mm/frame.

### Sprint = sprint_mx_medium
1. Stretch flight phases (both feet >3 cm up) ~40% → 20 frames (0.667 s); keep stance timing. Clip ground speed ~3.95 m/s (0.97x suited, 1.21x unsuited).
2. +4 cm parabolic hip arc in flight (total bob ~13 cm).
3. 8° forward lean; head +6° to keep visor level.
4. Ankle gap 0.12-0.18 m.
5. Chest yaw ±10° opposing pelvis, pelvis roll ±4°, shoulder roll ±5°, lateral hip sway ±2.5 cm.
6. Elbows 85-95°, abduction 12-15°; back-swing elbow ≥3 cm from pack; fist never crosses midline or above chest display.
7. Backpack/upper-spine lag ±3° pitch, 2 frames behind hip vertical velocity; hand relax ±10° at extremes.
8. Hips ≥0.88 m (no jog crouch).

### Jump start = jump_start_q
1. Drop f0 (crouch); keep f1-f7 (~0.2 s).
2. f1-f2 arms up to 35° abduction, 30° forward; head +5°.
3. Halve f6-f7 tuck: thigh ≤45°, knees 60°.
4. Last frame == first frame of new `jump`.
5. Hips at standing height on f1.
6. Game: blend in 0.06-0.08 s; fix the t=0 freeze.

### Land = land_q
1. Crouch depth ×0.5: min hips 0.86 m (was 0.74).
2. Spine pitch ≤20° (was ~45°); head up, visor ahead.
3. Knees over toes; knee gap ≥ ankle gap; ankle gap constant 0.20 m.
4. Both feet IK-pinned all clip (0 mm drift).
5. Timing: contact f0, lowest f4 (0.13 s), overshoot +1.5 cm above idle hips at f10, settle f14; 15 frames (0.5 s), last 4 frames == idle f0.
6. Arms: start in air-pose arms (~30° abd), dip to 15° at f4 with elbows 30°, return to sides; hands never in front of pelvis.
7. Game: if ground speed at touchdown >1.0 m/s, skip `land`, cross-fade 0.15 s into walk/sprint at a contact frame (optional 5 cm procedural hip dip over 0.2 s); don't cut speed after a running landing; land→idle blend 0.2 s; walk input may interrupt after 0.2 s.

### Game side
1. Pick locomotion by ground speed: idle <0.15 m/s, walk to ~3.1 m/s, sprint above; 0.25 s cross-fade or BlendSpace1D (idle 0, walk 2.0, sprint 3.95); sync phase walk↔sprint.
2. Speed clamp 0.5-2.5 → 0.75-1.5; below 0.75x blend toward idle instead.
3. Blends: idle→walk 0.2, walk→sprint 0.25, any→jump_start 0.07, jump_start→jump 0.1, jump→land 0.06, stop→idle 0.2 s.
4. Update clip_ground_speed constants after re-export (walk ~2.0, sprint ~3.95).
5. Third-person camera: boots ~8% above bottom edge; a little fill/rim light on the character in dark areas.

## C. Jump (air): build
31 frames (1.0 s), non-looping, from the jump_q pose, hip offset 0.
- f0 rise (== jump_start last frame): thighs 20°/35° flex, knees 40°, toes pointed 25°; arms 35° abd, 20° fwd, elbows 25°; chest -3°, head +5°.
- f10-f18 apex float: thighs 45°/55°, knees 70°; arms drift to 45° abd, elbows 35°, wrists relaxed; chest 0°; ±2° chest roll, ±3° arm drift (never frozen).
- f24-f30 fall/reach: thighs 15°, knees 20°, ankles dorsiflexed 10° (feet flat), ankle gap 0.20 m; arms 30° abd, 15° fwd; chest +6°, head -5°. Hold f30.
- Hands ≥5 cm from helmet and pack; backpack lag ±2° opposing vertical velocity.
- Drive time from vertical velocity: t = clamp((v0 - vy) / (2*v0), 0, 1) × length, v0 = 1.93 m/s. Ledge walk-off enters at the apex pose; long falls hold the fall pose. Fallback: play once, hold last frame; ledge walk-off seeks 0.5 s with 0.15 s blend.

## D. Top 3
1. Fix the jump chain (t=0 freeze, no airborne crouch, velocity-driven three-pose arc, skip standing land when moving).
2. Rebuild the walk for the real speed (stride ×1.3, arms in with bent swinging elbows, knees forward, ankle gap 0.16-0.18, lean forward, head up).
3. Motion that reads from behind and visible feet (pelvis roll/sway, chest counter-rotation, shoulder roll, bob, backpack lag, relaxed hands; speed-based walk/sprint blend; camera shows boots). Idle: ~1 cm breathing, ±1.5 cm weight shift, small helmet look-arounds.
