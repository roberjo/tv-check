#!/bin/sh
# Runs BrightScript files with @rokucommunity/brs and fails on any failed
# check, runtime error or missing summary. Usage: brs.sh <root> <files...>
ROOT=$1
shift
OUT=$(npx -y -p @rokucommunity/brs@0.47.6 brs --root "$ROOT" "$@" 2>&1 | grep -v 'npm warn')
echo "$OUT"
if echo "$OUT" | grep -q -E '^  FAIL|BRIGHTSCRIPT: ERROR|FAILED \('; then exit 1; fi
echo "$OUT" | grep -q -E 'ALL TESTS PASSED|LIVE SMOKE OK' || { echo "no test summary: the run stopped early"; exit 1; }
