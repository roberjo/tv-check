' Loads the synthetic feeds (tests/fixtures/feeds, made by make_fixtures.py)
' through the same ingest() the TV uses, and pins the clock to Sunday
' 2026-10-18 10:00 AM.

function fixtureConfig() as object
    now = ParseJson(ReadAsciiFile("pkg:/feeds/now.json"))
    m.testNowUtc = now.utc
    m.testNowWall = now.wall
    m.offDevice = true
    cfg = ParseJson(ReadAsciiFile("pkg:/family.example.json"))
    cfg.lat = cfg.home.lat
    cfg.lon = cfg.home.lon
    cfg.city = cfg.home.city
    cfg.curbWeekday = 1
    cfg.calendarUrl = ""
    for each mem in cfg.members
        if mem.activities <> invalid then mem.band = true
    end for
    m.cache = {}
    m.fetched = {}
    m.health = {}
    feed("weather", ["weather.json"])
    feed("alerts", ["alerts.json"])
    feed("lake", ["lake.json"])
    feed("lc", ["lc.ics"])
    feed("radar", ["radar_caps.xml"])
    sports = []
    for each team in espnTeams()
        sports.Push("espn_" + team.key + ".json")
    end for
    feed("sports", sports)
    store("calendar", ingest("calendar", [ReadAsciiFile("pkg:/sample.ics")]))
    store("news", [{headline: "Shriners blend fellowship with a mission of service", source: "Local Daily News"},
                   {headline: "City council approves new downtown park", source: "Local Daily News"}])
    return cfg
end function

' Ingests fixture files as if they were the source's HTTP responses.
sub feed(name as string, files as object)
    bodies = []
    for each f in files
        bodies.Push(ReadAsciiFile("pkg:/feeds/" + f))
    end for
    store(name, ingest(name, bodies))
end sub
