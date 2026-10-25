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
    m.place = placeOf(cfg)
    m.cache = {}
    m.fetched = {}
    m.health = {}
    m.lastSig = ""
    m.lastSave = 0
    m.warm = loadCache()
    if m.warm then seedHealth()
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
            syncWallpapers()
        catch e
            print "Daybreak wallpaper error: "; e.message
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
        calendar: {ttl: 600, maxAge: 24 * 3600}, radar: {ttl: 600, maxAge: 1800},
        air: {ttl: 1800, maxAge: 6 * 3600}, tropics: {ttl: 1800, maxAge: 6 * 3600},
        wallpapers: {ttl: 86400, maxAge: 30 * 86400}
    }
end function

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
        wallpapers: wallpapers
    }
end function

function due(name as string, ttl as integer) as boolean
    if name = "sports" and liveGame() then ttl = 120 ' scores every 2 minutes during a game
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
        ut.AddHeader("User-Agent", "Daybreak home TV dashboard (personal, " + currentPlace().town + " " + currentPlace().region + ")")
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
    if name = "wallpapers" then return normWallpapers(parseJsonSafe(bodies[0]))
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
    if name = "air" then return normAir(parseJsonSafe(bodies[0]))
    if name = "tropics" then return normStorms(parseJsonSafe(bodies[0]))
    return invalid
end function

' ParseJson for HTTP bodies: an empty or non-JSON body (an error page) is
' invalid without a parser error.
function parseJsonSafe(text as string) as dynamic
    t = text.Trim()
    if t = "" or (Left(t, 1) <> "{" and Left(t, 1) <> "[") then return invalid
    return ParseJson(t)
end function

' True while a tracked game is in progress (or should have started in the
' last 4 hours and hasn't finished).
function liveGame() as boolean
    all = m.cache.sports
    if all = invalid then return false
    now = tNowWall()
    for each entry in all
        for each ev in entry.events
            if ev.state = "in" then return true
            if ev.state = "pre" and not ev.tbd and ev.start <= now and ev.start >= now - 4 * 3600 then return true
        end for
    end for
    return false
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

' After a warm start, diagnostics show each saved source as fetched when it
' was saved, until the next fetch replaces the row.
sub seedHealth()
    for each name in m.fetched
        t = m.fetched[name]
        m.health[name] = {ok: true, lastTry: t, lastOk: t, fails: 0, code: 200, ms: invalid, bytes: invalid,
                          error: "", parts: 1, okParts: 1, saved: true}
    end for
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
    ' no cache yet on a first launch; reading a missing file logs an error on the TV
    if m.offDevice <> true and not CreateObject("roFileSystem").Exists(cachePath()) then return false
    j = parseJsonSafe(ReadAsciiFile(cachePath()))
    if j = invalid or j.v <> 2 or j.cache = invalid or j.fetched = invalid then return false
    m.cache = j.cache
    m.fetched = j.fetched
    return true
end function

' --- per-source parsing -----------------------------------------------------------

function espnTeams() as object
    return currentPlace().teams
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
            status = ""
            if comp.status.type.shortDetail <> invalid then status = comp.status.type.shortDetail
            out.Push({start: tUtcIsoToWall(ev.date), state: comp.status.type.state, home: (mine.homeAway = "home"),
                      opp: opp, network: network, tbd: tbd, won: won, my: scoreOf(mine), their: scoreOf(other), status: status})
        end if
    end for
    return out
end function

' Google News queries, already URL-encoded (the build encodes family.json's).
function newsQueries() as object
    return currentPlace().news.queries
end function

function parseNews(bodies as object) as dynamic
    skip = CreateObject("roRegex", "obituar|funeral|legacy\.com|in memory|passed away|\bobit", "i")
    social = CreateObject("roRegex", "instagram|facebook|tiktok|youtube|twitter|nfhs|reddit", "i")
    noise = CreateObject("roRegex", "\bvarsity\b.*@|@.*\bvarsity\b|live (&|and) on demand", "i")
    gentle = CreateObject("roRegex", "shoot|shot\b|killed|murder|homicide|stabb|deadly|fatal|arrest|incident report|charged with|assault", "i")
    localRe = CreateObject("roRegex", currentPlace().news.local, "i")
    ownSource = currentPlace().news.ownSource
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
                ' very short headlines from the town's own paper are section labels, not news
                if ok and ownSource <> invalid and Instr(1, source, ownSource) > 0 and headline.Split(" ").Count() <= 4 then ok = false
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
    d.place = currentPlace()
    d.home = {lat: cfg.lat, lon: cfg.lon}
    d.weather = fresh("weather")
    d.alerts = fresh("alerts")
    d.alertsKnown = d.alerts <> invalid
    if d.alerts = invalid then d.alerts = []
    ' expired alerts drop out (alerts refresh every 2 minutes, but the cache can lag)
    live = []
    for each a in d.alerts
        if a.expires = invalid or a.expires = 0 or a.expires > now then live.Push(a)
    end for
    d.alerts = live
    d.takeover = takeoverAlert(d.alerts, now)
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
    d.curb = invalid
    if d.place.curbside = "lagrange" then d.curb = curbNext(today, cfg.curbWeekday)
    d.birthdays = birthdays(cfg.members, today, 30)
    utc = tNowUtc()
    d.moon = moonPhase(utc - utc mod 3600) ' hourly, so the data doesn't change every minute
    d.shower = nextShower(today, 14)
    d.radarTimes = fresh("radar")
    if d.radarTimes = invalid then d.radarTimes = []
    d.rainSoon = rainSoon(d.weather, now)
    d.air = deriveAir(fresh("air"), now)
    d.storms = deriveStorms(fresh("tropics"), cfg)
    d.countdowns = cal.countdowns
    d.chores = choreTurns(cfg.chores, cfg.members, today)
    d.wallpapers = {}
    picks = wallpaperPicks(fresh("wallpapers"), today)
    for each sc in picks
        wp = picks[sc]
        if haveWallpaper(wp.id) then d.wallpapers[sc] = {uri: wallpaperPath(wp.id), place: wp.place, credit: wp.credit}
    end for
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
        p = f.properties
        expires = 0
        if p.expires <> invalid then expires = tLocalIsoToWall(p.expires) ' NWS gives local time with its offset
        if p.ends <> invalid then expires = tLocalIsoToWall(p.ends)
        out.Push({event: ev, level: level, headline: strOrEmpty(p.headline), instruction: Left(strOrEmpty(p.instruction).Replace(Chr(10), " "), 420), expires: expires})
    end for
    return out
end function

' Warnings that take over the screen (app and screensaver) until they expire.
function takeoverEvents() as object
    return {"Tornado Warning": true, "Severe Thunderstorm Warning": true, "Flash Flood Warning": true,
            "Extreme Wind Warning": true, "Hurricane Warning": true, "Tornado Emergency": true, "Flash Flood Emergency": true}
end function

function takeoverAlert(alerts as object, now as integer) as dynamic
    events = takeoverEvents()
    for each a in alerts
        if events.DoesExist(a.event) and (a.expires = invalid or a.expires = 0 or a.expires > now) then return a
    end for
    return invalid
end function

function normLake(j as dynamic) as dynamic
    if j = invalid then return invalid
    ts = j.value.timeSeries
    if ts = invalid or ts.Count() = 0 then return invalid
    vals = ts[0].values[0].value
    v = vals[vals.Count() - 1]
    return {level: Val(v.value), time: tLocalIsoToWall(v.dateTime)}
end function

' rivalry: the place's pair of tracked team names ([a, b]); a final between
' them becomes the "house divided" result.
function deriveSports(all as dynamic, now as integer) as object
    out = {games: [], finals: [], rivalry: invalid, records: {}}
    if all = invalid then return out
    pair = currentPlace().rivalry
    rivA = ""
    rivB = ""
    if pair <> invalid and pair.Count() = 2
        rivA = pair[0]
        rivB = pair[1]
    end if
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
                    rivalry = rivA <> "" and (ev.opp = rivA or ev.opp = rivB) and (team.name = rivA or team.name = rivB)
                    out.finals.Push({team: team.name, color: team.color, won: ev.won, score: ev.my + "–" + ev.their, detail: detail,
                                     start: ev.start, pro: true, rivalry: rivalry})
                    if rivalry and team.name = rivB
                        hi = Val(ev.my)
                        lo = Val(ev.their)
                        winner = rivA
                        loser = rivB
                        if ev.won
                            winner = rivB
                            loser = rivA
                        end if
                        if lo > hi
                            t = hi
                            hi = lo
                            lo = t
                        end if
                        host = ev.opp
                        if ev.home then host = rivB
                        out.rivalry = {winner: winner, loser: loser, hi: hi, lo: lo, network: ev.network, host: host}
                    end if
                end if
            else if ev.start >= now - 4 * 3600 and ev.start <= now + 14 * 86400
                out.games.Push({name: team.name, short: team.short, color: team.color, accent: team.accent,
                                start: ev.start, state: ev.state, detail: detail, network: ev.network, tbd: ev.tbd,
                                my: ev.my, their: ev.their, status: ev.status})
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

function deriveLc(events as dynamic, now as integer) as object
    out = {games: [], finals: []}
    c = currentPlace().college
    if events = invalid or c = invalid then return out
    for each ev in events
        title = ev.title
        if ev.result <> ""
            if ev.start >= now - 36 * 3600 and ev.start <= now
                out.finals.Push({team: c.team, color: c.color, won: (ev.result = "W"), score: ev.us + "–" + ev.them,
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
                out.games.Push({name: c.team + " " + sport, short: c.short, color: c.color, accent: invalid,
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
    out = {items: [], notes: [], groceries: [], countdowns: []}
    if events = invalid then return out
    health = CreateObject("roRegex", "doctor|pediatric|well-?check|dentist|dental|orthodont|flu shot|vaccin|clinic|hospital|therap|physical|appointment|wellstar|medical|urgent care|derm|optom|eye exam", "i")
    school = CreateObject("roRegex", "\bSAT\b|\bACT\b|PSAT|school|exam|report card|early release|band|homecoming|graduation|registration|teacher|class|semester", "i")
    deadline = CreateObject("roRegex", "deadline|due|closes", "i")
    ' closings and schedule changes, added by the family when the district announces them
    closing = CreateObject("roRegex", "\bno school\b|school(s)? (closed|closing|cancel)|early release|early dismissal|delayed (opening|start)|late start|virtual (learning )?day|e-?learning day", "i")
    both = CreateObject("roRegex", "\s*[—-]\s*(both|all) (kids|girls|boys)\s*$", "i")
    groupRe = CreateObject("roRegex", "\b(both|all) (kids|girls|boys)\b", "i")
    memberRes = []
    for each mem in cfg.members
        memberRes.Push({name: mem.name, re: CreateObject("roRegex", "\b" + mem.name + "\b", "")})
    end for
    today = tDay(now)
    for each ev in events
        if not ev.cancelled and UCase(Left(ev.summary.Trim(), 10)) = "COUNTDOWN:"
            ' "Countdown: Beach trip": days until its next occurrence, up to a year out
            occ = icsOccurrences(ev, today, today + 366 * 86400)
            if occ.Count() > 0
                out.countdowns.Push({title: Mid(ev.summary.Trim(), 11).Trim(), day: tDay(occ[0]), days: (tDay(occ[0]) - today) \ 86400})
            end if
        else if not ev.cancelled
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
                                    color: colorFor(who, cfg), health: isHealth, school: isSchool or closing.IsMatch(title),
                                    closing: closing.IsMatch(title) and not isHealth,
                                    deadline: deadline.IsMatch(title) and not isHealth})
                end if
            end for
        end if
    end for
    out.items.SortBy("start")
    out.countdowns.SortBy("days")
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
        tips.Push({p: p, kind: "alert", ref: a.event, t: a.event + " for " + d.place.area + "."})
    end for
    c = d.curb
    n = 99
    if c <> invalid then n = (c.pickup - today) \ 86400
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
    ' school closings and early releases today or tomorrow come right after warnings
    for each e in d.calendar
        dn = (tDay(e.start) - today) \ 86400
        if isTrue(e.closing) and dn >= 0 and dn <= 1
            t = tDayWord(e.start, today) + ": " + e.title
            if not e.allDay then t = t + " at " + tClock(e.start)
            if e.subtitle <> "" then t = t + " (" + e.subtitle + ")"
            tips.Push({p: 1, kind: "school", ref: e.title, t: t + "."})
        end if
    end for
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
    if d.air <> invalid and d.air.peak >= 101
        tips.Push({p: 5, kind: "air", ref: "air", t: "Air quality " + LCase(aqiLabel(d.air.peak)) + " " + tDayWord(d.air.peakAt, today) + " (AQI " + d.air.peak.ToStr() + "). Limit time outdoors if sensitive."})
    end if
    for each c in d.countdowns
        if c.days > 0 and c.days <= 14 then tips.Push({p: 6, kind: "countdown", ref: c.title, t: c.title + " is in " + c.days.ToStr() + " days."})
        if c.days = 0 then tips.Push({p: 6, kind: "countdown", ref: c.title, t: c.title + " is today!"})
    end for
    for each st in d.storms
        p = 7
        if st.miles <= 500 then p = 3
        tips.Push({p: p, kind: "tropics", ref: st.name, t: st.kind + " " + st.name + " (" + st.mph.ToStr() + " mph) is " + st.miles.ToStr() + " mi from " + d.place.town + "."})
    end for
    if d.lake <> invalid and d.place.lake <> invalid and d.lake.level < d.place.lake.lowAlert
        tips.Push({p: 8, kind: "lake", ref: "lake", t: d.place.lake.name + " is low at " + fmt1(d.lake.level) + " ft. Check ramps before launching."})
    end if
    ' SortBy doesn't promise a stable order; sort on priority, then insertion order.
    for i = 0 to tips.Count() - 1
        tips[i].order = tips[i].p * 1000 + i
    end for
    tips.SortBy("order")
    return tips
end function

' --- air quality and the tropics ------------------------------------------------------

' Open-Meteo air quality -> {aqi (now), pm25, hours: [{t, aqi}]}
function normAir(j as dynamic) as dynamic
    if j = invalid or j.current = invalid or j.current.us_aqi = invalid then return invalid
    hours = []
    if j.hourly <> invalid and j.hourly.us_aqi <> invalid
        for i = 0 to j.hourly.time.Count() - 1
            if j.hourly.us_aqi[i] <> invalid then hours.Push({t: tLocalIsoToWall(j.hourly.time[i]), aqi: Int(j.hourly.us_aqi[i])})
        end for
    end if
    return {aqi: Int(j.current.us_aqi), pm25: numOr(j.current.pm2_5, 0), hours: hours}
end function

' Now, and the worst hour in the next 24 (for the heads-up).
function deriveAir(a as dynamic, now as integer) as dynamic
    if a = invalid then return invalid
    peak = a.aqi
    peakAt = now
    for each h in a.hours
        if h.t > now and h.t <= now + 24 * 3600 and h.aqi > peak
            peak = h.aqi
            peakAt = h.t
        end if
    end for
    return {aqi: a.aqi, label: aqiLabel(a.aqi), peak: peak, peakAt: peakAt}
end function

' US AQI categories (EPA).
function aqiLabel(aqi as integer) as string
    if aqi <= 50 then return "Good"
    if aqi <= 100 then return "Moderate"
    if aqi <= 150 then return "Unhealthy for sensitive groups"
    if aqi <= 200 then return "Unhealthy"
    if aqi <= 300 then return "Very unhealthy"
    return "Hazardous"
end function

' NHC CurrentStorms.json -> Atlantic storms [{name, kind, mph, lat, lon}]
function normStorms(j as dynamic) as dynamic
    if j = invalid or j.activeStorms = invalid then return invalid
    kinds = {HU: "Hurricane", TS: "Tropical Storm", TD: "Tropical Depression", STS: "Subtropical Storm",
             STD: "Subtropical Depression", PTC: "Potential Tropical Cyclone", PC: "Post-tropical cyclone"}
    out = []
    for each s in j.activeStorms
        bin = ""
        if s.binNumber <> invalid then bin = s.binNumber
        if Left(bin, 2) = "AT"
            kind = kinds[s.classification]
            if kind = invalid then kind = "Storm"
            kt = Val(strOrEmpty(s.intensity))
            out.Push({name: s.name, kind: kind, mph: Int(kt * 1.15078 + 0.5), lat: s.latitudeNumeric, lon: s.longitudeNumeric})
        end if
    end for
    return out
end function

function strOrEmpty(v as dynamic) as string
    if v = invalid then return ""
    if type(v) = "roString" or type(v) = "String" then return v
    return v.ToStr()
end function

' Storms with their great-circle distance from home in miles, nearest first.
function deriveStorms(storms as dynamic, cfg as object) as object
    out = []
    if storms = invalid then return out
    for each s in storms
        if s.lat <> invalid and s.lon <> invalid
            st = {}
            st.Append(s)
            st.miles = milesBetween(cfg.lat, cfg.lon, s.lat, s.lon)
            out.Push(st)
        end if
    end for
    out.SortBy("miles")
    return out
end function

function milesBetween(lat1 as float, lon1 as float, lat2 as float, lon2 as float) as integer
    r = 3958.8
    k = 3.14159265 / 180
    dLat = (lat2 - lat1) * k
    dLon = (lon2 - lon1) * k
    a = Sin(dLat / 2) * Sin(dLat / 2) + Cos(lat1 * k) * Cos(lat2 * k) * Sin(dLon / 2) * Sin(dLon / 2)
    c = 2 * Atn(Sqr(a) / Sqr(1 - a))
    return Int(r * c + 0.5)
end function

' --- wallpapers ------------------------------------------------------------------------
' Photo backgrounds come from a catalog (daybreak/wallpapers, served from the
' repo): the TV fetches it daily, picks a photo per screen per day, and
' downloads today's and tomorrow's picks into cachefs: in the background.

' Catalog -> [{id, file, place, credit, tags, screens}]. Ids become file names
' on the TV, so only lowercase letters, digits and dashes pass.
function normWallpapers(j as dynamic) as dynamic
    if j = invalid or type(j.photos) <> "roArray" then return invalid
    safeId = CreateObject("roRegex", "^[a-z0-9-]{1,40}$", "")
    safeFile = CreateObject("roRegex", "^img/[a-z0-9-]{1,40}\.jpg$", "")
    out = []
    for each p in j.photos
        if out.Count() < 100 and type(p) = "roAssociativeArray" and isText(p.id) and isText(p.file)
            if safeId.IsMatch(p.id) and safeFile.IsMatch(p.file) and type(p.screens) = "roArray"
                out.Push({id: p.id, file: p.file, place: Left(strOrEmpty(p.place), 60), credit: Left(strOrEmpty(p.credit), 80),
                          tags: textList(p.tags), screens: textList(p.screens)})
            end if
        end if
    end for
    return out
end function

function isText(v as dynamic) as boolean
    return v <> invalid and GetInterface(v, "ifString") <> invalid
end function

function textList(v as dynamic) as object
    out = []
    if type(v) = "roArray"
        for each x in v
            if isText(x) then out.Push(x)
        end for
    end if
    return out
end function

function hasItem(list as object, v as string) as boolean
    for each x in list
        if x = v then return true
    end for
    return false
end function

' Screens that can show a wallpaper, in pick order.
function wallpaperScreens() as object
    return ["ambient", "briefing", "season", "tonight", "week", "recap", "lake", "school", "board"]
end function

' A photo for each screen on this day: different photos on different screens,
' changing daily. A photo only goes behind screens it passed the contrast
' audit on (its screens list), and the lake screen takes lake photos.
function wallpaperPicks(photos as dynamic, day as integer) as object
    picks = {}
    if photos = invalid then return picks
    used = {}
    n = day \ 86400
    screens = wallpaperScreens()
    for si = 0 to screens.Count() - 1
        sc = screens[si]
        cands = []
        for each p in photos
            if hasItem(p.screens, sc) and (sc <> "lake" or hasItem(p.tags, "lake")) then cands.Push(p)
        end for
        if cands.Count() > 0
            start = (n * 7 + si * 5) mod cands.Count()
            pick = invalid
            for k = 0 to cands.Count() - 1
                c = cands[(start + k) mod cands.Count()]
                if pick = invalid and not used.DoesExist(c.id) then pick = c
            end for
            if pick = invalid then pick = cands[start] ' fewer photos than screens: repeat one
            used[pick.id] = true
            picks[sc] = pick
        end if
    end for
    return picks
end function

function wallpaperPath(id as string) as string
    return "cachefs:/wp-" + id + ".jpg"
end function

function haveWallpaper(id as string) as boolean
    if m.offDevice = true then return m.testWallpapers <> invalid and m.testWallpapers.DoesExist(id)
    return CreateObject("roFileSystem").Exists(wallpaperPath(id))
end function

' Downloads today's and tomorrow's photos, at most 3 per refresh so a slow
' connection never holds up the data, and deletes any other saved photos.
sub syncWallpapers()
    photos = fresh("wallpapers")
    base = currentPlace().wallpapers
    if photos = invalid or base = invalid or m.offDevice = true then return
    today = tDay(tNowWall())
    keep = {}
    for each day in [today, today + 86400]
        picks = wallpaperPicks(photos, day)
        for each sc in picks
            keep[picks[sc].id] = picks[sc]
        end for
    end for
    fs = CreateObject("roFileSystem")
    for each f in fs.GetDirectoryListing("cachefs:/")
        if Left(f, 3) = "wp-" and (Right(f, 4) <> ".jpg" or not keep.DoesExist(Mid(f, 4, Len(f) - 7))) then fs.Delete("cachefs:/" + f)
    end for
    budget = 3
    for each id in keep
        if budget > 0 and not fs.Exists(wallpaperPath(id))
            budget = budget - 1
            downloadWallpaper(base + keep[id].file, wallpaperPath(id))
        end if
    end for
end sub

' Saves under a temporary name and keeps the file only if it arrived whole.
sub downloadWallpaper(url as string, path as string)
    tmp = path + ".part"
    ut = CreateObject("roUrlTransfer")
    ut.SetUrl(url)
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.SetMinimumTransferRate(4096, 20) ' give up on a stalled transfer
    code = ut.GetToFile(tmp)
    fs = CreateObject("roFileSystem")
    st = fs.Stat(tmp)
    if code = 200 and st <> invalid and st.size > 20000 then fs.Rename(tmp, path) else fs.Delete(tmp)
end sub
