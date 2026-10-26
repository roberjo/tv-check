' Every source's parser against malformed, partial and wrongly typed
' responses: none may crash (refresh() would keep the last good data, but a
' parser should say "unreadable" by returning invalid, not by throwing).
' News (RSS) isn't covered: the emulator lacks roXMLList's GetNamedElements
' and GetText, which parseNews relies on and the TV has.
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
        wallpapers: ["{'photos':5}", "{'photos':[5,{},{'id':['x']}]}", "{'photos':[{'id':'a','file':'img/a.jpg','screens':[5,'week'],'tags':'lake'}]}"]
    }
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
    ' derive must survive whatever the parsers kept
    try
        derive(cfg)
        survived = true
    catch e
        survived = false
        print "  derive crash: "; e.message
    end try
    check("derive survives", survived, true)
    testSummary("robust")
end sub
