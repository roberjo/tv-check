#!/bin/sh
# derive() and every screen, off-device, against the committed synthetic feeds
# (tests/fixtures/feeds) with the clock pinned. Needs no network.
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES=$DIR/tests/fixtures
cp "$DIR/../config/family.example.json" "$FIXTURES/family.example.json"
L=$DIR/channel/source/lib
C=$DIR/channel/components
for t in test_data test_screens; do
  sh "$DIR/tests/brs.sh" "$FIXTURES" "$L/time.brs" "$L/ics.brs" "$L/rules.brs" \
    "$C/DataTask.brs" "$C/ui.brs" "$C/screens.brs" "$C/overlays.brs" \
    "$DIR/tests/assert.brs" "$DIR/tests/harness.brs" "$DIR/tests/$t.brs"
done
