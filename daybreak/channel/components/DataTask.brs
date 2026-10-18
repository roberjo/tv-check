' Daybreak data task: runs for the life of the app, refreshing each source on
' its own schedule and publishing one derived "data" object every minute.
' Sources (free, keyless): Open-Meteo, NWS alerts, USGS lake gauge, ESPN team
' schedules (unofficial), LaGrange College iCal, Google News RSS, the family
' Google Calendar (secret iCal), NOAA MRMS radar times.

sub init()
    m.top.functionName = "runLoop"
end sub

sub runLoop()
    cfg = m.top.config
    m.cache = {}
    m.fetched = {}
    port = CreateObject("roMessagePort")
    while true
        ' One bad feed or parse must never stop the updates: log and carry on.
        try
            refresh(cfg)
        catch e
            print "Daybreak refresh error: "; e.message
        end try
        try
            m.top.data = derive(cfg)
        catch e
            print "Daybreak derive error: "; e.message
        end try
        wait(60000, port)
    end while
end sub

' --- fetching ---------------------------------------------------------------

function due(name as string, ttl as integer) as boolean
    last = m.fetched[name]
    return last = invalid or tNowUtc() - last >= ttl
end function

function httpGet(url as string) as string
    ut = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    ut.SetMessagePort(port)
    ut.SetUrl(url)
    if Left(url, 5) = "https"
        ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
        ut.InitClientCertificates()
    end if
    ut.AddHeader("User-Agent", "Daybreak home TV dashboard (personal, LaGrange GA)")
    ut.EnableEncodings(true)
    if ut.AsyncGetToString()
        msg = wait(25000, port)
        if type(msg) = "roUrlEvent"
            if msg.GetResponseCode() = 200 then return msg.GetString()
        else
            ut.AsyncCancel()
        end if
    end if
    return ""
end function

sub refresh(cfg as object)
    lat = cfg.lat.ToStr()
    lon = cfg.lon.ToStr()
    if due("weather", 600)
        url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
        url = url + "&timezone=America%2FNew_York&forecast_days=8&temperature_unit=fahrenheit&wind_speed_unit=mph"
        url = url + "&current=temperature_2m,weather_code,wind_speed_10m"
        url = url + "&hourly=temperature_2m,weather_code,precipitation_probability,cloud_cover"
        url = url + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max"
        store("weather", ParseJson(httpGet(url)))
    end if
    if due("alerts", 120) then store("alerts", ParseJson(httpGet("https://api.weather.gov/alerts/active?point=" + lat + "," + lon)))
    if due("lake", 1800) then store("lake", ParseJson(httpGet("https://waterservices.usgs.gov/nwis/iv/?format=json&sites=02339400&parameterCd=00062")))
    if due("sports", 900)
        all = []
        for each team in espnTeams()
            j = ParseJson(httpGet("https://site.api.espn.com/apis/site/v2/sports/" + team.path + "/schedule"))
            if j <> invalid then all.Push({team: team, json: j})
        end for
        if all.Count() > 0 then store("sports", all)
    end if
    if due("lc", 1800)
        t = httpGet("https://lagrangepanthers.com/calendar.ashx/calendar.ics")
        if t <> "" then store("lc", icsParse(t))
    end if
    if due("news", 1800) then store("news", fetchNews())
    if due("calendar", 600)
        t = httpGet(cfg.calendarUrl)
        if t <> "" then store("calendar", icsParse(t))
    end if
    if due("radar", 600) then store("radar", radarTimes())
end sub

sub store(name as string, value as dynamic)
    if value <> invalid
        m.cache[name] = value
        m.fetched[name] = tNowUtc()
    end if
end sub

function espnTeams() as object
    return [
        {key: "georgia", name: "Georgia", short: "UGA", color: "#BA0C2F", id: "61", path: "football/college-football/teams/61"},
        {key: "auburn", name: "Auburn", short: "AU", color: "#0C2340", accent: "#E87722", id: "2", path: "football/college-football/teams/2"},
        {key: "falcons", name: "Falcons", short: "ATL", color: "#A71930", id: "1", path: "football/nfl/teams/1"},
        {key: "hawks", name: "Hawks", short: "HWK", color: "#C8102E", id: "1", path: "basketball/nba/teams/1"},
        {key: "braves", name: "Braves", short: "ATL", color: "#13274F", accent: "#CE1141", id: "15", path: "baseball/mlb/teams/15"}
    ]
end function

function fetchNews() as object
    queries = ["%22LaGrange%22+GA+when%3A2d", "%22Troup+County%22+when%3A3d", "%22LaGrange+Daily+News%22+when%3A2d"]
    skip = CreateObject("roRegex", "obituar|funeral|legacy\.com|in memory|passed away|\bobit", "i")
    social = CreateObject("roRegex", "instagram|facebook|tiktok|youtube|twitter|nfhs|reddit", "i")
    noise = CreateObject("roRegex", "\bvarsity\b.*@|@.*\bvarsity\b|live (&|and) on demand", "i")
    gentle = CreateObject("roRegex", "shoot|shot\b|killed|murder|homicide|stabb|deadly|fatal|arrest|incident report|charged with|assault", "i")
    localRe = CreateObject("roRegex", "lagrange|troup|west point|hogansville|callaway|pine mountain", "i")
    tail = CreateObject("roRegex", "\s+-\s+[^-]+$", "")
    seen = {}
    out = []
    for each q in queries
        x = CreateObject("roXMLElement")
        if x.Parse(httpGet("https://news.google.com/rss/search?q=" + q + "&hl=en-US&gl=US&ceid=US:en"))
            for each item in x.GetNamedElements("channel").GetNamedElements("item")
                title = item.GetNamedElements("title").GetText()
                source = item.GetNamedElements("source").GetText()
                headline = tail.Replace(title, "").Trim()
                key = LCase(Left(headline, 60))
                ok = not seen.DoesExist(key) and not skip.IsMatch(title + " " + source) and not social.IsMatch(source)
                ok = ok and not noise.IsMatch(title) and localRe.IsMatch(title + " " + source) and not gentle.IsMatch(title)
                if ok and Instr(1, source, "LaGrange") > 0 and headline.Split(" ").Count() <= 4 then ok = false
                if ok
                    seen[key] = true
                    out.Push({headline: headline, source: source})
                end if
            end for
        end if
    end for
    return out
end function

function radarTimes() as object
    caps = httpGet("https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows?service=WMS&request=GetCapabilities")
    re = CreateObject("roRegex", "<Dimension name=""time""[^>]*>([^<]+)", "")
    mt = re.Match(caps)
    if mt.Count() < 2 then return invalid
    times = mt[1].Split(",")
    picks = []
    i = times.Count() - 1
    while i >= 0 and picks.Count() < 12
        picks.Unshift(times[i])
        i = i - 5
    end while
    return picks
end function

' --- deriving -----------------------------------------------------------------

function derive(cfg as object) as object
    now = tNowWall()
    today = tDay(now)
    d = {version: tNowUtc(), now: now, today: today, household: cfg.household, city: cfg.city, members: cfg.members}
    d.weather = deriveWeather(m.cache.weather)
    d.alerts = deriveAlerts(m.cache.alerts)
    d.lake = deriveLake(m.cache.lake)
    sports = deriveSports(m.cache.sports, now)
    lc = deriveLc(m.cache.lc, now)
    d.games = mergeGames(sports.games, lc.games)
    d.finals = mergeFinals(sports.finals, lc.finals)
    d.rivalry = sports.rivalry
    d.records = sports.records
    cal = deriveCalendar(m.cache.calendar, cfg, now)
    d.calendar = cal.items
    d.notes = cal.notes
    d.groceries = cal.groceries
    d.news = []
    if m.cache.news <> invalid then d.news = m.cache.news
    d.curb = curbNext(today, cfg.curbWeekday)
    d.birthdays = birthdays(cfg.members, today, 30)
    d.moon = moonPhase(tNowUtc())
    d.shower = nextShower(today, 14)
    d.radarTimes = []
    if m.cache.radar <> invalid then d.radarTimes = m.cache.radar
    d.rainSoon = rainSoon(d.weather, now)
    d.headsUp = headsUp(d)
    return d
end function

function deriveWeather(j as dynamic) as object
    if j = invalid or j.daily = invalid then return invalid
    days = []
    for i = 0 to j.daily.time.Count() - 1
        days.Push({day: tLocalIsoToWall(j.daily.time[i]), code: j.daily.weather_code[i],
                   hi: Int(j.daily.temperature_2m_max[i] + 0.5), lo: Int(j.daily.temperature_2m_min[i] + 0.5),
                   sunrise: tLocalIsoToWall(j.daily.sunrise[i]), sunset: tLocalIsoToWall(j.daily.sunset[i]),
                   rain: numOr(j.daily.precipitation_probability_max[i], 0), wind: Int(j.daily.wind_speed_10m_max[i] + 0.5)})
    end for
    hours = []
    for i = 0 to j.hourly.time.Count() - 1
        hours.Push({t: tLocalIsoToWall(j.hourly.time[i]), temp: Int(j.hourly.temperature_2m[i] + 0.5),
                    code: j.hourly.weather_code[i], rain: numOr(j.hourly.precipitation_probability[i], 0),
                    cloud: numOr(j.hourly.cloud_cover[i], 0)})
    end for
    return {temp: Int(j.current.temperature_2m + 0.5), code: j.current.weather_code, wind: Int(j.current.wind_speed_10m + 0.5),
            days: days, hours: hours}
end function

function numOr(v as dynamic, fallback as dynamic) as dynamic
    if v = invalid then return fallback
    return v
end function

function deriveAlerts(j as dynamic) as object
    out = []
    if j = invalid or j.features = invalid then return out
    for each f in j.features
        ev = f.properties.event
        level = "advisory"
        if Instr(1, ev, "Warning") > 0
            level = "warning"
        else if Instr(1, ev, "Watch") > 0
            level = "watch"
        end if
        out.Push({event: ev, level: level})
    end for
    return out
end function

function deriveLake(j as dynamic) as object
    if j = invalid then return invalid
    ts = j.value.timeSeries
    if ts = invalid or ts.Count() = 0 then return invalid
    vals = ts[0].values[0].value
    v = vals[vals.Count() - 1]
    return {level: Val(v.value), time: tLocalIsoToWall(v.dateTime)}
end function

function deriveSports(all as dynamic, now as integer) as object
    out = {games: [], finals: [], rivalry: invalid, records: {}}
    if all = invalid then return out
    for each entry in all
        team = entry.team
        w = 0
        l = 0
        for each ev in entry.json.events
            comp = ev.competitions[0]
            mine = invalid
            other = invalid
            for each c in comp.competitors
                if c.team.id = team.id then mine = c else other = c
            end for
            if mine <> invalid and other <> invalid
                state = comp.status.type.state
                start = tUtcIsoToWall(ev.date)
                opp = other.team.shortDisplayName
                if opp = invalid then opp = other.team.displayName
                home = (mine.homeAway = "home")
                detail = "at " + opp
                if home then detail = "vs " + opp
                network = ""
                if comp.broadcasts <> invalid
                    for each b in comp.broadcasts
                        if b.media <> invalid and b.media.shortName <> invalid
                            if network <> "" then network = network + ", "
                            network = network + b.media.shortName
                        end if
                    end for
                end if
                if state = "post"
                    won = false
                    if mine.winner <> invalid
                        if mine.winner = true then won = true
                    end if
                    if won then w = w + 1 else l = l + 1
                    if start >= now - 36 * 3600
                        score = scoreOf(mine) + "–" + scoreOf(other)
                        rivalry = (opp = "Auburn" or opp = "Georgia") and (team.key = "georgia" or team.key = "auburn")
                        out.finals.Push({team: team.name, color: team.color, won: won, score: score, detail: detail,
                                         start: start, pro: true, rivalry: rivalry})
                        if rivalry and team.key = "auburn"
                            hi = Val(scoreOf(mine))
                            lo = Val(scoreOf(other))
                            winner = "Georgia"
                            loser = "Auburn"
                            if won
                                winner = "Auburn"
                                loser = "Georgia"
                            end if
                            if lo > hi
                                t = hi
                                hi = lo
                                lo = t
                            end if
                            host = opp
                            if home then host = "Auburn"
                            out.rivalry = {winner: winner, loser: loser, hi: hi, lo: lo, network: network, host: host}
                        end if
                    end if
                else if start >= now - 4 * 3600 and start <= now + 14 * 86400
                    tbd = false
                    if comp.timeValid <> invalid
                        if comp.timeValid = false then tbd = true
                    end if
                    out.games.Push({name: team.name, short: team.short, color: team.color, accent: team.accent,
                                    start: start, state: state, detail: detail, network: network, tbd: tbd})
                end if
            end if
        end for
        out.records[team.key] = w.ToStr() + "–" + l.ToStr()
    end for
    return out
end function

function scoreOf(c as object) as string
    s = c.score
    if type(s) = "roAssociativeArray" then s = s.displayValue
    if s = invalid then return "0"
    return s.ToStr()
end function

function deriveLc(events as dynamic, now as integer) as object
    out = {games: [], finals: []}
    if events = invalid then return out
    res = CreateObject("roRegex", "^\[(W|L|T)\]\s*", "")
    score = CreateObject("roRegex", "\\n([WLT]) (\d+)-(\d+)", "")
    for each ev in events
        title = ev.summary.Replace("LaGrange College ", "").Trim()
        if Left(title, 9) <> "CANCELLED"
            mt = res.Match(title)
            if mt.Count() > 1
                title = res.Replace(title, "")
                sm = score.Match(ev.description)
                if sm.Count() > 3 and ev.start >= now - 36 * 3600 and ev.start <= now
                    out.finals.Push({team: "Panthers", color: "#8E1B24", won: (mt[1] = "W"), score: sm[2] + "–" + sm[3],
                                     detail: lcShort(title), start: ev.start, pro: false, rivalry: false})
                end if
            else if not ev.allDay and ev.start >= now and ev.start <= now + 14 * 86400
                home = Instr(1, title, " vs ") > 0
                if Instr(1, title, "Football") > 0 or (home and tDay(ev.start) = tDay(now))
                    sep = " at "
                    if home then sep = " vs "
                    parts = title.Split(sep)
                    sport = LCase(parts[0].Trim())
                    opp = ""
                    if parts.Count() > 1 then opp = lcShort(parts[1].Split(" - ")[0])
                    out.games.Push({name: "Panthers " + sport, short: "LC", color: "#8E1B24", accent: invalid,
                                    start: ev.start, state: "pre", detail: sep.Trim() + " " + opp, network: "", tbd: false})
                end if
            end if
        end if
    end for
    return out
end function

function lcShort(s as string) as string
    return s.Replace(" College", "").Replace(" University", "").Replace(" (Ga.)", "").Trim()
end function

function mergeGames(a as object, b as object) as object
    out = []
    out.Append(a)
    out.Append(b)
    out.SortBy("start")
    return out
end function

function mergeFinals(a as object, b as object) as object
    out = []
    out.Append(a)
    out.Append(b)
    out.SortBy("start", "r")
    return out
end function

function deriveCalendar(events as dynamic, cfg as object, now as integer) as object
    out = {items: [], notes: [], groceries: []}
    if events = invalid then return out
    health = CreateObject("roRegex", "doctor|pediatric|well-?check|dentist|dental|orthodont|flu shot|vaccin|clinic|hospital|therap|physical|appointment|wellstar|medical|urgent care|derm|optom|eye exam", "i")
    school = CreateObject("roRegex", "\bSAT\b|\bACT\b|PSAT|school|exam|report card|early release|band|homecoming|graduation|registration|teacher|class|semester", "i")
    deadline = CreateObject("roRegex", "deadline|due|closes", "i")
    both = CreateObject("roRegex", "\s*[—-]\s*(both|all) (kids|girls|boys)\s*$", "i")
    today = tDay(now)
    for each ev in events
        if not ev.cancelled
            for each start in icsOccurrences(ev, today - 7 * 86400, today + 21 * 86400)
                title = ev.summary.Trim()
                finish = start + 3600
                if ev.finish <> invalid then finish = start + (ev.finish - ev.start)
                if ev.allDay then finish = start + 86400
                who = []
                for each mem in cfg.members
                    if CreateObject("roRegex", "\b" + mem.name + "\b", "").IsMatch(title) then who.Push(mem.name)
                end for
                if UCase(Left(title, 3)) = "TV:"
                    if now >= start - 12 * 3600 and now < finish
                        out.notes.Push({text: Mid(title, 4).Trim(), from: whoText(who), color: colorFor(who, cfg)})
                    end if
                else if UCase(Left(title, 4)) = "BUY:"
                    if finish >= today
                        for each item in Mid(title, 5).Split(",")
                            if item.Trim() <> "" then out.groceries.Push(item.Trim())
                        end for
                    end if
                else if start >= today
                    isHealth = health.IsMatch(title) or health.IsMatch(ev.location)
                    isSchool = school.IsMatch(title) and not isHealth
                    if CreateObject("roRegex", "\b(both|all) (kids|girls|boys)\b", "i").IsMatch(title) or (isSchool and who.Count() = 0)
                        who = []
                        for each mem in cfg.members
                            if mem.school <> invalid then who.Push(mem.name)
                        end for
                    end if
                    shown = both.Replace(title, "")
                    if isHealth then shown = "Appointment"
                    main = shown
                    subText = ""
                    for each sep in [" — ", " – ", " - "]
                        if subText = "" and Instr(1, shown, sep) > 0
                            k = Instr(1, shown, sep)
                            main = Left(shown, k - 1).Trim()
                            subText = Mid(shown, k + Len(sep)).Trim()
                        end if
                    end for
                    out.items.Push({start: start, allDay: ev.allDay, title: main, subtitle: subText, who: who, whoText: whoText(who),
                                    color: colorFor(who, cfg), health: isHealth, school: isSchool,
                                    deadline: deadline.IsMatch(title) and not isHealth})
                end if
            end for
        end if
    end for
    out.items.SortBy("start")
    return out
end function

function whoText(who as object) as string
    if who.Count() = 0 then return "Everyone"
    return who.Join(" & ")
end function

function colorFor(who as object, cfg as object) as string
    if who.Count() = 1
        for each mem in cfg.members
            if mem.name = who[0] then return mem.color
        end for
    end if
    if who.Count() > 1 then return "#D9A6E0"
    return "#F4F1EA"
end function

function birthdays(members as object, today as integer, within as integer) as object
    out = []
    y = tParts(today).y
    for each mem in members
        mo = Val(Left(mem.birthday, 2))
        dy = Val(Right(mem.birthday, 2))
        b = tYmd(y, mo, dy)
        if b < today then b = tYmd(y + 1, mo, dy)
        n = (b - today) \ 86400
        if n <= within then out.Push({name: mem.name, day: b, days: n, color: mem.color})
    end for
    out.SortBy("days")
    return out
end function

function rainSoon(w as dynamic, now as integer) as boolean
    if w = invalid then return false
    for each h in w.hours
        if h.t > now - 3600 and h.t <= now + 2 * 3600 and h.rain >= 50 then return true
    end for
    return false
end function

' Rule-based insights, most important first (replaces the Claude summaries).
function headsUp(d as object) as object
    tips = []
    today = d.today
    for each a in d.alerts
        p = 1
        if a.level = "warning" then p = 0
        tips.Push({p: p, t: a.event + " for Troup County."})
    end for
    c = d.curb
    n = (c.pickup - today) \ 86400
    if n <= 1 or (tWeekday(d.now) = 0 and n <= 2)
        moved = ""
        if c.holiday <> invalid then moved = " (moved for " + c.holiday + ")"
        extra = "bulky trash"
        if c.yard then extra = "yard waste (no grass clippings)"
        tips.Push({p: 2, t: tDayWord(c.pickup, today) + moved + ": garbage plus " + extra + ". Curb by 7 AM."})
    end if
    for each e in d.calendar
        dn = (tDay(e.start) - today) \ 86400
        if e.deadline and dn >= 0 and dn <= 7
            t = e.title + " is " + LCase(tDayWord(e.start, today))
            if dn >= 2 then t = e.title + " is " + tDayWord(e.start, today)
            if e.subtitle <> "" then t = t + " (" + e.subtitle + ")"
            if e.who.Count() > 0 then t = t + " for " + e.who.Join(" and ")
            tips.Push({p: 3, t: t + "."})
        end if
    end for
    for i = 0 to d.calendar.Count() - 1
        a = d.calendar[i]
        for j = i + 1 to d.calendar.Count() - 1
            b = d.calendar[j]
            if not a.allDay and not b.allDay and tDay(a.start) = tDay(b.start) and Abs(a.start - b.start) < 5400 and (tDay(a.start) - today) \ 86400 <= 7
                tips.Push({p: 4, t: tDayWord(a.start, today) + ": " + a.title + " and " + b.title + " overlap."})
            end if
        end for
    end for
    if d.weather <> invalid
        for i = 1 to 3
            day = d.weather.days[i]
            if day.rain >= 60 then tips.Push({p: 5, t: "Rain likely " + tDayWord(day.day, today) + " (" + day.rain.ToStr() + "%)."})
            if day.lo <= 34 then tips.Push({p: 5, t: "Frost possible " + tDayWord(day.day, today) + " morning (" + day.lo.ToStr() + "°). Cover tender plants."})
        end for
    end if
    for each b in d.birthdays
        if b.days <= 14 then tips.Push({p: 6, t: b.name + "'s birthday is " + tDayWord(b.day, today) + "."})
    end for
    if d.shower <> invalid and (d.shower.peak - today) \ 86400 <= 4
        tips.Push({p: 7, t: "The " + d.shower.name + " meteor shower peaks " + tDayWord(d.shower.peak, today) + " night. Best before dawn."})
    end if
    if d.lake <> invalid and d.lake.level < 626
        tips.Push({p: 8, t: "West Point Lake is low at " + fmt1(d.lake.level) + " ft. Check ramps before launching."})
    end if
    tips.SortBy("p")
    out = []
    for each tip in tips
        if out.Count() < 3 then out.Push(tip.t)
    end for
    return out
end function
