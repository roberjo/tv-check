"""Read the family Google Calendar (secret iCal URL in .env as FAMILY_CALENDAR_ICS)
and list upcoming events. Stdlib only; handles all-day and timed events, UTC and
TZID times, simple weekly/daily/monthly/yearly RRULEs with COUNT/UNTIL/BYDAY, and
EXDATE exceptions (single deleted occurrences of a repeating event).

Usage: python3 scripts/family_calendar.py [days=21]
"""
import datetime as dt
import pathlib
import re
import sys
import urllib.request
from zoneinfo import ZoneInfo

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ZoneInfo("America/New_York")
DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def env(key):
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip()
    raise SystemExit(f"{key} not set in .env")


def parse_dt(prop, value):
    if "VALUE=DATE" in prop or re.fullmatch(r"\d{8}", value):
        return dt.datetime.strptime(value, "%Y%m%d").date()
    if value.endswith("Z"):
        return dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc).astimezone(LOCAL)
    tz = re.search(r"TZID=([^;:]+)", prop)
    return dt.datetime.strptime(value, "%Y%m%dT%H%M%S").replace(tzinfo=ZoneInfo(tz.group(1)) if tz else LOCAL).astimezone(LOCAL)


def events(text):
    text = re.sub(r"\r?\n[ \t]", "", text)
    for block in re.findall(r"BEGIN:VEVENT(.*?)END:VEVENT", text, re.S):
        props, exdates = {}, set()
        for line in block.strip().splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                if k.split(";")[0] == "EXDATE":
                    for value in v.split(","):
                        x = parse_dt(k, value.strip())
                        exdates.add(x.date() if isinstance(x, dt.datetime) else x)
                    continue
                props.setdefault(k.split(";")[0], (k, v))
        if "DTSTART" not in props:
            continue
        start = parse_dt(*props["DTSTART"])
        summary = props.get("SUMMARY", ("", "(no title)"))[1].replace("\\,", ",").replace("\\;", ";")
        status = props.get("STATUS", ("", ""))[1]
        yield {"start": start, "summary": summary, "rrule": props.get("RRULE", ("", ""))[1],
               "location": props.get("LOCATION", ("", ""))[1].replace("\\,", ","), "cancelled": status == "CANCELLED",
               "exdates": exdates}


def occurrences(ev, lo, hi):
    start, rule = ev["start"], ev["rrule"]
    as_date = start if isinstance(start, dt.date) and not isinstance(start, dt.datetime) else start.date()
    if not rule:
        if lo <= as_date <= hi:
            yield start
        return
    r = dict(p.split("=", 1) for p in rule.split(";"))
    step = {"DAILY": 1, "WEEKLY": 7}.get(r.get("FREQ"))
    interval = int(r.get("INTERVAL", 1))
    until = parse_dt("", r["UNTIL"]) if "UNTIL" in r else None
    until_d = (until.date() if isinstance(until, dt.datetime) else until) if until else hi
    count = int(r.get("COUNT", 10**6))
    byday = [DAYS.index(d[-2:]) for d in r.get("BYDAY", "").split(",") if d] if r.get("FREQ") == "WEEKLY" else []
    n, d = 0, as_date
    while d <= min(hi, until_d) and n < count:
        if r.get("FREQ") == "WEEKLY" and byday:
            week0 = as_date - dt.timedelta(days=as_date.weekday())
            in_week = ((d - week0).days // 7) % interval == 0
            hit = in_week and d.weekday() in byday
        elif step:
            hit = (d - as_date).days % (step * interval) == 0
        elif r.get("FREQ") == "MONTHLY":
            hit = d.day == as_date.day
        elif r.get("FREQ") == "YEARLY":
            hit = (d.month, d.day) == (as_date.month, as_date.day)
        else:
            hit = d == as_date
        if hit:
            n += 1
            if d >= lo and d not in ev.get("exdates", ()):
                yield start.replace(year=d.year, month=d.month, day=d.day) if isinstance(start, dt.datetime) else d
        d += dt.timedelta(days=1)


def upcoming(days=21, today=None):
    today = today or dt.datetime.now(LOCAL).date()
    hi = today + dt.timedelta(days=days)
    with urllib.request.urlopen(env("FAMILY_CALENDAR_ICS"), timeout=20) as r:
        text = r.read().decode("utf-8", "replace")
    out, total = [], 0
    for ev in events(text):
        total += 1
        if ev["cancelled"]:
            continue
        for when in occurrences(ev, today, hi):
            out.append({**ev, "when": when})
    key = lambda e: (e["when"] if isinstance(e["when"], dt.datetime) else dt.datetime.combine(e["when"], dt.time.min, LOCAL))
    return sorted(out, key=key), total


if __name__ == "__main__":
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 21
    items, total = upcoming(days)
    print(f"{total} events in the calendar; {len(items)} in the next {days} days")
    for e in items:
        w = e["when"]
        when = w.strftime("%a %b %d %I:%M %p") if isinstance(w, dt.datetime) else w.strftime("%a %b %d") + " all day"
        print(f"  {when:24} {e['summary']}" + (f"  @ {e['location']}" if e["location"] else "") + ("  (repeats)" if e["rrule"] else ""))
