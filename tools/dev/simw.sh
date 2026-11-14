#!/bin/bash
# simc.sh <out dir> <runs per class> <difficulty> <class...> - smart bot, classes in parallel, prints the summary
M="${M:-/c/Users/ChiNoMyA/OneDrive/Desktop/Chi/project/Packcraft}"
G="/c/Users/ChiNoMyA/Downloads/Godot_v4.4.1-stable_win64.exe/Godot_v4.4.1-stable_win64_console.exe"
O="$1"; N="$2"; DF="$3"; shift 3; ST=${ST:-pro}; CFG=${CFG:-x:0}; ASC=${ASC:-0}; END=${END:-0}
mkdir -p "$O"; rm -f "$O"/*.out
for c in "$@"; do echo "$c"; done | xargs -P 9 -I{} env ST=$ST bash -c "\"$G\" --headless --path \"$M\" --script res://tests/qa_harness.gd -- --mode=mc --style=$ST --cfg=$CFG --cls={} --diff=$DF --asc=$ASC --endless=$END --start=0 --count=$N 2>&1 | grep '^RUN|' > \"$O/pro_{}.out\""
node "$M/tests/qa_analyze.js" "$O" "$M/data/game_data.json" | sed -n '/Final level/p;/Boss fights/p;/style x class/,/^$/p;/class x path/,/^$/p' | grep -E "smart|pro |/|Final|Boss fights"
