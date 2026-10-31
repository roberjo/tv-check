' Feed canary, run by daybreak/tests/feed_canary.py in two passes:
'   1. pkg:/live/canary.json is {}: prints the TV's own request URLs
'      (sourceUrls() for the fictional family and the default place) as
'      "CANARY-URLS <json>", so the canary can't drift from the app.
'   2. after the fetch: ingests every saved response through the TV's parsers
'      and prints "CANARY <source> ok|fail <detail>" per source.
' News is checked in Python (feed_canary.py): the emulator can't read RSS.
sub Main()
    cfg = ParseJson(ReadAsciiFile("pkg:/family.example.json"))
    cfg.lat = cfg.home.lat
    cfg.lon = cfg.home.lon
    cfg.calendarUrl = "" ' never the family calendar
    m.offDevice = true
    m.cache = {}
    m.fetched = {}
    m.health = {}
    manifest = ParseJson(ReadAsciiFile("pkg:/live/canary.json"))
    if manifest.Count() = 0
        print "CANARY-URLS " + FormatJson(sourceUrls(cfg))
        print "ALL TESTS PASSED (canary urls)"
        return
    end if
    ' venues first: the forecast at a venue is matched to it by the TV's own URL
    names = []
    if manifest.DoesExist("venues") then names.Push("venues")
    for each name in manifest
        if name <> "venues" then names.Push(name)
    end for
    for each name in names
        entry = manifest[name]
        if name = "gamewx"
            entry.urls = []
            vm = venueMap()
            for each zip in vm
                if not isTrue(vm[zip].none) then entry.urls.Push(gameWxUrl(vm[zip]))
            end for
        end if
        if name <> "news"
            bodies = []
            for each f in entry.files
                bodies.Push(ReadAsciiFile("pkg:/live/" + f))
            end for
            m.ingestUrls = entry.urls
            v = invalid
            detail = ""
            try
                v = ingest(name, bodies)
            catch e
                detail = "parser threw: " + e.message
            end try
            if v = invalid
                if detail = "" then detail = "unreadable (ingest returned invalid)"
                print "CANARY " + name + " fail " + detail
            else
                print "CANARY " + name + " ok " + canarySize(v)
                store(name, v)
            end if
        end if
    end for
    print "ALL TESTS PASSED (canary)"
end sub

function canarySize(v as dynamic) as string
    if type(v) = "roArray" then return v.Count().ToStr() + " items"
    if type(v) = "roAssociativeArray" then return v.Count().ToStr() + " fields"
    return type(v)
end function
