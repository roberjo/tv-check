#!/bin/sh
# Renders every Daybreak screen from the TV's own SceneGraph code: the
# BrightScript builds each screen off-device (synthetic feeds, pinned clock),
# dumps the node tree, and render.py draws it with the package's fonts and
# images. Needs a full build first (fonts and images are generated).
# Usage: preview.sh [out-dir] [--audit] [--docs <dir>]
#        preview.sh <out-dir> --wallpapers <report.json>   (see daybreak/wallpapers/build.py)
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$DIR/out/preview}
FIXTURES=$DIR/tests/fixtures
cp "$DIR/../config/family.example.json" "$FIXTURES/family.example.json"
L=$DIR/channel/source/lib
C=$DIR/channel/components
"$DIR/../.venv/bin/python" "$DIR/preview/font_metrics.py" "$FIXTURES/font_metrics.json"
DRIVER=$DIR/preview/preview.brs
cp "$DIR/wallpapers/catalog.json" "$FIXTURES/wallpaper_catalog.json"
[ $# -gt 0 ] && shift  # drop out-dir; the rest goes to render.py
if [ "$1" = "--wallpapers" ]; then
  # every catalog photo behind every screen it could appear on; $2 = JSON report
  DRIVER=$DIR/preview/wallpapers.brs
  set -- --wallpaper-report "$2"
fi
DUMP=$(mktemp)
sh "$DIR/tests/brs.sh" "$FIXTURES" "$L/time.brs" "$L/ics.brs" "$L/rules.brs" \
  "$C/DataTask.brs" "$C/ui.brs" "$C/screens.brs" "$C/overlays.brs" \
  "$DIR/tests/assert.brs" "$DIR/tests/harness.brs" "$DIR/preview/dump.brs" "$DRIVER" > "$DUMP"
"$DIR/../.venv/bin/python" "$DIR/preview/render.py" "$DUMP" "$OUT" "$@"
rm -f "$DUMP"
