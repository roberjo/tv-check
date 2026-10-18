' Builds every screen off-device with real derived data to catch runtime errors.
sub Main()
    cfg = ParseJson(ReadAsciiFile("pkg:/family.example.json"))
    cfg.lat = cfg.home.lat
    cfg.lon = cfg.home.lon
    cfg.curbWeekday = 1
    cfg.city = cfg.home.city
    for each mem in cfg.members
        if mem.activities <> invalid then mem.band = true
    end for
    m.cache = {
        weather: ParseJson(ReadAsciiFile("pkg:/live/weather.json")),
        alerts: ParseJson(ReadAsciiFile("pkg:/live/alerts.json")),
        lake: ParseJson(ReadAsciiFile("pkg:/live/lake.json")),
        lc: icsParse(ReadAsciiFile("pkg:/live/lc.ics")),
        calendar: icsParse(ReadAsciiFile("pkg:/sample.ics")),
        news: [{headline: "Shriners blend fellowship with a mission of service", source: "LaGrange Daily News"}],
        radar: ["2026-10-18T02:19:50.000Z", "2026-10-18T02:29:50.000Z"]
    }
    sports = []
    for each team in espnTeams()
        sports.Push({team: team, json: ParseJson(ReadAsciiFile("pkg:/live/espn_" + team.key + ".json"))})
    end for
    m.cache.sports = sports
    d = derive(cfg)
    ' city now comes from derive()
    ' extra cases: a board note, groceries, a live alert and a game in 3 hours
    d.notes = [{text: "Dinner at 6:30 tonight", from: "Jordan", color: "#9EC79B"}]
    d.groceries = ["Milk", "Eggs"]
    print "app playlist: "; chooseScreens(d, "app").Join(", ")
    print "screensaver:  "; chooseScreens(d, "screensaver").Join(", ")
    for each id in ["ambient", "briefing", "tonight", "week", "lake", "sky", "recap", "school", "board", "season", "radar"]
        g = buildScreen(id, d)
        print "  built "; id; ": "; g.getChildCount(); " nodes"
    end for
    d.games.Unshift({name: "Falcons", short: "ATL", color: "#A71930", accent: invalid, start: d.now + 3 * 3600, state: "pre", detail: "vs Bears", network: "Fox", tbd: false})
    d.alerts = [{event: "Tornado Warning", level: "warning"}]
    print "with warning + game: "; chooseScreens(d, "app").Join(", ")
    g = buildScreen("gameday", d)
    print "  built gameday: "; g.getChildCount(); " nodes"
    g = buildScreen("radar", d)
    print "  built radar (alert): "; g.getChildCount(); " nodes"
    print "SCREENS OK"
end sub
