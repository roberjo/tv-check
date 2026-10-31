' Every source's parser against malformed, partial and wrongly typed
' responses: none may crash (refresh() would keep the last good data, but a
' parser should say "unreadable" by returning invalid, not by throwing).
' News: every rule in filterNews() against tests/fixtures/feeds/news.xml. Only
' rssItems() (the XML reading) is left to the TV: the emulator lacks
' roXMLList's GetNamedElements and GetText.
' Run via daybreak/tests/run_data.sh.
sub Main()
    cfg = fixtureConfig()
    q = Chr(34)
    junk = ["", "null", "0", "[]", "{}", q + "text" + q, "<html><body>503 Service Unavailable</body></html>", "{" + q + "a" + q + ":"]
    shapes = {
        weather: ["{'daily':{}}", "{'daily':{'time':['2026-10-18']}}", "{'daily':{'time':'2026-10-18'},'hourly':5}",
                  "{'current':{},'daily':{'time':[],'weather_code':[]},'hourly':{'time':['2026-10-18T10:00']}}",
                  "{'current':{'temperature_2m':null},'daily':{'time':['2026-10-18'],'weather_code':[0],'temperature_2m_max':[null],'temperature_2m_min':[50],'sunrise':['x'],'sunset':[5],'precipitation_probability_max':[null],'wind_speed_10m_max':[3]},'hourly':{'time':['2026-10-18T10:00'],'temperature_2m':[50],'weather_code':[0],'precipitation_probability':[1],'cloud_cover':[2]}}"],
        alerts: ["{'features':5}", "{'features':[{}]}", "{'features':[{'properties':{}}]}", "{'features':[{'properties':{'event':5,'expires':'soon'}}]}"],
        lake: ["{'value':{}}", "{'value':{'timeSeries':[]}}", "{'value':{'timeSeries':[{'values':[{'value':[]}]}]}}", "{'value':{'timeSeries':[{'values':[{'value':[{'value':'x','dateTime':5}]}]}]}}"],
        sports: ["{'events':5}", "{'events':[{}]}", "{'events':[{'competitions':[]}]}", "{'events':[{'date':5,'competitions':[{'competitors':[{},{'team':{}}]}]}]}"],
        lc: ["BEGIN:VCALENDAR", "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:[W] x\nEND:VCALENDAR", "BEGIN:VEVENT\nDTSTART:garbage\nEND:VEVENT"],
        calendar: ["BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART;VALUE=DATE:2026\nSUMMARY:TV:\nEND:VEVENT\nEND:VCALENDAR", "BEGIN:VEVENT\nRRULE:FREQ=WEEKLY;COUNT=x\nEND:VEVENT"],
        radar: ["<WMS_Capabilities/>", "<a><Dimension name='time'></Dimension></a>", "<a><Dimension name='time'>x,y</Dimension></a>"],
        air: ["{'current':{}}", "{'current':{'us_aqi':null},'hourly':{'time':['x'],'us_aqi':[null]}}", "{'hourly':{'time':5}}"],
        tropics: ["{'activeStorms':5}", "{'activeStorms':[{}]}", "{'activeStorms':[{'latitudeNumeric':'x','intensity':null}]}"],
        wallpapers: ["{'photos':5}", "{'photos':[5,{},{'id':['x']}]}", "{'photos':[{'id':'a','file':'img/a.jpg','screens':[5,'week'],'tags':'lake'}]}"],
        venues: ["{'results':5}", "{'results':[{}]}", "{'results':[{'latitude':'x','longitude':null,'country_code':5}]}", "{'results':[{'latitude':999,'longitude':5,'country_code':'US'}]}"],
        gamewx: ["{'hourly':5}", "{'hourly':{'time':[5]}}", "{'hourly':{'time':['2026-10-18T00:00'],'temperature_2m':[null],'precipitation_probability':['x'],'weather_code':{}}}"]
    }
    venueUrls = {venues: ["https://geocoding-api.open-meteo.com/v1/search?name=60605&count=1&countryCode=US&format=json"],
                 gamewx: [gameWxUrl(venueMap()["60605"])]}
    crashes = []
    for each name in shapes
        bodies = []
        bodies.Append(junk)
        for each sh in shapes[name]
            bodies.Push(sh.Replace("'", q))
        end for
        for each b in bodies
            parts = [b]
            if name = "sports" then parts = [b, b, b, b, b]
            if venueUrls.DoesExist(name) then m.ingestUrls = venueUrls[name]
            try
                ingest(name, parts)
            catch e
                crashes.Push(name + " <- " + Left(b, 40) + ": " + e.message)
            end try
        end for
    end for
    for each c in crashes
        print "  crash: "; c
    end for
    check("no parser crashes on bad responses", crashes.Count(), 0)
    ' warm-start data saved by an older version: a 1.8 catalog entry has no seasons
    old = [{id: "old-one", file: "img/old-one.jpg", place: "Old", credit: "x · CC0", tags: ["lake"], screens: ["week", "lake"]}]
    try
        picks = wallpaperPicks(old, m.testNowWall - m.testNowWall mod 86400)
        oldOk = picks.week.id = "old-one"
    catch e
        oldOk = false
        print "  old catalog crash: "; e.message
    end try
    check("a catalog saved by an older version still works", oldOk, true)
    store("wallpapers", old)
    ' derive must survive whatever the parsers kept
    try
        derive(cfg)
        survived = true
    catch e
        survived = false
        print "  derive crash: "; e.message
    end try
    check("derive survives", survived, true)
    ' news: one fixture item per rule
    items = testRssItems(ReadAsciiFile("pkg:/feeds/news.xml"))
    check("news fixture items", items.Count(), 11)
    kept = filterNews(items)
    heads = []
    for each n in kept
        v = ""
        if n.violent then v = " (violent)"
        heads.Push(n.headline + " | " + n.source + v)
    end for
    check("news keeps local stories, marks violent crime", heads.Join(Chr(10)), [
        "LaGrange council approves new downtown park | LaGrange Daily News",
        "Troup County deputies arrest man after shooting on Hogansville Road | WTVM (violent)",
        "Callaway & Hogansville schools add after-school tutoring | LaGrange Daily News"].Join(Chr(10)))
    ' each dropped rule, on its own (so a rule that stops working is named)
    drops = {obituary: 1, "social media": 3, "stream listing": 4, "styled-Unicode scam": 5, "scam wording": 6,
             "section label": 7, "not local": 9}
    for each why in drops
        check("news drops: " + why, filterNews([items[drops[why]]]).Count(), 0)
    end for
    check("news drops: duplicate", filterNews([items[0], items[8]]).Count(), 1)
    ' wrongly typed items never crash the filter
    try
        odd = filterNews([{}, {title: 5, source: invalid}, {title: "LaGrange"}, 7])
        oddOk = odd.Count() = 1
    catch e
        oddOk = false
        print "  news crash: "; e.message
    end try
    check("news filter survives odd items", oddOk, true)
    check("no RSS, no news (keeps the last good)", parseNewsOffDevice(["", "<html>503</html>"]), invalid)
    testSummary("robust")
end sub

' parseNews() with the test RSS reader in place of rssItems().
function parseNewsOffDevice(bodies as object) as dynamic
    items = []
    parsed = 0
    for each body in bodies
        got = testRssItems(body)
        if got <> invalid
            parsed = parsed + 1
            items.Append(got)
        end if
    end for
    if parsed = 0 then return invalid
    return filterNews(items)
end function
