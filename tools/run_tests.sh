#!/usr/bin/env bash
# Runs every test in tests/ headless, on a throwaway copy of the project.
# The bash twin of tools/run_tests.ps1, for CI (GitHub Actions) and Linux/Mac.
#
#   GODOT=/path/to/godot tools/run_tests.sh            # all tests
#   GODOT=/path/to/godot tools/run_tests.sh naming     # tests whose file name contains "naming"
#
# Exit code = number of failed test files.
set -u
GODOT="${GODOT:-godot}"
ONLY="${1:-}"
TIMEOUT="${TIMEOUT:-180}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/corkcheck"

rm -rf "$TMP"
mkdir -p "$TMP"
for f in "$PROJECT"/* "$PROJECT"/.[!.]*; do
	name="$(basename "$f")"
	if [ "$name" = ".godot" ] || [ "$name" = ".git" ]; then continue; fi
	cp -r "$f" "$TMP/"
done

# Let Godot scan the copy once (builds the class list). --quit-after, not
# --quit: --quit can stop the scan before it writes the class list.
"$GODOT" --headless --xr-mode off --editor --path "$TMP" --quit-after 300 2>&1 | grep -E "SCRIPT ERROR|Parse Error" | head -20

failed=0
for test in "$TMP"/tests/test_*.gd; do
	name="$(basename "$test")"
	case "$name" in *"$ONLY"*) ;; *) continue ;; esac
	echo "=== $name ==="
	out="$TMP/_out_${name%.gd}.txt"
	timeout "$TIMEOUT" "$GODOT" --headless --xr-mode off --path "$TMP" --script "res://tests/$name" > "$out" 2>&1
	code=$?
	grep -E "^FAIL|SCRIPT ERROR|ALL PASSED|FAILED$" "$out"
	if [ $code -eq 124 ]; then
		echo "TIMEOUT after $TIMEOUT s"
		failed=$((failed + 1))
	elif ! grep -q "ALL PASSED" "$out"; then
		echo "(exit code $code)"
		failed=$((failed + 1))
	fi
done

if [ $failed -eq 0 ]; then
	echo "ALL TEST FILES PASSED"
else
	echo "$failed TEST FILE(S) FAILED"
fi
exit $failed
