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
    check("tip order", kinds.Join(","), "curb,deadline,rain,frost,shower,lake")
    check("heads up (top 3)", d.headsUp.Join(" / "), "Tomorrow: garbage plus yard waste (no grass clippings). Curb by 7 AM. / Science fair registration deadline is Friday (Nov 7 fair) for Riley and Casey. / Rain likely Tuesday (65%).")
    check("tips skip what's shown", tipTexts(d.tips, {curb: true, "Science fair registration deadline": true}, 2).Join(" / "), "Rain likely Tuesday (65%). / Frost possible Wednesday morning (33°). Cover tender plants.")
    ' alerts
    m.cache.alerts = ParseJson(ReadAsciiFile("pkg:/feeds/alerts_warning.json"))
    d = derive(cfg)
    check("alerts", d.alerts[0].level + " " + d.alerts[1].level, "warning watch")
    check("warning tip first", d.tips[0].kind + " " + d.tips[1].kind, "alert alert")
    testSummary("data")
end sub
