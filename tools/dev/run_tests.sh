#!/usr/bin/env bash
# Runs every tests/*_test.gd headless, each with a time limit so one hung test never blocks the rest.
# bash tools/dev/run_tests.sh [seconds per test, default 300] [name filter]
G="${GODOT:-C:/Users/ChiNoMyA/Downloads/Godot_v4.4.1-stable_win64.exe/Godot_v4.4.1-stable_win64_console.exe}"
LIM="${1:-300}"
cd "$(dirname "$0")/../.."
fails=0
for t in tests/*${2}*_test.gd; do
	s=$(date +%s)
	out=$(timeout -k 5 "$LIM" "$G" --headless --path . -s "$t" 2>&1)
	code=$?
	sec=$(( $(date +%s) - s ))
	if [ $code -eq 124 ] || [ $code -eq 137 ]; then res="TIMEOUT after ${LIM}s"
	else res=$(echo "$out" | grep -E "TEST: |failures: " | tail -1); [ -z "$res" ] && res="INFO (report only, exit $code)"; fi
	case "$res" in *PASS*|*"failures: 0"*|INFO*) ;; *) fails=$((fails+1)); res="$res | $(echo "$out" | grep -m3 -E "FAIL" | tr '\n' ' ')";; esac
	printf '%-28s %4ss  %s\n' "$(basename "$t")" "$sec" "${res:0:220}"
done
echo "== $fails not passing"
