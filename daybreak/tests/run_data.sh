#!/bin/sh
# Runs DataTask.derive() and builds every screen off-device against saved live feeds
# (fetch them first with tests/fetch_fixtures.sh) plus the synthetic calendar.
DIR=$(cd "$(dirname "$0")/.." && pwd)
FIXTURES=${1:-$DIR/tests/fixtures}
for t in test_data test_screens; do
  npx -y -p @rokucommunity/brs@0.47.6 brs --root "$FIXTURES" \
    "$DIR/channel/source/lib/time.brs" "$DIR/channel/source/lib/ics.brs" "$DIR/channel/source/lib/rules.brs" \
    "$DIR/channel/components/DataTask.brs" "$DIR/channel/components/ui.brs" "$DIR/channel/components/screens.brs" \
    "$DIR/tests/$t.brs" 2>&1 | grep -v 'npm warn'
done
