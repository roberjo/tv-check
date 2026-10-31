"""Daily feed canary: fetch every live source Daybreak uses and parse it the
way the TV does, so a broken feed shows up here instead of on the TV.

1. The TV's own sourceUrls() (via test_canary.brs in the emulator) gives the
   request URLs for the fictional family and the default place. The family
   calendar is never fetched.
2. Each URL is fetched (saved to tests/fixtures/live/, gitignored).
3. Every response goes through the TV's ingest() in the emulator (pass 2 of
   test_canary.brs). Game venues: a fixed ZIP (Sanford Stadium, 30602) is
   geocoded and its forecast fetched, so the chain is checked every day,
   not only in game weeks.
4. News: the RSS is parsed and filtered here with a port of filterNews(); a
   feed that doesn't parse or has no items fails.
5. run_live.sh (derive() on the saved feeds) must finish.

Usage: python3 daybreak/tests/feed_canary.py [--report out.md] [--break source]
--break points one source at a bad URL, to prove a failure is reported.
Exits 1 if any source fails. Stdlib only.
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent
DAYBREAK = HERE.parent
ROOT = DAYBREAK.parent
FIX = HERE / "fixtures"
LIVE = FIX / "live"
UA = "Mozilla/5.0 (Daybreak feed canary; +https://github.com/roberjo/tv-check)"
VENUE_ZIP = "30602"
# file names run_live.sh / test_live.brs expect
SINGLE = {"weather": "weather.json", "alerts": "alerts.json", "lake": "lake.json", "lc": "lc.ics"}
TEAM_KEYS = ["georgia", "auburn", "falcons", "hawks", "braves"]  # placeDefaults().teams order


def brs(test, quiet=False):
    lib, comp = DAYBREAK / "channel" / "source" / "lib", DAYBREAK / "channel" / "components"
    files = [lib / "time.brs", lib / "ics.brs", lib / "rules.brs", *sorted((comp / "data").glob("*.brs")), HERE / test]
    r = subprocess.run(["sh", str(HERE / "brs.sh"), str(FIX)] + [str(f) for f in files], capture_output=True, text=True)
    if r.returncode != 0 and not quiet:
        print(r.stdout[-2000:], r.stderr[-2000:])
    return r.returncode, r.stdout


def fetch(url, timeout=25):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except (urllib.error.URLError, OSError) as e:
        return 0, str(e).encode()


def news_filter(items, local, own_source):
    """Port of DataTask.filterNews(): returns the kept {headline, source, violent}."""
    skip = re.compile(r"obituar|funeral|legacy\.com|in memory|passed away|\bobit", re.I)
    social = re.compile(r"instagram|facebook|tiktok|youtube|twitter|nfhs|reddit", re.I)
    noise = re.compile(r"\bvarsity\b.*@|@.*\bvarsity\b|live (&|and) on demand", re.I)
    gentle = re.compile(r"shoot|shot\b|killed|murder|homicide|stabb|deadly|fatal|arrest|incident report|charged with|assault", re.I)
    spam = re.compile(r"live\s*stream|stream(ing)?\s+free|watch\s+(it\s+)?live|on\s+tv\s+channel|\[\S*ream\]|here'?s\*", re.I)
    local_re = re.compile(local, re.I)
    tail = re.compile(r"\s+-\s+[^-]+$")
    seen, out = set(), []
    for title, source in items:
        headline = tail.sub("", title).strip()
        key = headline[:60].lower()
        ok = key not in seen and not skip.search(title + " " + source) and not social.search(source)
        ok = ok and not noise.search(title) and local_re.search(title + " " + source)
        ok = ok and not spam.search(title) and not any(ord(c) > 0x2BFF for c in title)
        if ok and own_source and own_source in source and len(headline.split(" ")) <= 4:
            ok = False
        if ok:
            seen.add(key)
            out.append({"headline": headline, "source": source, "violent": bool(gentle.search(title))})
    return out


def place_news():
    """local regex and ownSource from placeDefaults() in rules.brs."""
    text = (DAYBREAK / "channel" / "source" / "lib" / "rules.brs").read_text()
    local = re.search(r'local:\s*"([^"]+)"', text).group(1)
    own = re.search(r'ownSource:\s*"([^"]+)"', text).group(1)
    return local, own


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--report", type=pathlib.Path)
    ap.add_argument("--break", dest="broken", help="point this source at a bad URL")
    args = ap.parse_args()

    shutil.copy(ROOT / "config" / "family.example.json", FIX / "family.example.json")
    LIVE.mkdir(parents=True, exist_ok=True)
    (LIVE / "canary.json").write_text("{}")
    code, out = brs("test_canary.brs")
    m = re.search(r"^CANARY-URLS (.*)$", out, re.M)
    if code != 0 or not m:
        sys.exit("couldn't get the TV's source URLs from the emulator")
    urls = json.loads(m.group(1))
    urls.pop("calendar", None)  # never the family calendar
    urls.pop("venues", None)
    urls.pop("gamewx", None)
    if args.broken:
        if args.broken not in urls:
            sys.exit(f"--break: no source {args.broken!r} (have {', '.join(sorted(urls))})")
        urls[args.broken] = [re.sub(r"^(https://[^/]+)/", r"\1/daybreak-canary-broken/", u) for u in urls[args.broken]]

    results = {}  # source -> (ok, detail)
    manifest = {}
    for name, lst in urls.items():
        if not lst:
            results[name] = (True, "not requested today (off season or not configured)")
            continue
        files, fails = [], []
        for i, u in enumerate(lst):
            status, body = fetch(u)
            if name in SINGLE:
                fname = SINGLE[name]
            elif name == "sports":
                fname = f"espn_{TEAM_KEYS[i] if i < len(TEAM_KEYS) else i}.json"
            else:
                fname = f"{name}_{i}.txt"
            (LIVE / fname).write_bytes(body if status == 200 else b"")
            files.append(fname)
            if status != 200:
                host = re.sub(r"^https?://([^/]+).*", r"\1", u)
                fails.append(f"HTTP {status or 'error'} from {host}" + (f" ({body.decode(errors='replace')[:80]})" if status == 0 else ""))
        manifest[name] = {"files": files, "urls": lst}
        if fails:
            results[name] = (False, "; ".join(fails))

    # game venues: geocode a fixed ZIP, then its forecast (the TV's own URL shapes)
    geo_url = f"https://geocoding-api.open-meteo.com/v1/search?name={VENUE_ZIP}&count=1&countryCode=US&format=json"
    status, body = fetch(geo_url)
    (LIVE / "venues_0.txt").write_bytes(body if status == 200 else b"")
    manifest["venues"] = {"files": ["venues_0.txt"], "urls": [geo_url]}
    if status != 200:
        results["venues"] = (False, f"HTTP {status} from geocoding-api.open-meteo.com")
    else:
        try:
            r0 = json.loads(body)["results"][0]
            wx_url = (f"https://api.open-meteo.com/v1/forecast?latitude={r0['latitude']}&longitude={r0['longitude']}"
                      "&hourly=temperature_2m,precipitation_probability,weather_code&temperature_unit=fahrenheit"
                      "&timezone=America%2FNew_York&forecast_days=8")
            status, body = fetch(wx_url)
            (LIVE / "gamewx_0.txt").write_bytes(body if status == 200 else b"")
            manifest["gamewx"] = {"files": ["gamewx_0.txt"], "urls": []}  # test_canary.brs keys it by the TV's own gameWxUrl()
            if status != 200:
                results["gamewx"] = (False, f"HTTP {status} from api.open-meteo.com")
        except (ValueError, KeyError, IndexError, TypeError) as e:
            results["venues"] = (False, f"geocoder answer has no result ({type(e).__name__})")

    # news: parse the RSS here (the emulator can't)
    news = manifest.pop("news", None)
    if news and "news" not in results:
        local, own = place_news()
        items, bad = [], []
        for f in news["files"]:
            try:
                root = ET.fromstring((LIVE / f).read_bytes())
                for it in root.iter("item"):
                    items.append(((it.findtext("title") or ""), (it.findtext("source") or "")))
            except ET.ParseError as e:
                bad.append(f"{f}: {e}")
        if bad:
            results["news"] = (False, "RSS doesn't parse: " + "; ".join(bad))
        elif not items:
            results["news"] = (False, "no items in any news feed")
        else:
            kept = news_filter(items, local, own)
            results["news"] = (True, f"{len(items)} items, {len(kept)} kept by the filter")

    # every other source through the TV's parsers
    (LIVE / "canary.json").write_text(json.dumps(manifest))
    code, out = brs("test_canary.brs")
    (LIVE / "canary.json").unlink(missing_ok=True)
    for line in out.splitlines():
        mm = re.match(r"^CANARY (\w+) (ok|fail) ?(.*)$", line)
        if mm and mm.group(1) not in results:
            results[mm.group(1)] = (mm.group(2) == "ok", mm.group(3))
    if code != 0:
        results["parsers"] = (False, "the emulator run stopped early (BrightScript error); see the job log")
    for name in manifest:
        results.setdefault(name, (False, "no result from the emulator"))

    # derive() on the saved feeds
    needed = ["weather.json", "alerts.json", "lake.json", "lc.ics"] + [f"espn_{k}.json" for k in TEAM_KEYS]
    if all((LIVE / f).exists() and (LIVE / f).stat().st_size > 0 for f in needed):
        r = subprocess.run(["sh", str(HERE / "run_live.sh")], capture_output=True, text=True)
        results["derive"] = (r.returncode == 0, "run_live.sh finished" if r.returncode == 0 else "run_live.sh failed: " + r.stdout[-300:])
    else:
        results["derive"] = (False, "skipped: a feed it needs is missing")

    failing = {k: v for k, v in results.items() if not v[0]}
    lines = ["| Source | Result | Detail |", "|---|---|---|"]
    for name in sorted(results):
        ok, detail = results[name]
        lines.append(f"| {name} | {'ok' if ok else '**FAIL**'} | {detail.replace('|', '/')} |")
    table = "\n".join(lines)
    print(table)
    print(f"\nfeed canary: {len(results) - len(failing)}/{len(results)} ok")
    if args.report:
        args.report.write_text(table + "\n")
    sys.exit(1 if failing else 0)


if __name__ == "__main__":
    main()
