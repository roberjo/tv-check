' Smoke run: DataTask's derive() on today's live feeds (saved by
' fetch_fixtures.sh into tests/fixtures/live) and prints what the TV would
' show. Nothing is asserted; run via daybreak/tests/run_live.sh.
sub Main()
    cfg = ParseJson(ReadAsciiFile("pkg:/family.example.json"))
    cfg.lat = cfg.home.lat
    cfg.lon = cfg.home.lon
    cfg.curbWeekday = 1
    m.cache = {}
    m.fetched = {}
    m.health = {}
    for each name in ["weather", "alerts", "lake"]
        store(name, ingest(name, [ReadAsciiFile("pkg:/live/" + name + ".json")]))
    end for
    store("lc", ingest("lc", [ReadAsciiFile("pkg:/live/lc.ics")]))
    store("calendar", ingest("calendar", [ReadAsciiFile("pkg:/sample.ics")]))
    store("news", [{headline: "Shriners blend fellowship with a mission of service", source: "LaGrange Daily News"}])
    bodies = []
    for each team in espnTeams()
        bodies.Push(ReadAsciiFile("pkg:/live/espn_" + team.key + ".json"))
    end for
    store("sports", ingest("sports", bodies))
    d = derive(cfg)
    print "now "; tLongDate(d.now); " "; tClock(d.now)
    print "weather "; d.weather.temp; " code "; d.weather.code; " days "; d.weather.days.Count(); " hours "; d.weather.hours.Count()
    print "today hi/lo "; d.weather.days[0].hi; "/"; d.weather.days[0].lo; " sunrise "; tClock(d.weather.days[0].sunrise); " sunset "; tClock(d.weather.days[0].sunset)
    if d.lake <> invalid then print "alerts "; d.alerts.Count(); "  lake "; fmt1(d.lake.level); " at "; tClock(d.lake.time)
    print "games:"
    for each g in d.games
        print "  "; tDayWord(g.start, d.today); " "; tClock(g.start); "  "; g.name; " "; g.detail; " "; g.network; " ["; g.state; "]"
    end for
    print "finals:"
    for each f in d.finals
        print "  "; f.team; " "; f.detail; " "; f.score; " won="; f.won; " rivalry="; f.rivalry
    end for
    if d.rivalry <> invalid then print "rivalry: "; d.rivalry.winner; " "; d.rivalry.hi; "-"; d.rivalry.lo; " over "; d.rivalry.loser; " (host "; d.rivalry.host; ", "; d.rivalry.network; ")"
    print "records: georgia "; d.records.georgia; "  auburn "; d.records.auburn
    print "calendar:"
    for each e in d.calendar
        print "  "; tDayWord(e.start, d.today); "  "; e.title; " | "; e.subtitle; " | "; e.whoText; " health="; e.health; " deadline="; e.deadline
    end for
    print "notes "; d.notes.Count(); " groceries "; d.groceries.Count()
    print "curb "; tDayWord(d.curb.pickup, d.today); " "; d.curb.extra
    shower = "none within 14 days"
    if d.shower <> invalid then shower = d.shower.name
    print "moon "; d.moon.name; " "; Int(d.moon.illum * 100 + 0.5); "%  shower "; shower
    print "rainSoon "; d.rainSoon
    print "LIVE SMOKE OK"
    print "heads up:"
    for each t in d.headsUp
        print "  - "; t
    end for
end sub
