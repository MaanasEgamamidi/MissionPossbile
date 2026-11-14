#!/bin/sh
cd "/g/nasa app/_work/p13"
G="/c/Users/josev/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,memory.total --format=csv > perf/ablation.gpu_before.txt 2>&1
timeout 300 "$G" --path . --script res://tools/perf/perf_ablation.gd -- --views=room_greenhouse,exterior_storm --frames=40 "--out=G:/nasa app/_work/p13/perf/ablation.json" > perf/ablation.log 2>&1
echo "ablation exit $? $(date +%T)"
nvidia-smi --query-gpu=timestamp,utilization.gpu,memory.used,memory.total --format=csv > perf/switch_memory.gpu_before.txt 2>&1
timeout 240 "$G" --path . --script res://tools/perf/perf_switch_memory.gd -- --quality=2 --switches=8 --settle=30 --views=none "--out=G:/nasa app/_work/p13/perf/switch_memory.json" > perf/switch_memory.log 2>&1
echo "switch exit $? $(date +%T)"
