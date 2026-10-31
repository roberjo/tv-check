#!/bin/sh
# Smoke run of derive() on today's live public feeds. Fetch them first with
# tests/fetch_fixtures.sh (saved to the gitignored tests/fixtures/live).
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES=$DIR/tests/fixtures
L=$DIR/channel/source/lib
C=$DIR/channel/components
sh "$DIR/tests/brs.sh" "$FIXTURES" "$L/time.brs" "$L/ics.brs" "$L/rules.brs" \
  "$C"/data/*.brs "$C/ui.brs" "$C"/screens/*.brs "$DIR/tests/test_live.brs"
