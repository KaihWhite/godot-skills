#!/bin/sh
# Usage: tools/run_smoke.sh <scene_basename>
# Runs res://tests/<scene_basename>.tscn headless. Copy to <project>/tools/.
# A watchdog kills Godot after SMOKE_TIMEOUT seconds (default 300): a script parse
# error means the harness never calls quit(), which would otherwise hang forever.
# The run fails unless the output has "result=PASS" and no "SCRIPT ERROR"
# (a runtime error aborts a _test_* method without failing its checks).
# Only the process this script started is ever killed. If the script is
# interrupted (Ctrl-C, or killed), it stops that process and its watchdog.
GODOT="${GODOT:-godot}"
TIMEOUT="${SMOKE_TIMEOUT:-300}"
cd "$(dirname "$0")/.." || exit 1
log="$(mktemp -t "run_smoke_$1.XXXXXX")"
pid=""
watchdog=""
cleanup() {
	[ -n "$pid" ] && kill "$pid" 2>/dev/null
	[ -n "$watchdog" ] && kill "$watchdog" 2>/dev/null
	rm -f "$log"
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . "res://tests/$1.tscn" >"$log" 2>&1 &
pid=$!
(
	elapsed=0
	while kill -0 "$pid" 2>/dev/null; do
		if grep -q "Parse Error" "$log" 2>/dev/null; then
			sleep 1
			kill "$pid" 2>/dev/null
			echo "[run_smoke] $1 FAIL: parse error (killed early)" >>"$log"
			break
		fi
		if [ "$elapsed" -ge "$TIMEOUT" ]; then
			kill "$pid"
			echo "[run_smoke] $1 TIMED OUT after ${TIMEOUT}s (parse error or hang)" >>"$log"
			break
		fi
		sleep 1
		elapsed=$((elapsed + 1))
	done
) &
watchdog=$!
wait "$pid"
status=$?
wait "$watchdog"
cat "$log"
if [ "$status" -eq 0 ] && grep -q -e "SCRIPT ERROR" -e "Parse Error" "$log"; then
	echo "[run_smoke] $1 FAIL: SCRIPT ERROR in output"
	status=1
fi
if [ "$status" -eq 0 ] && ! grep -q "result=PASS" "$log"; then
	echo "[run_smoke] $1 FAIL: no result=PASS line"
	status=1
fi
rm -f "$log"
exit "$status"
