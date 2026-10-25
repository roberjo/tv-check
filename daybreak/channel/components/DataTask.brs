' Daybreak data task: runs for the life of the app. Each minute it fetches
' every source that's due (in parallel), reduces each response to the compact
' form Daybreak uses, and publishes derived data when its content changes.
' The last good data is saved to cachefs: so the next launch starts warm.
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
    m.health = {}
    m.lastSig = ""
    m.lastSave = 0
    m.warm = loadCache()
    publish(cfg) ' warm start: show the saved data right away
    port = CreateObject("roMessagePort")
    while true
        ' One bad feed or parse must never stop the updates: log and carry on.
        try
            refresh(cfg)
        catch e
            print "Daybreak refresh error: "; e.message
        end try
        try
            publish(cfg)
        catch e
            print "Daybreak derive error: "; e.message
        end try
        wait(60000, port)
    end while
end sub

' Publishes data only when its content changed (the scene rebuilds on every
' publish); health goes out every minute for the diagnostics screen.
sub publish(cfg as object)
    d = derive(cfg)
    sig = dataSignature(d)
    if sig <> m.lastSig
        m.lastSig = sig
        m.top.data = d
    end if
    m.top.health = {sources: m.health, savedAt: m.lastSave, warm: m.warm, cacheBytes: m.cacheBytes}
end sub

' Everything in the data except the clock fields, as JSON.
function dataSignature(d as object) as string
    c = {}
    for each k in d
        if k <> "now" and k <> "version" then c[k] = d[k]
    end for
    return FormatJson(c)
end function

' --- sources ------------------------------------------------------------------

' Refresh interval (ttl) and the age after which data is dropped (maxAge), in seconds.
function sourceLimits() as object
    return {
        weather: {ttl: 600, maxAge: 3 * 3600}, alerts: {ttl: 120, maxAge: 1800}, lake: {ttl: 1800, maxAge: 12 * 3600},
        sports: {ttl: 900, maxAge: 6 * 3600}, lc: {ttl: 1800, maxAge: 24 * 3600}, news: {ttl: 1800, maxAge: 12 * 3600},
        calendar: {ttl: 600, maxAge: 24 * 3600}, radar: {ttl: 600, maxAge: 1800}
    }
end function

function sourceUrls(cfg as object) as object
    lat = cfg.lat.ToStr()
    lon = cfg.lon.ToStr()
    wx = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
    wx = wx + "&timezone=America%2FNew_York&forecast_days=8&temperature_unit=fahrenheit&wind_speed_unit=mph"
    wx = wx + "&current=temperature_2m,weather_code,wind_speed_10m"
    wx = wx + "&hourly=temperature_2m,weather_code,precipitation_probability,cloud_cover"
    wx = wx + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max"
    sports = []
    for each team in espnTeams()
        sports.Push("https://site.api.espn.com/apis/site/v2/sports/" + team.path + "/schedule")
    end for
    news = []
    for each q in newsQueries()
        news.Push("https://news.google.com/rss/search?q=" + q + "&hl=en-US&gl=US&ceid=US:en")
    end for
    calendar = []
    if cfg.calendarUrl <> invalid and cfg.calendarUrl <> "" then calendar.Push(cfg.calendarUrl)
    return {
        weather: [wx],
        alerts: ["https://api.weather.gov/alerts/active?point=" + lat + "," + lon],
        lake: ["https://waterservices.usgs.gov/nwis/iv/?format=json&sites=02339400&parameterCd=00062"],
        sports: sports,
        lc: ["https://lagrangepanthers.com/calendar.ashx/calendar.ics"],
        news: news,
        calendar: calendar,
        radar: ["https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows?service=WMS&request=GetCapabilities"]
    }
end function

function due(name as string, ttl as integer) as boolean
    last = m.fetched[name]
    return last = invalid or tNowUtc() - last >= ttl
end function

sub refresh(cfg as object)
    limits = sourceLimits()
    urls = sourceUrls(cfg)
    reqs = []
    for each name in urls
        if urls[name].Count() > 0 and due(name, limits[name].ttl)
            for each u in urls[name]
                reqs.Push({source: name, url: u})
            end for
        end if
    end for
    if reqs.Count() = 0 then return
    fetchAll(reqs, 25000)
    bySource = {}
    for each r in reqs
        if not bySource.DoesExist(r.source) then bySource[r.source] = []
        bySource[r.source].Push(r)
    end for
    changed = false
    for each name in bySource
        parts = bySource[name]
        bodies = []
        h = {code: 0, ms: 0, bytes: 0, error: "", parts: parts.Count(), okParts: 0}
        for each r in parts
            bodies.Push(r.body)
            h.bytes = h.bytes + Len(r.body)
            if r.ms > h.ms then h.ms = r.ms
            if r.code = 200 then h.okParts = h.okParts + 1
            if h.code <> 200 then h.code = r.code
            if r.error <> "" then h.error = r.error
        end for
        value = invalid
        if h.okParts > 0
            try
                value = ingest(name, bodies)
            catch e
                h.error = "parse: " + e.message
            end try
            if value = invalid and h.error = "" then h.error = "unreadable response"
        end if
        if value <> invalid
            store(name, value)
            changed = true
        end if
        noteHealth(name, value <> invalid, h)
    end for
    if changed and tNowUtc() - m.lastSave >= 600 then saveCache()
end sub

' Runs every request at once on one port; each gets code, body, ms and error.
sub fetchAll(reqs as object, timeoutMs as integer)
    port = CreateObject("roMessagePort")
    pending = {}
    for each r in reqs
        r.code = 0
        r.body = ""
        r.ms = 0
        r.error = ""
        ut = CreateObject("roUrlTransfer")
        ut.SetMessagePort(port)
        ut.SetUrl(r.url)
        if Left(r.url, 5) = "https"
            ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
            ut.InitClientCertificates()
        end if
        ut.AddHeader("User-Agent", "Daybreak home TV dashboard (personal, LaGrange GA)")
        ut.EnableEncodings(true)
        r.clock = CreateObject("roTimespan")
        if ut.AsyncGetToString()
            pending[ut.GetIdentity().ToStr()] = {ut: ut, req: r}
        else
            r.error = "could not start request"
        end if
    end for
    clock = CreateObject("roTimespan")
    while pending.Count() > 0
        remaining = timeoutMs - clock.TotalMilliseconds()
        if remaining <= 0 then exit while
        msg = wait(remaining, port)
        if type(msg) = "roUrlEvent"
            key = msg.GetSourceIdentity().ToStr()
            p = pending[key]
            if p <> invalid
                r = p.req
                r.code = msg.GetResponseCode()
                r.ms = r.clock.TotalMilliseconds()
                if r.code = 200 then r.body = msg.GetString() else r.error = msg.GetFailureReason()
                pending.Delete(key)
            end if
        end if
    end while
    for each key in pending
        pending[key].ut.AsyncCancel()
        pending[key].req.error = "timed out"
        pending[key].req.ms = timeoutMs
    end for
end sub

' Reduces raw responses (one body per URL) to the compact form derive() uses.
' Returns invalid when nothing usable came back.
function ingest(name as string, bodies as object) as dynamic
    if name = "weather" then return normWeather(parseJsonSafe(bodies[0]))
    if name = "alerts" then return normAlerts(parseJsonSafe(bodies[0]))
    if name = "lake" then return normLake(parseJsonSafe(bodies[0]))
    if name = "sports"
        out = []
        teams = espnTeams()
        for i = 0 to teams.Count() - 1
            if i < bodies.Count() and bodies[i] <> ""
                evs = normEspn(parseJsonSafe(bodies[i]), teams[i])
                if evs <> invalid then out.Push({team: teams[i], events: evs})
            end if
        end for
        if out.Count() = 0 then return invalid
        return out
    end if
    if name = "lc" or name = "calendar"
        if bodies[0] = "" or Instr(1, bodies[0], "BEGIN:VCALENDAR") = 0 then return invalid
        if name = "lc" then return normLc(icsParse(bodies[0]))
        events = icsParse(bodies[0])
        for each ev in events
            ev.Delete("description") ' never shown; keeps the saved cache small
        end for
        return events
    end if
    if name = "news" then return parseNews(bodies)
    if name = "radar" then return radarTimes(bodies[0], 8)
    return invalid
end function

' ParseJson for HTTP bodies: an empty or non-JSON body (an error page) is
' invalid without a parser error.
function parseJsonSafe(text as string) as dynamic
    t = text.Trim()
    if t = "" or (Left(t, 1) <> "{" and Left(t, 1) <> "[") then return invalid
    return ParseJson(t)
end function

sub store(name as string, value as dynamic)
    if value <> invalid
        m.cache[name] = value
        m.fetched[name] = tNowUtc()
    end if
end sub

sub noteHealth(name as string, ok as boolean, h as object)
    prev = m.health[name]
    fails = 0
    lastOk = invalid
    if prev <> invalid
        fails = prev.fails
        lastOk = prev.lastOk
    end if
    if ok
        fails = 0
        lastOk = tNowUtc()
    else
        fails = fails + 1
    end if
    m.health[name] = {ok: ok, lastTry: tNowUtc(), lastOk: lastOk, fails: fails, code: h.code, ms: h.ms,
                      bytes: h.bytes, error: h.error, parts: h.parts, okParts: h.okParts}
end sub

' Cached data younger than the source's maxAge, else invalid.
function fresh(name as string) as dynamic
    v = m.cache[name]
    if v = invalid then return invalid
    t = m.fetched[name]
    lim = sourceLimits()[name]
    if t <> invalid and lim <> invalid and tNowUtc() - t > lim.maxAge then return invalid
    return v
end function

' --- warm start -------------------------------------------------------------------

function cachePath() as string
    if m.offDevice = true then return "tmp:/daybreak-cache.json" ' off-device runners have no cachefs:
    return "cachefs:/daybreak-cache.json"
end function

sub saveCache()
    text = FormatJson({v: 2, cache: m.cache, fetched: m.fetched})
    if WriteAsciiFile(cachePath(), text)
        m.cacheBytes = Len(text)
        m.lastSave = tNowUtc()
    end if
end sub

function loadCache() as boolean
    j = parseJsonSafe(ReadAsciiFile(cachePath()))
    if j = invalid or j.v <> 2 or j.cache = invalid or j.fetched = invalid then return false
    m.cache = j.cache
    m.fetched = j.fetched
    return true
end function

' --- per-source parsing -----------------------------------------------------------

function espnTeams() as object
    return [
        {key: "georgia", name: "Georgia", short: "UGA", color: "#BA0C2F", id: "61", path: "football/college-football/teams/61"},
        {key: "auburn", name: "Auburn", short: "AU", color: "#0C2340", accent: "#E87722", id: "2", path: "football/college-football/teams/2"},
        {key: "falcons", name: "Falcons", short: "ATL", color: "#A71930", id: "1", path: "football/nfl/teams/1"},
        {key: "hawks", name: "Hawks", short: "HWK", color: "#C8102E", id: "1", path: "basketball/nba/teams/1"},
        {key: "braves", name: "Braves", short: "ATL", color: "#13274F", accent: "#CE1141", id: "15", path: "baseball/mlb/teams/15"}
    ]
end function

' ESPN schedule -> [{start, state, home, opp, network, tbd, won, my, their}]
function normEspn(j as dynamic, team as object) as dynamic
    if j = invalid or j.events = invalid then return invalid
    out = []
    for each ev in j.events
        comp = ev.competitions[0]
        mine = invalid
        other = invalid
        for each c in comp.competitors
            if c.team.id = team.id then mine = c else other = c
        end for
        if mine <> invalid and other <> invalid
            opp = other.team.shortDisplayName
            if opp = invalid then opp = other.team.displayName
            network = ""
            if comp.broadcasts <> invalid
                for each b in comp.broadcasts
                    if b.media <> invalid and b.media.shortName <> invalid
                        if network <> "" then network = network + ", "
                        network = network + b.media.shortName
                    end if
                end for
            end if
            won = false
            if mine.winner <> invalid
                if mine.winner = true then won = true
            end if
            tbd = false
            if comp.timeValid <> invalid
                if comp.timeValid = false then tbd = true
            end if
            out.Push({start: tUtcIsoToWall(ev.date), state: comp.status.type.state, home: (mine.homeAway = "home"),
                      opp: opp, network: network, tbd: tbd, won: won, my: scoreOf(mine), their: scoreOf(other)})
        end if
    end for
    return out
end function

function newsQueries() as object
    return ["%22LaGrange%22+GA+when%3A2d", "%22Troup+County%22+when%3A3d", "%22LaGrange+Daily+News%22+when%3A2d"]
end function

function parseNews(bodies as object) as dynamic
    skip = CreateObject("roRegex", "obituar|funeral|legacy\.com|in memory|passed away|\bobit", "i")
    social = CreateObject("roRegex", "instagram|facebook|tiktok|youtube|twitter|nfhs|reddit", "i")
    noise = CreateObject("roRegex", "\bvarsity\b.*@|@.*\bvarsity\b|live (&|and) on demand", "i")
    gentle = CreateObject("roRegex", "shoot|shot\b|killed|murder|homicide|stabb|deadly|fatal|arrest|incident report|charged with|assault", "i")
    localRe = CreateObject("roRegex", "lagrange|troup|west point|hogansville|callaway|pine mountain", "i")
    tail = CreateObject("roRegex", "\s+-\s+[^-]+$", "")
    seen = {}
    out = []
    parsed = 0
    for each body in bodies
        x = CreateObject("roXMLElement")
        if body <> "" and x.Parse(body)
            parsed = parsed + 1
            for each item in x.GetNamedElements("channel").GetNamedElements("item")
                title = item.GetNamedElements("title").GetText()
                source = item.GetNamedElements("source").GetText()
                headline = tail.Replace(title, "").Trim()
                key = LCase(Left(headline, 60))
                ok = not seen.DoesExist(key) and not skip.IsMatch(title + " " + source) and not social.IsMatch(source)
                ok = ok and not noise.IsMatch(title) and localRe.IsMatch(title + " " + source)
                if ok and Instr(1, source, "LaGrange") > 0 and headline.Split(" ").Count() <= 4 then ok = false
                if ok
                    seen[key] = true
                    out.Push({headline: headline, source: source, violent: gentle.IsMatch(title)})
                end if
            end for
        end if
    end for
    if parsed = 0 then return invalid
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

' --- deriving -----------------------------------------------------------------

function derive(cfg as object) as object
    now = tNowWall()
    today = tDay(now)
    d = {version: tNowUtc(), now: now, today: today, household: cfg.household, city: cfg.city, members: cfg.members, apps: cfg.apps}
    d.weather = fresh("weather")
    d.alerts = fresh("alerts")
    d.alertsKnown = d.alerts <> invalid
    if d.alerts = invalid then d.alerts = []
    d.lake = fresh("lake")
    sports = deriveSports(fresh("sports"), now)
    lc = deriveLc(fresh("lc"), now)
    d.games = mergeGames(sports.games, lc.games)
    d.finals = mergeFinals(sports.finals, lc.finals)
    d.rivalry = sports.rivalry
    d.records = sports.records
    cal = deriveCalendar(fresh("calendar"), cfg, now)
    d.calendar = cal.items
    d.notes = cal.notes
    d.groceries = cal.groceries
    d.news = []
    gentleNews = not isFalse(currentSettings().gentleNews)
    news = fresh("news")
    if news <> invalid
        for each n in news
            if not (gentleNews and isTrue(n.violent)) then d.news.Push(n)
        end for
    end if
    d.curb = curbNext(today, cfg.curbWeekday)
    d.birthdays = birthdays(cfg.members, today, 30)
    utc = tNowUtc()
    d.moon = moonPhase(utc - utc mod 3600) ' hourly, so the data doesn't change every minute
    d.shower = nextShower(today, 14)
    d.radarTimes = fresh("radar")
    if d.radarTimes = invalid then d.radarTimes = []
    d.rainSoon = rainSoon(d.weather, now)
    d.asOf = asOfTimes()
    d.tips = headsUp(d)
    d.headsUp = tipTexts(d.tips, {}, 3)
    return d
end function

' Settings from the scene (the menu); defaults off-device.
function currentSettings() as object
    if m.top <> invalid and m.top.settings <> invalid then return m.top.settings
    if m.testSettings <> invalid then return m.testSettings
    return {gentleNews: true}
end function

' Wall-clock fetch times of sources older than twice their refresh interval
' (still within maxAge), for "as of" labels.
function asOfTimes() as object
    out = {}
    limits = sourceLimits()
    offset = tNowWall() - tNowUtc()
    for each name in limits
        t = m.fetched[name]
        if t <> invalid and m.cache[name] <> invalid
            age = tNowUtc() - t
            if age > 2 * limits[name].ttl and age <= limits[name].maxAge then out[name] = t + offset
        end if
    end for
    return out
end function

function normWeather(j as dynamic) as object
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

function normAlerts(j as dynamic) as dynamic
    if j = invalid or j.features = invalid then return invalid
    out = []
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

function normLake(j as dynamic) as dynamic
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
        for each ev in entry.events
            detail = "at " + ev.opp
            if ev.home then detail = "vs " + ev.opp
            if ev.state = "post"
                if ev.won then w = w + 1 else l = l + 1
                if ev.start >= now - 36 * 3600
                    rivalry = (ev.opp = "Auburn" or ev.opp = "Georgia") and (team.key = "georgia" or team.key = "auburn")
                    out.finals.Push({team: team.name, color: team.color, won: ev.won, score: ev.my + "–" + ev.their, detail: detail,
                                     start: ev.start, pro: true, rivalry: rivalry})
                    if rivalry and team.key = "auburn"
                        hi = Val(ev.my)
                        lo = Val(ev.their)
                        winner = "Georgia"
                        loser = "Auburn"
                        if ev.won
                            winner = "Auburn"
                            loser = "Georgia"
                        end if
                        if lo > hi
                            t = hi
                            hi = lo
                            lo = t
                        end if
                        host = ev.opp
                        if ev.home then host = "Auburn"
                        out.rivalry = {winner: winner, loser: loser, hi: hi, lo: lo, network: ev.network, host: host}
                    end if
                end if
            else if ev.start >= now - 4 * 3600 and ev.start <= now + 14 * 86400
                out.games.Push({name: team.name, short: team.short, color: team.color, accent: team.accent,
                                start: ev.start, state: ev.state, detail: detail, network: ev.network, tbd: ev.tbd,
                                my: ev.my, their: ev.their})
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

' College iCal -> [{title, start, allDay, result ("W"/"L"/"T" or ""), us, them}],
' without the long descriptions. Cancelled events are dropped.
function normLc(events as dynamic) as dynamic
    if events = invalid then return invalid
    res = CreateObject("roRegex", "^\[(W|L|T)\]\s*", "")
    score = CreateObject("roRegex", "\\n([WLT]) (\d+)-(\d+)", "")
    out = []
    for each ev in events
        title = ev.summary.Replace("LaGrange College ", "").Trim()
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

function deriveLc(events as dynamic, now as integer) as object
    out = {games: [], finals: []}
    if events = invalid then return out
    for each ev in events
        title = ev.title
        if ev.result <> ""
            if ev.start >= now - 36 * 3600 and ev.start <= now
                out.finals.Push({team: "Panthers", color: "#8E1B24", won: (ev.result = "W"), score: ev.us + "–" + ev.them,
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
    groupRe = CreateObject("roRegex", "\b(both|all) (kids|girls|boys)\b", "i")
    memberRes = []
    for each mem in cfg.members
        memberRes.Push({name: mem.name, re: CreateObject("roRegex", "\b" + mem.name + "\b", "")})
    end for
    today = tDay(now)
    for each ev in events
        if not ev.cancelled
            for each start in icsOccurrences(ev, today - 7 * 86400, today + 21 * 86400)
                title = ev.summary.Trim()
                finish = start + 3600
                if ev.allDay then finish = start + 86400
                if ev.finish <> invalid and ev.finish > ev.start then finish = start + (ev.finish - ev.start)
                who = []
                for each mr in memberRes
                    if mr.re.IsMatch(title) then who.Push(mr.name)
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
                    if groupRe.IsMatch(title) or (isSchool and who.Count() = 0)
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

' Rule-based insights, most important first. Each tip has a priority p, a
' kind (alert, curb, deadline, overlap, rain, frost, birthday, shower, lake)
' and a ref naming what it's about, so a screen can skip tips it already shows.
function headsUp(d as object) as object
    tips = []
    today = d.today
    for each a in d.alerts
        p = 1
        if a.level = "warning" then p = 0
        tips.Push({p: p, kind: "alert", ref: a.event, t: a.event + " for Troup County."})
    end for
    c = d.curb
    n = (c.pickup - today) \ 86400
    if n <= 1 or (tWeekday(d.now) = 0 and n <= 2)
        moved = ""
        if c.holiday <> invalid then moved = " (moved for " + c.holiday + ")"
        extra = "bulky trash"
        if c.yard then extra = "yard waste (no grass clippings)"
        t = tDayWord(c.pickup, today) + moved + ": garbage plus " + extra + ". Curb by 7 AM."
        caveat = curbCaveat(c)
        if caveat <> "" then t = t + " " + caveat + "."
        tips.Push({p: 2, kind: "curb", ref: "curb", t: t})
    end if
    for each e in d.calendar
        dn = (tDay(e.start) - today) \ 86400
        if e.deadline and dn >= 0 and dn <= 7
            t = e.title + " is " + LCase(tDayWord(e.start, today))
            if dn >= 2 then t = e.title + " is " + tDayWord(e.start, today)
            if e.subtitle <> "" then t = t + " (" + e.subtitle + ")"
            if e.who.Count() > 0 then t = t + " for " + e.who.Join(" and ")
            tips.Push({p: 3, kind: "deadline", ref: e.title, t: t + "."})
        end if
    end for
    for i = 0 to d.calendar.Count() - 1
        a = d.calendar[i]
        for j = i + 1 to d.calendar.Count() - 1
            b = d.calendar[j]
            if not a.allDay and not b.allDay and tDay(a.start) = tDay(b.start) and Abs(a.start - b.start) < 5400 and (tDay(a.start) - today) \ 86400 <= 7
                tips.Push({p: 4, kind: "overlap", ref: a.title, t: tDayWord(a.start, today) + ": " + a.title + " and " + b.title + " overlap."})
            end if
        end for
    end for
    if d.weather <> invalid
        for i = 1 to 3
            day = d.weather.days[i]
            if day.rain >= 60 then tips.Push({p: 5, kind: "rain", ref: tKey(day.day), t: "Rain likely " + tDayWord(day.day, today) + " (" + day.rain.ToStr() + "%)."})
            if day.lo <= 34 then tips.Push({p: 5, kind: "frost", ref: tKey(day.day), t: "Frost possible " + tDayWord(day.day, today) + " morning (" + day.lo.ToStr() + "°). Cover tender plants."})
        end for
    end if
    for each b in d.birthdays
        if b.days <= 14 then tips.Push({p: 6, kind: "birthday", ref: b.name + "'s birthday", t: b.name + "'s birthday is " + tDayWord(b.day, today) + "."})
    end for
    if d.shower <> invalid and (d.shower.peak - today) \ 86400 <= 4
        tips.Push({p: 7, kind: "shower", ref: d.shower.name, t: "The " + d.shower.name + " meteor shower peaks " + tDayWord(d.shower.peak, today) + " night. Best before dawn."})
    end if
    if d.lake <> invalid and d.lake.level < 626
        tips.Push({p: 8, kind: "lake", ref: "lake", t: "West Point Lake is low at " + fmt1(d.lake.level) + " ft. Check ramps before launching."})
    end if
    ' SortBy doesn't promise a stable order; sort on priority, then insertion order.
    for i = 0 to tips.Count() - 1
        tips[i].order = tips[i].p * 1000 + i
    end for
    tips.SortBy("order")
    return tips
end function
