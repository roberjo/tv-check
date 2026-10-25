"""Per-character advance widths of the bundled fonts, for off-device layout.

The BrightScript emulator can't measure text, so previews would lay text out
with a rough estimate. preview.sh writes this table (per font file, keyed by
code point, in 1/1000 em) and preview.brs hands it to ui.brs's uiWidth.

Usage: font_metrics.py <out.json>
"""
import json
import pathlib
import sys

from PIL import ImageFont

FONTS = pathlib.Path(__file__).resolve().parent.parent / "channel" / "fonts"
CHARS = [chr(c) for c in range(32, 127)] + list("°·–—…“”’éñ✱")

out = {}
for path in sorted(FONTS.glob("*.ttf")):
    f = ImageFont.truetype(str(path), 1000)
    table = {str(ord(ch)): round(f.getlength(ch)) for ch in CHARS}
    table["avg"] = round(sum(table.values()) / len(table))
    out[path.name] = table
pathlib.Path(sys.argv[1]).write_text(json.dumps(out))
print(f"font metrics for {len(out)} fonts")
