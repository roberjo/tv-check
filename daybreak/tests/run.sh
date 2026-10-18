#!/bin/sh
# Off-device BrightScript tests for the shared library (curbside, dates, sky, iCal).
# Uses tests/fixtures (synthetic calendar); live feeds are optional (see fetch_fixtures.sh).
DIR=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES=${1:-$DIR/tests/fixtures}
npx -y -p @rokucommunity/brs@0.47.6 brs --root "$FIXTURES" \
  "$DIR/channel/source/lib/time.brs" "$DIR/channel/source/lib/ics.brs" "$DIR/channel/source/lib/rules.brs" \
  "$DIR/tests/test_lib.brs" 2>&1 | grep -v 'npm warn'
