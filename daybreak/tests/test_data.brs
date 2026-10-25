' derive() against the synthetic feeds with the clock pinned to Sunday
' 2026-10-18 10:00 AM. Run via daybreak/tests/run_data.sh.
sub Main()
    cfg = fixtureConfig()
    d = derive(cfg)
    check("now", tLongDate(d.now) + " " + tClock(d.now), "Sunday, October 18 10:00 AM")
    ' weather
    check("weather now", d.weather.temp.ToStr() + "° " + wxLabel(d.weather.code), "50° Clear")
    check("forecast days / hours", d.weather.days.Count().ToStr() + " / " + d.weather.hours.Count().ToStr(), "8 / 192")
    check("sunrise", tClock(d.weather.days[0].sunrise), "7:46 AM")
    check("rain soon", d.rainSoon, false)
    ' lake
    check("lake level", fmt1(d.lake.level) + " at " + tClock(d.lake.time), "625.5 at 9:45 AM")
    ' sports
    first = d.games[0]
    check("next game", first.name + " " + first.detail + " " + tClock(first.start) + " " + first.network, "Falcons vs Bears 1:00 PM Fox")
    names = []
    for each g in d.games
        names.Push(g.name)
    end for
    check("games in time order", names.Join(", "), "Falcons, Panthers women's volleyball, Hawks, Auburn, Panthers football, Georgia")
    check("TBA game", d.games[3].name + " tbd=" + d.games[3].tbd.ToStr(), "Auburn tbd=true")
    check("game day soon", soonGames(d).Count(), 1)
    check("rivalry", d.rivalry.winner + " " + d.rivalry.hi.ToStr() + "-" + d.rivalry.lo.ToStr() + " host " + d.rivalry.host, "Georgia 27-20 host Auburn")
    check("records", d.records.georgia + " " + d.records.auburn + " " + d.records.braves, "2–0 1–1 0–0")
    finals = []
    for each f in d.finals
        finals.Push(f.team + " " + f.score)
    end for
    check("finals newest first", finals.Join(", "), "Georgia 27–20, Auburn 20–27, Panthers 2–1")
    ' calendar
    cal = []
    for each e in d.calendar
        cal.Push(tKey(e.start) + " " + e.title + " [" + e.whoText + "]")
    end for
    check("calendar", cal.Join(" | "), "2026-10-18 Family photo with Grandma [Everyone] | 2026-10-20 Casey band rehearsal [Casey] | 2026-10-23 Science fair registration deadline [Riley & Casey] | 2026-10-27 Casey band rehearsal [Casey] | 2026-11-06 Appointment [Riley] | 2026-11-07 Science fair [Riley & Casey]")
    check("health shown as Appointment", d.calendar[4].health, true)
    check("deadline flagged", d.calendar[2].deadline.ToStr() + " " + d.calendar[2].subtitle, "true Nov 7 fair")
    check("board note", d.notes[0].text, "Dinner at 6:30 tonight")
    check("groceries", d.groceries.Join(", "), "milk, eggs, coffee")
    ' rules
    check("curb", tDayWord(d.curb.pickup, d.today) + " " + d.curb.extra, "Tomorrow yard waste")
    check("shower", d.shower.name + " " + tKey(d.shower.peak), "Orionids 2026-10-21")
    kinds = []
    for each t in d.tips
        kinds.Push(t.kind)
    end for
    check("tip order", kinds.Join(","), "curb,deadline,rain,frost,countdown,shower,tropics,lake")
    check("heads up (top 3)", d.headsUp.Join(" / "), "Tomorrow: garbage plus yard waste (no grass clippings). Curb by 7 AM. / Science fair registration deadline is Friday (Nov 7 fair) for Riley and Casey. / Rain likely Tuesday (65%).")
    check("tips skip what's shown", tipTexts(d.tips, {curb: true, "Science fair registration deadline": true}, 2).Join(" / "), "Rain likely Tuesday (65%). / Frost possible Wednesday morning (33°). Cover tender plants.")
    ' air quality, countdowns, the tropics
    check("air now", d.air.aqi.ToStr() + " " + d.air.label + " peak " + d.air.peak.ToStr(), "58 Moderate peak 86")
    check("countdown", d.countdowns[0].title + " in " + d.countdowns[0].days.ToStr() + " days", "Beach trip in 12 days")
    check("countdowns aren't calendar rows", d.calendar.Count(), 6)
    check("atlantic storms only", d.storms.Count().ToStr() + " " + d.storms[0].kind + " " + d.storms[0].name + " " + d.storms[0].mph.ToStr() + " mph", "1 Hurricane Nadine 98 mph")
    check("storm distance (559 mi by haversine)", d.storms[0].miles, 559)
    stormTip = invalid
    for each t in d.tips
        if t.kind = "tropics" then stormTip = t
    end for
    check("far storm tip is low priority", stormTip.p.ToStr() + " " + stormTip.t, "7 Hurricane Nadine (98 mph) is 559 mi from LaGrange.")
    check("AQI categories", aqiLabel(42) + ", " + aqiLabel(120) + ", " + aqiLabel(180) + ", " + aqiLabel(320), "Good, Unhealthy for sensitive groups, Unhealthy, Hazardous")
    ' live scores: an in-progress game keeps its score and status, and sports refresh every 2 minutes
    check("no live game", liveGame(), false)
    live = ingest("sports", ["", "", "", "", ReadAsciiFile("pkg:/feeds/espn_live.json")])
    store("sports", live)
    d5 = derive(cfg)
    g = d5.games[0]
    check("live game", g.name + " " + g.state + " " + g.my + "-" + g.their + " " + g.status, "Braves in 4-2 Bot 6th")
    check("live refresh", liveGame(), true)
    m.fetched.sports = m.testNowUtc - 150
    check("sports due after 2 minutes during a game", due("sports", 900), true)
    feed("sports", ["espn_georgia.json", "espn_auburn.json", "espn_falcons.json", "espn_hawks.json", "espn_braves.json"])
    ' another town: no lake, college or curbside, different rivalry and area
    m.place = placeOf({place: {town: "Athens", region: "GA", area: "Clarke County", lake: "none", college: "none", curbside: "none", rivalry: ["Georgia", "Falcons"]}})
    d6 = derive(cfg)
    check("no curbside", d6.curb, invalid)
    check("no college games", d6.games.Count(), 4)
    check("place names", d6.place.town + " / " + d6.place.area, "Athens / Clarke County")
    check("other rivalry has no final", d6.rivalry, invalid)
    tipKinds = []
    for each t in d6.tips
        tipKinds.Push(t.kind)
    end for
    check("no curb or lake tips", tipKinds.Join(","), "deadline,rain,frost,countdown,shower,tropics")
    m.place = invalid
    ' chores: Sunday Oct 18 2026 is day 290 and week 41 since the anchors
    turns = []
    for each c in d.chores
        turns.Push(c.task + "=" + c.who + ">" + c.next)
    end for
    check("chore turns", turns.Join(" | "), "Dishes after dinner=Riley>Casey | Trash and recycling to the curb=Casey>Riley | Feed the dog=Jordan>Riley")
    check("daily chore moves tomorrow", choreTurns(cfg.chores, cfg.members, d.today + 86400)[0].who, "Casey")
    check("weekly chore holds through Saturday", choreTurns(cfg.chores, cfg.members, d.today + 6 * 86400)[1].who, "Casey")
    check("weekly chore moves Sunday", choreTurns(cfg.chores, cfg.members, d.today + 7 * 86400)[1].who, "Riley")
    ' alerts
    feed("alerts", ["alerts_warning.json"])
    d = derive(cfg)
    check("alerts", d.alerts[0].level + " " + d.alerts[1].level, "warning watch")
    check("warning tip first", d.tips[0].kind + " " + d.tips[1].kind, "alert alert")
    ' radar: the latest 8 MRMS times, 16 minutes apart, oldest first
    check("radar frames", d.radarTimes.Count().ToStr() + " " + d.radarTimes[0] + " .. " + d.radarTimes[7], "8 2026-10-18T12:06:00.000Z .. 2026-10-18T13:58:00.000Z")
    ' ingest rejects empty and unreadable responses
    check("empty weather", ingest("weather", [""]), invalid)
    check("html instead of json", ingest("alerts", ["<html>busy</html>"]), invalid)
    check("not a calendar", ingest("calendar", ["Not found"]), invalid)
    check("news with no readable feed", ingest("news", ["", "oops"]), invalid)
    check("sports with one team answering", ingest("sports", ["", ReadAsciiFile("pkg:/feeds/espn_auburn.json")])[0].team.key, "auburn")
    ' the signature ignores the clock, so a minute later nothing is republished
    feed("alerts", ["alerts.json"])
    d1 = derive(cfg)
    m.testNowUtc = m.testNowUtc + 60
    m.testNowWall = m.testNowWall + 60
    d2 = derive(cfg)
    check("same content a minute later", dataSignature(d1) = dataSignature(d2), true)
    ' freshness: "as of" past twice the refresh interval, dropped past maxAge
    m.fetched.lake = m.testNowUtc - 2 * 3600
    m.fetched.weather = m.testNowUtc - 4 * 3600
    d3 = derive(cfg)
    check("lake as of", tClock(d3.asOf.lake), "8:01 AM")
    check("expired weather dropped", d3.weather, invalid)
    check("signature changes with content", dataSignature(d3) = dataSignature(d2), false)
    m.fetched.alerts = m.testNowUtc - 3600
    d4 = derive(cfg)
    check("expired alerts are unknown, not none", d4.alertsKnown.ToStr() + " " + d4.alerts.Count().ToStr(), "false 0")
    ' health
    noteHealth("lake", false, {code: 503, ms: 812, bytes: 0, error: "Service Unavailable", parts: 1, okParts: 0})
    noteHealth("lake", false, {code: 0, ms: 25000, bytes: 0, error: "timed out", parts: 1, okParts: 0})
    check("health after two failures", m.health.lake.fails.ToStr() + " " + m.health.lake.error, "2 timed out")
    noteHealth("lake", true, {code: 200, ms: 140, bytes: 930, error: "", parts: 1, okParts: 1})
    check("health recovers", m.health.lake.fails.ToStr() + " " + m.health.lake.ok.ToStr(), "0 true")
    ' warm start: save, wipe, load
    saveCache()
    before = derive(cfg)
    m.cache = {}
    m.fetched = {}
    check("cache loads", loadCache(), true)
    check("same data after a warm start", dataSignature(derive(cfg)) = dataSignature(before), true)
    testSummary("data")
end sub
