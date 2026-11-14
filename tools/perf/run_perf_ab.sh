#!/bin/sh
# Perf overhaul A/B benchmark (WINDOWED, needs the GPU; close every other Godot game window first: the Prompt 13
# numbers were spoiled by a hung game instance holding the GPU).
# Runs perf_bench's ten views six times: every perf switch OFF (baseline, = commit d5c8df6), the shipped defaults
# (zones, exterior cull, view gating), and ALL switches on except the warm-up (adds colony LOD, Mars ranges,
# sun/fixture tuning),
# twice in that order. The repeat shows how much the GPU share drifted between runs. Each run starts a fresh colony
# (the bench save folder is cleared) so the sol clock, sun and crew are the same in every run, and the first three
# runs save one still per view for image comparison (tools/perf/compare_shots.py).
#   sh tools/perf/run_perf_ab.sh    -> G:/nasa app/_perf/ab_<n>_<mode>.json + .log + nvidia-smi + shots_<n>_<mode>/
cd "/g/nasa app/mars_colony_godot" || exit 1
G="/c/Users/josev/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
OUT="/g/nasa app/_perf"
SAVES="$APPDATA/Godot/app_userdata/Mars Colony/perf_bench_saves"
mkdir -p "$OUT"
n=0
for mode in off default all off default all; do
  n=$((n + 1))
  flag=""
  [ "$mode" = off ] && flag="--perf-off"
  [ "$mode" = all ] && flag="--perf-on --perf-set=shader_warmup_enabled:false"   # warm-up tour would sit inside the timing
  shots=""
  [ "$n" -le 3 ] && shots="--shots=G:/nasa app/_perf/shots_${n}_${mode}"
  rm -rf "$SAVES"
  nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,memory.total --format=csv > "$OUT/ab_${n}_${mode}.gpu_before.txt" 2>&1
  timeout 600 "$G" --path . --script res://tools/perf/perf_bench.gd -- --quality=2 --cap=0 --seconds=8 $flag \
    "--out=G:/nasa app/_perf/ab_${n}_${mode}.json" ${shots:+"$shots"} > "$OUT/ab_${n}_${mode}.log" 2>&1
  echo "run $n ($mode) exit $? $(date +%T)"
done
