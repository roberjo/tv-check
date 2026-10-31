' Data task: each source's URL and parser (the compact form the TV keeps).

' --- sources ------------------------------------------------------------------

function sourceUrls(cfg as object) as object
    lat = cfg.lat.ToStr()
    lon = cfg.lon.ToStr()
    wx = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
    wx = wx + "&timezone=" + currentPlace().timezone.Replace("/", "%2F") + "&forecast_days=8&temperature_unit=fahrenheit&wind_speed_unit=mph"
    wx = wx + "&current=temperature_2m,weather_code,wind_speed_10m"
    wx = wx + "&hourly=temperature_2m,weather_code,precipitation_probability,cloud_cover"
    wx = wx + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max"
    sports = []
    for each team in espnTeams()
        sports.Push("https://site.api.espn.com/apis/site/v2/sports/" + team.path + "/schedule")
    end for
    place = currentPlace()
    news = []
    for each q in newsQueries()
        news.Push("https://news.google.com/rss/search?q=" + q + "&hl=en-US&gl=US&ceid=US:en")
    end for
    calendar = []
    if cfg.calendarUrl <> invalid and cfg.calendarUrl <> "" then calendar.Push(cfg.calendarUrl)
    lake = []
    if place.lake <> invalid then lake.Push("https://waterservices.usgs.gov/nwis/iv/?format=json&sites=" + place.lake.site + "&parameterCd=00062")
    college = []
    if place.college <> invalid then college.Push(place.college.ics)
    ' Atlantic hurricane season, June through November
    tropics = []
    month = tParts(tNowWall()).m
    if month >= 6 and month <= 11 then tropics.Push("https://www.nhc.noaa.gov/CurrentStorms.json")
    wallpapers = []
    if place.wallpapers <> invalid then wallpapers.Push(place.wallpapers + "catalog.json")
    ' outdoor games this week: look up each new venue's ZIP once, then its forecast
    venues = []
    gamewx = []
    known = venueMap()
    for each zip in gameWxZips(fresh("sports"), tNowWall())
        if known.DoesExist(zip)
            if not isTrue(known[zip].none) then gamewx.Push(gameWxUrl(known[zip]))
        else
            venues.Push("https://geocoding-api.open-meteo.com/v1/search?name=" + zip + "&count=1&countryCode=US&format=json")
        end if
    end for
    return {
        weather: [wx],
        alerts: ["https://api.weather.gov/alerts/active?point=" + lat + "," + lon],
        lake: lake,
        sports: sports,
        lc: college,
        news: news,
        calendar: calendar,
        radar: ["https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows?service=WMS&request=GetCapabilities"],
        air: ["https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + lat + "&longitude=" + lon + "&current=us_aqi,pm2_5&hourly=us_aqi&forecast_days=2&timezone=" + currentPlace().timezone.Replace("/", "%2F")],
        tropics: tropics,
        wallpapers: wallpapers,
        venues: venues,
        gamewx: gamewx
    }
end function

' --- per-source parsing -----------------------------------------------------------

function espnTeams() as object
    return currentPlace().teams
end function

' The team's logo from its ESPN schedule, as ESPN's dark-background variant
' (it reads on both the team-color and dark cards). Only ESPN's own logo CDN
' is accepted, since the URL comes from a feed; anything else gives "".
function espnLogo(j as dynamic) as string
    t = aaOf(aaOf(j).team)
    u = strOrEmpty(t.logo) ' what schedules give; ESPN's team endpoint uses logos[].href instead
    if u = "" then u = strOrEmpty(aaOf(arrAt(t.logos, 0)).href)
    if not CreateObject("roRegex", "^https://a\.espncdn\.com/i/teamlogos/[a-z]+/500/[a-z0-9]+\.png$", "").IsMatch(u) then return ""
    return u.Replace("/500/", "/500-dark/")
end function

' ESPN schedule -> [{start, state, home, opp, network, tbd, won, my, their}]
function normEspn(j as dynamic, team as object) as dynamic
    if type(aaOf(j).events) <> "roArray" then return invalid
    out = []
    for each ev in j.events
        ev = aaOf(ev)
        comp = aaOf(arrAt(ev.competitions, 0))
        mine = invalid
        other = invalid
        for each c in arrOf(comp.competitors)
            c = aaOf(c)
            if aaOf(c.team).id = team.id then mine = c else other = c
        end for
        if mine <> invalid and other <> invalid and isText(ev.date)
            opp = aaOf(other.team).shortDisplayName
            if not isText(opp) then opp = strOrEmpty(aaOf(other.team).displayName)
            network = ""
            for each b in arrOf(comp.broadcasts)
                name = aaOf(aaOf(b).media).shortName
                if isText(name)
                    if network <> "" then network = network + ", "
                    network = network + name
                end if
            end for
            st = aaOf(aaOf(comp.status).type)
            venue = aaOf(comp.venue)
            zip = Left(strOrEmpty(aaOf(venue.address).zipCode), 5)
            if not CreateObject("roRegex", "^\d{5}$", "").IsMatch(zip) then zip = ""
            out.Push({venue: strOrEmpty(venue.fullName), zip: zip,
                      start: tUtcIsoToWall(ev.date), state: strOrEmpty(st.state), home: (mine.homeAway = "home"),
                      opp: opp, network: network, tbd: isFalse(comp.timeValid), won: isTrue(mine.winner),
                      my: scoreOf(mine), their: scoreOf(other), status: strOrEmpty(st.shortDetail)})
        end if
    end for
    return out
end function

' Google News queries, already URL-encoded (the build encodes family.json's).
function newsQueries() as object
    return currentPlace().news.queries
end function

' Livestream-scam posts that name a local team ("!+[𝐒𝐓ream]HERE'S*! Troup
' County vs Howard 𝐋𝐈𝐕𝐄 HS Football ＯＮ Ｔｖ"): styled Unicode letters, full-width
' forms and emoji (above U+2BFF; the TV's fonts can't draw them, and real local
' headlines don't use them), or the scam's wording.
function newsSpam(title as string) as boolean
    spam = CreateObject("roRegex", "live\s*stream|stream(ing)?\s+free|watch\s+(it\s+)?live|on\s+tv\s+channel|\[\S*ream\]|here'?s\*", "i")
    if spam.IsMatch(title) then return true
    for i = 1 to Len(title)
        if Asc(Mid(title, i, 1)) > &h2BFF then return true
    end for
    return false
end function

function parseNews(bodies as object) as dynamic
    items = []
    parsed = 0
    for each body in bodies
        got = rssItems(body)
        if got <> invalid
            parsed = parsed + 1
            items.Append(got)
        end if
    end for
    if parsed = 0 then return invalid
    return filterNews(items)
end function

' Title and source of each RSS item, or invalid if the body isn't XML. Only
' this part needs roXMLList (GetNamedElements, GetText), which the off-device
' emulator lacks; the tests feed filterNews() from their own RSS reader.
function rssItems(body as string) as dynamic
    x = CreateObject("roXMLElement")
    if body = "" or not x.Parse(body) then return invalid
    out = []
    for each item in x.GetNamedElements("channel").GetNamedElements("item")
        out.Push({title: item.GetNamedElements("title").GetText(), source: item.GetNamedElements("source").GetText()})
    end for
    return out
end function

' Every news rule: local only, no obituaries, social media, stream listings,
' scams, section labels or repeats; violent crime is marked for gentle news.
function filterNews(items as object) as object
    skip = CreateObject("roRegex", "obituar|funeral|legacy\.com|in memory|passed away|\bobit", "i")
    social = CreateObject("roRegex", "instagram|facebook|tiktok|youtube|twitter|nfhs|reddit", "i")
    noise = CreateObject("roRegex", "\bvarsity\b.*@|@.*\bvarsity\b|live (&|and) on demand", "i")
    gentle = CreateObject("roRegex", "shoot|shot\b|killed|murder|homicide|stabb|deadly|fatal|arrest|incident report|charged with|assault", "i")
    localRe = CreateObject("roRegex", currentPlace().news.local, "i")
    ownSource = currentPlace().news.ownSource
    tail = CreateObject("roRegex", "\s+-\s+[^-]+$", "")
    seen = {}
    out = []
    for each raw in items
        it = aaOf(raw)
        title = strOrEmpty(it.title)
        source = strOrEmpty(it.source)
        headline = tail.Replace(title, "").Trim()
        key = LCase(Left(headline, 60))
        ok = not seen.DoesExist(key) and not skip.IsMatch(title + " " + source) and not social.IsMatch(source)
        ok = ok and not noise.IsMatch(title) and localRe.IsMatch(title + " " + source) and not newsSpam(title)
        ' very short headlines from the town's own paper are section labels, not news
        if ok and ownSource <> invalid and Instr(1, source, ownSource) > 0 and headline.Split(" ").Count() <= 4 then ok = false
        if ok
            seen[key] = true
            out.Push({headline: headline, source: source, violent: gentle.IsMatch(title)})
        end if
    end for
    return out
end function

' The latest `count` radar times from the WMS capabilities, about 16 minutes
' apart (MRMS publishes every 2 minutes), oldest first.
function radarTimes(caps as string, count as integer) as dynamic
    re = CreateObject("roRegex", "<Dimension name=""time""[^>]*>([^<]+)", "")
    mt = re.Match(caps)
    if mt.Count() < 2 then return invalid
    times = mt[1].Split(",")
    picks = []
    i = times.Count() - 1
    while i >= 0 and picks.Count() < count
        picks.Unshift(times[i].Trim())
        i = i - 8
    end while
    return picks
end function

function normWeather(j as dynamic) as dynamic
    dl = aaOf(aaOf(j).daily)
    days = []
    times = arrOf(dl.time)
    for i = 0 to times.Count() - 1
        hi = numAt(dl.temperature_2m_max, i, invalid)
        lo = numAt(dl.temperature_2m_min, i, invalid)
        if isText(times[i]) and hi <> invalid and lo <> invalid
            days.Push({day: tLocalIsoToWall(times[i]), code: numAt(dl.weather_code, i, 0), hi: Int(hi + 0.5), lo: Int(lo + 0.5),
                       sunrise: textTime(arrAt(dl.sunrise, i)), sunset: textTime(arrAt(dl.sunset, i)),
                       rain: numAt(dl.precipitation_probability_max, i, 0), wind: Int(numAt(dl.wind_speed_10m_max, i, 0) + 0.5)})
        end if
    end for
    if days.Count() < 7 then return invalid ' screens show a week ahead
    hl = aaOf(j.hourly)
    hours = []
    times = arrOf(hl.time)
    for i = 0 to times.Count() - 1
        temp = numAt(hl.temperature_2m, i, invalid)
        if isText(times[i]) and temp <> invalid
            hours.Push({t: tLocalIsoToWall(times[i]), temp: Int(temp + 0.5), code: numAt(hl.weather_code, i, 0),
                        rain: numAt(hl.precipitation_probability, i, 0), cloud: numAt(hl.cloud_cover, i, 0)})
        end if
    end for
    cur = aaOf(j.current)
    temp = numOf(cur.temperature_2m, invalid)
    if temp = invalid and hours.Count() > 0 then temp = hours[0].temp
    if temp = invalid then temp = days[0].hi
    return {temp: Int(temp + 0.5), code: numOf(cur.weather_code, days[0].code), wind: Int(numOf(cur.wind_speed_10m, 0) + 0.5),
            days: days, hours: hours}
end function

function normAlerts(j as dynamic) as dynamic
    if type(aaOf(j).features) <> "roArray" then return invalid
    out = []
    for each f in j.features
        p = aaOf(aaOf(f).properties)
        ev = strOrEmpty(p.event)
        if ev <> ""
            level = "advisory"
            if Instr(1, ev, "Warning") > 0
                level = "warning"
            else if Instr(1, ev, "Watch") > 0
                level = "watch"
            end if
            expires = textTime(p.expires) ' NWS gives local time with its offset
            if isText(p.ends) then expires = textTime(p.ends)
            out.Push({event: ev, level: level, headline: strOrEmpty(p.headline), instruction: Left(strOrEmpty(p.instruction).Replace(Chr(10), " "), 420), expires: expires})
        end if
    end for
    return out
end function

function normLake(j as dynamic) as dynamic
    ts = arrOf(aaOf(aaOf(j).value).timeSeries)
    if ts.Count() = 0 then return invalid
    vals = arrOf(aaOf(arrAt(aaOf(ts[0]).values, 0)).value)
    if vals.Count() = 0 then return invalid
    v = aaOf(vals[vals.Count() - 1])
    if not isText(v.value) or not isText(v.dateTime) then return invalid
    return {level: Val(v.value), time: tLocalIsoToWall(v.dateTime)}
end function

' College iCal -> [{title, start, allDay, result ("W"/"L"/"T" or ""), us, them}],
' without the long descriptions. Cancelled events are dropped.
function normLc(events as dynamic) as dynamic
    if events = invalid then return invalid
    res = CreateObject("roRegex", "^\[(W|L|T)\]\s*", "")
    score = CreateObject("roRegex", "\\n([WLT]) (\d+)-(\d+)", "")
    collegeName = ""
    if currentPlace().college <> invalid then collegeName = currentPlace().college.name
    out = []
    for each ev in events
        title = ev.summary.Replace(collegeName + " ", "").Trim()
        if Left(title, 9) <> "CANCELLED"
            item = {title: title, start: ev.start, allDay: ev.allDay, result: "", us: "", them: ""}
            mt = res.Match(title)
            if mt.Count() > 1
                item.title = res.Replace(title, "")
                sm = score.Match(ev.description)
                if sm.Count() > 3
                    item.result = mt[1]
                    item.us = sm[2]
                    item.them = sm[3]
                end if
            end if
            out.Push(item)
        end if
    end for
    return out
end function

' --- air quality and the tropics ------------------------------------------------------

' Open-Meteo air quality -> {aqi (now), pm25, hours: [{t, aqi}]}
function normAir(j as dynamic) as dynamic
    aqi = numOf(aaOf(aaOf(j).current).us_aqi, invalid)
    if aqi = invalid then return invalid
    hours = []
    hl = aaOf(j.hourly)
    times = arrOf(hl.time)
    for i = 0 to times.Count() - 1
        v = numAt(hl.us_aqi, i, invalid)
        if v <> invalid and isText(times[i]) then hours.Push({t: tLocalIsoToWall(times[i]), aqi: Int(v)})
    end for
    return {aqi: Int(aqi), pm25: numOf(j.current.pm2_5, 0), hours: hours}
end function

' NHC CurrentStorms.json -> Atlantic storms [{name, kind, mph, lat, lon}]
function normStorms(j as dynamic) as dynamic
    if type(aaOf(j).activeStorms) <> "roArray" then return invalid
    kinds = {HU: "Hurricane", TS: "Tropical Storm", TD: "Tropical Depression", STS: "Subtropical Storm",
             STD: "Subtropical Depression", PTC: "Potential Tropical Cyclone", PC: "Post-tropical cyclone"}
    out = []
    for each s in j.activeStorms
        s = aaOf(s)
        lat = numOf(s.latitudeNumeric, invalid)
        lon = numOf(s.longitudeNumeric, invalid)
        if Left(strOrEmpty(s.binNumber), 2) = "AT" and lat <> invalid and lon <> invalid
            kind = invalid
            if isText(s.classification) then kind = kinds[s.classification]
            if kind = invalid then kind = "Storm"
            kt = Val(strOrEmpty(s.intensity))
            out.Push({name: strOrEmpty(s.name), kind: kind, mph: Int(kt * 1.15078 + 0.5), lat: lat, lon: lon})
        end if
    end for
    return out
end function

function strOrEmpty(v as dynamic) as string
    if isText(v) then return v
    return ""
end function

' Type-checked access to parsed JSON: feeds can send anything, so parsers
' read through these instead of trusting the shape.
function aaOf(v as dynamic) as object
    if type(v) = "roAssociativeArray" then return v
    return {}
end function

function arrOf(v as dynamic) as object
    if type(v) = "roArray" then return v
    return []
end function

function arrAt(v as dynamic, i as integer) as dynamic
    a = arrOf(v)
    if i < a.Count() then return a[i]
    return invalid
end function

function numOf(v as dynamic, fallback as dynamic) as dynamic
    if v = invalid then return fallback
    if GetInterface(v, "ifInt") <> invalid or GetInterface(v, "ifFloat") <> invalid or GetInterface(v, "ifDouble") <> invalid or GetInterface(v, "ifLongInt") <> invalid then return v
    return fallback
end function

function numAt(v as dynamic, i as integer, fallback as dynamic) as dynamic
    return numOf(arrAt(v, i), fallback)
end function

' A local ISO time as wall seconds, or 0 when it isn't one.
function textTime(v as dynamic) as integer
    if not isText(v) or Len(v) < 10 then return 0
    return tLocalIsoToWall(v)
end function
