' Loads the synthetic feeds (tests/fixtures/feeds, made by make_fixtures.py)
' into the data task's cache and pins the clock to Sunday 2026-10-18 10:00 AM.

function fixtureConfig() as object
    now = ParseJson(ReadAsciiFile("pkg:/feeds/now.json"))
    m.testNowUtc = now.utc
    m.testNowWall = now.wall
    cfg = ParseJson(ReadAsciiFile("pkg:/family.example.json"))
    cfg.lat = cfg.home.lat
    cfg.lon = cfg.home.lon
    cfg.city = cfg.home.city
    cfg.curbWeekday = 1
    cfg.calendarUrl = ""
    for each mem in cfg.members
        if mem.activities <> invalid then mem.band = true
    end for
    m.cache = {
        weather: ParseJson(ReadAsciiFile("pkg:/feeds/weather.json")),
        alerts: ParseJson(ReadAsciiFile("pkg:/feeds/alerts.json")),
        lake: ParseJson(ReadAsciiFile("pkg:/feeds/lake.json")),
        lc: icsParse(ReadAsciiFile("pkg:/feeds/lc.ics")),
        calendar: icsParse(ReadAsciiFile("pkg:/sample.ics")),
        news: [{headline: "Shriners blend fellowship with a mission of service", source: "Local Daily News"},
               {headline: "City council approves new downtown park", source: "Local Daily News"}],
        radar: ParseJson(ReadAsciiFile("pkg:/feeds/radar.json"))
    }
    sports = []
    for each team in espnTeams()
        sports.Push({team: team, json: ParseJson(ReadAsciiFile("pkg:/feeds/espn_" + team.key + ".json"))})
    end for
    m.cache.sports = sports
    return cfg
end function
