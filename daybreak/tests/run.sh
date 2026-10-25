#!/bin/sh
# Off-device tests for the shared library: curbside, dates, sky, iCal.
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES=${1:-$DIR/tests/fixtures}
L=$DIR/channel/source/lib
sh "$DIR/tests/brs.sh" "$FIXTURES" "$L/time.brs" "$L/ics.brs" "$L/rules.brs" "$DIR/tests/assert.brs" "$DIR/tests/test_lib.brs"
