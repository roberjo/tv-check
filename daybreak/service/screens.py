"""Daybreak screens, rendered on the Mac as 1920x1080 JPEGs.

Each render_* function takes the gathered data and returns (Screen, meta). meta
carries the clock box the TV draws on top (so the time is always exact) and an
optional OK-button action. Rule-based "heads up" insights replace Claude.
"""
import datetime as dt
import json
import pathlib

from PIL import Image

import draw as D
import sources as S

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FAMILY = S.FAMILY
DEFAULT_APPS = ["Netflix", "YouTube", "Prime Video", "Disney+", "Hulu", "Max"]


# --- helpers ---------------------------------------------------------------------

def gather():
    return {"now": S.now(), "weather": S.weather(), "alerts": S.alerts() or [], "lake": S.lake(),
            "moon": S.moon(), "shower": S.next_meteor_shower(), "sports": S.sports() or [],
            "lc": S.lagrange_college() or [], "news": S.news() or [], "calendar": S.calendar() or [],
            "birthdays": S.birthdays(within=30), "curb": S.curbside()}


def day_word(d, today):
    d = d.date() if isinstance(d, dt.datetime) else d
    n = (d - today).days
    if n == 0:
        return "Today"
    if n == 1:
        return "Tomorrow"
    if n == -1:
        return "Yesterday"
    if 1 < n < 7:
        return d.strftime("%A")
    return d.strftime("%a %b %-d")


def clock(t):
    return t.strftime("%-I:%M %p")


def as_dt(w):
    return w if isinstance(w, dt.datetime) else dt.datetime.combine(w, dt.time(0), S.TZ)


def upcoming_games(data, days=7, include_lc=True):
    now = data["now"]
    out = []
    for g in data["sports"]:
        if g["state"] == "in" or (g["state"] == "pre" and now - dt.timedelta(hours=3) <= g["start"] <= now + dt.timedelta(days=days)):
            out.append({"name": g["team"]["name"], "short": g["team"]["short"], "color": g["team"]["color"],
                        "accent": g["team"].get("accent"), "start": g["start"], "state": g["state"],
                        "detail": ("vs " if g["home"] else "at ") + g["opponent"], "network": g["network"], "game": g})
    if include_lc:
        for e in data["lc"]:
            start = e["start"] if isinstance(e["start"], dt.datetime) else None
            if not start or e["result"] or not (now <= start <= now + dt.timedelta(days=days)):
                continue
            home = " vs " in f" {e['title']} "
            if "Football" in e["title"] or (home and start.date() == now.date()):
                sport, _, rest = e["title"].partition(" vs ") if home else e["title"].partition(" at ")
                out.append({"name": "Panthers " + sport.lower().replace("women's ", "women's ").strip(), "short": "LC",
                            "color": "#8E1B24", "start": start, "state": "pre",
                            "detail": ("vs " if home else "at ") + rest.split(" - ")[0].replace(" College", "").replace(" University", ""),
                            "network": "", "game": None})
    return sorted(out, key=lambda g: g["start"])


def finals(data, hours=36):
    now = data["now"]
    out = []
    for g in data["sports"]:
        if g["state"] == "post" and now - dt.timedelta(hours=hours) <= g["start"] <= now:
            out.append({"team": g["team"]["name"], "color": g["team"]["color"], "won": g["won"],
                        "score": f"{g['my_score']}–{g['their_score']}", "detail": ("vs " if g["home"] else "at ") + g["opponent"],
                        "start": g["start"], "pro": True, "game": g})
    for e in data["lc"]:
        start = as_dt(e["start"])
        if e["result"] and e["score"] and now - dt.timedelta(hours=hours) <= start <= now:
            out.append({"team": "Panthers", "color": "#8E1B24", "won": e["result"] == "W", "score": e["score"],
                        "detail": e["title"].replace(" College", "").replace(" University", "").replace(" (Ga.)", ""),
                        "start": start, "pro": False, "game": None})
    return sorted(out, key=lambda f: f["start"], reverse=True)


def season_record(data, key):
    w = l = 0
    for g in data["sports"]:
        if g["team"]["key"] == key and g["state"] == "post" and g["won"] is not None:
            w, l = (w + 1, l) if g["won"] else (w, l + 1)
    return w, l


def heads_up(data, limit=3):
    """Rule-based insights, most important first."""
    now, today = data["now"], data["now"].date()
    out = []
    for a in data["alerts"]:
        out.append((0 if a["level"] == "warning" else 1, f"{a['event']} for Troup County."))
    c = data["curb"]
    pickup = dt.date.fromisoformat(c["date"])
    if 0 <= (pickup - today).days <= 1 or (now.weekday() == 6 and (pickup - today).days <= 2):
        extra = "yard waste (no grass clippings)" if c["extra"]["kind"] == "yard" else "bulky trash"
        moved = f" (moved for {c['holiday']})" if c["holiday"] else ""
        out.append((2, f"{day_word(pickup, today)}{moved}: garbage plus {extra}. Curb by 7 AM."))
    for e in data["calendar"]:
        d = as_dt(e["when"]).date()
        if e["deadline"] and 0 <= (d - today).days <= 7:
            main, sub = split_title(e["title"])
            who = " and ".join(who_of(e))
            out.append((3, f"{main} is {day_word(d, today).replace('Today', 'today').replace('Tomorrow', 'tomorrow')}"
                           + (f" ({sub})" if sub else "") + (f" for {who}" if who else "") + "."))
    timed = [e for e in data["calendar"] if not e["all_day"]]
    for i, a in enumerate(timed):
        for b in timed[i + 1:]:
            if a["when"].date() == b["when"].date() and abs((a["when"] - b["when"]).total_seconds()) < 5400 and (a["when"].date() - today).days <= 7:
                out.append((4, f"{day_word(a['when'], today)}: {a['title']} and {b['title']} overlap."))
    for day in data["weather"]["days"][1:4]:
        if day["rain"] >= 60:
            out.append((5, f"Rain likely {day_word(day['date'], today)} ({day['rain']}%)."))
        if day["lo"] <= 34:
            out.append((5, f"Frost possible {day_word(day['date'], today)} morning ({day['lo']}°). Cover tender plants."))
    for b in data["birthdays"]:
        if b["days"] <= 14:
            out.append((6, f"{b['name']}'s birthday is {day_word(b['date'], today)}."))
    s = data["shower"]
    if s and (s["peak"] - today).days <= 4:
        out.append((7, f"The {s['name']} meteor shower peaks {day_word(s['peak'], today)} night. Best before dawn."))
    if data["lake"] and data["lake"]["level"] < S.WINTER_POOL - 2:
        out.append((8, f"West Point Lake is low at {data['lake']['level']:.1f} ft. Check ramps before launching."))
    return [t for _, t in sorted(out)[:limit]]


def split_title(t):
    """'SAT registration deadline — Nov 7 test' -> ('SAT registration deadline', 'Nov 7 test')."""
    for sep in (" — ", " – ", " - "):
        if sep in t:
            a, b = t.split(sep, 1)
            return a.strip(), b.strip()
    return t, ""


def who_of(e):
    if e["who"]:
        return e["who"]
    return [m["name"] for m in FAMILY["members"] if m.get("school")] if e["school"] else []


def fans_of(team):
    return " & ".join(m["name"] for m in FAMILY["members"] if m.get("allegiance") == team) or f"{team} fans"


def greeting(now):
    h = now.hour
    part = "morning" if 4 <= h < 12 else "afternoon" if h < 17 else "evening"
    return f"Good {part}, {FAMILY['household']}"


def header(sc, eyebrow, title, accent=D.AMBER, clock_box=True):
    sc.label(D.MARGIN_X, 70, eyebrow, 24, accent)
    size = sc.fit(title, 76, 1200 if clock_box else 1696, 500, "Outfit")
    sc.text(D.MARGIN_X, 112, title, size, 500, D.TEXT, "Outfit")
    return {"x": 1808, "y": 78, "size": 104, "weight": 300, "align": "right", "color": "#F4F1EA"} if clock_box else None


def team_chip(sc, x, y, s, short, color, accent=None):
    sc.d.rounded_rectangle((x, y, x + s, y + s), int(s * 0.26), fill=D.hexrgb(color),
                           outline=D.hexrgb(accent) if accent else None, width=3 if accent else 0)
    size = sc.fit(short, int(s * 0.36), s - 8, 600, "Outfit", 12)
    sc.text(x + s / 2, y + s / 2, short, size, 600, D.TEXT, "Outfit", anchor="mm")


# --- screens -------------------------------------------------------------------------

def render_ambient(data):
    now, w = data["now"], data["weather"]
    today_w = w["days"][0]
    sc = D.Screen(D.INK_DEEP)
    sc.photo("callaway_pool.jpg", 0.55, D.INK_DEEP)
    shadow = lambda x, y, s, size, weight=400, fill=D.TEXT, fam="Manrope", anchor="la": (
        sc.text(x + 2, y + 3, s, size, weight, (0, 0, 0, 90), fam, anchor), sc.text(x, y, s, size, weight, fill, fam, anchor))
    shadow(160, 410, now.strftime("%A, %B %-d"), 38, 500, D.TEXT_2_ON_PHOTO)
    label, kind = S.describe(w["code"])
    sc.icon(kind if now.hour < 19 or kind != "sun" else "moon", 1530, 190, 70, D.AMBER)
    shadow(1760, 140, f"{w['temp']}°", 96, 300, D.TEXT, "Outfit", "ra")
    shadow(1760, 262, f"{label} · high {today_w['hi']}°", 30, 400, D.TEXT_2_ON_PHOTO, anchor="ra")
    shadow(1760, 304, FAMILY["home"]["city"], 24, 400, D.TEXT_2_ON_PHOTO, anchor="ra")
    # sun arc
    x0, x1, base, peak = 200, 1720, 880, 690
    sr, ss = today_w["sunrise"], today_w["sunset"]
    frac = min(1, max(0, (now - sr).total_seconds() / (ss - sr).total_seconds()))
    pts = [(x0 + (x1 - x0) * t / 100, base - (base - peak) * 4 * (t / 100) * (1 - t / 100)) for t in range(101)]
    sc.d.line((x0 - 40, base, x1 + 40, base), fill=(244, 241, 234, 64), width=2)
    for i in range(0, 100, 3):
        sc.d.line(pts[i] + pts[i + 1], fill=(244, 241, 234, 90), width=3)
    lit = pts[: int(frac * 100) + 1]
    if len(lit) > 1 and 0 < frac < 1:
        sc.d.line(sum(lit, ()), fill=D.AMBER, width=5)
    if 0 < frac < 1:
        px, py = pts[int(frac * 100)]
        sc.dot(px, py, 34, (244, 162, 89, 40))
        sc.dot(px, py, 16, D.AMBER)
    length = ss - sr
    shadow(160, 930, f"Sunrise {clock(sr)}     {length.seconds // 3600} h {length.seconds % 3600 // 60} m of daylight     Sunset {clock(ss)}", 26, 400, D.TEXT_2_ON_PHOTO)
    shadow(160, 975, "Reflection pool, Callaway Gardens · Pine Mountain, GA", 20, 400, D.TEXT_2_ON_PHOTO)
    nxt = next_up(data)
    if nxt:
        tw = sc.measure(nxt, 26, 600)
        sc.d.rounded_rectangle((1760 - tw - 76, 930, 1760, 994), 32, fill=(7, 11, 20, 190), outline=(244, 241, 234, 50))
        sc.dot(1760 - tw - 46, 962, 7, D.AMBER)
        sc.text(1760 - 28, 962, nxt, 26, 600, anchor="rm")
    return sc, {"clock": {"x": 160, "y": 112, "size": 300, "weight": 200, "align": "left", "color": "#F4F1EA", "ampm": True}}


def next_up(data):
    now, today = data["now"], data["now"].date()
    games = upcoming_games(data, days=2, include_lc=False)
    if games and games[0]["state"] == "in":
        return f"{games[0]['name']} {games[0]['detail']} is on now"
    if games and (games[0]["start"] - now).total_seconds() < 12 * 3600:
        delta = games[0]["start"] - now
        return f"{games[0]['name']} in {delta.seconds // 3600} h {delta.seconds % 3600 // 60} m"
    c = data["curb"]
    if (dt.date.fromisoformat(c["date"]) - today).days <= 1:
        return f"{day_word(dt.date.fromisoformat(c['date']), today)}: garbage + {'yard waste' if c['extra']['kind'] == 'yard' else 'bulky trash'}"
    for e in data["calendar"]:
        if as_dt(e["when"]) >= now:
            return f"{day_word(as_dt(e['when']), today)}: {e['title']}"
    return None


def weather_card(sc, x, y, w, h, data):
    wx, now = data["weather"], data["now"]
    today_w = wx["days"][0]
    sc.card(x, y, w, h)
    sc.icon("sun", x + 58, y + 58, 40, D.TEXT_2)
    sc.label(x + 90, y + 46, "Weather")
    label, kind = S.describe(wx["code"])
    sc.text(x + 44, y + 110, f"{wx['temp']}°", 168, 300, D.TEXT, "Outfit")
    sc.text(x + 330, y + 160, label, 36, 600)
    sc.text(x + 330, y + 210, f"High {today_w['hi']}° · low {today_w['lo']}°", 26, 400, D.TEXT_2)
    hours = [hh for hh in wx["hours"] if hh["time"] > now][:15:3]
    cw = (w - 88 - 4 * 12) / 5
    for i, hh in enumerate(hours[:5]):
        cx = x + 44 + i * (cw + 12)
        sc.bar(cx, y + 300, cw, 96, (26, 36, 64), 18)
        sc.text(cx + cw / 2, y + 316, hh["time"].strftime("%-I %p"), 22, 400, D.TEXT_2, anchor="ma")
        sc.text(cx + cw / 2, y + 348, f"{hh['temp']}°", 34, 400, D.TEXT, "Outfit", anchor="ma")
    sr, ss = today_w["sunrise"], today_w["sunset"]
    frac = min(1, max(0, (now - sr).total_seconds() / (ss - sr).total_seconds()))
    ax0, ax1, ab = x + 52, x + w - 52, y + h - 70
    pts = [(ax0 + (ax1 - ax0) * t / 100, ab - 54 * 4 * (t / 100) * (1 - t / 100)) for t in range(101)]
    for i in range(0, 100, 3):
        sc.d.line(pts[i] + pts[i + 1], fill=(42, 54, 86), width=3)
    if 0 < frac < 1:
        sc.d.line(sum(pts[: int(frac * 100) + 1], ()), fill=D.AMBER, width=4)
        sc.dot(*pts[int(frac * 100)], 9, D.AMBER)
    sc.text(x + 44, y + h - 52, f"Sunrise {clock(sr)}", 22, 400, D.TEXT_2)
    sc.text(x + w - 44, y + h - 52, f"Sunset {clock(ss)}", 22, 400, D.TEXT_2, anchor="ra")


def render_briefing(data):
    now, today = data["now"], data["now"].date()
    sc = D.Screen()
    sc.photo("callaway_pavilion.jpg", 0.78, D.INK)
    ck = header(sc, f"{now.strftime('%A, %B %-d').upper()} · LAGRANGE, GA", greeting(now))
    top, hgt = 246, 540
    col_w = [600, 532, 532]
    xs = [D.MARGIN_X, D.MARGIN_X + 600 + 32, D.MARGIN_X + 600 + 32 + 532 + 32]
    weather_card(sc, xs[0], top, col_w[0], hgt, data)
    # calendar
    x, w = xs[1], col_w[1]
    sc.card(x, top, w, hgt)
    sc.label(x + 40, top + 46, "Family calendar")
    rows = []
    c = data["curb"]
    pickup = dt.date.fromisoformat(c["date"])
    if (pickup - today).days <= 3:
        rows.append((day_word(pickup, today), "Garbage + " + ("yard waste" if c["extra"]["kind"] == "yard" else "bulky trash"),
                     "Curb by 7 AM" + (f" · moved for {c['holiday']}" if c["holiday"] else ""), D.AMBER))
    for e in data["calendar"]:
        if as_dt(e["when"]) < now - dt.timedelta(hours=1):
            continue
        when = day_word(as_dt(e["when"]), today) + ("" if e["all_day"] else " " + clock(e["when"]).replace(":00", ""))
        who = who_of(e)
        color = D.hexrgb(S.member(who[0])["color"]) if len(who) == 1 else (217, 166, 224) if who else D.TEXT
        main, sub = split_title(e["title"])
        rows.append((when, main, " · ".join(x for x in (" & ".join(who) if who else "Everyone", sub) if x), color))
    for b in data["birthdays"]:
        rows.append((day_word(b["date"], today), f"{b['name']}'s birthday", "Celebrate!", D.hexrgb(b["color"])))
    yy = top + 100
    for when, title, sub, color in rows[:4]:
        sc.text(x + 40, yy, when, 22, 700, D.AMBER)
        sc.text(x + 40, yy + 30, sc.wrap(title, 28, w - 80, 600, max_lines=1)[0], 28, 600)
        sc.dot(x + 47, yy + 82, 6, color)
        sc.text(x + 62, yy + 70, sc.wrap(sub, 21, w - 102, 400, max_lines=1)[0], 21, 400, D.TEXT_2)
        yy += 106
    if not rows:
        sc.text(x + 40, yy, "Nothing on the calendar this week.", 26, 400, D.TEXT_2)
    # game watch
    x, w = xs[2], col_w[2]
    sc.card(x, top, w, hgt)
    sc.label(x + 40, top + 46, "Game watch")
    yy = top + 100
    seen_teams, picks = set(), []
    for g in upcoming_games(data, days=14):
        if g["name"] not in seen_teams:
            seen_teams.add(g["name"])
            picks.append(g)
    for g in picks[:6]:
        team_chip(sc, x + 36, yy, 50, g["short"], g["color"], g.get("accent"))
        sc.text(x + 104, yy - 2, sc.wrap(g["name"], 25, w - 140, 600, max_lines=1)[0], 25, 600)
        when = "Live now" if g["state"] == "in" else f"{day_word(g['start'], today)} {clock(g['start'])}"
        tail = f" · {g['network']}" if g["network"] else ""
        sc.text(x + 104, yy + 30, sc.wrap(f"{when} · {g['detail']}{tail}", 20, w - 140, 400, max_lines=1)[0], 20, 400, D.TEXT_2)
        yy += 70
    # footer: headlines + heads up
    fy = 818
    sc.card(D.MARGIN_X, fy, 1110, 200)
    sc.label(D.MARGIN_X + 40, fy + 30, "LaGrange today", 20)
    for i, n in enumerate(data["news"][:3]):
        nx = D.MARGIN_X + 40 + i * 350
        sc.text(nx, fy + 70, n["source"].upper()[:26], 16, 700, D.AMBER)
        sc.para(nx, fy + 96, n["headline"], 23, 320, 500, max_lines=3, leading=1.25)
    hx = D.MARGIN_X + 1110 + 32
    sc.card(hx, fy, 1696 - 1110 - 32, 200, fill=(26, 36, 64), outline=(42, 54, 86))
    sc.label(hx + 36, fy + 30, "Heads up", 20, D.AMBER)
    hy = fy + 70
    for t in heads_up(data, 2):
        hy = sc.para(hx + 36, hy, t, 23, 1696 - 1110 - 32 - 72, 500, max_lines=2, leading=1.25) + 10
    return sc, {"clock": ck}


def render_tonight(data):
    now, today = data["now"], data["now"].date()
    sc = D.Screen((9, 12, 24))
    ck = header(sc, f"{now.strftime('%A').upper()} NIGHT", greeting(now), D.VIOLET)
    top = 246
    games = [g for g in upcoming_games(data, days=1) if g["start"].date() == today or g["state"] == "in"]
    hero = games[0] if games else None
    hx, hw, hh = D.MARGIN_X, 1000, 520
    if hero:
        sc.card(hx, top, hw, hh, fill=D.hexrgb(hero["color"]), outline=None, r=32)
        sc.dot(hx + 64, top + 66, 8, D.AMBER)
        sc.label(hx + 84, top + 54, "On now" if hero["state"] == "in" else "Starting soon", 24, D.TEXT)
        sc.text(hx + 56, top + 140, hero["name"], sc.fit(hero["name"], 112, hw - 112, 600, "Outfit"), 600, D.TEXT, "Outfit")
        sc.text(hx + 56, top + 290, f"{hero['detail']} · {clock(hero['start'])}" + (f" on {hero['network']}" if hero["network"] else ""), 34, 500, D.TEXT)
        action = None
    else:
        sc.card(hx, top, hw, hh, r=32)
        sc.label(hx + 56, top + 54, "Tonight", 24, D.VIOLET)
        cal = [e for e in data["calendar"] if as_dt(e["when"]).date() == today and as_dt(e["when"]) >= now]
        title = cal[0]["title"] if cal else "A quiet night in"
        sc.para(hx + 56, top + 130, title, 80, hw - 112, 500, fam="Outfit", max_lines=2, leading=1.05)
        sc.text(hx + 56, top + 330, "Nothing else on the family calendar tonight." if not cal else clock(cal[0]["when"]), 30, 400, D.TEXT_2)
        action = None
    # right column
    rx, rw = hx + hw + 32, 1696 - hw - 32
    tonight = [h for h in data["weather"]["hours"] if now < h["time"] <= now + dt.timedelta(hours=10)]
    lo = min((h["temp"] for h in tonight), default=data["weather"]["temp"])
    tomorrow = data["weather"]["days"][1]
    sc.card(rx, top, rw, 220)
    sc.label(rx + 40, top + 40, "Tonight")
    sc.icon("moon", rx + 90, top + 140, 90, D.VIOLET)
    sc.text(rx + 160, top + 92, f"{data['weather']['temp']}°", 88, 300, D.TEXT, "Outfit")
    sc.text(rx + 340, top + 108, S.describe(data["weather"]["code"])[0], 30, 600)
    sc.text(rx + 340, top + 150, f"Low {lo}° · tomorrow {tomorrow['hi']}°", 24, 400, D.TEXT_2)
    cy0 = top + 252
    sc.card(rx, cy0, rw, hh - 252)
    sc.label(rx + 40, cy0 + 34, "Coming up")
    yy = cy0 + 80
    c = data["curb"]
    pickup = dt.date.fromisoformat(c["date"])
    if (pickup - today).days <= 1:
        sc.card(rx + 30, yy - 10, rw - 60, 92, fill=(42, 36, 24), outline=D.AMBER, r=18)
        sc.text(rx + 54, yy + 2, f"{day_word(pickup, today)}: garbage + {'yard waste' if c['extra']['kind'] == 'yard' else 'bulky trash'}", 26, 700)
        sc.text(rx + 54, yy + 42, "Curb by 7 AM" + (" · no grass clippings" if c["extra"]["kind"] == "yard" else ""), 21, 400, D.TEXT_2_ON_PHOTO)
        yy += 110
    for e in [e for e in data["calendar"] if as_dt(e["when"]) > now][:2]:
        sc.text(rx + 40, yy, sc.wrap(split_title(e["title"])[0], 26, rw - 300, 600, max_lines=1)[0], 26, 600)
        sc.text(rx + rw - 40, yy, day_word(as_dt(e["when"]), today), 24, 400, D.TEXT_2, anchor="ra")
        yy += 48
    # app row
    ay = top + hh + 44
    sc.label(D.MARGIN_X, ay, "Your evening apps", 22, D.TEXT_2)
    tw = (1696 - 5 * 24) / 6
    for i, name in enumerate((FAMILY.get("apps") or DEFAULT_APPS)[:6]):
        ax = D.MARGIN_X + i * (tw + 24)
        sc.card(ax, ay + 44, tw, 110, fill=(26, 31, 54), outline=D.VIOLET if i == 0 else (34, 40, 66), r=22, width=2)
        sc.text(ax + tw / 2, ay + 99, name, 30, 700, anchor="mm")
    return sc, {"clock": ck, "action": action}


def render_week(data):
    now = data["now"]
    start = now.date() + dt.timedelta(days=1 if now.hour >= 17 else 0)
    days = [start + dt.timedelta(days=i) for i in range(7)]
    sc = D.Screen()
    header(sc, f"THE WEEK AHEAD · {days[0].strftime('%B %-d').upper()} TO {days[-1].strftime('%B %-d').upper()}", "Sunday Reset" if now.weekday() == 6 else "The week ahead", clock_box=False)
    sc.text(1808, 150, f"Updated {clock(now)}", 24, 400, D.TEXT_2, anchor="ra")
    top, h = 240, 560
    cw = (1696 - 6 * 16) / 7
    wx = {d["date"]: d for d in data["weather"]["days"]}
    games = upcoming_games(data, days=8)
    c = data["curb"]
    pickup = dt.date.fromisoformat(c["date"])
    for i, day in enumerate(days):
        x = D.MARGIN_X + i * (cw + 16)
        is_pickup = day == pickup
        sc.card(x, top, cw, h, outline=D.AMBER if is_pickup else D.CARD_LINE, width=2 if is_pickup else 1, r=24)
        sc.text(x + 20, top + 26, day.strftime("%a").upper(), 24, 700, D.AMBER if is_pickup else D.TEXT_2)
        sc.text(x + cw - 20, top + 16, str(day.day), 44, 400, D.TEXT, "Outfit", anchor="ra")
        if day in wx:
            sc.text(x + 20, top + 78, f"{wx[day]['hi']}° / {wx[day]['lo']}°", 22, 400, D.TEXT_2)
            sc.text(x + 20, top + 106, S.describe(wx[day]["code"])[0].lower() + (f" · {wx[day]['rain']}%" if wx[day]["rain"] >= 30 else ""), 20, 400, D.TEXT_2)
        yy = top + 150
        items = []
        if is_pickup:
            items.append(("box", "Curb by 7 AM", "Garbage + " + ("yard waste" if c["extra"]["kind"] == "yard" else "bulky trash"), D.AMBER, (42, 36, 24), dt.time(0, 0)))
        for e in data["calendar"]:
            if as_dt(e["when"]).date() == day:
                color = D.hexrgb(S.member(e["who"][0])["color"]) if len(e["who"]) == 1 else (217, 166, 224)
                if e["deadline"]:
                    items.append(("box", "Deadline", split_title(e["title"])[0], (217, 166, 224), (42, 32, 51), dt.time(0, 1)))
                else:
                    items.append(("item", "All day" if e["all_day"] else clock(e["when"]), e["title"], color, None,
                                  dt.time(0, 2) if e["all_day"] else e["when"].time()))
        for g in games:
            if g["start"].date() == day:
                items.append(("item", clock(g["start"]), f"{g['name']} {g['detail']}", None, None, g["start"].time()))
        if day.weekday() == 4 and any(m.get("activities") for m in FAMILY["members"]):
            for mem in (m for m in FAMILY["members"] if "Marching band" in m.get("activities", [])):
                items.append(("box", mem["name"], "Marching band at the Friday game", D.hexrgb(mem["color"]), (42, 38, 20), dt.time(19, 30)))
        items.sort(key=lambda it: it[5])
        shown = 0
        for kind, head, body, color, bg, _ in items:
            body_lines = sc.wrap(body, 20, cw - 52 if kind == "box" else cw - 40, 600, max_lines=2)
            need = 34 + len(body_lines) * 26 + (24 if kind == "box" else 10)
            if yy + need > top + h - 20:
                sc.text(x + 20, top + h - 46, f"+{len(items) - shown} more", 20, 600, D.TEXT_2)
                break
            if kind == "box":
                sc.card(x + 14, yy - 8, cw - 28, need - 8, fill=bg, outline=None, r=14)
                sc.text(x + 26, yy, head, 20, 700, color)
                for j, ln in enumerate(body_lines):
                    sc.text(x + 26, yy + 28 + j * 26, ln, 20, 500)
            else:
                sc.text(x + 20, yy, head, 20, 400, D.TEXT_2)
                for j, ln in enumerate(body_lines):
                    sc.text(x + 20, yy + 28 + j * 26, ln, 20, 600)
            yy += need
            shown += 1
    fy = 830
    sc.card(D.MARGIN_X, fy, 1696, 190)
    sc.label(D.MARGIN_X + 40, fy + 30, "Heads up", 20, D.AMBER)
    tips = heads_up(data, 3)
    tw = (1696 - 80 - 2 * 36) / 3
    for i, t in enumerate(tips):
        sc.para(D.MARGIN_X + 40 + i * (tw + 36), fy + 72, t, 24, tw, 500, max_lines=3, leading=1.3)
    return sc, {"clock": None}


def render_lake(data):
    lk, today = data["lake"], data["now"].date()
    sc = D.Screen((8, 20, 32))
    header(sc, "OUTDOORS · WEST POINT LAKE", "Lake conditions", D.BLUE, clock_box=False)
    sc.text(1808, 150, f"USGS gauge 02339400 · {clock(lk['time'])}", 24, 400, (159, 179, 200), anchor="ra")
    top = 246
    sc.card(D.MARGIN_X, top, 560, 770, fill=(14, 32, 51), outline=(27, 53, 80), r=32)
    gx, gy0, gh = D.MARGIN_X + 60, top + 60, 640
    lo_ft, hi_ft = 620.0, 640.0
    ypos = lambda ft: gy0 + (hi_ft - ft) / (hi_ft - lo_ft) * gh
    sc.bar(gx, gy0, 64, gh, (19, 42, 66), 32)
    level = lk["level"]
    sc.d.rounded_rectangle((gx, ypos(level), gx + 64, gy0 + gh), 32, fill=D.BLUE)
    for ft, name, dash in ((635, "Summer full pool", False), (628, "Winter pool", True)):
        yy = ypos(ft)
        for xx in range(int(gx - 16), int(gx + 80), 12 if dash else 96):
            sc.d.line((xx, yy, min(xx + (6 if dash else 96), gx + 80), yy), fill=D.TEXT, width=3)
        sc.text(gx + 120, yy - 34, f"{ft:.0f} ft", 26, 700)
        sc.text(gx + 120, yy - 4, name, 21, 400, (159, 179, 200))
    sc.text(gx + 120, ypos(level) - 20, f"{level:.1f}", 84, 400, D.TEXT, "Outfit")
    sc.text(gx + 120, ypos(level) + 76, "feet now", 24, 600, D.BLUE)
    rx, rw = D.MARGIN_X + 560 + 32, 1696 - 560 - 32
    below_s, below_w = S.SUMMER_POOL - level, S.WINTER_POOL - level
    if below_w > 0:
        sc.card(rx, top, rw, 170, fill=(42, 36, 24), outline=(90, 69, 32))
        sc.icon("sun", -100, -100, 1)  # no-op keeps icon cache warm
        sc.text(rx + 44, top + 34, f"{below_s:.1f} ft below summer pool, {below_w:.1f} ft below winter pool", sc.fit(f"{below_s:.1f} ft below summer pool, {below_w:.1f} ft below winter pool", 38, rw - 88, 500, "Outfit"), 500, D.TEXT, "Outfit")
        sc.text(rx + 44, top + 100, "Low water. Check Corps ramp and beach status before you launch.", 24, 400, (225, 211, 190))
    else:
        sc.card(rx, top, rw, 170, fill=(14, 32, 51), outline=(27, 53, 80))
        sc.text(rx + 44, top + 50, "Lake is at normal levels", 40, 500, D.TEXT, "Outfit")
    days = data["weather"]["days"][:6]
    score = lambda d: (d["rain"] < 30) * 3 + (65 <= d["hi"] <= 88) * 2 + (d["wind"] <= 10) * 2 + (d["date"].weekday() >= 5)
    best = max(days, key=score)
    cards = [("Best lake day", day_word(best["date"], today), f"High {best['hi']}°, {S.describe(best['code'])[0].lower()}, wind up to {best['wind']} mph"),
             ("Sunset on the water", clock(days[0]["sunset"]), f"Golden hour starts {clock(days[0]['sunset'] - dt.timedelta(minutes=40))}"),
             ("Fishing moon", f"{round(data['moon']['illum'] * 100)}% lit", f"{data['moon']['name']} · full {data['moon']['next_full'].strftime('%b %-d')}")]
    cw = (rw - 2 * 28) / 3
    for i, (lab, big, small) in enumerate(cards):
        cx = rx + i * (cw + 28)
        sc.card(cx, top + 202, cw, 568, fill=(14, 32, 51), outline=(27, 53, 80))
        sc.label(cx + 36, top + 240, lab, 21, (159, 179, 200))
        sc.text(cx + 36, top + 300, big, sc.fit(big, 64, cw - 72, 500, "Outfit"), 500, D.TEXT, "Outfit")
        sc.para(cx + 36, top + 400, small, 26, cw - 72, 400, (201, 214, 227), max_lines=3)
    return sc, {"clock": None}


def render_sky(data):
    now, today = data["now"], data["now"].date()
    sc = D.Screen((5, 7, 15))
    import random
    rnd = random.Random(17)
    for _ in range(160):
        x, y, r = rnd.randint(0, 1920), rnd.randint(0, 1080), rnd.choice([1, 1, 1, 1.5, 2])
        sc.dot(x, y, r, (244, 241, 234, rnd.choice([60, 90, 130, 180])))
    tonight = [h for h in data["weather"]["hours"] if now.replace(hour=21, minute=0) <= h["time"] <= now.replace(hour=23, minute=59) + dt.timedelta(hours=3)]
    cloud = sum(h["cloud"] for h in tonight) / len(tonight) if tonight else 50
    sky_word = "Clear skies. Look up." if cloud < 30 else "Some clouds tonight." if cloud < 70 else "Cloudy tonight."
    header(sc, "TONIGHT'S SKY OVER LAGRANGE", sky_word, D.VIOLET, clock_box=False)
    m = data["moon"]
    disc = D.moon_image(300, m["illum"], m["waxing"])
    sc.img.paste(disc, (D.MARGIN_X, 330), disc)
    sc.text(D.MARGIN_X + 340, 380, f"{round(m['illum'] * 100)}%", 72, 300, D.TEXT, "Outfit")
    sc.text(D.MARGIN_X + 340, 470, m["name"], 28, 600)
    sc.text(D.MARGIN_X + 340, 512, f"Full moon {m['next_full'].strftime('%b %-d')}", 23, 400, (184, 190, 208))
    s = data["shower"]
    cx, cw = 700, 1808 - 700
    sc.card(cx, 300, cw, 380, fill=(19, 23, 41), outline=(42, 48, 80), r=32)
    if s:
        sc.label(cx + 48, 344, "This week's show" if (s["peak"] - today).days <= 7 else "Coming up", 22, D.VIOLET)
        sc.para(cx + 48, 392, f"{s['name']} meteor shower peaks {day_word(s['peak'], today)} night", 54, cw - 96, 500, fam="Outfit", max_lines=2, leading=1.08)
        sc.para(cx + 48, 540, "Best in the dark hours before dawn. Face away from town lights; the West Point Lake shoreline is darker than downtown.", 25, cw - 96, 400, (201, 206, 218), max_lines=3)
    else:
        sc.label(cx + 48, 344, "Tonight", 22, D.VIOLET)
        sc.para(cx + 48, 392, f"The moon is {m['name'].lower()}", 54, cw - 96, 500, fam="Outfit", max_lines=2)
    cards = [("Viewing tonight", f"{'Clear' if cloud < 30 else 'Partly cloudy' if cloud < 70 else 'Cloudy'}",
              f"{round(cloud)}% cloud cover · low {min((h['temp'] for h in tonight), default=data['weather']['temp'])}°"),
             ("Moonset and dark sky", "After midnight" if m["waxing"] and m["illum"] > 0.3 else "Dark all evening" if m["illum"] < 0.3 else "Moon up late",
              "Darkest skies come after the moon sets"),
             ("Sunrise tomorrow", clock(data["weather"]["days"][1]["sunrise"]), "Meteor watching ends at first light")]
    w3 = (1696 - 56) / 3
    for i, (lab, big, small) in enumerate(cards):
        x = D.MARGIN_X + i * (w3 + 28)
        sc.card(x, 760, w3, 240, fill=(19, 23, 41), outline=(42, 48, 80))
        sc.label(x + 36, 796, lab, 20, (163, 169, 194))
        sc.text(x + 36, 840, big, 40, 500, D.TEXT, "Outfit")
        sc.para(x + 36, 910, small, 22, w3 - 72, 400, (201, 206, 218), max_lines=2)
    return sc, {"clock": None}


def render_recap(data):
    now = data["now"]
    fs = finals(data)
    sc = D.Screen()
    header(sc, f"GAME RECAP · {now.strftime('%A, %B %-d').upper()}", "How your teams did", clock_box=False)
    top = 246
    rivalry = next((f for f in fs if f["pro"] and f["game"]["opponent"] in ("Auburn", "Georgia")), None)
    hero = rivalry or next((f for f in fs if f["pro"]), None) or (fs[0] if fs else None)
    hx, hw, hh = D.MARGIN_X, 900, 770
    if hero:
        if rivalry:
            g = rivalry["game"]
            au_won = (g["team"]["key"] == "auburn") == bool(rivalry["won"])
            winner, loser = ("Auburn", "Georgia") if au_won else ("Georgia", "Auburn")
            fans = {"Auburn": fans_of("Auburn"), "Georgia": fans_of("Georgia")}
            color = (12, 35, 64) if au_won else (92, 10, 24)
            sc.card(hx, top, hw, hh, fill=color, outline=None, r=32)
            sc.label(hx + 56, top + 56, "House divided · final", 24, (232, 119, 34) if au_won else (242, 196, 204))
            hi_s, lo_s = sorted([int(g["my_score"]), int(g["their_score"])], reverse=True)
            sc.text(hx + 56, top + 140, f"{winner} {hi_s}", 120, 600, D.TEXT, "Outfit")
            sc.text(hx + 56, top + 290, f"{loser} {lo_s}", 80, 400, (201, 206, 218), "Outfit")
            sc.para(hx + 56, top + 470, f"{fans[winner]} have bragging rights. {fans[loser]}, there's always next year.", 34, hw - 112, 500, max_lines=3)
            sc.text(hx + 56, top + hh - 80, f"{g['team']['name'] if g['home'] else g['opponent']} hosted · {g['network']}", 26, 400, (201, 206, 218))
        else:
            sc.card(hx, top, hw, hh, fill=D.hexrgb(hero["color"]), outline=None, r=32)
            sc.label(hx + 56, top + 56, ("Win · " if hero["won"] else "Loss · ") + hero["team"], 24, D.TEXT)
            sc.text(hx + 56, top + 160, hero["score"], 190, 600, D.TEXT, "Outfit")
            sc.text(hx + 56, top + 400, hero["detail"], 36, 600)
    else:
        sc.card(hx, top, hw, hh, r=32)
        sc.text(hx + 56, top + 80, "No finals in the last day", 48, 500, D.TEXT, "Outfit")
    rx, rw = hx + hw + 32, 1696 - hw - 32
    others = [f for f in fs if f is not hero and not (rivalry and f["pro"] and f["game"]["start"] == rivalry["game"]["start"]
                                                       and f["game"]["opponent"] in ("Auburn", "Georgia"))][:7]
    sc.card(rx, top, rw, 520)
    sc.label(rx + 40, top + 40, "More results", 21)
    yy = top + 92
    for f in others:
        won = f["won"]
        sc.bar(rx + 40, yy, 56, 38, (31, 58, 42) if won else (58, 32, 36), 10)
        sc.text(rx + 68, yy + 19, "W" if won else "L", 22, 800, (158, 199, 155) if won else (242, 167, 176), anchor="mm")
        label = f"{f['team']} {f['detail']}" if f["pro"] else f"Panthers {f['detail'].replace('Football', 'football').replace('Women', 'women').replace('Men', 'men').replace('Soccer', 'soccer').replace('Volleyball', 'volleyball').replace('Tennis', 'tennis')}"
        sc.text(rx + 116, yy + 2, sc.wrap(label, 24, rw - 260, 600, max_lines=1)[0], 24, 600)
        sc.text(rx + rw - 40, yy + 2, f["score"], 30, 400, D.TEXT, "Outfit", anchor="ra")
        yy += 58
    sc.card(rx, top + 552, rw, 218)
    sc.label(rx + 40, top + 590, "Season records", 21)
    for i, (key, name, fans) in enumerate((("georgia", "Georgia", fans_of("Georgia")), ("auburn", "Auburn", fans_of("Auburn")))):
        w_, l_ = season_record(data, key)
        sc.text(rx + 40, top + 640 + i * 56, f"{name} ({fans})", 26, 600)
        sc.text(rx + rw - 40, top + 640 + i * 56, f"{w_}–{l_}", 30, 400, D.TEXT, "Outfit", anchor="ra")
    return sc, {"clock": None}


def render_gameday(data):
    now = data["now"]
    games = [g for g in upcoming_games(data, days=1, include_lc=False) if g["state"] == "in" or (g["start"] - now).total_seconds() <= 6 * 3600]
    sc = D.Screen()
    if not games:
        return None, None
    panels = games[:2]
    pw = D.W / len(panels)
    for i, g in enumerate(panels):
        x = i * pw
        sc.d.rectangle((x, 0, x + pw, 790), fill=D.hexrgb(g["color"]))
        tx = x + D.MARGIN_X if i == 0 else x + pw - D.MARGIN_X
        anchor = "la" if i == 0 else "ra"
        sc.text(tx, 80, ("ON NOW" if g["state"] == "in" else "GAME DAY") + (" · HOUSE DIVIDED" if len(panels) == 2 and {p["name"] for p in panels} == {"Georgia", "Auburn"} else ""), 24, 700, D.TEXT, anchor=anchor)
        size = 132 if len(panels) == 2 else 160
        sc.text(tx, 130, g["name"], size, 600, D.TEXT, "Outfit", anchor=anchor)
        sc.text(tx, 130 + size + 20, g["detail"], 34, 500, D.TEXT, anchor=anchor)
        sc.text(tx, 560, clock(g["start"]).replace(" ", "  "), 100, 300, D.TEXT, "Outfit", anchor=anchor)
        if g["network"]:
            sc.text(tx, 690, f"on {g['network']}", 30, 600, D.TEXT, anchor=anchor)
    if len(panels) == 1:
        delta = panels[0]["start"] - now
        if delta.total_seconds() > 0:
            sc.text(D.W - D.MARGIN_X, 600, f"Kickoff in {delta.seconds // 3600} h {delta.seconds % 3600 // 60} m", 40, 500, D.TEXT, "Outfit", anchor="ra")
    by, bh = 830, 190
    others = [g for g in upcoming_games(data, days=7) if g not in panels][:4]
    cw = (1696 - 3 * 32) / 4
    for i, g in enumerate(others):
        x = D.MARGIN_X + i * (cw + 32)
        sc.card(x, by, cw, bh)
        sc.bar(x + 36, by + 34, 18, 18, D.hexrgb(g["color"]), 5)
        sc.text(x + 66, by + 26, sc.wrap(g["name"], 24, cw - 100, 700, max_lines=1)[0], 24, 700)
        sc.text(x + 36, by + 76, f"{day_word(g['start'], now.date())} {clock(g['start'])}", 36, 400, D.TEXT, "Outfit")
        sc.text(x + 36, by + 134, sc.wrap(g["detail"], 22, cw - 72, 400, max_lines=1)[0], 22, 400, D.TEXT_2)
    return sc, {"clock": None}


def render_school(data):
    today = data["now"].date()
    sc = D.Screen()
    schools = sorted({m["school"] for m in FAMILY["members"] if m.get("school")})
    header(sc, " · ".join(schools).upper() or "SCHOOL", "School this week", D.BLUE, clock_box=False)
    top = 246
    kids = [m for m in FAMILY["members"] if m.get("school")]
    items = [e for e in data["calendar"] if e["school"] and as_dt(e["when"]).date() >= today][:5]
    sc.card(D.MARGIN_X, top, 900, 770, fill=(19, 34, 53), outline=None, r=32)
    sc.label(D.MARGIN_X + 52, top + 50, "Coming up · from the family calendar", 22, D.BLUE)
    yy = top + 120
    for e in items:
        d = as_dt(e["when"]).date()
        sc.text(D.MARGIN_X + 52, yy, d.strftime("%b %-d"), 28, 700, D.BLUE)
        sc.text(D.MARGIN_X + 52, yy + 40, sc.wrap(e["title"], 32, 790, 600, max_lines=1)[0], 32, 600)
        sc.text(D.MARGIN_X + 52, yy + 84, f"{day_word(d, today)} · " + " & ".join(who_of(e) or ["Everyone"]), 22, 400, D.TEXT_2)
        yy += 128
    if not items:
        sc.text(D.MARGIN_X + 52, yy, "No school dates on the calendar this month.", 30, 400, D.TEXT_2)
    rx, rw = D.MARGIN_X + 932, 1696 - 932
    kh = (770 - 28) / max(1, len(kids))
    for i, k in enumerate(kids):
        ky = top + i * (kh + 28)
        sc.card(rx, ky, rw, kh - 28 if len(kids) > 1 else kh)
        sc.bar(rx + 28, ky, rw - 56, 8, D.hexrgb(k["color"]), 4)
        sc.text(rx + 40, ky + 40, k["name"], 48, 600, D.TEXT, "Outfit")
        sc.text(rx + 40, ky + 108, f"{k['school']} · {k['grade']}th grade" + (" · " + ", ".join(a.lower() for a in k.get("activities", [])) if k.get("activities") else ""), 24, 400, D.TEXT_2)
        nxt = next((e for e in items if k["name"] in e["who"] or not e["who"]), None)
        if nxt:
            sc.text(rx + 40, ky + 166, sc.wrap(f"Next: {nxt['title']} ({day_word(as_dt(nxt['when']).date(), today)})", 26, rw - 80, 500, max_lines=1)[0], 26, 500)
        if k.get("activities"):
            sc.text(rx + 40, ky + 214, "Friday nights: marching band at the game", 24, 500, D.hexrgb(k["color"]))
    return sc, {"clock": None}


BOARD = ROOT / "daybreak" / "data" / "board.json"


def board():
    try:
        return json.loads(BOARD.read_text())
    except (OSError, ValueError):
        return {"notes": [], "groceries": []}


def render_board(data):
    now = data["now"]
    b = board()
    notes = [n for n in b["notes"] if not n.get("until") or dt.datetime.fromisoformat(n["until"]) > now]
    c = data["curb"]
    if now.weekday() == 6 and now.hour >= 15 and (dt.date.fromisoformat(c["date"]) - now.date()).days <= 1:
        notes.append({"text": ("Leaves to the curb tonight" if c["extra"]["kind"] == "yard" else "Bulky items to the curb tonight"),
                      "from": "Daybreak · city schedule", "color": "#F4A259"})
    if not notes and not b["groceries"]:
        return None, None
    sc = D.Screen()
    header(sc, "FAMILY BOARD", f"Notes for the {FAMILY['household']}", clock_box=False)
    sc.text(1808, 150, "Add notes from your phone: /board", 24, 400, D.TEXT_2, anchor="ra")
    top, nw = 246, 1060
    cols = 2
    cw = (nw - 28) / cols
    for i, n in enumerate(notes[:4]):
        x = D.MARGIN_X + (i % cols) * (cw + 28)
        y = top + (i // cols) * (373 + 24)
        color = D.hexrgb(n.get("color") or (S.member(n.get("from", "")) or {}).get("color", "#7FB7E8"))
        sc.card(x, y, cw, 373, fill=tuple(int(v * 0.16 + 19 * 0.84) for v in color), outline=None)
        sc.bar(x + 28, y, cw - 56, 8, color, 4)
        sc.para(x + 40, y + 50, n["text"], 44, cw - 80, 500, fam="Outfit", max_lines=4, leading=1.15)
        sc.text(x + 40, y + 373 - 56, n.get("from", ""), 22, 400, D.TEXT_2)
    gx, gw = D.MARGIN_X + nw + 32, 1696 - nw - 32
    sc.card(gx, top, gw, 770)
    sc.label(gx + 40, top + 40, "Grocery list", 22)
    yy = top + 100
    for g in b["groceries"][:11]:
        done = g.get("done")
        sc.d.rounded_rectangle((gx + 40, yy + 4, gx + 66, yy + 30), 8, outline=D.TEXT_2, width=2, fill=(127, 137, 160) if done else None)
        sc.text(gx + 86, yy, g["item"], 28, 400, (127, 137, 160) if done else D.TEXT)
        yy += 56
    return sc, {"clock": None}


SEASON = {
    10: [("Fall color", "Starting to turn", "Usually peaks here in late October to early November. Callaway's trails are the closest showcase."),
         ("In the garden", "Plant pansies and shrubs", "Fall is Georgia's best season for trees and shrubs. Divide perennials; spring bulbs go in next month."),
         ("On the wing", "Monarchs passing through", "October is monarch migration month in Georgia. Late-blooming flowers help them refuel.")],
    11: [("Fall color", "Peak season", "Early November is usually peak color around LaGrange and Pine Mountain."),
         ("In the garden", "Plant spring bulbs", "Tulips, daffodils and hyacinths go in now through December. Mulch beds before the first hard freeze."),
         ("Outdoors", "Fantasy in Lights season", "Callaway Gardens' holiday light show opens in mid-November.")],
    12: [("Winter", "Bare branches, big skies", "Long nights and clear air make December great for stargazing; the Geminids peak mid-month."),
         ("In the garden", "Protect and plan", "Cover tender plants on frost nights and order seeds for spring."),
         ("On the wing", "Winter birds at feeders", "Juncos, white-throated sparrows and yellow-rumped warblers arrive for the winter.")],
}


def render_season(data):
    now = data["now"]
    items = SEASON.get(now.month)
    if not items:
        return None, None
    sc = D.Screen()
    sc.photo("callaway_pool.jpg", 0.7, D.INK)
    header(sc, f"WHAT'S IN SEASON · {now.strftime('%B').upper()}", "The season in West Georgia", clock_box=False)
    frost = [d for d in data["weather"]["days"][1:4] if d["lo"] <= 34]
    cards = items + [("Frost watch", f"Frost {day_word(frost[0]['date'], now.date())}" if frost else "None this week",
                      f"Low of {frost[0]['lo']}° forecast. Cover tender plants." if frost else "No frost in the 3-day forecast. Daybreak warns two days ahead.")]
    cw = (1696 - 3 * 28) / 4
    for i, (lab, big, small) in enumerate(cards):
        x = D.MARGIN_X + i * (cw + 28)
        sc.card(x, 560, cw, 440, fill=(11, 17, 32, 230), outline=(42, 54, 86))
        sc.label(x + 36, 598, lab, 21, D.AMBER)
        sc.para(x + 36, 646, big, 40, cw - 72, 500, fam="Outfit", max_lines=2, leading=1.1)
        sc.para(x + 36, 760, small, 24, cw - 72, 400, D.TEXT_2_ON_PHOTO, max_lines=6, leading=1.4)
    return sc, {"clock": None}


RADAR_DIR = ROOT / "daybreak" / "cache" / "radar"
LEGEND = [("Light", ((2, 253, 2), (1, 197, 1))), ("Moderate", ((253, 248, 2), (253, 149, 0))),
          ("Heavy", ((253, 0, 0), (188, 0, 0))), ("Severe, hail", ((248, 0, 253), (152, 84, 198)))]


def refresh_radar(frames=12):
    """Fetch base map (once) and the latest MRMS frames via scripts/radar_map.py."""
    import radar_map
    RADAR_DIR.mkdir(parents=True, exist_ok=True)
    b = radar_map.bbox()
    if not (RADAR_DIR / "base.png").exists():
        radar_map.build_base(b, RADAR_DIR)
    for old in RADAR_DIR.glob("radar_*.png"):
        old.unlink()
    fr = radar_map.radar_frames(b, RADAR_DIR, frames)
    meta = {"places": {k: radar_map.to_px(*v, b) for k, v in radar_map.PLACES.items()}, "frames": fr}
    (RADAR_DIR / "meta.json").write_text(json.dumps(meta))
    return meta


def render_radar(data):
    """Returns a list of (Screen, meta) frames, oldest first, plus a status summary."""
    meta = json.loads((RADAR_DIR / "meta.json").read_text())
    base = Image.open(RADAR_DIR / "base.png").convert("RGB")
    frames = meta["frames"]
    latest = Image.open(RADAR_DIR / frames[-1]["file"]).convert("RGBA").getchannel("A")
    near = sum(1 for (x, y) in ((x, y) for x in range(703, 1218, 6) for y in range(283, 798, 6))
               if (x - 960) ** 2 + (y - 540) ** 2 <= 257 ** 2 and latest.getpixel((x, y)) > 0)
    anywhere = frames[-1]["echo_pixels"]
    if near > 20:
        status, sub = "Rain near LaGrange", "Precipitation within 25 miles"
    elif anywhere > 2000:
        status, sub = "Rain in the region", "Nothing within 25 miles yet"
    else:
        status, sub = "No rain on radar", "Clear across Troup County and the surrounding area"
    alerts = data["alerts"]
    out = []
    for i, f in enumerate(frames):
        sc = D.Screen()
        sc.img.paste(base)
        layer = Image.open(RADAR_DIR / f["file"]).convert("RGBA")
        sc.img.paste(layer, (0, 0), layer)
        sc.d.ellipse((960 - 257, 540 - 257, 960 + 257, 540 + 257), outline=(244, 241, 234, 60), width=2)
        sc.dot(960, 540, 40, (244, 162, 89, 46))
        sc.dot(960, 540, 13, D.INK)
        sc.dot(960, 540, 9, D.AMBER)
        p = meta["places"]
        for name, (x, y) in p.items():
            if name == "LaGrange":
                sc.text(x + 24, y - 22, name, 34, 600, D.TEXT, "Outfit")
            elif name == "West Point Lake":
                sc.text(x - 70, y + 8, name, 22, 400, (127, 167, 214), anchor="ra")
            elif name == "Atlanta":
                sc.dot(x, y, 6, (201, 206, 218))
                sc.text(x - 16, y - 14, name, 24, 600, (201, 206, 218), anchor="ra")
            else:
                sc.dot(x, y, 5, (201, 206, 218))
                sc.text(x + 14, y - 13, name, 22, 400, (201, 206, 218))
        sc.text(960, 540 - 257 - 30, "25 mi", 18, 600, D.TEXT_2, anchor="ma")
        sc.card(112, 64, 520, 250, fill=(11, 17, 32, 232))
        sc.dot(150, 112, 7, D.GREEN if "No rain" in status else D.AMBER)
        sc.label(170, 98, "Live radar · West Georgia", 21)
        sc.text(152, 140, status, sc.fit(status, 52, 440, 500, "Outfit"), 500, D.TEXT, "Outfit")
        sc.para(152, 214, sub, 24, 440, 400, (201, 206, 218), max_lines=2)
        sc.card(1348, 64, 460, 250 if not alerts else 330, fill=(11, 17, 32, 232) if not alerts else (92, 10, 24, 240))
        sc.label(1388, 98, "Alerts · Troup County", 21)
        if alerts:
            yy = 140
            for a in alerts[:3]:
                yy = sc.para(1388, yy, a["event"], 32, 380, 600, max_lines=2) + 8
        else:
            sc.text(1388, 150, "None in effect", 40, 500, D.TEXT, "Outfit")
            sc.text(1388, 222, "National Weather Service, Peachtree City", 21, 400, D.TEXT_2)
        t = dt.datetime.fromisoformat(f["time"].replace("Z", "+00:00")).astimezone(S.TZ)
        sc.card(112, 876, 760, 140, fill=(11, 17, 32, 232))
        sc.text(152, 904, "Past 2 hours", 24, 600)
        sc.text(832, 904, clock(t), 24, 700, D.AMBER, anchor="ra")
        n = len(frames)
        segw = (680 - (n - 1) * 6) / n
        for j in range(n):
            sc.bar(152 + j * (segw + 6), 962, segw, 10, D.AMBER if j == i else (42, 54, 86), 5)
        sc.card(1248, 876, 560, 140, fill=(11, 17, 32, 232))
        sc.label(1284, 900, "Precipitation", 19)
        lw = (488 - 30) / 4
        for j, (name, (c1, c2)) in enumerate(LEGEND):
            lx = 1284 + j * (lw + 10)
            sc.d.rectangle((lx, 944, lx + lw / 2, 958), fill=c1)
            sc.d.rectangle((lx + lw / 2, 944, lx + lw, 958), fill=c2)
            sc.text(lx, 972, name, 19, 400, (201, 206, 218))
        out.append((sc, {"clock": None, "time": f["time"]}))
    return out, {"status": status, "near": near > 20, "alerts": alerts}


RENDERERS = {"ambient": render_ambient, "briefing": render_briefing, "tonight": render_tonight, "week": render_week,
             "lake": render_lake, "sky": render_sky, "recap": render_recap, "gameday": render_gameday,
             "school": render_school, "board": render_board, "season": render_season}
