#!/bin/sh
# Runs headless test suites one after another, each under its folder lock (_locks/test_<suite>), so several workers
# sharing this project never run the same suite at once. Writes one log per suite and a summary.
# Usage: sh tools/run_suites_locked.sh <log_dir> <suite> [<suite> ...]
GODOT="/c/Users/josev/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
LOG_DIR="$1"; shift
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/summary.txt"
: > "$SUMMARY"
for t in "$@"; do
	lock="_locks/test_$t"
	waited=0
	until mkdir "$lock" 2>/dev/null; do
		sleep 15; waited=$((waited + 15))
		if [ "$waited" -ge 1200 ]; then echo "$t LOCK-TIMEOUT" >> "$SUMMARY"; continue 2; fi
	done
	timeout 900 "$GODOT" --headless --path . --script "res://tests/$t.gd" > "$LOG_DIR/$t.log" 2>&1
	code=$?
	rmdir "$lock"
	result=$(grep -E "^RESULT" "$LOG_DIR/$t.log" | tail -1)
	errs=$(grep -cE "SCRIPT ERROR|Parse Error" "$LOG_DIR/$t.log")
	echo "$t exit=$code ${result:-NO-RESULT} script_errors=$errs" >> "$SUMMARY"
done
echo DONE >> "$SUMMARY"
