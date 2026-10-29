#!/usr/bin/env bash
# Runs all headless checks (PRD §14.1). Fails on any error or warning output.
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
status=0

echo "== godot --headless --import"
"$GODOT" --headless --import > build/import.log 2>&1 || status=1
if grep -E "ERROR|WARNING|SCRIPT ERROR|Parse Error" build/import.log; then
  echo "import produced errors/warnings"; status=1
fi

echo "== godot --headless -s tests/run_tests.gd"
"$GODOT" --headless -s tests/run_tests.gd > build/tests.log 2>&1
code=$?
grep -E "FAIL|Tests:" build/tests.log
if [ $code -ne 0 ]; then echo "tests exited with $code"; status=1; fi
if grep -E "ERROR|WARNING|SCRIPT ERROR|Parse Error" build/tests.log; then
  echo "tests produced errors/warnings"; status=1
fi

echo "== GDScript warnings-as-errors lint"
"$GODOT" --headless -s tools/lint_warnings.gd 2>/dev/null | grep -v "^Godot Engine" > override.cfg
timeout 120 "$GODOT" --headless -s tools/lint_load_all.gd > build/lint.log 2>&1
lint_code=$?
rm -f override.cfg
grep -E "lint:|LINT FAIL|SCRIPT ERROR|Parse Error|ERROR" build/lint.log | head -40
if [ $lint_code -ne 0 ]; then echo "lint failed"; status=1; fi

echo "== python3 tools/validate_maps.py"
python3 tools/validate_maps.py || status=1

if [ $status -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $status
