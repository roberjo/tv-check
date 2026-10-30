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


def wallpapers():
    """A small catalog shaped like daybreak/wallpapers/catalog.json, plus entries the TV must reject."""
    every = ["ambient", "briefing", "season", "tonight", "week", "recap", "lake", "school", "board"]
    def photo(pid, place, tags, screens):
        return {"id": pid, "file": f"img/{pid}.jpg", "place": place, "area": place, "tags": tags,
                "credit": "Test Photographer · CC0", "screens": screens}
    return {"v": 1, "photos": [
        photo("lake-one", "Test Lake", ["lake", "nature"], every),
        photo("town-one", "Test Town", ["town"], [s for s in every if s != "ambient"]),
        photo("park-one", "Test Park", ["nature"], every),
        photo("lake-two", "Other Lake", ["lake"], ["lake", "week"]),
        photo("dim-only", "Bright Field", ["nature"], ["week"]),
        photo("night-one", "Night Skyline", ["town", "night"], every),
        dict(photo("spring-one", "Spring Blossoms", ["nature"], every), seasons=["spring"]),
        dict(photo("fall-one", "Fall Color", ["nature"], every), seasons=["fall"]),
        {"id": "../escape", "file": "img/escape.jpg", "screens": every},
        {"id": "bad-file", "file": "../../etc/x.jpg", "screens": every},
        {"id": "no-screens", "file": "img/no-screens.jpg"}]}


def team(tid, name):
    return {"id": tid, "displayName": name, "shortDisplayName": name}


def event(date_z, me, other, home, state, mine=None, theirs=None, network="", time_valid=True, venue=None):
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
    if venue:  # (stadium, city, state, ZIP), as ESPN's schedule gives it
        competition["venue"] = {"fullName": venue[0], "address": {"city": venue[1], "state": venue[2], "zipCode": venue[3], "country": "USA"}}
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
            event("2026-10-24T16:00Z", au, team("99", "LSU"), True, "pre", time_valid=False,
                  venue=("Jordan-Hare Stadium", "Auburn", "AL", "36849")),
        ]},
        "falcons": {"events": [
            event("2026-10-11T17:00Z", team("1", "Falcons"), team("29", "Panthers"), True, "post", 17, 23, "Fox"),
            event("2026-10-18T17:00Z", team("1", "Falcons"), team("3", "Bears"), False, "pre", network="Fox",
                  venue=("Soldier Field", "Chicago", "IL", "60605")),
            event("2026-10-25T17:00Z", team("1", "Falcons"), team("26", "Seahawks"), True, "pre", network="CBS",
                  venue=("Mercedes-Benz Stadium", "Atlanta", "GA", "30313-1591")),
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


def radar_caps():
    """WMS capabilities with MRMS times every 2 minutes for the 3 hours before now."""
    end = dt.datetime(2026, 10, 18, 13, 58, tzinfo=dt.timezone.utc)
    times = [(end - dt.timedelta(minutes=2 * i)).strftime("%Y-%m-%dT%H:%M:%S.000Z") for i in range(90)][::-1]
    return ('<?xml version="1.0"?>\n<WMS_Capabilities><Capability><Layer><Layer><Name>conus_bref_qcd</Name>'
            '<Dimension name="time" default="current" units="ISO8601">' + ",".join(times)
            + "</Dimension></Layer></Layer></Capability></WMS_Capabilities>\n")


def air():
    """US AQI: moderate now, never reaching 101 in the next day."""
    hours = [(dt.datetime.combine(DAY0, dt.time()) + dt.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M") for h in range(48)]
    aqi = [40 + (h % 24) * 2 for h in range(48)]
    return {"current": {"time": "2026-10-18T10:00", "us_aqi": 58, "pm2_5": 12.4}, "hourly": {"time": hours, "us_aqi": aqi}}


def storms():
    """One Atlantic hurricane in the Gulf and one East Pacific storm (ignored)."""
    return {"activeStorms": [
        {"id": "al142026", "binNumber": "AT4", "name": "Nadine", "classification": "HU", "intensity": "85",
         "latitudeNumeric": 25.4, "longitudeNumeric": -88.1},
        {"id": "ep182026", "binNumber": "EP3", "name": "Rosa", "classification": "TS", "intensity": "45",
         "latitudeNumeric": 16.2, "longitudeNumeric": -108.4},
    ]}


def geocode():
    """Open-Meteo's geocoder answering a ZIP search (Soldier Field's)."""
    return {"results": [{"id": 4887398, "name": "Chicago", "latitude": 41.85003, "longitude": -87.65005, "country_code": "US",
                         "admin1": "Illinois", "postcodes": ["60601", "60605", "60607"]}], "generationtime_ms": 0.6}


def game_weather():
    """Hourly forecast at Soldier Field for 8 days: rain likely around the 1 PM kickoff today."""
    hours = [(dt.datetime.combine(DAY0, dt.time()) + dt.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M") for h in range(8 * 24)]
    temp = [round(48 + 6 * math.sin((h % 24 - 9) / 24 * 2 * math.pi), 1) for h in range(8 * 24)]
    rain = [70 if 11 <= h <= 16 else 10 for h in range(8 * 24)]
    code = [61 if 11 <= h <= 16 else 3 for h in range(8 * 24)]
    return {"latitude": 41.85, "longitude": -87.65, "timezone": "America/New_York",
            "hourly": {"time": hours, "temperature_2m": temp, "precipitation_probability": rain, "weather_code": code}}


def espn_live():
    """A Braves game in progress, for the live-score tests."""
    ev = event("2026-10-18T13:20Z", team("15", "Braves"), team("21", "Mets"), True, "in", 4, 2, "TBS")
    ev["competitions"][0]["status"]["type"]["shortDetail"] = "Bot 6th"
    for c in ev["competitions"][0]["competitors"]:
        c.pop("winner", None)
    return {"team": {"logo": "https://a.espncdn.com/i/teamlogos/mlb/500/atl.png"}, "events": [ev]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {"weather.json": weather(), "alerts.json": {"features": []},
             "alerts_warning.json": {"features": [
                 {"properties": {"event": "Tornado Warning", "expires": "2026-10-18T10:45:00-04:00",
                                 "headline": "Tornado Warning issued October 18 at 9:52AM EDT until October 18 at 10:45AM EDT by NWS Peachtree City GA",
                                 "instruction": "TAKE COVER NOW! Move to a basement or an interior room on the lowest floor of a sturdy building.\nAvoid windows."}},
                 {"properties": {"event": "Flood Watch", "expires": "2026-10-19T08:00:00-04:00"}},
                 {"properties": {"event": "Wind Advisory", "expires": "2026-10-18T09:00:00-04:00"}}]},
             "lake.json": lake(), "air.json": air(), "nhc.json": storms(), "espn_live.json": espn_live(),
             "wallpapers.json": wallpapers(), "geo_60605.json": geocode(), "gamewx_60605.json": game_weather()}
    logos = {"georgia": "ncaa/500/61", "auburn": "ncaa/500/2", "falcons": "nfl/500/atl", "hawks": "nba/500/atl", "braves": "mlb/500/atl"}
    for key, doc in espn().items():
        doc["team"] = {"logo": f"https://a.espncdn.com/i/teamlogos/{logos[key]}.png"}  # as ESPN's schedules give it
        files[f"espn_{key}.json"] = doc
    for name, doc in files.items():
        (OUT / name).write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    (OUT / "lc.ics").write_text(lc_ics())
    (OUT / "radar_caps.xml").write_text(radar_caps())
    (OUT / "radar.json").unlink(missing_ok=True)
    now = dt.datetime(2026, 10, 18, 10, 0, tzinfo=EDT)
    (OUT / "now.json").write_text(json.dumps({"utc": int(now.timestamp()),
                                              "wall": int(now.replace(tzinfo=dt.timezone.utc).timestamp())}) + "\n")
    print("wrote", len(files) + 3, "files to", OUT)


if __name__ == "__main__":
    main()
