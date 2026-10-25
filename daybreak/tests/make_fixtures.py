"""Write the synthetic feeds the off-device tests run against.

Every feed Daybreak fetches gets a small, deterministic stand-in shaped like
the real response, built around a fixed "now" (Sunday 2026-10-18 10:00 AM
Eastern). No network, no household data. Output: daybreak/tests/fixtures/feeds/.

Usage: python3 daybreak/tests/make_fixtures.py
"""
import datetime as dt
import json
import math
import pathlib

OUT = pathlib.Path(__file__).resolve().parent / "fixtures" / "feeds"
DAY0 = dt.date(2026, 10, 18)
EDT = dt.timezone(dt.timedelta(hours=-4))


def weather():
    days = [DAY0 + dt.timedelta(days=i) for i in range(8)]
    hi = [67, 70, 64, 55, 61, 66, 69, 71]
    lo = [44, 48, 52, 33, 40, 45, 49, 50]
    rain = [10, 20, 65, 10, 0, 30, 40, 10]
    code = [0, 2, 63, 1, 0, 3, 61, 2]
    sunrise = [f"{d}T07:{46 + i:02d}" for i, d in enumerate(days)]
    sunset = [f"{d}T19:{3 - min(i, 3):02d}" for i, d in enumerate(days)]
    hours, temps, hcode, hrain, cloud = [], [], [], [], []
    for h in range(8 * 24):
        t = dt.datetime.combine(DAY0, dt.time()) + dt.timedelta(hours=h)
        d = h // 24
        swing = (hi[d] - lo[d]) / 2
        temps.append(round(lo[d] + swing + swing * math.sin((t.hour - 9) / 24 * 2 * math.pi), 1))
        hours.append(t.strftime("%Y-%m-%dT%H:%M"))
        hcode.append(code[d])
        hrain.append(rain[d] if 12 <= t.hour <= 20 else max(0, rain[d] - 30))
        cloud.append(15 if code[d] <= 1 else 80)
    return {
        "timezone": "America/New_York",
        "current": {"time": "2026-10-18T10:00", "temperature_2m": 50.2, "weather_code": 0, "wind_speed_10m": 4.6},
        "hourly": {"time": hours, "temperature_2m": temps, "weather_code": hcode,
                   "precipitation_probability": hrain, "cloud_cover": cloud},
        "daily": {"time": [str(d) for d in days], "weather_code": code,
                  "temperature_2m_max": hi, "temperature_2m_min": lo, "sunrise": sunrise, "sunset": sunset,
                  "precipitation_probability_max": rain, "wind_speed_10m_max": [6, 8, 14, 9, 5, 7, 11, 6]},
    }


def team(tid, name):
    return {"id": tid, "displayName": name, "shortDisplayName": name}


def event(date_z, me, other, home, state, mine=None, theirs=None, network="", time_valid=True):
    def comp(t, side, score, won):
        c = {"team": t, "homeAway": side}
        if score is not None:
            c["score"] = {"displayValue": str(score)}
            c["winner"] = won
        return c
    mine_won = mine is not None and mine > theirs
    competition = {
        "competitors": [comp(me, "home" if home else "away", mine, mine_won),
                        comp(other, "away" if home else "home", theirs, not mine_won if mine is not None else None)],
        "status": {"type": {"state": state}},
        "broadcasts": [{"media": {"shortName": network}}] if network else [],
        "timeValid": time_valid,
    }
    return {"date": date_z, "competitions": [competition]}


def espn():
    uga, au = team("61", "Georgia"), team("2", "Auburn")
    return {
        "georgia": {"events": [
            event("2026-10-10T19:30Z", uga, team("333", "Alabama"), True, "post", 24, 21, "CBS"),
            event("2026-10-17T19:30Z", uga, au, False, "post", 27, 20, "ESPN"),
            event("2026-10-31T19:30Z", uga, team("57", "Florida"), False, "pre", network="CBS"),
        ]},
        "auburn": {"events": [
            event("2026-10-10T16:00Z", au, team("145", "Ole Miss"), True, "post", 31, 17, "SECN"),
            event("2026-10-17T19:30Z", au, uga, True, "post", 20, 27, "ESPN"),
            event("2026-10-24T16:00Z", au, team("99", "LSU"), True, "pre", time_valid=False),
        ]},
        "falcons": {"events": [
            event("2026-10-11T17:00Z", team("1", "Falcons"), team("29", "Panthers"), True, "post", 17, 23, "Fox"),
            event("2026-10-18T17:00Z", team("1", "Falcons"), team("3", "Bears"), True, "pre", network="Fox"),
        ]},
        "hawks": {"events": [
            event("2026-10-21T23:30Z", team("1", "Hawks"), team("19", "Magic"), False, "pre", network="FDSSE"),
        ]},
        "braves": {"events": []},
    }


def lc_ics():
    def ev(start_z, summary, desc=""):
        return ("BEGIN:VEVENT\nDTSTART:" + start_z + "\nSUMMARY:" + summary
                + ("\nDESCRIPTION:" + desc if desc else "") + "\nEND:VEVENT")
    return "\n".join([
        "BEGIN:VCALENDAR", "VERSION:2.0",
        ev("20261017T180000Z", "[W] LaGrange College Men's Soccer vs Covenant College",
           "[W] LaGrange College Men's Soccer vs Covenant College\\nW 2-1\\n"),
        ev("20261018T180000Z", "LaGrange College Women's Volleyball vs Piedmont University"),
        ev("20261024T170000Z", "LaGrange College Football at Huntingdon College"),
        ev("20261025T170000Z", "CANCELLED LaGrange College Golf at Berry College"),
        "END:VCALENDAR", ""])


def lake():
    return {"value": {"timeSeries": [{"values": [{"value": [
        {"value": "625.52", "dateTime": "2026-10-18T09:30:00.000-04:00"},
        {"value": "625.48", "dateTime": "2026-10-18T09:45:00.000-04:00"}]}]}]}}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {"weather.json": weather(), "alerts.json": {"features": []},
             "alerts_warning.json": {"features": [{"properties": {"event": "Tornado Warning"}},
                                                  {"properties": {"event": "Flood Watch"}}]},
             "lake.json": lake(), "radar.json": ["2026-10-18T12:20:00.000Z", "2026-10-18T13:10:00.000Z",
                                                  "2026-10-18T13:50:00.000Z"]}
    for key, doc in espn().items():
        files[f"espn_{key}.json"] = doc
    for name, doc in files.items():
        (OUT / name).write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    (OUT / "lc.ics").write_text(lc_ics())
    now = dt.datetime(2026, 10, 18, 10, 0, tzinfo=EDT)
    (OUT / "now.json").write_text(json.dumps({"utc": int(now.timestamp()),
                                              "wall": int(now.replace(tzinfo=dt.timezone.utc).timestamp())}) + "\n")
    print("wrote", len(files) + 2, "files to", OUT)


if __name__ == "__main__":
    main()
