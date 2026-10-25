' Daybreak screens, built natively from the DataTask's derived data. Layouts
' mirror daybreak/service/screens.py (the reference renderer on the Mac).

' --- which screens, in what order ----------------------------------------------

function availableScreens(d as object) as object
    a = {ambient: true, briefing: true, tonight: true, week: true, sky: true, school: true, radar: true}
    if d.weather = invalid
        a.Delete("briefing")
        a.Delete("ambient")
        a.Delete("week")
    end if
    if d.lake <> invalid then a.lake = true
    if d.finals.Count() > 0 then a.recap = true
    if soonGames(d).Count() > 0 then a.gameday = true
    if d.notes.Count() > 0 or d.groceries.Count() > 0 then a.board = true
    if seasonItems(tParts(d.now).m) <> invalid then a.season = true
    return a
end function

function chooseScreens(d as object, mode as string) as object
    a = availableScreens(d)
    h = tHour(d.now)
    wd = tWeekday(d.now)
    warning = false
    for each al in d.alerts
        if al.level = "warning" then warning = true
    end for
    order = []
    if warning then order.Push("radar")
    order.Push("gameday")
    if h >= 4 and h < 11
        order.Append(["briefing", "recap"])
        if wd >= 1 and wd <= 5 then order.Push("school")
    else if h >= 11 and h < 17
        if h < 14 then order.Push("recap")
        order.Push("ambient")
        if wd = 0 or wd = 6 or (d.weather <> invalid and d.weather.days[0].rain < 30) then order.Push("lake")
        order.Push("season")
    else
        order.Push("tonight")
        recent = false
        for each f in d.finals
            if f.start >= d.now - 10 * 3600 then recent = true
        end for
        if recent then order.Push("recap")
        if wd = 0 or wd = 6 then order.Push("week")
        if wd = 0 or wd <= 4 then order.Push("school")
        order.Push("sky")
    end if
    if d.rainSoon or warning then order.Unshift("radar")
    order.Append(["board", "week", "radar", "lake", "sky", "recap", "season", "ambient", "briefing"])
    seen = {}
    out = []
    for each s in order
        if a.DoesExist(s) and not seen.DoesExist(s)
            seen[s] = true
            out.Push(s)
        end if
    end for
    if mode = "screensaver"
        ss = ["ambient"]
        for each s in out
            if ss.Count() < 4 and s <> "ambient" and s <> "board" then ss.Push(s)
        end for
        return ss
    end if
    return out
end function

function screenSeconds(id as string) as integer
    if id = "briefing" or id = "week" or id = "tonight" then return 30
    if id = "radar" then return 16
    return 20
end function

function buildScreen(id as string, d as object) as object
    m.clockNodes = invalid
    m.radarFrames = invalid
    g = CreateObject("roSGNode", "Group")
    if id = "ambient" then buildAmbient(g, d)
    if id = "briefing" then buildBriefing(g, d)
    if id = "tonight" then buildTonight(g, d)
    if id = "week" then buildWeek(g, d)
    if id = "lake" then buildLake(g, d)
    if id = "sky" then buildSky(g, d)
    if id = "recap" then buildRecap(g, d)
    if id = "gameday" then buildGameday(g, d)
    if id = "school" then buildSchool(g, d)
    if id = "board" then buildBoard(g, d)
    if id = "season" then buildSeason(g, d)
    if id = "radar" then buildRadar(g, d)
    return g
end function

' --- shared pieces ----------------------------------------------------------------

function greeting(d as object) as string
    h = tHour(d.now)
    part = "evening"
    if h >= 4 and h < 12
        part = "morning"
    else if h >= 12 and h < 17
        part = "afternoon"
    end if
    return "Good " + part + ", " + d.household
end function

sub header(g as object, eyebrow as string, title as string, accent = "#F4A259" as string, withClock = true as boolean)
    uiLabel(g, 112, 62, eyebrow, 24, accent)
    w = 1696
    if withClock then w = 1200
    uiText(g, 112, 100, title, 76, 500, "Outfit", "#F4F1EA", w)
    if withClock then addClock(g, 1808, 82, 104, 300, "right")
end sub

sub addClock(g as object, x as integer, y as integer, size as integer, weight as integer, align as string)
    clock = uiText(g, x, y, "", size, weight, "Outfit")
    ampm = uiText(g, x, y, "", Int(size * 0.33), 300, "Outfit", "#C9CEDA")
    m.clockNodes = {clock: clock, ampm: ampm, x: x, y: y, size: size, align: align}
end sub

sub updateClock()
    c = m.clockNodes
    if c = invalid then return
    now = tNowWall()
    h = tHour(now)
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    c.clock.text = h12.ToStr() + ":" + tPad((now mod 3600) \ 60, 2)
    c.ampm.text = suffix
    cw = uiWidth(c.clock, c.size)
    aw = uiWidth(c.ampm, Int(c.size * 0.33))
    drop = Int(c.size * 0.6)
    if c.align = "right"
        c.ampm.translation = [c.x - aw, c.y + drop]
        c.clock.translation = [c.x - aw - 16 - cw, c.y]
    else
        c.clock.translation = [c.x, c.y]
        c.ampm.translation = [c.x + cw + 20, c.y + drop]
    end if
end sub

' Full-screen photo, or a plain fill when memory is low (a decoded 1080p photo is 8 MB).
sub uiBackdrop(g as object, uri as string, fallback as string)
    if m.lowMemory = true then uiRect(g, 0, 0, 1920, 1080, fallback) else uiImage(g, uri, 0, 0, 1920, 1080)
end sub

' Small right-aligned amber "as of" note in a card header (nothing when fresh).
sub asOfTag(g as object, xRight as integer, y as integer, text as string)
    if text <> "" then uiText(g, xRight, y, text, 20, 600, "Manrope", "#F4A259", 240, "right")
end sub

' "as of 9:40 AM" when a source's data is older than twice its refresh interval.
function asOfText(d as object, source as string) as string
    if d.asOf = invalid or d.asOf[source] = invalid then return ""
    return "as of " + tClock(d.asOf[source])
end function

function soonGames(d as object) as object
    out = []
    for each gm in d.games
        if gm.short <> "LC" and not gm.tbd and (gm.state = "in" or (gm.start - d.now) <= 6 * 3600) then out.Push(gm)
    end for
    return out
end function

function gameWhen(gm as object, today as integer) as string
    if gm.state = "in" then return "Live now"
    if gm.tbd then return tDayWord(gm.start, today) + " · time TBA"
    return tDayWord(gm.start, today) + " " + tClock(gm.start)
end function

function curbText(c as object) as string
    return "Garbage + " + c.extra
end function

sub sunArc(g as object, x as float, y as float, w as float, h as float, uri as string, d as object, dotR as float)
    uiImage(g, uri, x, y, w, h)
    day = d.weather.days[0]
    frac = (d.now - day.sunrise) / (day.sunset - day.sunrise)
    if frac > 0 and frac < 1
        px = x + w * frac
        py = y + h - 4 - (h - 8) * 4 * frac * (1 - frac)
        uiDot(g, px, py, dotR * 2.1, "#F4A259", 0.16)
        uiDot(g, px, py, dotR, "#F4A259")
    end if
end sub

' --- screens ------------------------------------------------------------------------

sub buildAmbient(g as object, d as object)
    uiBackdrop(g, "pkg:/images/bg_ambient.jpg", "#0B1120")
    w = d.weather
    today = w.days[0]
    addClock(g, 160, 96, 300, 200, "left")
    uiText(g, 160, 404, tLongDate(d.now), 38, 500, "Manrope", "#E1E4EC")
    kind = wxKind(w.code)
    if tHour(d.now) >= 19 or tHour(d.now) < 6 then kind = "moon"
    uiImage(g, "pkg:/images/wx_" + kind + ".png", 1440, 136, 104, 104, "#F4A259")
    uiText(g, 1760, 128, w.temp.ToStr() + "°", 96, 300, "Outfit", "#F4F1EA", 300, "right")
    uiText(g, 1760, 258, wxLabel(w.code) + " · high " + today.hi.ToStr() + "°", 30, 400, "Manrope", "#E1E4EC", 700, "right")
    city = d.city
    if asOfText(d, "weather") <> "" then city = city + " · weather " + asOfText(d, "weather")
    uiText(g, 1760, 302, city, 24, 400, "Manrope", "#E1E4EC", 700, "right")
    sunArc(g, 200, 690, 1520, 190, "pkg:/images/arc_ambient.png", d, 16)
    uiRect(g, 160, 880, 1600, 2, "#F4F1EA", 0.25)
    len = today.sunset - today.sunrise
    uiText(g, 160, 920, "Sunrise " + tClock(today.sunrise) + "      " + (len \ 3600).ToStr() + " h " + ((len mod 3600) \ 60).ToStr() + " m of daylight      Sunset " + tClock(today.sunset), 26, 400, "Manrope", "#E1E4EC")
    uiText(g, 160, 968, "Reflection pool, Callaway Gardens · Pine Mountain, GA", 20, 400, "Manrope", "#E1E4EC")
    nxt = nextUp(d)
    if nxt <> ""
        tw = uiTextWidth(g, nxt, 26, 600)
        uiCard(g, 1760 - tw - 80, 928, tw + 80, 64, "#070B14", "#3A3F4C", 32, 0.82)
        uiDot(g, 1760 - tw - 48, 960, 7, "#F4A259")
        uiText(g, 1760 - 28, 943, nxt, 26, 600, "Manrope", "#F4F1EA", Int(tw) + 4, "right")
    end if
end sub

function nextUp(d as object) as string
    for each gm in d.games
        if gm.short <> "LC" and not gm.tbd
            if gm.state = "in" then return gm.name + " " + gm.detail + " is on now"
            delta = gm.start - d.now
            if delta > 0 and delta < 12 * 3600 then return gm.name + " in " + (delta \ 3600).ToStr() + " h " + ((delta mod 3600) \ 60).ToStr() + " m"
        end if
    end for
    if (d.curb.pickup - d.today) \ 86400 <= 1 then return tDayWord(d.curb.pickup, d.today) + ": " + LCase(curbText(d.curb))
    for each e in d.calendar
        if e.start >= d.now - 3600 then return tDayWord(e.start, d.today) + ": " + e.title
    end for
    return ""
end function

sub weatherCard(g as object, x as integer, y as integer, w as integer, h as integer, d as object)
    wx = d.weather
    today = wx.days[0]
    uiCard(g, x, y, w, h)
    uiImage(g, "pkg:/images/wx_sun.png", x + 36, y + 34, 44, 44, "#A9B1C4")
    uiLabel(g, x + 90, y + 44, "Weather")
    asOfTag(g, x + w - 40, y + 44, asOfText(d, "weather"))
    uiText(g, x + 40, y + 96, wx.temp.ToStr() + "°", 168, 300, "Outfit")
    uiText(g, x + 330, y + 150, wxLabel(wx.code), 36, 600, "Manrope", "#F4F1EA", w - 360)
    uiText(g, x + 330, y + 200, "High " + today.hi.ToStr() + "° · low " + today.lo.ToStr() + "°", 26, 400, "Manrope", "#A9B1C4", w - 360)
    hours = []
    for each hr in wx.hours
        if hr.t > d.now and hours.Count() < 5 and ((hr.t - d.now) \ 3600) mod 3 = 0 then hours.Push(hr)
    end for
    cw = Int((w - 88 - 48) / 5)
    for i = 0 to hours.Count() - 1
        cx = x + 44 + i * (cw + 12)
        uiCard(g, cx, y + 300, cw, 96, "#1A2440", "", 18)
        uiText(g, cx + cw / 2, y + 314, tClock(hours[i].t).Replace(":00", ""), 22, 400, "Manrope", "#A9B1C4", cw, "center")
        uiText(g, cx + cw / 2, y + 344, hours[i].temp.ToStr() + "°", 34, 400, "Outfit", "#F4F1EA", cw, "center")
    end for
    sunArc(g, x + 48, y + h - 128, w - 96, 56, "pkg:/images/arc_card.png", d, 9)
    uiText(g, x + 44, y + h - 56, "Sunrise " + tClock(today.sunrise), 22, 400, "Manrope", "#A9B1C4")
    uiText(g, x + w - 44, y + h - 56, "Sunset " + tClock(today.sunset), 22, 400, "Manrope", "#A9B1C4", 260, "right")
end sub

sub buildBriefing(g as object, d as object)
    uiBackdrop(g, "pkg:/images/bg_briefing.jpg", "#0B1120")
    header(g, UCase(tLongDate(d.now)) + " · LAGRANGE, GA", greeting(d))
    top = 246
    weatherCard(g, 112, top, 600, 540, d)
    ' calendar
    x = 744
    w = 532
    uiCard(g, x, top, w, 540)
    uiLabel(g, x + 40, top + 44, "Family calendar")
    asOfTag(g, x + w - 40, top + 44, asOfText(d, "calendar"))
    rows = briefingRows(d)
    shownRefs = {}
    yy = top + 98
    for i = 0 to rows.Count() - 1
        if i < 4
            r = rows[i]
            shownRefs[r.ref] = true
            uiText(g, x + 40, yy, r.when, 22, 700, "Manrope", "#F4A259", w - 80)
            uiText(g, x + 40, yy + 30, r.title, 28, 600, "Manrope", "#F4F1EA", w - 80)
            uiDot(g, x + 47, yy + 82, 6, r.color)
            uiText(g, x + 62, yy + 69, r.sub, 21, 400, "Manrope", "#A9B1C4", w - 102)
            yy = yy + 106
        end if
    end for
    if rows.Count() = 0 then uiText(g, x + 40, yy, "Nothing on the calendar this week.", 26, 400, "Manrope", "#A9B1C4", w - 80)
    ' game watch: next game per team
    x = 1308
    uiCard(g, x, top, w, 540)
    uiLabel(g, x + 40, top + 44, "Game watch")
    asOfTag(g, x + w - 40, top + 44, asOfText(d, "sports"))
    seen = {}
    yy = top + 98
    shown = 0
    for each gm in d.games
        if not seen.DoesExist(gm.name) and shown < 6
            seen[gm.name] = true
            teamChip(g, x + 36, yy, 50, gm.short, gm.color, gm.accent)
            uiText(g, x + 104, yy - 4, gm.name, 25, 600, "Manrope", "#F4F1EA", w - 140)
            tail = ""
            if gm.network <> "" then tail = " · " + gm.network
            uiText(g, x + 104, yy + 28, gameWhen(gm, d.today) + " · " + gm.detail + tail, 20, 400, "Manrope", "#A9B1C4", w - 140)
            yy = yy + 70
            shown = shown + 1
        end if
    end for
    ' headlines + heads up
    fy = 818
    uiCard(g, 112, fy, 1110, 200)
    uiLabel(g, 152, fy + 28, "LaGrange today", 20)
    for i = 0 to 2
        if i < d.news.Count()
            nx = 152 + i * 350
            uiText(g, nx, fy + 66, UCase(Left(d.news[i].source, 26)), 16, 700, "Manrope", "#F4A259", 320)
            uiText(g, nx, fy + 92, d.news[i].headline, 23, 500, "Manrope", "#F4F1EA", 320, "left", 3)
        end if
    end for
    hx = 1254
    uiCard(g, hx, fy, 554, 200, "#1A2440", "#2A3656")
    uiLabel(g, hx + 36, fy + 28, "Heads up", 20, "#F4A259")
    yy = fy + 66
    for each t in tipTexts(d.tips, shownRefs, 2)
        l = uiText(g, hx + 36, yy, t, 23, 500, "Manrope", "#F4F1EA", 482, "left", 2)
        yy = yy + uiHeight(l, 23) + 10
    end for
end sub

' Briefing calendar rows in time order: curbside counts as 7 AM on pickup day,
' all-day events and birthdays as the start of their day. ref matches the
' heads-up tip about the same thing.
function briefingRows(d as object) as object
    rows = []
    if (d.curb.pickup - d.today) \ 86400 <= 3
        sub2 = "Curb by 7 AM"
        if d.curb.holiday <> invalid then sub2 = sub2 + " · moved for " + d.curb.holiday
        caveat = curbCaveat(d.curb)
        if caveat <> "" then sub2 = sub2 + " · " + caveat
        rows.Push({when: tDayWord(d.curb.pickup, d.today), title: curbText(d.curb), sub: sub2, color: "#F4A259",
                   sort: d.curb.pickup + 7 * 3600, ref: "curb"})
    end if
    for each e in d.calendar
        if e.start >= d.now - 3600 or (e.allDay and e.start >= d.today)
            when = tDayWord(e.start, d.today)
            if not e.allDay then when = when + " " + tClock(e.start).Replace(":00", "")
            s = e.whoText
            if e.subtitle <> "" then s = s + " · " + e.subtitle
            rows.Push({when: when, title: e.title, sub: s, color: e.color, sort: e.start, ref: e.title})
        end if
    end for
    for each b in d.birthdays
        ref = b.name + "'s birthday"
        rows.Push({when: tDayWord(b.day, d.today), title: ref, sub: "Celebrate!", color: b.color, sort: b.day, ref: ref})
    end for
    return sortStable(rows, "sort")
end function

' Insertion sort that keeps equal items in their original order (SortBy
' doesn't promise that). Fine for the short lists screens use.
function sortStable(items as object, key as string) as object
    out = []
    for each it in items
        k = out.Count()
        while k > 0 and out[k - 1][key] > it[key]
            k = k - 1
        end while
        out.Push(invalid)
        for j = out.Count() - 1 to k + 1 step -1
            out[j] = out[j - 1]
        end for
        out[k] = it
    end for
    return out
end function

sub buildTonight(g as object, d as object)
    uiRect(g, 0, 0, 1920, 1080, "#090C18")
    header(g, UCase(tWeekdayNames()[tWeekday(d.now)]) + " NIGHT", greeting(d), "#B3A6F2")
    top = 246
    hero = invalid
    for each gm in d.games
        if hero = invalid and not gm.tbd and (gm.state = "in" or tDay(gm.start) = d.today) then hero = gm
    end for
    if hero <> invalid
        uiCard(g, 112, top, 1000, 520, hero.color, "", 32)
        uiDot(g, 176, top + 66, 8, "#F4A259")
        lbl = "Starting soon"
        if hero.state = "in" then lbl = "On now"
        uiLabel(g, 196, top + 54, lbl, 24, "#F4F1EA")
        uiText(g, 168, top + 120, hero.name, 112, 600, "Outfit", "#F4F1EA", 900)
        t = hero.detail + " · " + tClock(hero.start)
        if hero.network <> "" then t = t + " on " + hero.network
        uiText(g, 168, top + 290, t, 34, 500, "Manrope", "#F4F1EA", 880)
    else
        uiCard(g, 112, top, 1000, 520, "#131729", "#222842", 32)
        uiLabel(g, 168, top + 54, "Tonight", 24, "#B3A6F2")
        title = "A quiet night in"
        sub2 = "Nothing else on the family calendar tonight."
        for each e in d.calendar
            if tDay(e.start) = d.today and e.start >= d.now and title = "A quiet night in"
                title = e.title
                sub2 = tClock(e.start)
            end if
        end for
        uiText(g, 168, top + 120, title, 80, 500, "Outfit", "#F4F1EA", 888, "left", 2)
        uiText(g, 168, top + 330, sub2, 30, 400, "Manrope", "#A9B1C4", 888)
    end if
    rx = 1144
    rw = 664
    lo = d.weather.temp
    for each hr in d.weather.hours
        if hr.t > d.now and hr.t <= d.now + 10 * 3600 and hr.temp < lo then lo = hr.temp
    end for
    uiCard(g, rx, top, rw, 220)
    uiLabel(g, rx + 40, top + 38, "Tonight")
    uiImage(g, "pkg:/images/wx_moon.png", rx + 36, top + 88, 100, 100, "#B3A6F2")
    uiText(g, rx + 160, top + 80, d.weather.temp.ToStr() + "°", 88, 300, "Outfit")
    uiText(g, rx + 340, top + 100, wxLabel(d.weather.code), 30, 600, "Manrope", "#F4F1EA", 300)
    uiText(g, rx + 340, top + 144, "Low " + lo.ToStr() + "° · tomorrow " + d.weather.days[1].hi.ToStr() + "°", 24, 400, "Manrope", "#A9B1C4", 300)
    cy0 = top + 252
    uiCard(g, rx, cy0, rw, 268)
    uiLabel(g, rx + 40, cy0 + 32, "Coming up")
    yy = cy0 + 78
    if (d.curb.pickup - d.today) \ 86400 <= 1
        uiCard(g, rx + 30, yy - 10, rw - 60, 92, "#2A2418", "#F4A259", 18)
        uiText(g, rx + 54, yy, tDayWord(d.curb.pickup, d.today) + ": " + LCase(curbText(d.curb)), 26, 700, "Manrope", "#F4F1EA", rw - 108)
        s = "Curb by 7 AM"
        if d.curb.yard then s = s + " · no grass clippings"
        if curbCaveat(d.curb) <> "" then s = s + " · " + curbCaveat(d.curb)
        uiText(g, rx + 54, yy + 40, s, 21, 400, "Manrope", "#E1E4EC", rw - 108)
        yy = yy + 108
    end if
    n = 0
    for each e in d.calendar
        if e.start > d.now and n < 2
            uiText(g, rx + 40, yy, e.title, 26, 600, "Manrope", "#F4F1EA", rw - 280)
            uiText(g, rx + rw - 40, yy, tDayWord(e.start, d.today), 24, 400, "Manrope", "#A9B1C4", 220, "right")
            yy = yy + 46
            n = n + 1
        end if
    end for
    ay = top + 564
    uiLabel(g, 112, ay, "Your evening apps", 22)
    apps = d.apps
    if apps = invalid or apps.Count() = 0 then apps = ["Netflix", "YouTube", "Prime Video", "Disney+", "Hulu", "Max"]
    tw = (1696 - 5 * 24) / 6
    for i = 0 to 5
        if i >= apps.Count() then exit for
        ax = 112 + i * (tw + 24)
        border = "#222842"
        if i = 0 then border = "#B3A6F2"
        uiCard(g, ax, ay + 44, tw, 110, "#1A1F36", border, 22)
        uiText(g, ax + tw / 2, ay + 82, apps[i], 30, 700, "Manrope", "#F4F1EA", Int(tw), "center")
    end for
end sub

sub buildWeek(g as object, d as object)
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    start = d.today
    if tHour(d.now) >= 17 then start = d.today + 86400
    title = "The week ahead"
    if tWeekday(d.now) = 0 then title = "Sunday Reset"
    header(g, "THE WEEK AHEAD · " + UCase(tShortDate(start)) + " TO " + UCase(tShortDate(start + 6 * 86400)), title, "#F4A259", false)
    updated = "Updated " + tClock(d.now)
    if asOfText(d, "weather") <> "" then updated = "Forecast " + asOfText(d, "weather")
    uiText(g, 1808, 140, updated, 24, 400, "Manrope", "#A9B1C4", 400, "right")
    top = 240
    h = 560
    cw = (1696 - 6 * 16) / 7
    for i = 0 to 6
        day = start + i * 86400
        x = 112 + i * (cw + 16)
        isPickup = (tDay(d.curb.pickup) = day)
        border = "#1F2A44"
        dayColor = "#A9B1C4"
        if isPickup
            border = "#F4A259"
            dayColor = "#F4A259"
        end if
        uiCard(g, x, top, cw, h, "#131B2E", border, 22)
        uiText(g, x + 20, top + 22, UCase(Left(tWeekdayNames()[tWeekday(day)], 3)), 24, 700, "Manrope", dayColor)
        uiText(g, x + cw - 20, top + 10, tParts(day).d.ToStr(), 44, 400, "Outfit", "#F4F1EA", 100, "right")
        for each wd in d.weather.days
            if wd.day = day
                uiText(g, x + 20, top + 76, wd.hi.ToStr() + "° / " + wd.lo.ToStr() + "°", 22, 400, "Manrope", "#A9B1C4", cw - 40)
                s = LCase(wxLabel(wd.code))
                if wd.rain >= 30 then s = s + " · " + wd.rain.ToStr() + "%"
                uiText(g, x + 20, top + 104, s, 20, 400, "Manrope", "#A9B1C4", cw - 40)
            end if
        end for
        items = []
        if isPickup then items.Push({box: true, head: "Curb by 7 AM", body: curbText(d.curb), color: "#F4A259", bg: "#2A2418", sort: 0})
        for each e in d.calendar
            if tDay(e.start) = day
                if e.deadline
                    items.Push({box: true, head: "Deadline", body: e.title, color: "#D9A6E0", bg: "#2A2033", sort: 1})
                else
                    head = "All day"
                    srt = 2
                    if not e.allDay
                        head = tClock(e.start)
                        srt = e.start - day
                    end if
                    items.Push({box: false, head: head, body: e.title, sort: srt})
                end if
            end if
        end for
        for each gm in d.games
            if tDay(gm.start) = day
                head = tClock(gm.start)
                if gm.tbd then head = "Time TBA"
                items.Push({box: false, head: head, body: gm.name + " " + gm.detail, sort: gm.start - day})
            end if
        end for
        if tWeekday(day) = 5
            for each mem in d.members
                if mem.band = true then items.Push({box: true, head: mem.name, body: "Marching band at the Friday game", color: mem.color, bg: "#2A2614", sort: 19 * 3600 + 1800})
            end for
        end if
        items.SortBy("sort")
        yy = top + 150
        shown = 0
        for each it in items
            if yy < top + h - 110
                if it.box
                    bh = 96
                    uiCard(g, x + 12, yy - 8, cw - 24, bh, it.bg, "", 14)
                    uiText(g, x + 24, yy, it.head, 20, 700, "Manrope", it.color, cw - 48)
                    uiText(g, x + 24, yy + 28, it.body, 20, 500, "Manrope", "#F4F1EA", cw - 48, "left", 2)
                    yy = yy + bh + 10
                else
                    uiText(g, x + 20, yy, it.head, 20, 400, "Manrope", "#A9B1C4", cw - 40)
                    l = uiText(g, x + 20, yy + 28, it.body, 20, 600, "Manrope", "#F4F1EA", cw - 40, "left", 2)
                    yy = yy + 40 + uiHeight(l, 20)
                end if
                shown = shown + 1
            end if
        end for
        if shown < items.Count() then uiText(g, x + 20, top + h - 48, "+" + (items.Count() - shown).ToStr() + " more", 20, 600, "Manrope", "#A9B1C4")
    end for
    fy = 830
    uiCard(g, 112, fy, 1696, 190)
    uiLabel(g, 152, fy + 28, "Heads up", 20, "#F4A259")
    tw = (1696 - 80 - 72) / 3
    for i = 0 to 2
        if i < d.headsUp.Count() then uiText(g, 152 + i * (tw + 36), fy + 70, d.headsUp[i], 24, 500, "Manrope", "#F4F1EA", Int(tw), "left", 3)
    end for
end sub

sub buildLake(g as object, d as object)
    lk = d.lake
    uiRect(g, 0, 0, 1920, 1080, "#081420")
    header(g, "OUTDOORS · WEST POINT LAKE", "Lake conditions", "#7FB7E8", false)
    uiText(g, 1808, 140, "USGS gauge 02339400 · " + tClock(lk.time), 24, 400, "Manrope", "#9FB3C8", 600, "right")
    top = 246
    uiCard(g, 112, top, 560, 770, "#0E2033", "#1B3550", 32)
    gx = 172
    gy0 = top + 60
    gh = 640
    uiCard(g, gx, gy0, 64, gh, "#132A42", "", 32)
    lvl = lk.level
    ly = gy0 + (640 - lvl) / 20 * gh
    uiCard(g, gx, ly, 64, gy0 + gh - ly, "#7FB7E8", "", 32)
    for each pool in [[635, "Summer full pool"], [628, "Winter pool"]]
        py = gy0 + (640 - pool[0]) / 20 * gh
        uiRect(g, gx - 16, py - 1, 96, 3, "#F4F1EA")
        uiText(g, gx + 120, py - 36, pool[0].ToStr() + " ft", 26, 700)
        uiText(g, gx + 120, py - 4, pool[1], 21, 400, "Manrope", "#9FB3C8")
    end for
    uiText(g, gx + 120, ly - 24, fmt1(lvl), 84, 400, "Outfit")
    uiText(g, gx + 120, ly + 76, "feet now", 24, 600, "Manrope", "#7FB7E8")
    rx = 704
    rw = 1104
    if lvl < 628
        uiCard(g, rx, top, rw, 170, "#2A2418", "#5A4520")
        uiText(g, rx + 44, top + 30, fmt1(635 - lvl) + " ft below summer pool, " + fmt1(628 - lvl) + " ft below winter pool", 38, 500, "Outfit", "#F4F1EA", rw - 88)
        uiText(g, rx + 44, top + 98, "Low water. Check Corps ramp and beach status before you launch.", 24, 400, "Manrope", "#E1D3BE", rw - 88)
    else
        uiCard(g, rx, top, rw, 170, "#0E2033", "#1B3550")
        uiText(g, rx + 44, top + 54, "Lake is at normal levels", 40, 500, "Outfit")
    end if
    best = d.weather.days[0]
    bestScore = -1
    for i = 0 to 5
        dd = d.weather.days[i]
        sc = 0
        if dd.rain < 30 then sc = sc + 3
        if dd.hi >= 65 and dd.hi <= 88 then sc = sc + 2
        if dd.wind <= 10 then sc = sc + 2
        if tWeekday(dd.day) = 0 or tWeekday(dd.day) = 6 then sc = sc + 1
        if sc > bestScore
            bestScore = sc
            best = dd
        end if
    end for
    sunset = d.weather.days[0].sunset
    cards = [["Best lake day", tDayWord(best.day, d.today), "High " + best.hi.ToStr() + "°, " + LCase(wxLabel(best.code)) + ", wind up to " + best.wind.ToStr() + " mph"],
             ["Sunset on the water", tClock(sunset), "Golden hour starts " + tClock(sunset - 2400)],
             ["Fishing moon", Int(d.moon.illum * 100 + 0.5).ToStr() + "% lit", d.moon.name + " · full " + tShortDate(tUtcToWallApprox(d.moon.nextFull))]]
    cw = (rw - 56) / 3
    for i = 0 to 2
        cx = rx + i * (cw + 28)
        uiCard(g, cx, top + 202, cw, 568, "#0E2033", "#1B3550")
        uiLabel(g, cx + 36, top + 238, cards[i][0], 21, "#9FB3C8")
        uiText(g, cx + 36, top + 290, cards[i][1], 60, 500, "Outfit", "#F4F1EA", Int(cw) - 72)
        uiText(g, cx + 36, top + 400, cards[i][2], 26, 400, "Manrope", "#C9D6E3", Int(cw) - 72, "left", 3)
    end for
end sub

function tUtcToWallApprox(utc as integer) as integer
    return utc + (tNowWall() - tNowUtc())
end function

sub buildSky(g as object, d as object)
    uiBackdrop(g, "pkg:/images/bg_sky.jpg", "#05070F")
    cloud = 0
    n = 0
    for each hr in d.weather.hours
        if hr.t >= d.today + 21 * 3600 and hr.t <= d.today + 27 * 3600
            cloud = cloud + hr.cloud
            n = n + 1
        end if
    end for
    if n > 0 then cloud = cloud / n else cloud = 50
    title = "Cloudy tonight."
    if cloud < 70 then title = "Some clouds tonight."
    if cloud < 30 then title = "Clear skies. Look up."
    header(g, "TONIGHT'S SKY OVER LAGRANGE", title, "#B3A6F2", false)
    mp = d.moon
    idx = Int(mp.age / 29.530588853 * 30)
    if idx > 29 then idx = 29
    uiImage(g, "pkg:/images/moon_" + tPad(idx, 2) + ".png", 112, 330, 300, 300)
    uiText(g, 452, 370, Int(mp.illum * 100 + 0.5).ToStr() + "%", 72, 300, "Outfit")
    uiText(g, 452, 462, mp.name, 28, 600, "Manrope", "#F4F1EA", 240)
    uiText(g, 452, 504, "Full moon " + tShortDate(tUtcToWallApprox(mp.nextFull)), 23, 400, "Manrope", "#B8BED0", 240)
    uiCard(g, 700, 300, 1108, 380, "#131729", "#2A3050", 32)
    s = d.shower
    if s <> invalid
        lbl = "Coming up"
        if (s.peak - d.today) \ 86400 <= 7 then lbl = "This week's show"
        uiLabel(g, 748, 340, lbl, 22, "#B3A6F2")
        uiText(g, 748, 384, s.name + " meteor shower peaks " + tDayWord(s.peak, d.today) + " night", 54, 500, "Outfit", "#F4F1EA", 1012, "left", 2)
        uiText(g, 748, 540, "Best in the dark hours before dawn. Face away from town lights; the West Point Lake shoreline is darker than downtown.", 25, 400, "Manrope", "#C9CEDA", 1012, "left", 3)
    else
        uiLabel(g, 748, 340, "Tonight", 22, "#B3A6F2")
        uiText(g, 748, 384, "The moon is " + LCase(mp.name), 54, 500, "Outfit", "#F4F1EA", 1012, "left", 2)
    end if
    lo = 99
    for each hr in d.weather.hours
        if hr.t >= d.today + 21 * 3600 and hr.t <= d.today + 30 * 3600 and hr.temp < lo then lo = hr.temp
    end for
    viewing = "Cloudy"
    if cloud < 70 then viewing = "Partly cloudy"
    if cloud < 30 then viewing = "Clear"
    dark = "Moon up late"
    if mp.illum < 0.3 then dark = "Dark all evening"
    if mp.waxing and mp.illum >= 0.3 then dark = "After midnight"
    cards = [["Viewing tonight", viewing, Int(cloud).ToStr() + "% cloud cover · low " + lo.ToStr() + "°"],
             ["Moonset and dark sky", dark, "Darkest skies come after the moon sets"],
             ["Sunrise tomorrow", tClock(d.weather.days[1].sunrise), "Meteor watching ends at first light"]]
    w3 = (1696 - 56) / 3
    for i = 0 to 2
        x = 112 + i * (w3 + 28)
        uiCard(g, x, 760, w3, 240, "#131729", "#2A3050")
        uiLabel(g, x + 36, 794, cards[i][0], 20, "#A3A9C2")
        uiText(g, x + 36, 834, cards[i][1], 40, 500, "Outfit", "#F4F1EA", Int(w3) - 72)
        uiText(g, x + 36, 906, cards[i][2], 22, 400, "Manrope", "#C9CEDA", Int(w3) - 72, "left", 2)
    end for
end sub

sub buildRecap(g as object, d as object)
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    header(g, "GAME RECAP · " + UCase(tLongDate(d.now)), "How your teams did", "#F4A259", false)
    top = 246
    r = d.rivalry
    hero = invalid
    if r = invalid
        for each f in d.finals
            if hero = invalid and f.pro then hero = f
        end for
        if hero = invalid and d.finals.Count() > 0 then hero = d.finals[0]
    end if
    if r <> invalid
        auWon = (r.winner = "Auburn")
        fans = {Auburn: fansOf(d, "Auburn"), Georgia: fansOf(d, "Georgia")}
        color = "#5C0A18"
        accent = "#F2C4CC"
        if auWon
            color = "#0C2340"
            accent = "#E87722"
        end if
        uiCard(g, 112, top, 900, 770, color, "", 32)
        uiLabel(g, 168, top + 54, "House divided · final", 24, accent)
        uiText(g, 168, top + 120, r.winner + " " + r.hi.ToStr(), 120, 600, "Outfit")
        uiText(g, 168, top + 280, r.loser + " " + r.lo.ToStr(), 80, 400, "Outfit", "#C9CEDA")
        uiText(g, 168, top + 460, fans[r.winner] + " have bragging rights. " + fans[r.loser] + ", there's always next year.", 34, 500, "Manrope", "#F4F1EA", 788, "left", 3)
        uiText(g, 168, top + 690, r.host + " hosted · " + r.network, 26, 400, "Manrope", "#C9CEDA", 788)
    else if hero <> invalid
        uiCard(g, 112, top, 900, 770, hero.color, "", 32)
        res = "Loss · "
        if hero.won then res = "Win · "
        uiLabel(g, 168, top + 54, res + hero.team, 24, "#F4F1EA")
        uiText(g, 168, top + 140, hero.score, 190, 600, "Outfit")
        uiText(g, 168, top + 400, hero.detail, 36, 600, "Manrope", "#F4F1EA", 788)
    end if
    rx = 1044
    rw = 764
    uiCard(g, rx, top, rw, 520)
    uiLabel(g, rx + 40, top + 38, "More results", 21)
    yy = top + 90
    n = 0
    for each f in d.finals
        skip = (f.rivalry and r <> invalid) or (hero <> invalid and f.start = hero.start and f.team = hero.team)
        if not skip and n < 7
            bg = "#3A2024"
            fg = "#F2A7B0"
            wl = "L"
            if f.won
                bg = "#1F3A2A"
                fg = "#9EC79B"
                wl = "W"
            end if
            uiCard(g, rx + 40, yy, 56, 38, bg, "", 10)
            uiText(g, rx + 68, yy + 4, wl, 22, 800, "Manrope", fg, 56, "center")
            label = f.team + " " + f.detail
            if not f.pro then label = "Panthers " + sportCase(f.detail)
            uiText(g, rx + 116, yy + 2, label, 24, 600, "Manrope", "#F4F1EA", rw - 280)
            uiText(g, rx + rw - 40, yy, f.score, 30, 400, "Outfit", "#F4F1EA", 140, "right")
            yy = yy + 58
            n = n + 1
        end if
    end for
    uiCard(g, rx, top + 552, rw, 218)
    uiLabel(g, rx + 40, top + 588, "Season records", 21)
    i = 0
    for each t in [["georgia", "Georgia"], ["auburn", "Auburn"]]
        uiText(g, rx + 40, top + 636 + i * 56, t[1] + " (" + fansOf(d, t[1]) + ")", 26, 600)
        rec = d.records[t[0]]
        if rec = invalid then rec = "—"
        uiText(g, rx + rw - 40, top + 636 + i * 56, rec, 30, 400, "Outfit", "#F4F1EA", 200, "right")
        i = i + 1
    end for
end sub

' "Men's Soccer vs Covenant" -> "men's soccer vs Covenant"
function sportCase(detail as string) as string
    for each sep in [" vs ", " at "]
        k = Instr(1, detail, sep)
        if k > 0 then return LCase(Left(detail, k - 1)) + Mid(detail, k)
    end for
    return LCase(detail)
end function

function fansOf(d as object, team as string) as string
    names = []
    for each mem in d.members
        if mem.allegiance = team then names.Push(mem.name)
    end for
    return names.Join(" & ")
end function

sub buildGameday(g as object, d as object)
    games = soonGames(d)
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    panels = []
    for each gm in games
        if panels.Count() < 2 then panels.Push(gm)
    end for
    pw = 1920 / panels.Count()
    divided = panels.Count() = 2 and ((panels[0].name = "Georgia" and panels[1].name = "Auburn") or (panels[0].name = "Auburn" and panels[1].name = "Georgia"))
    for i = 0 to panels.Count() - 1
        gm = panels[i]
        x = i * pw
        uiRect(g, x, 0, pw, 790, gm.color)
        align = "left"
        tx = x + 112
        if i = 1
            align = "right"
            tx = x + pw - 112
        end if
        lbl = "GAME DAY"
        if gm.state = "in" then lbl = "ON NOW"
        if divided then lbl = lbl + " · HOUSE DIVIDED"
        uiText(g, tx, 72, lbl, 24, 700, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        size = 160
        if panels.Count() = 2 then size = 132
        uiText(g, tx, 110, gm.name, size, 600, "Outfit", "#F4F1EA", Int(pw) - 224, align)
        uiText(g, tx, 130 + size + 20, gm.detail, 34, 500, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        uiText(g, tx, 540, tClock(gm.start), 100, 300, "Outfit", "#F4F1EA", Int(pw) - 224, align)
        if gm.network <> "" then uiText(g, tx, 680, "on " + gm.network, 30, 600, "Manrope", "#F4F1EA", Int(pw) - 224, align)
    end for
    if panels.Count() = 1
        delta = panels[0].start - d.now
        if delta > 0 then uiText(g, 1808, 580, "Kickoff in " + (delta \ 3600).ToStr() + " h " + ((delta mod 3600) \ 60).ToStr() + " m", 40, 500, "Outfit", "#F4F1EA", 700, "right")
    end if
    others = []
    for each gm in d.games
        isPanel = false
        for each p in panels
            if p.start = gm.start and p.name = gm.name then isPanel = true
        end for
        if not isPanel and others.Count() < 4 then others.Push(gm)
    end for
    cw = (1696 - 96) / 4
    for i = 0 to others.Count() - 1
        gm = others[i]
        x = 112 + i * (cw + 32)
        uiCard(g, x, 830, cw, 190)
        uiCard(g, x + 36, 864, 18, 18, gm.color, "", 10)
        uiText(g, x + 66, 856, gm.name, 24, 700, "Manrope", "#F4F1EA", Int(cw) - 100)
        uiText(g, x + 36, 900, gameWhen(gm, d.today), 34, 400, "Outfit", "#F4F1EA", Int(cw) - 72)
        uiText(g, x + 36, 960, gm.detail, 22, 400, "Manrope", "#A9B1C4", Int(cw) - 72)
    end for
end sub

sub buildSchool(g as object, d as object)
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    schools = {}
    for each mem in d.members
        if mem.school <> invalid then schools[UCase(mem.school)] = true
    end for
    eyebrow = "SCHOOL"
    if schools.Count() > 0 then eyebrow = schools.Keys().Join(" · ")
    header(g, eyebrow, "School this week", "#7FB7E8", false)
    top = 246
    items = []
    for each e in d.calendar
        if e.school and e.start >= d.today and items.Count() < 5 then items.Push(e)
    end for
    uiCard(g, 112, top, 900, 770, "#132235", "", 32)
    uiLabel(g, 164, top + 48, "Coming up · from the family calendar", 22, "#7FB7E8")
    yy = top + 116
    for each e in items
        uiText(g, 164, yy, tShortDate(e.start), 28, 700, "Manrope", "#7FB7E8")
        t = e.title
        if e.subtitle <> "" then t = t + " · " + e.subtitle
        uiText(g, 164, yy + 38, t, 32, 600, "Manrope", "#F4F1EA", 796)
        uiText(g, 164, yy + 82, tDayWord(e.start, d.today) + " · " + e.whoText, 22, 400, "Manrope", "#A9B1C4", 796)
        yy = yy + 128
    end for
    if items.Count() = 0 then uiText(g, 164, yy, "No school dates on the calendar this month.", 30, 400, "Manrope", "#A9B1C4", 796)
    kids = []
    for each mem in d.members
        if mem.school <> invalid then kids.Push(mem)
    end for
    if kids.Count() = 0 then return
    rx = 1044
    rw = 764
    kh = (770 - 28 * (kids.Count() - 1)) / kids.Count()
    for i = 0 to kids.Count() - 1
        k = kids[i]
        ky = top + i * (kh + 28)
        uiCard(g, rx, ky, rw, kh)
        uiCard(g, rx + 28, ky, rw - 56, 8, k.color, "", 10)
        uiText(g, rx + 40, ky + 36, k.name, 48, 600, "Outfit")
        info = k.school + " · " + k.grade.ToStr() + "th grade"
        if k.band = true then info = info + " · marching band"
        uiText(g, rx + 40, ky + 104, info, 24, 400, "Manrope", "#A9B1C4", rw - 80)
        nextShown = false
        for each e in items
            for each nm in e.who
                if nm = k.name and not nextShown
                    uiText(g, rx + 40, ky + 160, "Next: " + e.title + " (" + tDayWord(e.start, d.today) + ")", 26, 500, "Manrope", "#F4F1EA", rw - 80)
                    nextShown = true
                end if
            end for
        end for
        if k.band = true then uiText(g, rx + 40, ky + 208, "Friday nights: marching band at the game", 24, 500, "Manrope", k.color, rw - 80)
    end for
end sub

sub buildBoard(g as object, d as object)
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    header(g, "FAMILY BOARD", "Notes for the " + d.household, "#F4A259", false)
    uiText(g, 1808, 140, "Add an event called ""TV: your note"" to the family calendar", 24, 400, "Manrope", "#A9B1C4", 900, "right")
    top = 246
    cw = (1060 - 28) / 2
    for i = 0 to d.notes.Count() - 1
        if i < 4
            n = d.notes[i]
            x = 112 + (i mod 2) * (cw + 28)
            y = top + (i \ 2) * 397
            uiCard(g, x, y, cw, 373, "#1B2433", "")
            uiCard(g, x + 28, y, cw - 56, 8, n.color, "", 10)
            uiText(g, x + 40, y + 46, n.text, 44, 500, "Outfit", "#F4F1EA", Int(cw) - 80, "left", 4)
            uiText(g, x + 40, y + 316, n.from, 22, 400, "Manrope", "#A9B1C4", Int(cw) - 80)
        end if
    end for
    gx = 1204
    gw = 604
    uiCard(g, gx, top, gw, 770)
    uiLabel(g, gx + 40, top + 38, "Grocery list", 22)
    yy = top + 98
    for i = 0 to d.groceries.Count() - 1
        if i < 11
            uiCard(g, gx + 40, yy + 4, 26, 26, "#131B2E", "#A9B1C4", 10)
            uiText(g, gx + 86, yy, d.groceries[i], 28, 400, "Manrope", "#F4F1EA", gw - 126)
            yy = yy + 56
        end if
    end for
    if d.groceries.Count() = 0 then uiText(g, gx + 40, yy, "Add ""Buy: milk, eggs"" to the family calendar", 24, 400, "Manrope", "#A9B1C4", gw - 80, "left", 3)
end sub

function seasonItems(month as integer) as dynamic
    if month = 10 then return [["Fall color", "Starting to turn", "Usually peaks here in late October to early November. Callaway's trails are the closest showcase."], ["In the garden", "Plant pansies and shrubs", "Fall is Georgia's best season for trees and shrubs. Divide perennials; spring bulbs go in next month."], ["On the wing", "Monarchs passing through", "October is monarch migration month in Georgia. Late-blooming flowers help them refuel."]]
    if month = 11 then return [["Fall color", "Peak season", "Early November is usually peak color around LaGrange and Pine Mountain."], ["In the garden", "Plant spring bulbs", "Tulips, daffodils and hyacinths go in now through December. Mulch beds before the first hard freeze."], ["Outdoors", "Fantasy in Lights season", "Callaway Gardens' holiday light show opens in mid-November."]]
    if month = 12 then return [["Winter", "Bare branches, big skies", "Long nights and clear air make December great for stargazing; the Geminids peak mid-month."], ["In the garden", "Protect and plan", "Cover tender plants on frost nights and order seeds for spring."], ["On the wing", "Winter birds at feeders", "Juncos, white-throated sparrows and yellow-rumped warblers arrive for the winter."]]
    return invalid
end function

sub buildSeason(g as object, d as object)
    uiBackdrop(g, "pkg:/images/bg_season.jpg", "#0B1120")
    header(g, "WHAT'S IN SEASON · " + UCase(tMonthNames()[tParts(d.now).m - 1]), "The season in West Georgia", "#F4A259", false)
    cards = []
    cards.Append(seasonItems(tParts(d.now).m))
    frost = invalid
    for i = 1 to 3
        if frost = invalid and d.weather.days[i].lo <= 34 then frost = d.weather.days[i]
    end for
    if frost <> invalid
        cards.Push(["Frost watch", "Frost " + tDayWord(frost.day, d.today), "Low of " + frost.lo.ToStr() + "° forecast. Cover tender plants."])
    else
        cards.Push(["Frost watch", "None this week", "No frost in the 3-day forecast. Daybreak warns two days ahead."])
    end if
    cw = (1696 - 84) / 4
    for i = 0 to 3
        x = 112 + i * (cw + 28)
        uiCard(g, x, 560, cw, 440, "#0B1120", "#2A3656", 28, 0.9)
        uiLabel(g, x + 36, 596, cards[i][0], 21, "#F4A259")
        uiText(g, x + 36, 640, cards[i][1], 40, 500, "Outfit", "#F4F1EA", Int(cw) - 72, "left", 2)
        uiText(g, x + 36, 760, cards[i][2], 24, 400, "Manrope", "#E1E4EC", Int(cw) - 72, "left", 6)
    end for
end sub

sub buildRadar(g as object, d as object)
    uiImage(g, "pkg:/images/radar_base.jpg", 0, 0, 1920, 1080)
    layer = radarLayer(d.radarTimes)
    parent = layer.group.getParent()
    if parent <> invalid then parent.removeChild(layer.group)
    g.appendChild(layer.group)
    frames = layer.frames
    for each f in frames
        f.poster.visible = false
    end for
    if frames.Count() > 0 then frames[frames.Count() - 1].poster.visible = true
    m.radarFrames = frames
    m.radarFrame = frames.Count() - 1
    uiImage(g, "pkg:/images/ring_radar.png", 703, 283, 514, 514, "#F4F1EA", 0.35)
    uiDot(g, 960, 540, 40, "#F4A259", 0.18)
    uiDot(g, 960, 540, 13, "#0B1120")
    uiDot(g, 960, 540, 9, "#F4A259")
    places = [["West Point", 869, 655], ["Hogansville", 1029, 445], ["Pine Mountain", 1066, 664], ["Newnan", 1098, 296], ["Carrollton", 933, 154], ["Columbus", 986, 951], ["Auburn", 692, 845]]
    for each p in places
        uiDot(g, p[1], p[2], 5, "#C9CEDA")
        uiText(g, p[1] + 14, p[2] - 14, p[0], 22, 400, "Manrope", "#C9CEDA")
    end for
    uiDot(g, 1344, 32, 6, "#C9CEDA")
    uiText(g, 1328, 18, "Atlanta", 24, 600, "Manrope", "#C9CEDA", 160, "right")
    uiText(g, 984, 516, "LaGrange", 34, 600, "Outfit")
    uiText(g, 840, 532, "West Point Lake", 22, 400, "Manrope", "#7FA7D6", 240, "right")
    uiText(g, 960, 248, "25 mi", 18, 600, "Manrope", "#A9B1C4", 120, "center")
    status = "No rain nearby"
    sub2 = "Forecast for LaGrange shows no rain in the next 2 hours"
    if d.rainSoon
        status = "Rain likely soon"
        sub2 = "Forecast shows rain near LaGrange within 2 hours"
    end if
    uiCard(g, 112, 64, 520, 250, "#0B1120", "#1F2A44", 28, 0.92)
    dotColor = "#9EC79B"
    if d.rainSoon then dotColor = "#F4A259"
    uiDot(g, 150, 108, 7, dotColor)
    uiLabel(g, 170, 96, "Live radar · West Georgia", 21)
    uiText(g, 152, 134, status, 46, 500, "Outfit", "#F4F1EA", 440)
    uiText(g, 152, 206, sub2, 24, 400, "Manrope", "#C9CEDA", 440, "left", 2)
    warn = d.alerts.Count() > 0
    fill = "#0B1120"
    if warn then fill = "#5C0A18"
    uiCard(g, 1348, 64, 460, 250, fill, "#1F2A44", 28, 0.92)
    uiLabel(g, 1388, 96, "Alerts · Troup County", 21)
    if warn
        yy = 136
        for each a in d.alerts
            if yy < 280
                l = uiText(g, 1388, yy, a.event, 32, 600, "Manrope", "#F4F1EA", 380, "left", 2)
                yy = yy + uiHeight(l, 32) + 8
            end if
        end for
    else if d.alertsKnown = false
        uiText(g, 1388, 140, "Unavailable", 40, 500, "Outfit")
        uiText(g, 1388, 214, "Couldn't reach the National Weather Service. Check local news in severe weather.", 21, 400, "Manrope", "#F4A259", 400, "left", 2)
    else
        uiText(g, 1388, 140, "None in effect", 40, 500, "Outfit")
        uiText(g, 1388, 214, "National Weather Service, Peachtree City", 21, 400, "Manrope", "#A9B1C4", 400)
    end if
    uiCard(g, 112, 876, 760, 140, "#0B1120", "#1F2A44", 28, 0.92)
    uiText(g, 152, 900, "Past 2 hours", 24, 600)
    m.radarTimeLabel = uiText(g, 832, 900, "", 24, 700, "Manrope", "#F4A259", 300, "right")
    m.radarSegs = []
    n = frames.Count()
    if n > 0
        segw = (680 - (n - 1) * 6) / n
        for j = 0 to n - 1
            m.radarSegs.Push(uiCard(g, 152 + j * (segw + 6), 960, segw, 10, "#2A3656", "", 10))
        end for
    end if
    uiCard(g, 1248, 876, 560, 140, "#0B1120", "#1F2A44", 28, 0.92)
    uiLabel(g, 1284, 898, "Precipitation", 19)
    legend = [["Light", "#02FD02", "#01C501"], ["Moderate", "#FDF802", "#FD9500"], ["Heavy", "#FD0000", "#BC0000"], ["Severe, hail", "#F800FD", "#9854C6"]]
    lw = (488 - 30) / 4
    for j = 0 to 3
        lx = 1284 + j * (lw + 10)
        uiRect(g, lx, 944, lw / 2, 14, legend[j][1])
        uiRect(g, lx + lw / 2, 944, lw / 2, 14, legend[j][2])
        uiText(g, lx, 968, legend[j][0], 19, 400, "Manrope", "#C9CEDA")
    end for
    showRadarFrame(m.radarFrame)
end sub

' Radar frames as one group of posters, kept between builds of the radar
' screen while the frame times are unchanged, so rotating back to radar (or a
' data refresh) doesn't create and download a second set. Frames load at
' 960x540 (about 2 MB each decoded instead of 8 MB) and are scaled to fill
' the screen; low memory keeps only the latest 4.
function radarLayer(times as object) as object
    picks = times
    if m.lowMemory = true and times.Count() > 4
        picks = []
        for i = times.Count() - 4 to times.Count() - 1
            picks.Push(times[i])
        end for
    end if
    key = picks.Join(",")
    if m.radarCache <> invalid and m.radarCache.key = key then return m.radarCache
    group = CreateObject("roSGNode", "Group")
    frames = []
    bbox = "-9644575,3799871,-9286707,4001172"
    for each t in picks
        url = "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows?service=WMS&version=1.3.0&request=GetMap&layers=conus_bref_qcd&crs=EPSG:3857&bbox=" + bbox + "&width=960&height=540&format=image/png&transparent=true&time=" + t
        p = uiImage(group, url, 0, 0, 1920, 1080)
        p.loadWidth = 960
        p.loadHeight = 540
        p.visible = false
        frames.Push({poster: p, time: t})
    end for
    m.radarCache = {key: key, group: group, frames: frames}
    return m.radarCache
end function

sub showRadarFrame(i as integer)
    if m.radarFrames = invalid or m.radarFrames.Count() = 0 then return
    for j = 0 to m.radarFrames.Count() - 1
        m.radarFrames[j].poster.visible = (j = i)
        color = "0x2A3656FF"
        if j = i then color = "0xF4A259FF"
        m.radarSegs[j].blendColor = color
    end for
    m.radarTimeLabel.text = tClock(tUtcIsoToWall(Left(m.radarFrames[i].time, 19) + "Z"))
end sub
