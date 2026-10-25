#!/bin/sh
# Runs BrightScript files with @rokucommunity/brs and fails on any failed
# check, runtime error or missing summary. Usage: brs.sh <root> <files...>
ROOT=$1
shift
# Wall-clock conversions use the host's zone; pin the household's so results
# don't depend on where the tests run (CI runners are UTC).
export TZ=America/New_York
# the version locked in package-lock.json (npm ci), else the same version via npx
BRS="$(cd "$(dirname "$0")/../.." && pwd)/node_modules/.bin/brs"
if [ -x "$BRS" ]; then
  OUT=$("$BRS" --root "$ROOT" "$@" 2>&1)
else
  OUT=$(npx -y -p @rokucommunity/brs@0.47.6 brs --root "$ROOT" "$@" 2>&1 | grep -v 'npm warn')
fi
echo "$OUT"
if echo "$OUT" | grep -q -E '^  FAIL|BRIGHTSCRIPT: ERROR|FAILED \('; then exit 1; fi
echo "$OUT" | grep -q -E 'ALL TESTS PASSED|LIVE SMOKE OK' || { echo "no test summary: the run stopped early"; exit 1; }
