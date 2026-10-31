' (DataTask.xml loads every file in components/data/.)
' Daybreak data task: runs for the life of the app. Each minute it fetches
' every source that's due (in parallel), reduces each response to the compact
' form Daybreak uses, and publishes derived data when its content changes.
' The last good data is saved to cachefs: so the next launch starts warm.
' Sources (free, keyless): Open-Meteo, NWS alerts, USGS lake gauge, ESPN team
' schedules (unofficial), LaGrange College iCal, Google News RSS, the family
' Google Calendar (secret iCal), NOAA MRMS radar times, Open-Meteo geocoding
' (game venues by ZIP code) and forecasts at outdoor game venues.

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
    m.bytesTotal = 0 ' downloaded this session, for the network graph
    m.warm = loadCache()
    if m.warm then seedHealth()
    ' warm start: show the saved data right away. Saved data can come from an
    ' older version, so this is guarded like the loop: a crash here would
    ' otherwise end the task and leave the loading screen up for good.
    try
        publish(cfg)
    catch e
        print "Daybreak warm-start error: "; e.message
    end try
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
    m.top.health = {sources: m.health, savedAt: m.lastSave, warm: m.warm, oldCache: m.refetch <> invalid and m.refetch.Count() > 0, cacheBytes: m.cacheBytes, wallpapers: m.wallpaperFiles,
                     bytesTotal: m.bytesTotal}
end sub

' Everything in the data except the clock fields, as JSON.
function dataSignature(d as object) as string
    c = {}
    for each k in d
        if k <> "now" and k <> "version" then c[k] = d[k]
    end for
    return FormatJson(c)
end function

function due(name as string, ttl as integer) as boolean
    if m.refetch <> invalid and m.refetch.DoesExist(name) then return true
    if name = "sports" and liveGame() then ttl = 120 ' scores every 2 minutes during a game
    ' a venue that just appeared needn't wait out the 3 hours (at most every 10 minutes)
    if name = "gamewx" and gameWxMissing()
        h = m.health.gamewx
        return h = invalid or tNowUtc() - h.lastTry >= 600
    end if
    last = m.fetched[name]
    return last = invalid or tNowUtc() - last >= ttl
end function

sub refresh(cfg as object)
    limits = sourceLimits()
    urls = sourceUrls(cfg)
    reqs = []
    for each name in urls
        if urls[name].Count() = 0 and m.refetch <> invalid then m.refetch.Delete(name) ' nothing to fetch
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
            m.bytesTotal = m.bytesTotal + Len(r.body)
            if r.ms > h.ms then h.ms = r.ms
            if r.code = 200 then h.okParts = h.okParts + 1
            if h.code <> 200 then h.code = r.code
            if r.error <> "" then h.error = r.error
        end for
        value = invalid
        m.ingestUrls = []
        for each r in parts
            m.ingestUrls.Push(r.url)
        end for
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
        if m.refetch <> invalid then m.refetch.Delete(name)
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
                j = parseJsonSafe(bodies[i])
                evs = normEspn(j, teams[i])
                if evs <> invalid then out.Push({team: teams[i], events: evs, logo: espnLogo(j)})
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
    if name = "venues" then return normVenues(bodies, m.ingestUrls)
    if name = "gamewx" then return normGameWx(bodies, m.ingestUrls)
    return invalid
end function

' ParseJson for HTTP bodies: an empty or non-JSON body (an error page) is
' invalid without a parser error.
function parseJsonSafe(text as string) as dynamic
    t = text.Trim()
    if t = "" then return invalid
    ' error pages and cut-off downloads aren't JSON
    first = Left(t, 1)
    last = Right(t, 1)
    if not ((first = "{" and last = "}") or (first = "[" and last = "]")) then return invalid
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

' Bump when any source's compact form (what ingest() keeps) changes, so the
' first refresh after an update refetches everything instead of waiting out
' each source's ttl on data in the old shape.
'   3: 1.15, the first stamped cache (1.12 added venue ZIPs to sports)
function cacheSchema() as integer
    return 3
end function

function cachePath() as string
    if m.offDevice = true then return "tmp:/daybreak-cache.json" ' off-device runners have no cachefs:
    return "cachefs:/daybreak-cache.json"
end function

sub saveCache()
    text = FormatJson({v: 2, schema: cacheSchema(), cache: m.cache, fetched: m.fetched})
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
    ' Saved by an older version: keep showing it, but make every source due on
    ' the first refresh. A failed fetch keeps the old data until its maxAge.
    if numOf(j.schema, 0) <> cacheSchema()
        m.refetch = {}
        for each name in sourceLimits()
            m.refetch[name] = true
        end for
    end if
    return true
end function
