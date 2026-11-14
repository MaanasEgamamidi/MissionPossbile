#!/bin/sh
# Runs the four Prompt 13 benchmark passes one after another (windowed). Records GPU load from nvidia-smi before each.
cd "/g/nasa app/_work/p13"
G="/c/Users/josev/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
for run in "high_uncapped 2 0 6" "medium_uncapped 1 0 6" "high_capped 2 60 0" "medium_capped 1 60 0"; do
  set -- $run
  nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,memory.total --format=csv > perf/$1.gpu_before.txt 2>&1
  timeout 400 "$G" --path . --script res://tools/perf/perf_bench.gd -- --quality=$2 --cap=$3 --seconds=5 --switches=$4 "--out=G:/nasa app/_work/p13/perf/$1.json" > perf/$1.log 2>&1
  echo "$1 exit $? $(date +%T)"
done
