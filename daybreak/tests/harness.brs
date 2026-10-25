' Loads the synthetic feeds (tests/fixtures/feeds, made by make_fixtures.py)
' through the same ingest() the TV uses, and pins the clock to Sunday
' 2026-10-18 10:00 AM.

function fixtureConfig() as object
    now = ParseJson(ReadAsciiFile("pkg:/feeds/now.json"))
    m.testNowUtc = now.utc
    m.testNowWall = now.wall
    m.offDevice = true
    m.place = invalid
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
    feed("air", ["air.json"])
    feed("tropics", ["nhc.json"])
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

' What gatherDiagnostics() returns on the TV, with made-up values.
function sampleDiagnostics() as object
    now = m.testNowUtc
    ok = {ok: true, lastTry: now - 30, lastOk: now - 30, fails: 0, code: 200, ms: 180, bytes: 48000, error: "", parts: 1, okParts: 1}
    sources = {}
    for each k in ["weather", "alerts", "lc", "calendar", "radar"]
        sources[k] = ok
    end for
    sources.sports = {ok: true, lastTry: now - 60, lastOk: now - 60, fails: 0, code: 200, ms: 640, bytes: 920000, error: "", parts: 5, okParts: 4}
    sources.lake = {ok: false, lastTry: now - 60, lastOk: now - 13 * 3600, fails: 3, code: 0, ms: 25000, bytes: 0, error: "timed out", parts: 1, okParts: 0}
    sources.news = {ok: false, lastTry: now - 60, lastOk: now - 1900, fails: 1, code: 503, ms: 300, bytes: 0, error: "", parts: 3, okParts: 0}
    return {nowUtc: now, version: "1.4.52", limits: sourceLimits(), speed: {state: "done", mbps: 87.42, latencyMs: 23},
            health: {sources: sources, savedAt: now - 300, warm: true, cacheBytes: 210000},
            memory: {availableKb: 145400, limitPercent: 38, level: "normal", lowMode: false, nodes: 412},
            device: {model: "TCL Roku TV (A108X)", os: "15.0 build 4170", display: "2160p60 · UI FHD", appUptimeMin: 135},
            network: {type: "Ethernet", ip: "192.168.1.20", link: true}}
end function
