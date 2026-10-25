#!/bin/sh
# Renders every Daybreak screen from the TV's own SceneGraph code: the
# BrightScript builds each screen off-device (synthetic feeds, pinned clock),
# dumps the node tree, and render.py draws it with the package's fonts and
# images. Needs a full build first (fonts and images are generated).
# Usage: preview.sh [out-dir] [--audit]
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$DIR/out/preview}
FIXTURES=$DIR/tests/fixtures
cp "$DIR/../config/family.example.json" "$FIXTURES/family.example.json"
L=$DIR/channel/source/lib
C=$DIR/channel/components
DUMP=$(mktemp)
sh "$DIR/tests/brs.sh" "$FIXTURES" "$L/time.brs" "$L/ics.brs" "$L/rules.brs" \
  "$C/DataTask.brs" "$C/ui.brs" "$C/screens.brs" "$C/overlays.brs" \
  "$DIR/tests/assert.brs" "$DIR/tests/harness.brs" "$DIR/preview/preview.brs" > "$DUMP"
shift 2>/dev/null || true
"$DIR/../.venv/bin/python" "$DIR/preview/render.py" "$DUMP" "$OUT" "$@"
rm -f "$DUMP"
