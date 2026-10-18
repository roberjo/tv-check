"""Daybreak data sources. Every fetch is cached with a TTL and falls back to the
last good value, so one flaky source never blanks a screen.

All sources are free and keyless: Open-Meteo (weather), NWS (alerts), USGS
(West Point Lake level), NOAA MRMS (radar, via scripts/radar_map.py), ESPN's
public schedule JSON (pro/SEC teams; unofficial), LaGrange College's Sidearm
iCal feed, Google News RSS, the family Google Calendar (secret iCal in .env),
and the City of LaGrange curbside rules (scripts/sanitation.py).
"""
import datetime as dt
import json
import math
import pathlib
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import family_calendar  # noqa: E402
import sanitation  # noqa: E402

TZ = ZoneInfo("America/New_York")
UA = {"User-Agent": "Daybreak home TV dashboard (personal, LaGrange GA)"}
_family = ROOT / "config" / "family.json"
FAMILY = json.loads((_family if _family.exists() else ROOT / "config" / "family.example.json").read_text())
LAT, LON = FAMILY["home"]["lat"], FAMILY["home"]["lon"]
ENV = dict(l.split("=", 1) for l in (ROOT / ".env").read_text().splitlines() if "=" in l and not l.startswith("#"))
GENTLE_NEWS = ENV.get("GENTLE_NEWS", "1") != "0"

_cache = {}
_lock = threading.Lock()


def cached(name, ttl):
    """Cache a zero-arg fetcher for ttl seconds; on failure return the last good value."""
    def wrap(fn):
        def inner():
            with _lock:
                hit = _cache.get(name)
            if hit and time.time() - hit[0] < ttl:
                return hit[1]
            try:
                value = fn()
                with _lock:
                    _cache[name] = (time.time(), value)
                return value
            except Exception as e:  # network or parse failure: keep showing the last good data
                print(f"[sources] {name} failed: {e!r}", file=sys.stderr)
                return hit[1] if hit else None
        return inner
    return wrap


def get(url, timeout=20):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def now():
    return dt.datetime.now(TZ)


# --- weather -----------------------------------------------------------------

WMO = {0: ("Clear", "sun"), 1: ("Mostly clear", "sun"), 2: ("Partly cloudy", "partly"), 3: ("Cloudy", "cloud"),
       45: ("Fog", "cloud"), 48: ("Fog", "cloud"), 51: ("Drizzle", "rain"), 53: ("Drizzle", "rain"),
       55: ("Drizzle", "rain"), 56: ("Freezing drizzle", "rain"), 57: ("Freezing drizzle", "rain"),
       61: ("Light rain", "rain"), 63: ("Rain", "rain"), 65: ("Heavy rain", "rain"), 66: ("Freezing rain", "rain"),
       67: ("Freezing rain", "rain"), 71: ("Light snow", "snow"), 73: ("Snow", "snow"), 75: ("Heavy snow", "snow"),
       77: ("Snow", "snow"), 80: ("Showers", "rain"), 81: ("Showers", "rain"), 82: ("Heavy showers", "rain"),
       85: ("Snow showers", "snow"), 86: ("Snow showers", "snow"), 95: ("Thunderstorms", "storm"),
       96: ("Thunderstorms", "storm"), 99: ("Thunderstorms", "storm")}


def describe(code):
    return WMO.get(int(code), ("—", "cloud"))


@cached("weather", 600)
def weather():
    q = urllib.parse.urlencode({
        "latitude": LAT, "longitude": LON, "timezone": "America/New_York", "forecast_days": 8,
        "temperature_unit": "fahrenheit", "wind_speed_unit": "mph",
        "current": "temperature_2m,weather_code,wind_speed_10m,is_day",
        "hourly": "temperature_2m,weather_code,precipitation_probability,cloud_cover",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max",
    })
    d = json.loads(get("https://api.open-meteo.com/v1/forecast?" + q))
    days = []
    for i, day in enumerate(d["daily"]["time"]):
        days.append({
            "date": dt.date.fromisoformat(day),
            "code": d["daily"]["weather_code"][i],
            "hi": round(d["daily"]["temperature_2m_max"][i]), "lo": round(d["daily"]["temperature_2m_min"][i]),
            "sunrise": dt.datetime.fromisoformat(d["daily"]["sunrise"][i]).replace(tzinfo=TZ),
            "sunset": dt.datetime.fromisoformat(d["daily"]["sunset"][i]).replace(tzinfo=TZ),
            "rain": d["daily"]["precipitation_probability_max"][i] or 0,
            "wind": round(d["daily"]["wind_speed_10m_max"][i]),
        })
    hours = [{"time": dt.datetime.fromisoformat(t).replace(tzinfo=TZ), "temp": round(d["hourly"]["temperature_2m"][i]),
              "code": d["hourly"]["weather_code"][i], "rain": d["hourly"]["precipitation_probability"][i] or 0,
              "cloud": d["hourly"]["cloud_cover"][i]} for i, t in enumerate(d["hourly"]["time"])]
    c = d["current"]
    return {"temp": round(c["temperature_2m"]), "code": c["weather_code"], "wind": round(c["wind_speed_10m"]),
            "days": days, "hours": hours}


# --- alerts --------------------------------------------------------------------

@cached("alerts", 60)
def alerts():
    d = json.loads(get(f"https://api.weather.gov/alerts/active?point={LAT},{LON}"))
    out = []
    for f in d["features"]:
        p = f["properties"]
        level = "warning" if "Warning" in p["event"] else "watch" if "Watch" in p["event"] else "advisory"
        out.append({"event": p["event"], "headline": p.get("headline") or p["event"], "level": level,
                    "ends": p.get("ends") or p.get("expires")})
    return out


# --- West Point Lake -------------------------------------------------------------

SUMMER_POOL, WINTER_POOL = 635.0, 628.0


@cached("lake", 1800)
def lake():
    d = json.loads(get("https://waterservices.usgs.gov/nwis/iv/?format=json&sites=02339400&parameterCd=62614,00062"))
    ts = d["value"]["timeSeries"][0]
    v = ts["values"][0]["value"][-1]
    return {"level": float(v["value"]), "time": dt.datetime.fromisoformat(v["dateTime"]).astimezone(TZ)}


# --- moon and sky ----------------------------------------------------------------

SYNODIC = 29.530588853
NEW_MOON_REF = dt.datetime(2000, 1, 6, 18, 14, tzinfo=dt.timezone.utc)
METEOR_SHOWERS = [("Quadrantids", 1, 3), ("Lyrids", 4, 22), ("Eta Aquariids", 5, 5), ("Perseids", 8, 12),
                  ("Orionids", 10, 21), ("Leonids", 11, 17), ("Geminids", 12, 13)]


def moon(at=None):
    at = at or now()
    age = ((at - NEW_MOON_REF).total_seconds() / 86400) % SYNODIC
    illum = (1 - math.cos(2 * math.pi * age / SYNODIC)) / 2
    waxing = age < SYNODIC / 2
    if age < 1 or age > SYNODIC - 1:
        name = "New moon"
    elif abs(age - SYNODIC / 2) < 1:
        name = "Full moon"
    elif abs(age - SYNODIC / 4) < 1:
        name = "First quarter"
    elif abs(age - 3 * SYNODIC / 4) < 1:
        name = "Last quarter"
    else:
        name = ("Waxing " if waxing else "Waning ") + ("crescent" if illum < 0.5 else "gibbous")
    full_in = ((SYNODIC / 2 - age) % SYNODIC)
    return {"illum": illum, "waxing": waxing, "name": name, "age": age,
            "next_full": (at + dt.timedelta(days=full_in)).date()}


def next_meteor_shower(today=None, within_days=14):
    today = today or now().date()
    for name, m, d in METEOR_SHOWERS:
        for year in (today.year, today.year + 1):
            peak = dt.date(year, m, d)
            if 0 <= (peak - today).days <= within_days:
                return {"name": name, "peak": peak}
    return None


# --- sports ----------------------------------------------------------------------

TEAMS = [
    {"key": "georgia", "name": "Georgia", "short": "UGA", "color": "#BA0C2F", "path": "football/college-football/teams/61"},
    {"key": "auburn", "name": "Auburn", "short": "AU", "color": "#0C2340", "accent": "#E87722", "path": "football/college-football/teams/2"},
    {"key": "falcons", "name": "Falcons", "short": "ATL", "color": "#A71930", "path": "football/nfl/teams/1"},
    {"key": "hawks", "name": "Hawks", "short": "HWK", "color": "#C8102E", "path": "basketball/nba/teams/1"},
    {"key": "braves", "name": "Braves", "short": "ATL", "color": "#13274F", "accent": "#CE1141", "path": "baseball/mlb/teams/15"},
]
ESPN_IDS = {"football/college-football/teams/61": "61", "football/college-football/teams/2": "2",
            "football/nfl/teams/1": "1", "basketball/nba/teams/1": "1", "baseball/mlb/teams/15": "15"}


@cached("sports", 900)
def sports():
    games = []
    for team in TEAMS:
        try:
            d = json.loads(get(f"https://site.api.espn.com/apis/site/v2/sports/{team['path']}/schedule"))
        except Exception as e:
            print(f"[sources] espn {team['key']}: {e!r}", file=sys.stderr)
            continue
        my_id = ESPN_IDS[team["path"]]
        for ev in d.get("events", []):
            comp = ev["competitions"][0]
            mine = next((c for c in comp["competitors"] if c["team"]["id"] == my_id), None)
            other = next((c for c in comp["competitors"] if c["team"]["id"] != my_id), None)
            if not mine or not other:
                continue
            state = comp["status"]["type"]["state"]
            score = lambda c: (c.get("score") or {}).get("displayValue") if isinstance(c.get("score"), dict) else c.get("score")
            games.append({
                "team": team, "start": dt.datetime.fromisoformat(ev["date"].replace("Z", "+00:00")).astimezone(TZ),
                "opponent": other["team"].get("shortDisplayName") or other["team"]["displayName"],
                "home": mine.get("homeAway") == "home", "state": state,
                "tbd": comp.get("timeValid") is False,
                "network": ", ".join(b.get("media", {}).get("shortName", "") for b in comp.get("broadcasts", []) if b.get("media")),
                "my_score": score(mine), "their_score": score(other), "won": mine.get("winner"),
            })
    return sorted(games, key=lambda g: g["start"])


@cached("lagrange_college", 1800)
def lagrange_college():
    text = get("https://lagrangepanthers.com/calendar.ashx/calendar.ics").decode("utf-8", "replace")
    out = []
    for e in family_calendar.events(text):
        summary = e["summary"].replace("LaGrange College ", "").strip()
        if summary.startswith("CANCELLED"):
            continue
        result = re.match(r"\[(W|L|T)\]\s*(.*)", summary)
        desc_score = None
        out.append({"start": e["start"], "title": result.group(2) if result else summary,
                    "result": result.group(1) if result else None, "score": desc_score})
    # Scores live in DESCRIPTION ("W 21-10"); re-scan the raw feed for them.
    for block in re.findall(r"BEGIN:VEVENT(.*?)END:VEVENT", re.sub(r"\r?\n[ \t]", "", text), re.S):
        m = re.search(r"DESCRIPTION:.*?\\n([WLT] \d+-\d+)", block)
        s = re.search(r"SUMMARY:(?:\[[WLT]\]\s*)?(?:LaGrange College )?(.*)", block)
        if m and s:
            for item in out:
                if item["title"] == s.group(1).strip() and item["result"]:
                    item["score"] = m.group(1)[2:].replace("-", "–")
    return out


# --- news ----------------------------------------------------------------------------

NEWS_QUERIES = ['"LaGrange" GA when:2d', '"Troup County" when:3d', '"LaGrange Daily News" when:2d']
SKIP = re.compile(r"obituar|funeral|legacy\.com|in memory|passed away|\bobit", re.I)
SKIP_SOURCES = re.compile(r"instagram|facebook|tiktok|youtube|twitter|^x$|nfhs|reddit", re.I)
# "Gentle news" (default on): the living-room screen skips violent-crime items. Set GENTLE_NEWS=0 in .env to show all.
GENTLE = re.compile(r"shoot|shot\b|killed|murder|homicide|stabb|deadly|fatal|arrest|incident report|charged with|assault", re.I)
SCHEDULE_NOISE = re.compile(r"\bvarsity\b.*@|@.*\bvarsity\b|live (?:&|and) on demand", re.I)
LOCAL = re.compile(r"lagrange|troup|west point|hogansville|callaway|pine mountain", re.I)


@cached("news", 1800)
def news():
    seen, items = set(), []
    for q in NEWS_QUERIES:
        xml = get("https://news.google.com/rss/search?" + urllib.parse.urlencode({"q": q, "hl": "en-US", "gl": "US", "ceid": "US:en"}))
        for item in ET.fromstring(xml).iter("item"):
            title = item.findtext("title") or ""
            source = item.findtext("source") or ""
            headline = re.sub(r"\s+-\s+[^-]+$", "", title).strip()
            key = headline.lower()[:60]
            if (key in seen or SKIP.search(title) or SKIP.search(source) or SKIP_SOURCES.search(source)
                    or SCHEDULE_NOISE.search(title) or not LOCAL.search(title + " " + source)
                    or (GENTLE_NEWS and GENTLE.search(title))):
                continue
            if "LaGrange" in source and len(headline.split()) <= 4:
                continue  # bare names from the paper are almost always obituaries
            seen.add(key)
            pub = item.findtext("pubDate")
            items.append({"headline": headline, "source": source,
                          "time": dt.datetime.strptime(pub, "%a, %d %b %Y %H:%M:%S %Z").replace(tzinfo=dt.timezone.utc) if pub else None})
    items.sort(key=lambda x: x["time"] or dt.datetime.min.replace(tzinfo=dt.timezone.utc), reverse=True)
    return items[:6]


# --- family calendar ----------------------------------------------------------------

HEALTH = re.compile(r"doctor|pediatric|well-?check|dentist|dental|orthodont|flu shot|vaccin|clinic|hospital|"
                    r"therap|physical|appointment|wellstar|medical|urgent care|derm|optom|eye exam", re.I)
SCHOOL = re.compile(r"\bSAT\b|\bACT\b|PSAT|school|exam|report card|early release|band|homecoming|graduation|"
                    r"registration|teacher|class|semester", re.I)


@cached("calendar", 600)
def calendar(days=21):
    items, _ = family_calendar.upcoming(days)
    out = []
    for e in items:
        title = e["summary"]
        health = bool(HEALTH.search(title) or HEALTH.search(e.get("location") or ""))
        who = [m["name"] for m in FAMILY["members"] if re.search(rf"\b{m['name']}\b", title)]
        if re.search(r"\b(both|all) (kids|girls|boys)\b", title, re.I):
            who = [m["name"] for m in FAMILY["members"] if m.get("school")]
        out.append({"when": e["when"], "all_day": not isinstance(e["when"], dt.datetime),
                    "title": "Appointment" if health else re.sub(r"\s*[—-]\s*(both|all) (kids|girls|boys)\s*$", "", title, flags=re.I),
                    "who": who, "health": health, "school": bool(SCHOOL.search(title)) and not health,
                    "deadline": bool(re.search(r"deadline|due|closes", title, re.I))})
    return out


def birthdays(today=None, within=30):
    today = today or now().date()
    out = []
    for m in FAMILY["members"]:
        mo, d = map(int, m["birthday"].split("-"))
        b = dt.date(today.year, mo, d)
        if b < today:
            b = dt.date(today.year + 1, mo, d)
        if (b - today).days <= within:
            out.append({"name": m["name"], "date": b, "days": (b - today).days, "color": m["color"]})
    return sorted(out, key=lambda x: x["days"])


def curbside(today=None):
    return sanitation.next_pickup(today or now().date(), FAMILY["curbside"]["weekday"])


def member(name):
    return next((m for m in FAMILY["members"] if m["name"] == name), None)
