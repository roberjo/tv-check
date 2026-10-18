"""Render Daybreak's local radar: a dark base map of west Georgia plus
transparent NOAA MRMS reflectivity frames, all at 1920x1080 in EPSG:3857.

Sources (all US-government, public domain):
  USGS National Map shaded relief, hydrography, county lines, roads
  NOAA/NCEP MRMS base reflectivity (conus_bref_qcd) via WMS, ~2 min cadence
Labels are not baked in; meta.json gives pixel positions so the TV draws crisp text.

Usage: .venv/bin/python scripts/radar_map.py <outdir> [frames=12] [--base]
  --base  also (re)build base.png (only needed once; the radar frames change)
"""
import io
import json
import math
import pathlib
import re
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageChops

CENTER = (33.0393, -85.0313)  # LaGrange, GA
HALF_WIDTH_KM = 150
W, H = 1920, 1080
UA = {"User-Agent": "tv-check daybreak (personal project)"}

GROUND = (11, 17, 32)
WATER = (36, 66, 104)
COUNTY = (52, 64, 92)
STATE = (72, 84, 112)
ROAD = (70, 82, 110)

PLACES = {
    "LaGrange": (33.0393, -85.0313), "West Point": (32.8779, -85.1833), "Hogansville": (33.1732, -84.9150),
    "Pine Mountain": (32.8646, -84.8541), "Newnan": (33.3807, -84.7997), "Carrollton": (33.5801, -85.0766),
    "Columbus": (32.4610, -84.9877), "Auburn": (32.6099, -85.4808), "Atlanta": (33.7490, -84.3880),
    "West Point Lake": (33.0600, -85.1150),
}


def merc(lat, lon):
    r = 6378137
    return math.radians(lon) * r, math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * r


def bbox():
    x, y = merc(*CENTER)
    hw = HALF_WIDTH_KM * 1000 / math.cos(math.radians(CENTER[0]))
    hh = hw * H / W
    return x - hw, y - hh, x + hw, y + hh


def to_px(lat, lon, b):
    x, y = merc(lat, lon)
    return round((x - b[0]) / (b[2] - b[0]) * W), round((b[3] - y) / (b[3] - b[1]) * H)


def get(url, params):
    with urllib.request.urlopen(urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers=UA), timeout=60) as r:
        return r.read()


def arcgis(service, b, layers=None, extra=None):
    # Fetched at 2x: some layers (NHD waterbodies) only draw at 1:577k or closer, and it anti-aliases lines.
    p = {"bbox": ",".join(f"{v:.0f}" for v in b), "bboxSR": 3857, "imageSR": 3857, "size": f"{2 * W},{2 * H}",
         "format": "png32", "transparent": "true", "f": "image"}
    if layers:
        p["layers"] = f"show:{layers}"
    p.update(extra or {})
    img = Image.open(io.BytesIO(get(f"https://{service}/MapServer/export", p))).convert("RGBA")
    return img.resize((W, H), Image.LANCZOS)


def paint(base, layer, color, strength=1.0):
    """Use a layer's ink (alpha x darkness) as a mask and paint it in our color."""
    a = layer.getchannel("A")
    dark = ImageChops.invert(layer.convert("L"))
    mask = ImageChops.multiply(a, ImageChops.add(dark, Image.new("L", layer.size, 60)))
    mask = mask.point(lambda v: int(min(255, v * strength)))
    base.paste(Image.new("RGB", base.size, color), (0, 0), mask)


def build_base(b, out):
    relief = arcgis("basemap.nationalmap.gov/arcgis/rest/services/USGSShadedReliefOnly", b).convert("L")
    base = Image.merge("RGB", [relief.point(lambda v, g=g: int(g * (0.55 + 0.6 * v / 255))) for g in GROUND])
    # NHD waterbodies (lakes) and wide-river areas only: no creek lines or baked-in labels.
    no_labels = [{"id": i, "source": {"type": "mapLayer", "mapLayerId": i}, "drawingInfo": {"showLabels": False},
                  "definitionExpression": "areasqkm > 0.5"} for i in (10, 7)]
    paint(base, arcgis("hydro.nationalmap.gov/arcgis/rest/services/nhd", b, "10,7",
                       {"dynamicLayers": json.dumps(no_labels)}), WATER, 2.0)
    paint(base, arcgis("carto.nationalmap.gov/arcgis/rest/services/govunits", b, "23"), COUNTY, 0.9)
    paint(base, arcgis("carto.nationalmap.gov/arcgis/rest/services/govunits", b, "22"), STATE, 1.2)
    paint(base, arcgis("carto.nationalmap.gov/arcgis/rest/services/transportation", b, "29"), ROAD, 1.0)
    base.save(out / "base.png", optimize=True)


MRMS = "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows"


def radar_frames(b, out, n):
    caps = get(MRMS, {"service": "WMS", "request": "GetCapabilities"}).decode()
    times = re.search(r'<Dimension name="time"[^>]*>([^<]+)', caps).group(1).split(",")
    picks = times[-1::-5][:n][::-1]  # about every 10 minutes, oldest first
    frames = []
    for t in picks:
        png = get(MRMS, {"service": "WMS", "version": "1.3.0", "request": "GetMap", "layers": "conus_bref_qcd",
                         "crs": "EPSG:3857", "bbox": ",".join(f"{v:.0f}" for v in b), "width": W, "height": H,
                         "format": "image/png", "transparent": "true", "time": t})
        name = "radar_" + re.sub(r"[^0-9T]", "", t)[:13] + ".png"
        (out / name).write_bytes(png)
        img = Image.open(io.BytesIO(png)).convert("RGBA")
        echoes = sum(1 for v in img.getchannel("A").get_flattened_data() if v)
        frames.append({"time": t, "file": name, "echo_pixels": echoes})
    return frames


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    n = int(next((a for a in sys.argv[2:] if a.isdigit()), 12))
    b = bbox()
    if "--base" in sys.argv or not (out / "base.png").exists():
        build_base(b, out)
    frames = radar_frames(b, out, n)
    meta = {"bbox_3857": b, "size": [W, H], "half_width_km": HALF_WIDTH_KM,
            "places": {k: to_px(*v, b) for k, v in PLACES.items()}, "frames": frames}
    (out / "meta.json").write_text(json.dumps(meta, indent=1))
    print(json.dumps({"places": meta["places"], "frames": [(f["time"], f["echo_pixels"]) for f in frames]}, indent=1))
