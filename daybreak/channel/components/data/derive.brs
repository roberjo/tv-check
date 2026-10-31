' Data task: derive() turns the saved sources into what the screens show.

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
    gwx = fresh("gamewx")
    for each gm in d.games
        gm.wx = kickoffWeather(gm, gwx)
    end for
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
            ' (newsSpam again: headlines saved by an older version weren't checked)
            if not (gentleNews and isTrue(n.violent)) and not newsSpam(strOrEmpty(n.headline)) then d.news.Push(n)
        end for
    end if
    d.curb = invalid
    if d.place.curbside = "lagrange" then d.curb = curbNext(today, cfg.curbWeekday)
    d.birthdays = birthdays(cfg.members, today, 30)
    utc = tNowUtc()
    d.moon = moonPhase(utc - utc mod 3600) ' hourly, so the data doesn't change every minute
    d.shower = nextShower(today, 14)
    d.dst = invalid
    if observesDst(d.place.timezone) then d.dst = dstChange(today, 3)
    d.radarTimes = fresh("radar")
    if d.radarTimes = invalid then d.radarTimes = []
    d.rainSoon = rainSoon(d.weather, now)
    d.air = deriveAir(fresh("air"), now)
    d.storms = deriveStorms(fresh("tropics"), cfg)
    d.countdowns = cal.countdowns
    d.chores = choreTurns(cfg.chores, cfg.members, today)
    d.wallpapers = {}
    picks = wallpaperPicks(fresh("wallpapers"), today, hiddenPhotos())
    for each sc in picks
        wp = picks[sc]
        if haveWallpaper(wp.id) then d.wallpapers[sc] = {id: wp.id, uri: wallpaperPath(wp.id), place: wp.place, credit: wp.credit}
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

' Photos the family hid from the OK menu (ids), so the picks skip them.
function hiddenPhotos() as object
    h = currentSettings().hiddenPhotos
    if type(h) <> "roAssociativeArray" then return {}
    return h
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
