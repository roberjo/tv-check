"""Builds Daybreak's wallpaper catalog from sources.json.

For each photo in sources.json (a Wikimedia Commons file chosen by hand) this
fetches the license and author from the Commons API, downloads a 1920 or 3840
px rendition, crops it to 1920x1080 and writes:

  img/<id>.jpg     the wallpaper, as the TV downloads it
  catalog.json     what the TV reads: id, file, place, tags, credit, and the
                   screens each photo passed the contrast audit on
  CREDITS.md       title, author, license and source for every photo

Only free licenses are accepted (CC0, public domain, CC BY, CC BY-SA). The
crops are adaptations, so each keeps its original license (BY-SA ones stay
BY-SA). Downloads are cached in daybreak/cache/wallpapers/.

--audit renders every photo behind every screen it could appear on with the
TV's own screen code (daybreak/preview/preview.sh --wallpapers) and records the
screens where every label passes the design audit. Run it after any change to
the photos or to the photo screens' layouts.

Usage:
  .venv/bin/python daybreak/wallpapers/build.py           # fetch, crop, write the catalog
  .venv/bin/python daybreak/wallpapers/build.py --audit   # ...then audit and record screens
"""
import html
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CACHE = ROOT / "daybreak" / "cache" / "wallpapers"
IMG = HERE / "img"
W, H = 1920, 1080
UA = {"User-Agent": "DaybreakWallpaperBuilder/1.0 (https://github.com/roberjo/tv-check)"}
API = "https://commons.wikimedia.org/w/api.php?"
FREE = re.compile(r"^(CC0|Public domain|PD.*|CC BY(-SA)? \d\.\d)$")
# Screens a photo may sit behind (preview/wallpapers.brs builds each one).
SCREENS = ["ambient", "briefing", "season", "tonight", "week", "weekend", "recap", "lake", "school", "board"]


def get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except OSError:
            if i == tries - 1:
                raise
            time.sleep(5 * (i + 1))  # Commons rate-limits bursts
    return b""


def commons_info(title, width):
    q = {"action": "query", "format": "json", "titles": title, "prop": "imageinfo",
         "iiprop": "url|size|extmetadata", "iiurlwidth": str(width),
         "iiextmetadatafilter": "LicenseShortName|Artist|ObjectName"}
    pages = json.loads(get(API + urllib.parse.urlencode(q)))["query"]["pages"]
    page = next(iter(pages.values()))
    if "imageinfo" not in page:
        sys.exit(f"{title}: not found on Commons")
    return page["imageinfo"][0]


def plain(s, limit=48):
    """Commons' HTML author field -> short plain text."""
    s = html.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"^User:| \(talk\)$| at \w+ Wikipedia$", "", s).strip()  # wiki markup, not part of the name
    return s if len(s) <= limit else s[:limit - 1].rstrip() + "…"


def crop(src, focus):
    im = Image.open(src).convert("RGB")
    s = max(W / im.width, H / im.height)
    im = im.resize((round(im.width * s + 0.5), round(im.height * s + 0.5)), Image.LANCZOS)
    left = (im.width - W) // 2
    top = round((im.height - H) * focus)
    return im.crop((left, top, left + W, top + H))


def build():
    sources = json.loads((HERE / "sources.json").read_text())["photos"]
    old = {}
    if (HERE / "catalog.json").exists():
        old = {p["id"]: p for p in json.loads((HERE / "catalog.json").read_text())["photos"]}
    CACHE.mkdir(parents=True, exist_ok=True)
    IMG.mkdir(exist_ok=True)
    photos = []
    for src in sources:
        pid = src["id"]
        if not re.fullmatch(r"[a-z0-9-]{1,40}", pid):
            sys.exit(f"{pid}: ids are lowercase letters, digits and dashes")
        info = commons_info(src["file"], 1920)
        if info["width"] < info["height"] * 1.25:
            sys.exit(f"{pid}: too tall for a 16:9 crop (4:3 is the tallest that works)")
        if info.get("thumbwidth", info["width"]) < W or info.get("thumbheight", info["height"]) < H:
            info = commons_info(src["file"], 3840)  # wide panoramas need a bigger rendition for 1080 px of height
        md = info["extmetadata"]
        lic = md.get("LicenseShortName", {}).get("value", "")
        if not FREE.match(lic):
            sys.exit(f"{pid}: license {lic!r} isn't one Daybreak can use")
        author = plain(md.get("Artist", {}).get("value", "")) or "Unknown"
        cached = CACHE / f"{pid}.jpg"
        if not cached.exists():
            cached.write_bytes(get(info.get("thumburl") or info["url"]))
            time.sleep(1.5)
        out = IMG / f"{pid}.jpg"
        crop(cached, src.get("focus", 0.5)).save(out, quality=75, optimize=True)
        photo = {"id": pid, "file": f"img/{pid}.jpg", "place": src["place"], "area": src["area"], "tags": src["tags"],
                 "seasons": src.get("seasons", ["spring", "summer", "fall", "winter"]),
                 "credit": f"{author} · {lic}", "author": author, "license": lic, "source": info["descriptionurl"],
                 "screens": old.get(pid, {}).get("screens", [])}
        photos.append(photo)
        print(f"{pid}: {lic}, {author}, {out.stat().st_size // 1024} KB")
    for f in IMG.glob("*.jpg"):
        if f.stem not in {p["id"] for p in photos}:
            f.unlink()
    write(photos)


def write(photos):
    catalog = {"v": 1, "about": "Daybreak wallpapers; see CREDITS.md. Built by build.py from sources.json.", "photos": photos}
    (HERE / "catalog.json").write_text(json.dumps(catalog, indent=1, ensure_ascii=False) + "\n")
    lines = ["# Wallpaper credits", "",
             "Photos from Wikimedia Commons, cropped and resized to 1920x1080 for Daybreak by `build.py`.",
             "Each image here keeps its original license; CC BY-SA adaptations are shared under the same license.", "",
             "| Image | Place | Author | License | Source |", "|---|---|---|---|---|"]
    for p in photos:
        lines.append(f"| `{p['file']}` | {p['place']} | {p['author']} | {p['license']} | [Commons]({p['source']}) |")
    (HERE / "CREDITS.md").write_text("\n".join(lines) + "\n")


def audit():
    """Every photo behind every candidate screen; keep the screens with 0 issues."""
    report = ROOT / "daybreak" / "out" / "wallpaper_audit.json"
    subprocess.run(["sh", str(ROOT / "daybreak" / "preview" / "preview.sh"), str(ROOT / "daybreak" / "out" / "wallpapers"),
                    "--wallpapers", str(report)], check=True)
    results = json.loads(report.read_text())
    catalog = json.loads((HERE / "catalog.json").read_text())
    for p in catalog["photos"]:
        r = results.get(p["id"], {})
        p["screens"] = [s for s in SCREENS if s in r and r[s] == 0]
        failed = [f"{s} ({r[s]})" for s in SCREENS if r.get(s, 0) > 0]
        print(f"{p['id']}: {len(p['screens'])} screens" + (f"; fails {', '.join(failed)}" if failed else ""))
    write(catalog["photos"])


if __name__ == "__main__":
    if "--audit-only" not in sys.argv:
        build()
    if "--audit" in sys.argv or "--audit-only" in sys.argv:
        audit()
