' Daybreak screens, built natively from the DataTask's derived data. Layouts
' sit on the 12-column grid in ui.brs (gx/gw) and use nothing below 24 px.
' daybreak/preview renders these same builders off-device for design review.

' --- which screens, in what order ----------------------------------------------

function availableScreens(d as object) as object
    a = {ambient: true, briefing: true, tonight: true, week: true, sky: true, school: true, radar: true, night: true}
    if d.takeover <> invalid then a.alert = true
    wd = tWeekday(d.now)
    if (wd = 5 or wd = 6) and d.weather <> invalid then a.weekend = true
    if d.weather = invalid
        a.Delete("briefing")
        a.Delete("ambient")
        a.Delete("week")
        a.Delete("tonight")
        a.Delete("sky")
    end if
    if d.lake <> invalid and d.weather <> invalid and d.place.lake <> invalid then a.lake = true
    if d.finals.Count() > 0 then a.recap = true
    if soonGames(d).Count() > 0 then a.gameday = true
    if d.notes.Count() > 0 or d.groceries.Count() > 0 or d.countdowns.Count() > 0 or d.chores.Count() > 0 then a.board = true
    if seasonItems(tParts(d.now).m) <> invalid and d.weather <> invalid then a.season = true
    return a
end function

' hidden: screens turned off in Settings (never all of them: if nothing is
' left, the defaults come back).
function chooseScreens(d as object, mode as string, hidden = {} as object) as object
    a = availableScreens(d)
    trimmed = {}
    for each k in a
        if not hidden.DoesExist(k) then trimmed[k] = true
    end for
    if trimmed.Count() > 1 then a = trimmed
    h = tHour(d.now)
    wd = tWeekday(d.now)
    warning = false
    for each al in d.alerts
        if al.level = "warning" then warning = true
    end for
    ' a dangerous-weather warning takes over everything: the alert and radar only
    if d.takeover <> invalid then return ["alert", "radar"]
    ' late at night the screensaver is just a dim clock (plus radar in a warning)
    if mode = "screensaver" and (h >= 23 or h < 5)
        if warning then return ["radar", "night"]
        return ["night"]
    end if
    order = []
    if warning then order.Push("radar")
    order.Push("gameday")
    if h >= 4 and h < 11
        order.Push("briefing")
        if wd = 6 then order.Push("weekend")
        order.Push("recap")
        if wd >= 1 and wd <= 5 then order.Push("school")
    else if h >= 11 and h < 17
        if h < 14 then order.Push("recap")
        if wd = 5 or wd = 6 then order.Push("weekend")
        order.Push("ambient")
        if wd = 0 or wd = 6 or (d.weather <> invalid and d.weather.days[0].rain < 30) then order.Push("lake")
        order.Push("season")
    else
        order.Push("tonight")
        if wd = 5 then order.Push("weekend")
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
        ss = []
        if a.ambient = true then ss.Push("ambient")
        for each s in out
            if ss.Count() < 4 and s <> "ambient" and s <> "board" then ss.Push(s)
        end for
        if ss.Count() = 0 then ss.Push("night")
        return ss
    end if
    if out.Count() = 0 then out.Push("night")
    return out
end function

function screenSeconds(id as string) as integer
    if id = "briefing" or id = "week" or id = "tonight" or id = "weekend" then return 30
    if id = "radar" then return 16
    if id = "alert" then return 30
    if id = "night" then return 60
    return 20
end function

function screenTitles() as object
    return {ambient: "Ambient", briefing: "Briefing", tonight: "Tonight", week: "Week ahead", weekend: "Weekend", lake: "Lake", sky: "Sky",
            recap: "Game recap", gameday: "Game day", school: "School", board: "Family board", season: "Season",
            radar: "Radar", night: "Night clock", alert: "Weather warning"}
end function

function buildScreen(id as string, d as object) as object
    m.clockNodes = invalid
    m.radarFrames = invalid
    m.wallpaperCredit = invalid
    g = CreateObject("roSGNode", "Group")
    if id = "ambient" then buildAmbient(g, d)
    if id = "briefing" then buildBriefing(g, d)
    if id = "tonight" then buildTonight(g, d)
    if id = "week" then buildWeek(g, d)
    if id = "weekend" then buildWeekend(g, d)
    if id = "lake" then buildLake(g, d)
    if id = "sky" then buildSky(g, d)
    if id = "recap" then buildRecap(g, d)
    if id = "gameday" then buildGameday(g, d)
    if id = "school" then buildSchool(g, d)
    if id = "board" then buildBoard(g, d)
    if id = "season" then buildSeason(g, d)
    if id = "radar" then buildRadar(g, d)
    if id = "night" then buildNight(g, d)
    if id = "alert" then buildAlert(g, d)
    ' the photo's credit, bottom right (the scene hides it while its status line shows)
    ' (the license must stay readable: the "Photo:" label goes first, then the place)
    w = m.wallpaperCredit
    if w <> invalid
        credit = g.createChild("Group")
        credit.id = "photoCredit"
        text = "Photo: " + w.credit ' Ambient names the place in its caption
        if id <> "ambient"
            for each t in [w.place + " · " + w.credit, "Photo: " + w.place + " · " + w.credit] ' the longest that fits
                if uiTextWidth(credit, t, 24) <= 680 then text = t
            end for
        end if
        tw = uiTextWidth(credit, text, 24)
        if tw > 680 then tw = 680
        uiCard(credit, 1808 - tw - 18, 1026, tw + 36, 44, "#0B1120", "", 22, 0.72) ' readable on any photo
        uiText(credit, 1808, 1032, text, 24, 400, "Manrope", "#C9CEDA", 680, "right")
    end if
    return g
end function

' --- shared pieces ----------------------------------------------------------------

' The Sky card's sentence and tip for a moon phase name from moonPhase().
function moonWords(name as string) as object
    if name = "Full moon" then return {line: "The moon is full", tip: "Bright enough for an evening walk, too bright for faint stars."}
    if name = "New moon" then return {line: "It's a new moon", tip: "The darkest skies of the month: the best night for stars and the Milky Way."}
    if Right(name, 7) = "quarter" then return {line: "The moon is at " + LCase(name), tip: "Half lit. Binoculars show craters along the shadow line."}
    tip = "A thin moon leaves the sky dark for stars."
    if Right(name, 7) = "gibbous" then tip = "A bright moon washes out faint stars; planets still shine through."
    return {line: "The moon is a " + LCase(name), tip: tip}
end function

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

sub addClock(g as object, x as integer, y as integer, size as integer, weight as integer, align as string, color = "#F4F1EA" as string)
    clock = uiText(g, x, y, "", size, weight, "Outfit", color)
    ampm = uiText(g, x, y, "", Int(size * 0.33), 300, "Outfit", "#C9CEDA")
    if color <> "#F4F1EA" then ampm.color = hexc(color)
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
' Photo backdrop: today's wallpaper for this screen (d.wallpapers, downloaded
' by DataTask) under a fill in the screen's color at wallpaperDim(), else the
' packaged pre-dimmed photo, else the plain fill. Low-memory mode uses the fill.
' Sets m.wallpaperCredit to the photo, which buildScreen credits in the corner.
sub uiWallpaper(g as object, d as object, id as string, fill as string, packaged = "" as string)
    w = invalid
    if d.wallpapers <> invalid then w = d.wallpapers[id]
    if m.lowMemory = true
        uiRect(g, 0, 0, 1920, 1080, fill)
    else if w <> invalid
        uiImage(g, w.uri, 0, 0, 1920, 1080)
        uiRect(g, 0, 0, 1920, 1080, fill, wallpaperDim(id))
        m.wallpaperCredit = w
    else if packaged <> ""
        uiImage(g, packaged, 0, 0, 1920, 1080)
    else
        uiRect(g, 0, 0, 1920, 1080, fill)
    end if
end sub

' How much of the screen's fill covers a wallpaper: the photo screens show
' more of it, card screens keep it a quiet texture behind the cards.
function wallpaperDim(id as string) as float
    dims = {ambient: 0.55, briefing: 0.78, season: 0.7}
    if dims.DoesExist(id) then return dims[id]
    return 0.82
end function

sub uiBackdrop(g as object, uri as string, fallback as string)
    if m.lowMemory = true then uiRect(g, 0, 0, 1920, 1080, fallback) else uiImage(g, uri, 0, 0, 1920, 1080)
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

' "Live · 21–17 · Q3 4:12" for a game in progress.
function liveText(gm as object) as string
    t = "Live · " + gm.my + "–" + gm.their
    if gm.status <> invalid and gm.status <> "" then t = t + " · " + gm.status
    return t
end function

' A team's logo as a faint watermark (drawn before the card's text, so behind
' it). The TV loads it from ESPN's CDN and decodes it at the drawn size; none
' for teams without one (LaGrange College) or in low-memory mode.
sub teamLogo(g as object, uri as dynamic, x as float, y as float, size as integer, opacity = 0.16 as float)
    if not isText(uri) or uri = "" or m.lowMemory = true then return
    p = uiImage(g, uri, x, y, size, size, "", opacity)
    p.loadWidth = size
    p.loadHeight = size
    p.loadDisplayMode = "scaleToFit"
end sub

' A game's team as a small tile: the logo at full strength on a dark tile
' edged in the team color, or the short-name chip when there's no logo
' (LaGrange College) or memory is low.
sub teamBadge(g as object, x as float, y as float, size as integer, gm as object)
    if not isText(gm.logo) or gm.logo = "" or m.lowMemory = true
        teamChip(g, x, y, size, gm.short, gm.color, gm.accent)
        return
    end if
    uiCard(g, x, y, size, size, "#0B1120", gm.color, 14)
    teamLogo(g, gm.logo, x + 6, y + 6, size - 12, 1.0)
end sub

' The logo of a tracked team from its games or finals, or "".
function logoOf(d as object, name as string) as string
    for each list in [d.finals, d.games]
        for each x in list
            nm = x.team ' finals name the team in team, games in name
            if nm = invalid then nm = x.name
            if isText(nm) and nm = name and isText(x.logo) and x.logo <> "" then return x.logo
        end for
    end for
    return ""
end function

function gameWhen(gm as object, today as integer) as string
    if gm.state = "in" then return liveText(gm)
    if gm.tbd then return tDayWord(gm.start, today) + " · time TBA"
    return tDayWord(gm.start, today) + " " + tClock(gm.start)
end function

' Like gameWhen with a 3-letter weekday past tomorrow ("Wed 7:30 PM"), for tight rows.
function gameWhenShort(gm as object, today as integer) as string
    if gm.state = "in" then return liveText(gm)
    n = (tDay(gm.start) - today) \ 86400
    day = tDayWord(gm.start, today)
    if n >= 2 then day = Left(tWeekdayNames()[tWeekday(gm.start)], 3)
    if n >= 7 then day = tShortDate(gm.start)
    if gm.tbd then return day + " · TBA"
    return day + " " + tClock(gm.start).Replace(":00", "")
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

' --- weather warning -------------------------------------------------------------

' Full-screen warning: the event, the NWS headline and instructions, and how
' long it lasts. Alternates with radar until the warning expires.
sub buildAlert(g as object, d as object)
    a = d.takeover
    uiRect(g, 0, 0, 1920, 1080, "#5C0A18")
    uiRect(g, 0, 0, 1920, 12, "#F4A259")
    uiLabel(g, 112, 72, "National Weather Service · " + d.place.area, 26, "#F4C9A8")
    uiText(g, 112, 116, a.event, 104, 600, "Outfit", "#FFFFFF", 1696)
    until = ""
    if a.expires <> invalid and a.expires > 0 then until = "Until " + tClock(a.expires)
    if tDay(a.expires) <> d.today and a.expires > 0 then until = until + " " + tDayWord(a.expires, d.today)
    if until <> "" then uiText(g, 112, 262, until, 48, 500, "Outfit", "#FFFFFF", 1696)
    if a.headline <> "" then uiText(g, 112, 360, a.headline, 30, 500, "Manrope", "#FFFFFF", 1696, "left", 3)
    uiCard(g, 112, 520, 1696, 380, "#3A0610", "#8A2A38", 28)
    uiLabel(g, 152, 552, "What to do", 26, "#F4C9A8")
    todo = a.instruction
    if todo = "" then todo = "Follow instructions from local officials and the National Weather Service."
    uiText(g, 152, 600, todo, 34, 500, "Manrope", "#FFFFFF", 1616, "left", 7)
    uiText(g, 112, 950, "Radar follows. This screen stays up until the warning ends.", 26, 400, "Manrope", "#F4C9A8", 1696)
end sub

' --- loading and night -----------------------------------------------------------

' Shown before the first data arrives: the real date and clock, and placeholder
' cards where the Briefing will be.
function buildLoading(now as integer, message as string) as object
    m.clockNodes = invalid
    g = CreateObject("roSGNode", "Group")
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    uiLabel(g, 112, 62, UCase(tLongDate(now)), 24, "#F4A259")
    uiText(g, 112, 100, "Daybreak", 76, 500, "Outfit", "#F4F1EA", 1200)
    addClock(g, 1808, 82, 104, 300, "right")
    for c = 0 to 2
        x = gx(1 + c * 4)
        uiCard(g, x, 246, gw(4), 540)
        uiCard(g, x + 40, 290, 160, 24, "#1F2A44", "", 10)
        for r = 0 to 3
            uiCard(g, x + 40, 360 + r * 100, gw(4) - 80 - r * 40, 28, "#18223A", "", 10)
            uiCard(g, x + 40, 400 + r * 100, 180, 22, "#18223A", "", 10)
        end for
    end for
    uiCard(g, gx(1), 818, gw(8), 200)
    uiCard(g, gx(9), 818, gw(4), 200)
    uiText(g, gx(1) + gw(8) / 2, 896, message, 30, 500, "Manrope", "#C9CEDA", gw(8) - 80, "center")
    return g
end function

' Late-night screensaver: a dim clock that drifts every few minutes, with
' tomorrow's weather and first event.
sub buildNight(g as object, d as object)
    uiRect(g, 0, 0, 1920, 1080, "#000000")
    slot = ((tHour(d.now) * 60 + (d.now mod 3600) \ 60) \ 5)
    x = 200 + (slot mod 8) * 120
    y = 260 + ((slot \ 8) mod 5) * 80
    addClock(g, x, y, 170, 200, "left", "#8A90A0")
    uiText(g, x + 4, y + 220, tLongDate(d.now), 30, 500, "Manrope", "#8A90A0")
    ' after midnight, "tomorrow" means the day that's about to start
    tomorrow = d.today + 86400
    word = "Tomorrow"
    if tHour(d.now) < 5
        tomorrow = d.today
        word = "Today"
    end if
    lines = []
    if d.weather <> invalid
        for each t in d.weather.days
            if t.day = tomorrow
                s = word + " " + t.hi.ToStr() + "° / " + t.lo.ToStr() + "°, " + LCase(wxLabel(t.code))
                if t.rain >= 30 then s = s + " · rain " + t.rain.ToStr() + "%"
                lines.Push(s)
            end if
        end for
    end if
    for each e in d.calendar
        if tDay(e.start) = tomorrow and lines.Count() < 2
            when = "all day"
            if not e.allDay then when = tClock(e.start).Replace(":00", "")
            lines.Push("First up: " + e.title + ", " + when)
        end if
    end for
    for i = 0 to lines.Count() - 1
        uiText(g, x + 4, y + 276 + i * 42, lines[i], 26, 400, "Manrope", "#7A8090", 1100)
    end for
end sub

' --- screens ------------------------------------------------------------------------

sub buildAmbient(g as object, d as object)
    uiWallpaper(g, d, "ambient", "#0B1120", "pkg:/images/bg_ambient.jpg")
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
    uiText(g, 160, 912, "Sunrise " + tClock(today.sunrise) + "      " + (len \ 3600).ToStr() + " h " + ((len mod 3600) \ 60).ToStr() + " m of daylight      Sunset " + tClock(today.sunset), 26, 400, "Manrope", "#E1E4EC")
    caption = "Reflection pool, Callaway Gardens · Pine Mountain, GA"
    if m.wallpaperCredit <> invalid then caption = m.wallpaperCredit.place
    uiText(g, 160, 960, caption, 24, 400, "Manrope", "#E1E4EC", 1000)
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
            if gm.state = "in" then return gm.name + " " + gm.my + "–" + gm.their + " " + gm.detail
            delta = gm.start - d.now
            if delta > 0 and delta < 12 * 3600 then return gm.name + " in " + (delta \ 3600).ToStr() + " h " + ((delta mod 3600) \ 60).ToStr() + " m"
        end if
    end for
    if d.curb <> invalid
        if (d.curb.pickup - d.today) \ 86400 <= 1 then return tDayWord(d.curb.pickup, d.today) + ": " + LCase(curbText(d.curb))
    end if
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
    cardLabel(g, x + 92, y + 44, w - 132, "Weather", "#A9B1C4", asOfText(d, "weather"))
    uiText(g, x + 36, y + 100, wx.temp.ToStr() + "°", 150, 300, "Outfit")
    uiText(g, x + 290, y + 136, wxLabel(wx.code), 32, 600, "Manrope", "#F4F1EA", w - 326, "left", 2)
    uiText(g, x + 290, y + 186, "H " + today.hi.ToStr() + "° · L " + today.lo.ToStr() + "°", 26, 400, "Manrope", "#A9B1C4", w - 326)
    if d.air <> invalid
        airColor = "#9EC79B"
        if d.air.aqi > 50 then airColor = "#F2C14E"
        if d.air.aqi > 100 then airColor = "#F4A259"
        uiDot(g, x + 298, y + 238, 6, airColor)
        uiText(g, x + 312, y + 224, "Air " + LCase(d.air.label) + " · " + d.air.aqi.ToStr(), 24, 400, "Manrope", "#A9B1C4", w - 348)
    end if
    hours = []
    for each hr in wx.hours
        if hr.t > d.now and hours.Count() < 5 and ((hr.t - d.now) \ 3600) mod 3 = 0 then hours.Push(hr)
    end for
    cw = Int((w - 72 - 4 * 10) / 5)
    for i = 0 to hours.Count() - 1
        cx = x + 36 + i * (cw + 10)
        uiCard(g, cx, y + 300, cw, 100, "#1A2440", "", 18)
        uiText(g, cx + cw / 2, y + 312, tClock(hours[i].t).Replace(":00", ""), 24, 400, "Manrope", "#A9B1C4", cw, "center")
        uiText(g, cx + cw / 2, y + 344, hours[i].temp.ToStr() + "°", 34, 400, "Outfit", "#F4F1EA", cw, "center")
    end for
    sunArc(g, x + 48, y + h - 128, w - 96, 56, "pkg:/images/arc_card.png", d, 9)
    uiText(g, x + 36, y + h - 60, "Sunrise " + tClock(today.sunrise), 24, 400, "Manrope", "#A9B1C4")
    uiText(g, x + w - 36, y + h - 60, "Sunset " + tClock(today.sunset), 24, 400, "Manrope", "#A9B1C4", 240, "right")
end sub

sub buildBriefing(g as object, d as object)
    uiWallpaper(g, d, "briefing", "#0B1120", "pkg:/images/bg_briefing.jpg")
    header(g, UCase(tLongDate(d.now) + " · " + d.place.town + ", " + d.place.region), greeting(d))
    top = 246
    weatherCard(g, gx(1), top, gw(4), 540, d)
    ' calendar
    x = gx(5)
    w = gw(4)
    uiCard(g, x, top, w, 540)
    cardLabel(g, x + 40, top + 40, w - 80, "Family calendar", "#A9B1C4", asOfText(d, "calendar"))
    rows = briefingRows(d)
    shownRefs = {}
    yy = top + 92
    for i = 0 to rows.Count() - 1
        if i < 4
            r = rows[i]
            shownRefs[r.ref] = true
            uiText(g, x + 40, yy, r.when, 24, 700, "Manrope", "#F4A259", w - 80)
            uiText(g, x + 40, yy + 30, r.title, 28, 600, "Manrope", "#F4F1EA", w - 80)
            uiDot(g, x + 47, yy + 82, 6, r.color)
            uiText(g, x + 64, yy + 67, r.sub, 24, 400, "Manrope", "#A9B1C4", w - 104)
            yy = yy + 108
        end if
    end for
    if rows.Count() = 0 then uiText(g, x + 40, yy, "Nothing on the calendar this week.", 26, 400, "Manrope", "#A9B1C4", w - 80, "left", 2)
    ' game watch
    x = gx(9)
    uiCard(g, x, top, w, 540)
    cardLabel(g, x + 40, top + 40, w - 80, "Game watch", "#A9B1C4", asOfText(d, "sports"))
    yy = top + 94
    games = briefingGames(d)
    for each gm in games
        teamBadge(g, x + 36, yy, 64, gm)
        uiText(g, x + 120, yy - 2, gm.name, 26, 600, "Manrope", "#F4F1EA", w - 156)
        tail = ""
        if gm.network <> "" then tail = " · " + gm.network
        uiText(g, x + 120, yy + 34, gameWhenShort(gm, d.today) + " · " + gm.detail + tail, 24, 400, "Manrope", "#A9B1C4", w - 156)
        yy = yy + 86
    end for
    if games.Count() = 0 then uiText(g, x + 40, yy, "No games in the next two weeks.", 26, 400, "Manrope", "#A9B1C4", w - 80, "left", 2)
    ' headlines + heads up
    fy = 818
    uiCard(g, gx(1), fy, gw(8), 200)
    cardLabel(g, gx(1) + 40, fy + 28, gw(8) - 80, d.place.town + " today", "#A9B1C4", asOfText(d, "news"))
    colW = (gw(8) - 80 - 48) / 2
    for i = 0 to 1
        if i < d.news.Count()
            nx = gx(1) + 40 + i * (colW + 48)
            uiText(g, nx, fy + 68, UCase(Left(d.news[i].source, 30)), 24, 700, "Manrope", "#F4A259", Int(colW))
            uiText(g, nx, fy + 102, d.news[i].headline, 26, 500, "Manrope", "#F4F1EA", Int(colW), "left", 2)
        end if
    end for
    if d.news.Count() = 0 then uiText(g, gx(1) + 40, fy + 80, "No local headlines right now.", 26, 400, "Manrope", "#A9B1C4", gw(8) - 80)
    hx = gx(9)
    uiCard(g, hx, fy, gw(4), 200)
    uiRect(g, hx + 28, fy + 1, gw(4) - 56, 4, "#F4A259")
    uiLabel(g, hx + 40, fy + 28, "Heads up", 24, "#F4A259")
    yy = fy + 68
    for each t in tipTexts(d.tips, shownRefs, 2)
        if yy < fy + 150
            l = uiText(g, hx + 40, yy, t, 24, 500, "Manrope", "#F4F1EA", gw(4) - 80, "left", 2)
            yy = yy + uiHeight(l, 24) + 8
        end if
    end for
    if d.tips.Count() = 0 then uiText(g, hx + 40, yy, "All clear today.", 26, 500, "Manrope", "#A9B1C4", gw(4) - 80)
end sub

' Briefing calendar rows in time order: curbside counts as 7 AM on pickup day,
' all-day events and birthdays as the start of their day. ref matches the
' heads-up tip about the same thing.
function briefingRows(d as object) as object
    rows = []
    if d.curb <> invalid and (d.curb.pickup - d.today) \ 86400 <= 3
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

' Game watch: the next game of each tracked team (up to 4) and at most one
' small-college game, in time order.
function briefingGames(d as object) as object
    seen = {}
    picks = []
    college = 0
    for each gm in d.games
        if not seen.DoesExist(gm.name)
            if gm.short = "LC"
                if college < 1
                    college = college + 1
                    seen[gm.name] = true
                    picks.Push(gm)
                end if
            else if picks.Count() - college < 4
                seen[gm.name] = true
                picks.Push(gm)
            end if
        end if
    end for
    return sortStable(picks, "start")
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
    uiWallpaper(g, d, "tonight", "#090C18")
    header(g, UCase(tWeekdayNames()[tWeekday(d.now)]) + " NIGHT", greeting(d), "#B3A6F2")
    top = 246
    hero = invalid
    for each gm in d.games
        if hero = invalid and not gm.tbd and (gm.state = "in" or tDay(gm.start) = d.today) then hero = gm
    end for
    if hero <> invalid
        uiCard(g, gx(1), top, gw(7), 520, hero.color, "", 32)
        teamLogo(g, hero.logo, gx(1) + gw(7) - 460, top + 60, 400)
        uiDot(g, gx(1) + 64, top + 66, 8, "#F4A259")
        lbl = "Starting soon"
        if hero.state = "in" then lbl = "On now"
        uiLabel(g, gx(1) + 84, top + 54, lbl, 24, "#F4F1EA")
        uiText(g, gx(1) + 56, top + 120, hero.name, 112, 600, "Outfit", "#F4F1EA", gw(7) - 112)
        t = hero.detail + " · " + tClock(hero.start)
        if hero.state = "in" then t = hero.detail + " · " + liveText(hero)
        if hero.network <> "" then t = t + " on " + hero.network
        uiText(g, gx(1) + 56, top + 290, t, 34, 500, "Manrope", "#F4F1EA", gw(7) - 112)
        if hero.wx <> invalid then uiText(g, gx(1) + 56, top + 350, "Game time: " + gameWxText(hero.wx), 30, 500, "Manrope", "#F4F1EA", gw(7) - 112)
    else
        uiCard(g, gx(1), top, gw(7), 520, "#131729", "#222842", 32)
        uiLabel(g, gx(1) + 56, top + 54, "Tonight", 24, "#B3A6F2")
        title = "A quiet night in"
        sub2 = "Nothing else on the family calendar tonight."
        for each e in d.calendar
            if tDay(e.start) = d.today and e.start >= d.now and title = "A quiet night in"
                title = e.title
                sub2 = tClock(e.start)
            end if
        end for
        uiText(g, gx(1) + 56, top + 120, title, 80, 500, "Outfit", "#F4F1EA", gw(7) - 112, "left", 2)
        uiText(g, gx(1) + 56, top + 330, sub2, 30, 400, "Manrope", "#A9B1C4", gw(7) - 112)
    end if
    rx = gx(8)
    rw = gw(5)
    lo = d.weather.temp
    for each hr in d.weather.hours
        if hr.t > d.now and hr.t <= d.now + 10 * 3600 and hr.temp < lo then lo = hr.temp
    end for
    uiCard(g, rx, top, rw, 220)
    cardLabel(g, rx + 40, top + 38, rw - 80, "Tonight", "#A9B1C4", asOfText(d, "weather"))
    uiImage(g, "pkg:/images/wx_moon.png", rx + 36, top + 88, 100, 100, "#B3A6F2")
    uiText(g, rx + 160, top + 80, d.weather.temp.ToStr() + "°", 88, 300, "Outfit")
    uiText(g, rx + 340, top + 96, wxLabel(d.weather.code), 30, 600, "Manrope", "#F4F1EA", rw - 380)
    uiText(g, rx + 340, top + 140, "Low " + lo.ToStr() + "° · tomorrow " + d.weather.days[1].hi.ToStr() + "°", 24, 400, "Manrope", "#A9B1C4", rw - 380, "left", 2)
    cy0 = top + 252
    uiCard(g, rx, cy0, rw, 268)
    uiLabel(g, rx + 40, cy0 + 32, "Coming up")
    yy = cy0 + 78
    if d.curb <> invalid and (d.curb.pickup - d.today) \ 86400 <= 1
        uiCard(g, rx + 30, yy - 10, rw - 60, 96, "#2A2418", "#F4A259", 18)
        uiText(g, rx + 54, yy, tDayWord(d.curb.pickup, d.today) + ": " + LCase(curbText(d.curb)), 26, 700, "Manrope", "#F4F1EA", rw - 108)
        s = "Curb by 7 AM"
        if d.curb.yard then s = s + " · no grass clippings"
        if curbCaveat(d.curb) <> "" then s = s + " · " + curbCaveat(d.curb)
        uiText(g, rx + 54, yy + 40, s, 24, 400, "Manrope", "#E1E4EC", rw - 108)
        yy = yy + 112
    end if
    n = 0
    for each e in d.calendar
        if e.start > d.now and n < 2 and yy < cy0 + 220
            uiText(g, rx + 40, yy, e.title, 26, 600, "Manrope", "#F4F1EA", rw - 280)
            uiText(g, rx + rw - 40, yy, tDayWord(e.start, d.today), 24, 400, "Manrope", "#A9B1C4", 220, "right")
            yy = yy + 46
            n = n + 1
        end if
    end for
    ay = top + 564
    uiLabel(g, 112, ay, "Your evening apps")
    apps = d.apps
    if apps = invalid or apps.Count() = 0 then apps = ["Netflix", "YouTube", "Prime Video", "Disney+", "Hulu", "Max"]
    tw = gw(2)
    for i = 0 to 5
        if i >= apps.Count() then exit for
        ax = gx(1 + i * 2)
        border = "#222842"
        if i = 0 then border = "#B3A6F2"
        uiCard(g, ax, ay + 44, tw, 110, "#1A1F36", border, 22)
        uiText(g, ax + tw / 2, ay + 82, apps[i], 30, 700, "Manrope", "#F4F1EA", tw - 24, "center")
    end for
end sub

sub buildWeek(g as object, d as object)
    uiWallpaper(g, d, "week", "#0B1120")
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
        isPickup = d.curb <> invalid
        if isPickup then isPickup = (tDay(d.curb.pickup) = day)
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
                uiText(g, x + 20, top + 74, wd.hi.ToStr() + "° / " + wd.lo.ToStr() + "°", 24, 400, "Manrope", "#C9CEDA", cw - 40)
                s = LCase(wxLabel(wd.code))
                if wd.rain >= 30 then s = s + " · " + wd.rain.ToStr() + "%"
                uiText(g, x + 20, top + 104, s, 24, 400, "Manrope", "#A9B1C4", cw - 40)
            end if
        end for
        items = []
        if isPickup then items.Push({hitBox: true, head: "Curb by 7 AM", body: curbText(d.curb), color: "#F4A259", bg: "#2A2418", sort: 0})
        for each e in d.calendar
            if tDay(e.start) = day
                if e.deadline
                    items.Push({hitBox: true, head: "Deadline", body: e.title, color: "#D9A6E0", bg: "#2A2033", sort: 1})
                else
                    head = "All day"
                    srt = 2
                    if not e.allDay
                        head = tClock(e.start)
                        srt = e.start - day
                    end if
                    items.Push({hitBox: false, head: head, body: e.title, sort: srt})
                end if
            end if
        end for
        for each gm in d.games
            if tDay(gm.start) = day
                head = tClock(gm.start)
                if gm.tbd then head = "Time TBA"
                items.Push({hitBox: false, head: head, body: gm.name + " " + gm.detail, sort: gm.start - day})
            end if
        end for
        if tWeekday(day) = 5
            for each mem in d.members
                if mem.band = true then items.Push({hitBox: true, head: mem.name, body: "Marching band at the game", color: mem.color, bg: "#2A2614", sort: 19 * 3600 + 1800})
            end for
        end if
        items = sortStable(items, "sort")
        yy = top + 150
        shown = 0
        for each it in items
            if yy < top + h - 120
                if it.hitBox
                    chip = uiCard(g, x + 12, yy - 8, cw - 24, 72, it.bg, "", 14)
                    uiText(g, x + 24, yy, it.head, 24, 700, "Manrope", it.color, cw - 48)
                    l = uiText(g, x + 24, yy + 34, it.body, 24, 500, "Manrope", "#F4F1EA", cw - 48, "left", 2)
                    chip.height = 34 + uiHeight(l, 24) + 22 ' grows to the body's real height (one or two lines)
                    yy = yy + chip.height + 10
                else
                    uiText(g, x + 20, yy, it.head, 24, 400, "Manrope", "#A9B1C4", cw - 40)
                    l = uiText(g, x + 20, yy + 30, it.body, 24, 600, "Manrope", "#F4F1EA", cw - 40, "left", 2)
                    yy = yy + 42 + uiHeight(l, 24)
                end if
                shown = shown + 1
            end if
        end for
        if shown < items.Count() then uiText(g, x + 20, top + h - 52, "+" + (items.Count() - shown).ToStr() + " more", 24, 600, "Manrope", "#A9B1C4")
    end for
    fy = 830
    uiCard(g, 112, fy, 1696, 190)
    uiLabel(g, 152, fy + 28, "Heads up", 24, "#F4A259")
    tw = (1696 - 80 - 72) / 3
    for i = 0 to 2
        if i < d.headsUp.Count() then uiText(g, 152 + i * (tw + 36), fy + 70, d.headsUp[i], 24, 500, "Manrope", "#F4F1EA", Int(tw), "left", 3)
    end for
end sub

' The forecast at an outdoor game's kickoff ({temp, rain, code} from DataTask).
function gameWxText(wx as object) as string
    t = wx.temp.ToStr() + "°, " + LCase(wxLabel(wx.code))
    if wx.rain >= 20 then t = t + ", " + wx.rain.ToStr() + "% chance of rain"
    return t
end function

' --- the weekend (Fridays and Saturdays) -----------------------------------------------

' The Saturday of the coming weekend: today on a Saturday, else the next one.
function weekendStart(today as integer) as integer
    return today + ((6 - tWeekday(today)) mod 7) * 86400
end function

function weatherOn(d as object, day as integer) as dynamic
    if d.weather = invalid then return invalid
    for each wd in d.weather.days
        if wd.day = day then return wd
    end for
    return invalid
end function

' Lower is better outside: rain chance, distance from 72°, wind over 15 mph.
function outdoorScore(wd as object) as float
    s = wd.rain + Abs(wd.hi - 72) * 1.5
    if wd.wind > 15 then s = s + (wd.wind - 15) * 2
    return s
end function

' Which weekend day is better outside: 0 (Saturday) or 1 (Sunday); -1 when
' they're about the same, -2 when rain is likely both days, -3 without a forecast.
function bestOutdoorDay(sat as dynamic, sun as dynamic) as integer
    if sat = invalid or sun = invalid then return -3
    if sat.rain >= 60 and sun.rain >= 60 then return -2
    a = outdoorScore(sat)
    b = outdoorScore(sun)
    if Abs(a - b) < 8 then return -1
    if a < b then return 0
    return 1
end function

function weekendVerdict(best as integer, days as object) as string
    if best = -3 then return ""
    if best = -2 then return "A wet weekend: rain is likely both days. Plan something indoors."
    if best = -1 then return "Both days look about the same outside."
    names = ["Saturday", "Sunday"]
    wd = days[best]
    return names[best] + " is the better day to be outside: " + wd.hi.ToStr() + "°, " + LCase(wxLabel(wd.code)) + "."
end function

sub buildWeekend(g as object, d as object)
    uiWallpaper(g, d, "weekend", "#0B1120")
    sat = weekendStart(d.today)
    header(g, "THE WEEKEND · " + UCase(tShortDate(sat)) + " AND " + UCase(tShortDate(sat + 86400)), "Weekend outlook", "#F4A259", false)
    updated = "Updated " + tClock(d.now)
    if asOfText(d, "weather") <> "" then updated = "Forecast " + asOfText(d, "weather")
    uiText(g, 1808, 140, updated, 24, 400, "Manrope", "#A9B1C4", 400, "right")
    days = [weatherOn(d, sat), weatherOn(d, sat + 86400)]
    best = bestOutdoorDay(days[0], days[1])
    top = 240
    h = 560
    for i = 0 to 1
        day = sat + i * 86400
        x = gx(1 + i * 6)
        cw = gw(6)
        border = "#1F2A44"
        if best = i then border = "#F4A259"
        uiCard(g, x, top, cw, h, "#131B2E", border, 28)
        uiText(g, x + 40, top + 36, UCase(tWeekdayNames()[tWeekday(day)]), 24, 700, "Manrope", "#F4A259")
        if best = i
            uiCard(g, x + cw - 300, top + 26, 260, 48, "#2A2418", "", 24)
            uiText(g, x + cw - 170, top + 36, "Best day outside", 24, 700, "Manrope", "#F4A259", 240, "center")
        end if
        wd = days[i]
        if wd <> invalid
            hi = wd.hi.ToStr() + "°"
            uiText(g, x + 40, top + 80, hi, 96, 400, "Outfit", "#F4F1EA", 220)
            uiText(g, x + 40 + Int(uiTextWidth(g, hi, 96, 400, "Outfit")) + 20, top + 120, "/ " + wd.lo.ToStr() + "°", 44, 400, "Outfit", "#A9B1C4", 200)
            line = wxLabel(wd.code) + " · " + wd.rain.ToStr() + "% chance of rain · wind " + wd.wind.ToStr() + " mph"
            uiText(g, x + 40, top + 208, line, 28, 500, "Manrope", "#F4F1EA", cw - 80)
            uiText(g, x + 40, top + 250, "Sunrise " + tClock(wd.sunrise) + " · sunset " + tClock(wd.sunset), 24, 400, "Manrope", "#A9B1C4", cw - 80)
        else
            uiText(g, x + 40, top + 100, "No forecast yet", 40, 400, "Outfit", "#A9B1C4", cw - 80)
        end if
        uiRect(g, x + 40, top + 300, cw - 80, 2, "#1F2A44")
        items = []
        for each e in d.calendar
            if tDay(e.start) = day
                head = "All day"
                srt = 0
                if not e.allDay
                    head = tClock(e.start)
                    srt = e.start - day
                end if
                if e.deadline then head = "Deadline"
                items.Push({head: head, body: e.title, sort: srt})
            end if
        end for
        for each gm in d.games
            if tDay(gm.start) = day
                head = tClock(gm.start)
                if gm.tbd then head = "Time TBA"
                body = gm.name + " " + gm.detail
                if gm.wx <> invalid then body = body + " · " + gm.wx.temp.ToStr() + "°, " + gm.wx.rain.ToStr() + "% rain"
                items.Push({head: head, body: body, sort: gm.start - day})
            end if
        end for
        items = sortStable(items, "sort")
        yy = top + 326
        if items.Count() = 0 then uiText(g, x + 40, yy, "Nothing on the calendar", 24, 400, "Manrope", "#A9B1C4", cw - 80)
        for k = 0 to items.Count() - 1
            if k < 4
                uiText(g, x + 40, yy, items[k].head, 24, 600, "Manrope", "#A9B1C4", 180)
                uiText(g, x + 230, yy, items[k].body, 24, 500, "Manrope", "#F4F1EA", cw - 270)
                yy = yy + 50
            end if
        end for
        if items.Count() > 4 then uiText(g, x + 40, yy, "+" + (items.Count() - 4).ToStr() + " more", 24, 600, "Manrope", "#A9B1C4")
    end for
    fy = 830
    uiCard(g, 112, fy, 1696, 190)
    uiLabel(g, 152, fy + 28, "Outside", 24, "#F4A259")
    verdict = weekendVerdict(best, days)
    if verdict = "" then verdict = "The weekend forecast isn't in yet."
    uiText(g, 152, fy + 68, verdict, 32, 500, "Manrope", "#F4F1EA", 1616)
    pl = d.place.lake
    if d.lake <> invalid and pl <> invalid
        diff = d.lake.level - pl.summerPool
        where = fmt1(Abs(diff)) + " ft below full summer pool."
        if diff >= 0 then where = fmt1(diff) + " ft above full summer pool."
        uiText(g, 152, fy + 120, pl.name + " is at " + fmt1(d.lake.level) + " ft, " + where, 24, 400, "Manrope", "#A9B1C4", 1616)
    end if
end sub

sub buildLake(g as object, d as object)
    lk = d.lake
    uiWallpaper(g, d, "lake", "#081420")
    pl = d.place.lake
    header(g, "OUTDOORS · " + UCase(pl.name), "Lake conditions", "#7FB7E8", false)
    uiText(g, 1808, 140, "USGS gauge " + pl.site + " · " + tClock(lk.time), 24, 400, "Manrope", "#9FB3C8", 600, "right")
    top = 246
    uiCard(g, gx(1), top, gw(4), 770, "#0E2033", "#1B3550", 32)
    gx0 = gx(1) + 60
    gy0 = top + 60
    gh = 640
    uiCard(g, gx0, gy0, 64, gh, "#132A42", "", 32)
    lvl = lk.level
    ' the gauge shows 20 ft, from 5 ft above summer pool down
    gTop = pl.summerPool + 5
    ly = gy0 + (gTop - lvl) / 20 * gh
    if ly < gy0 then ly = gy0
    if ly > gy0 + gh - 40 then ly = gy0 + gh - 40
    uiCard(g, gx0, ly, 64, gy0 + gh - ly, "#7FB7E8", "", 32)
    for each pool in [[pl.summerPool, "Summer full pool"], [pl.winterPool, "Winter pool"]]
        py = gy0 + (gTop - pool[0]) / 20 * gh
        uiRect(g, gx0 - 16, py - 1, 96, 3, "#F4F1EA")
        uiText(g, gx0 + 120, py - 38, pool[0].ToStr() + " ft", 26, 700)
        uiText(g, gx0 + 120, py - 6, pool[1], 24, 400, "Manrope", "#9FB3C8")
    end for
    uiText(g, gx0 + 120, ly - 24, fmt1(lvl), 84, 400, "Outfit")
    uiText(g, gx0 + 120, ly + 76, "feet now", 24, 600, "Manrope", "#7FB7E8")
    rx = gx(5)
    rw = gw(8)
    if lvl < pl.winterPool
        uiCard(g, rx, top, rw, 170, "#2A2418", "#5A4520")
        uiText(g, rx + 44, top + 30, fmt1(pl.summerPool - lvl) + " ft below summer pool, " + fmt1(pl.winterPool - lvl) + " ft below winter pool", 38, 500, "Outfit", "#F4F1EA", rw - 88)
        uiText(g, rx + 44, top + 98, "Low water. Check Corps ramp and beach status before you launch.", 26, 400, "Manrope", "#E1D3BE", rw - 88)
    else
        uiCard(g, rx, top, rw, 170, "#0E2033", "#1B3550")
        uiText(g, rx + 44, top + 54, "Lake is at normal levels", 40, 500, "Outfit")
    end if
    best = d.weather.days[0]
    bestScore = -1
    for i = 0 to 5
        if i < d.weather.days.Count()
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
        end if
    end for
    sunset = d.weather.days[0].sunset
    cards = [["Best lake day", tDayWord(best.day, d.today), "High " + best.hi.ToStr() + "°, " + LCase(wxLabel(best.code)) + ", wind up to " + best.wind.ToStr() + " mph"],
             ["Sunset on the water", tClock(sunset), "Golden hour starts " + tClock(sunset - 2400)],
             ["Fishing moon", Int(d.moon.illum * 100 + 0.5).ToStr() + "% lit", d.moon.name + " · full " + tShortDate(tUtcToWallApprox(d.moon.nextFull))]]
    cw = (rw - 64) / 3
    for i = 0 to 2
        cx = rx + i * (cw + 32)
        uiCard(g, cx, top + 202, cw, 568, "#0E2033", "#1B3550")
        uiLabel(g, cx + 36, top + 238, cards[i][0], 24, "#9FB3C8")
        uiText(g, cx + 36, top + 290, cards[i][1], 60, 500, "Outfit", "#F4F1EA", Int(cw) - 72)
        uiText(g, cx + 36, top + 400, cards[i][2], 26, 400, "Manrope", "#C9D6E3", Int(cw) - 72, "left", 4)
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
    header(g, "TONIGHT'S SKY OVER " + UCase(d.place.town), title, "#B3A6F2", false)
    mp = d.moon
    idx = Int(mp.age / 29.530588853 * 30)
    if idx > 29 then idx = 29
    uiImage(g, "pkg:/images/moon_" + tPad(idx, 2) + ".png", 112, 330, 300, 300)
    uiText(g, 452, 370, Int(mp.illum * 100 + 0.5).ToStr() + "%", 72, 300, "Outfit")
    uiText(g, 452, 462, mp.name, 28, 600, "Manrope", "#F4F1EA", 240, "left", 2)
    uiText(g, 452, 540, "Full moon " + tShortDate(tUtcToWallApprox(mp.nextFull)), 24, 400, "Manrope", "#B8BED0", 240)
    uiCard(g, gx(5) + 16, 300, 1808 - gx(5) - 16, 380, "#131729", "#2A3050", 32)
    s = d.shower
    tx = gx(5) + 64
    tw = 1808 - tx - 48
    if s <> invalid
        lbl = "Coming up"
        if (s.peak - d.today) \ 86400 <= 7 then lbl = "This week's show"
        uiLabel(g, tx, 340, lbl, 24, "#B3A6F2")
        uiText(g, tx, 384, s.name + " meteor shower peaks " + tDayWord(s.peak, d.today) + " night", 54, 500, "Outfit", "#F4F1EA", tw, "left", 2)
        tip = "Best in the dark hours before dawn. Face away from town lights."
        if d.place.lake <> invalid then tip = tip + " The " + d.place.lake.name + " shoreline is darker than downtown."
        uiText(g, tx, 540, tip, 26, 400, "Manrope", "#C9CEDA", tw, "left", 3)
    else
        uiLabel(g, tx, 340, "Tonight", 24, "#B3A6F2")
        m2 = moonWords(mp.name)
        uiText(g, tx, 384, m2.line, 54, 500, "Outfit", "#F4F1EA", tw, "left", 2)
        uiText(g, tx, 540, m2.tip, 26, 400, "Manrope", "#C9CEDA", tw, "left", 3)
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
    for i = 0 to 2
        x = gx(1 + i * 4)
        w3 = gw(4)
        uiCard(g, x, 760, w3, 256, "#131729", "#2A3050")
        uiLabel(g, x + 36, 794, cards[i][0], 24, "#A3A9C2")
        uiText(g, x + 36, 836, cards[i][1], 40, 500, "Outfit", "#F4F1EA", w3 - 72)
        uiText(g, x + 36, 910, cards[i][2], 24, 400, "Manrope", "#C9CEDA", w3 - 72, "left", 2)
    end for
end sub

sub buildRecap(g as object, d as object)
    uiWallpaper(g, d, "recap", "#0B1120")
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
        fans = {}
        fans[r.winner] = fansOf(d, r.winner)
        fans[r.loser] = fansOf(d, r.loser)
        win = teamNamed(d, r.winner)
        color = "#5C0A18"
        accent = "#F4F1EA"
        if win <> invalid
            color = win.color
            if win.accent <> invalid then accent = win.accent
        end if
        uiCard(g, gx(1), top, gw(6) + 40, 770, color, "", 32)
        teamLogo(g, logoOf(d, r.winner), gx(1) + gw(6) + 40 - 500, top + 230, 460, 0.12)
        uiLabel(g, gx(1) + 56, top + 54, "House divided · final", 24, accent)
        uiText(g, gx(1) + 56, top + 120, r.winner + " " + r.hi.ToStr(), 120, 600, "Outfit")
        uiText(g, gx(1) + 56, top + 280, r.loser + " " + r.lo.ToStr(), 80, 400, "Outfit", "#C9CEDA")
        brag = r.winner + " fans have bragging rights."
        if fans[r.winner] <> "" then brag = fans[r.winner] + " have bragging rights."
        if fans[r.loser] <> "" then brag = brag + " " + fans[r.loser] + ", there's always next year."
        uiText(g, gx(1) + 56, top + 460, brag, 34, 500, "Manrope", "#F4F1EA", gw(6) - 72, "left", 3)
        uiText(g, gx(1) + 56, top + 690, r.host + " hosted · " + r.network, 26, 400, "Manrope", "#C9CEDA", gw(6) - 72)
    else if hero <> invalid
        uiCard(g, gx(1), top, gw(6) + 40, 770, hero.color, "", 32)
        teamLogo(g, hero.logo, gx(1) + gw(6) + 40 - 500, top + 270, 460, 0.12)
        res = "Loss · "
        if hero.won then res = "Win · "
        uiLabel(g, gx(1) + 56, top + 54, res + hero.team, 24, "#F4F1EA")
        uiText(g, gx(1) + 56, top + 140, hero.score, 190, 600, "Outfit")
        uiText(g, gx(1) + 56, top + 400, hero.detail, 36, 600, "Manrope", "#F4F1EA", gw(6) - 72)
    end if
    rx = gx(7) + 40
    rw = 1808 - rx
    uiCard(g, rx, top, rw, 520)
    uiLabel(g, rx + 40, top + 38, "More results")
    yy = top + 90
    n = 0
    for each f in d.finals
        skip = (f.rivalry and r <> invalid) or (hero <> invalid and f.start = hero.start and f.team = hero.team)
        if not skip and n < 6
            bg = "#3A2024"
            fg = "#F2A7B0"
            wl = "L"
            if f.won
                bg = "#1F3A2A"
                fg = "#9EC79B"
                wl = "W"
            end if
            uiCard(g, rx + 40, yy, 60, 42, bg, "", 10)
            uiText(g, rx + 70, yy + 5, wl, 24, 800, "Manrope", fg, 60, "center")
            label = f.team + " " + f.detail
            if not f.pro then label = f.team + " " + sportCase(f.detail)
            uiText(g, rx + 124, yy + 4, label, 26, 600, "Manrope", "#F4F1EA", rw - 300)
            uiText(g, rx + rw - 40, yy, f.score, 32, 400, "Outfit", "#F4F1EA", 150, "right")
            yy = yy + 64
            n = n + 1
        end if
    end for
    if n = 0 then uiText(g, rx + 40, yy, "No other finals in the last day and a half.", 26, 400, "Manrope", "#A9B1C4", rw - 80)
    uiCard(g, rx, top + 552, rw, 218)
    uiLabel(g, rx + 40, top + 588, "Season records")
    i = 0
    for each t in recordTeams(d)
        label = t.name
        if fansOf(d, t.name) <> "" then label = label + " (" + fansOf(d, t.name) + ")"
        uiText(g, rx + 40, top + 636 + i * 56, label, 26, 600, "Manrope", "#F4F1EA", rw - 280)
        rec = d.records[t.key]
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

function teamNamed(d as object, name as string) as dynamic
    for each t in d.place.teams
        if t.name = name then return t
    end for
    return invalid
end function

' Season records to show: the rivalry pair, or else the first two teams.
function recordTeams(d as object) as object
    out = []
    if d.place.rivalry <> invalid
        for each n in d.place.rivalry
            t = teamNamed(d, n)
            if t <> invalid then out.Push(t)
        end for
    end if
    if out.Count() = 0
        for i = 0 to d.place.teams.Count() - 1
            if i < 2 then out.Push(d.place.teams[i])
        end for
    end if
    return out
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
    divided = false
    pair = d.place.rivalry
    if panels.Count() = 2 and pair <> invalid and pair.Count() = 2
        divided = (panels[0].name = pair[0] and panels[1].name = pair[1]) or (panels[0].name = pair[1] and panels[1].name = pair[0])
    end if
    for i = 0 to panels.Count() - 1
        gm = panels[i]
        x = i * pw
        uiRect(g, x, 0, pw, 790, gm.color)
        align = "left"
        tx = x + 112
        ls = 640
        if panels.Count() = 2 then ls = 460
        lx = x + pw - ls - 80 ' the logo sits on the side away from the text
        if i = 1
            align = "right"
            tx = x + pw - 112
            lx = x + 80
        end if
        teamLogo(g, gm.logo, lx, (790 - ls) / 2, ls)
        lbl = "GAME DAY"
        if gm.state = "in" then lbl = "ON NOW"
        if divided then lbl = lbl + " · HOUSE DIVIDED"
        uiText(g, tx, 72, lbl, 24, 700, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        size = 160
        if panels.Count() = 2 then size = 132
        uiText(g, tx, 110, gm.name, size, 600, "Outfit", "#F4F1EA", Int(pw) - 224, align)
        uiText(g, tx, 130 + size + 20, gm.detail, 34, 500, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        if gm.state = "in"
            uiText(g, tx, 520, gm.my + "–" + gm.their, 120, 500, "Outfit", "#F4F1EA", Int(pw) - 224, align)
            if gm.status <> invalid and gm.status <> "" then uiText(g, tx, 400, gm.status, 34, 600, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        else
            uiText(g, tx, 540, tClock(gm.start), 100, 300, "Outfit", "#F4F1EA", Int(pw) - 224, align)
        end if
        if gm.network <> "" then uiText(g, tx, 680, "on " + gm.network, 30, 600, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        if gm.wx <> invalid then uiText(g, tx, 728, "Game time: " + gameWxText(gm.wx), 30, 500, "Manrope", "#F4F1EA", Int(pw) - 224, align)
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
    for i = 0 to others.Count() - 1
        gm = others[i]
        x = gx(1 + i * 3)
        cw = gw(3)
        uiCard(g, x, 830, cw, 190)
        teamLogo(g, gm.logo, x + cw - 140, 856, 120, 0.18)
        uiCard(g, x + 36, 866, 18, 18, gm.color, "", 10)
        uiText(g, x + 66, 856, gm.name, 26, 700, "Manrope", "#F4F1EA", cw - 100)
        uiText(g, x + 36, 900, gameWhenShort(gm, d.today), 34, 400, "Outfit", "#F4F1EA", cw - 72)
        uiText(g, x + 36, 958, gm.detail, 24, 400, "Manrope", "#A9B1C4", cw - 72)
    end for
end sub

sub buildSchool(g as object, d as object)
    uiWallpaper(g, d, "school", "#0B1120")
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
    uiCard(g, gx(1), top, gw(6) + 40, 770, "#132235", "", 32)
    uiLabel(g, gx(1) + 52, top + 48, "Coming up · from the family calendar", 24, "#7FB7E8")
    yy = top + 116
    for each e in items
        uiText(g, gx(1) + 52, yy, tShortDate(e.start), 28, 700, "Manrope", "#7FB7E8")
        t = e.title
        if e.subtitle <> "" then t = t + " · " + e.subtitle
        uiText(g, gx(1) + 52, yy + 38, t, 32, 600, "Manrope", "#F4F1EA", gw(6) - 64)
        uiText(g, gx(1) + 52, yy + 82, tDayWord(e.start, d.today) + " · " + e.whoText, 24, 400, "Manrope", "#A9B1C4", gw(6) - 64)
        yy = yy + 128
    end for
    if items.Count() = 0 then uiText(g, gx(1) + 52, yy, "No school dates on the calendar this month.", 30, 400, "Manrope", "#A9B1C4", gw(6) - 64)
    kids = []
    for each mem in d.members
        if mem.school <> invalid then kids.Push(mem)
    end for
    if kids.Count() = 0 then return
    rx = gx(7) + 40
    rw = 1808 - rx
    kh = (770 - 28 * (kids.Count() - 1)) / kids.Count()
    for i = 0 to kids.Count() - 1
        k = kids[i]
        ky = top + i * (kh + 28)
        uiCard(g, rx, ky, rw, kh)
        uiRect(g, rx + 28, ky + 1, rw - 56, 6, k.color)
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
    uiWallpaper(g, d, "board", "#0B1120")
    header(g, "FAMILY BOARD", "Notes for the " + d.household, "#F4A259", false)
    uiText(g, 1808, 140, "Add an event called ""TV: your note"" to the family calendar", 24, 400, "Manrope", "#A9B1C4", 900, "right")
    top = 246
    cw = gw(4)
    maxNotes = 4
    if d.chores.Count() > 0 then maxNotes = 2 ' chores take the bottom row
    for i = 0 to d.notes.Count() - 1
        if i < maxNotes
            n = d.notes[i]
            x = gx(1 + (i mod 2) * 4)
            y = top + (i \ 2) * 397
            uiCard(g, x, y, cw, 373, "#1B2433", "")
            uiRect(g, x + 28, y + 1, cw - 56, 6, n.color)
            uiText(g, x + 40, y + 46, n.text, 44, 500, "Outfit", "#F4F1EA", cw - 80, "left", 4)
            uiText(g, x + 40, y + 316, n.from, 24, 400, "Manrope", "#A9B1C4", cw - 80)
        end if
    end for
    if d.chores.Count() > 0
        cy0 = top + 397
        uiCard(g, gx(1), cy0, gw(8), 373)
        uiLabel(g, gx(1) + 40, cy0 + 36, "Whose turn")
        yy = cy0 + 88
        for each c in d.chores
            if yy < cy0 + 340
                uiDot(g, gx(1) + 52, yy + 18, 9, c.color)
                uiText(g, gx(1) + 76, yy, c.who, 30, 700, "Manrope", "#F4F1EA", 220)
                uiText(g, gx(1) + 310, yy + 2, c.task, 28, 500, "Manrope", "#F4F1EA", gw(8) - 600)
                when = "Tomorrow: "
                if c.every = "week" then when = "Next week: "
                uiText(g, gx(1) + gw(8) - 40, yy + 4, when + c.next, 24, 400, "Manrope", "#A9B1C4", 260, "right")
                yy = yy + 64
            end if
        end for
    end if
    gx0 = gx(9)
    gw0 = gw(4)
    gtop = top
    if d.countdowns.Count() > 0
        n = d.countdowns.Count()
        if n > 3 then n = 3
        ch = 84 + n * 70
        uiCard(g, gx0, top, gw0, ch, "#1B2433", "")
        uiRect(g, gx0 + 28, top + 1, gw0 - 56, 6, "#B3A6F2")
        uiLabel(g, gx0 + 40, top + 34, "Counting down", 24, "#B3A6F2")
        for i = 0 to n - 1
            c = d.countdowns[i]
            cy = top + 80 + i * 70
            days = c.days.ToStr()
            unit = "days"
            if c.days = 1 then unit = "day"
            if c.days = 0
                days = "Today"
                unit = ""
            end if
            uiText(g, gx0 + 40, cy, days, 44, 500, "Outfit", "#F4F1EA", 130)
            uiText(g, gx0 + 176, cy + 4, c.title, 26, 600, "Manrope", "#F4F1EA", gw0 - 216)
            uiText(g, gx0 + 176, cy + 36, unit + " · " + tShortDate(c.day), 24, 400, "Manrope", "#A9B1C4", gw0 - 216)
        end for
        gtop = top + ch + 24
    end if
    uiCard(g, gx0, gtop, gw0, top + 770 - gtop)
    uiLabel(g, gx0 + 40, gtop + 38, "Grocery list")
    yy = gtop + 98
    for i = 0 to d.groceries.Count() - 1
        if yy < top + 770 - 60
            uiCard(g, gx0 + 40, yy + 4, 28, 28, "#131B2E", "#A9B1C4", 10)
            uiText(g, gx0 + 88, yy, d.groceries[i], 28, 400, "Manrope", "#F4F1EA", gw0 - 128)
            yy = yy + 56
        end if
    end for
    if d.groceries.Count() = 0 then uiText(g, gx0 + 40, yy, "Add ""Buy: milk, eggs"" to the family calendar", 24, 400, "Manrope", "#A9B1C4", gw0 - 80, "left", 3)
end sub

' Three notes per month for West Georgia (USDA zone 8a), shown on the Season screen.
function seasonItems(month as integer) as dynamic
    if month = 1 then return [["Winter", "Long nights", "Early sunsets and cold, clear air make January good for stargazing. Orion is high in the evening sky."], ["In the garden", "Plan and prune", "Order seeds and prune fruit trees and summer-blooming shrubs while they're dormant."], ["On the wing", "Winter visitors", "Juncos and white-throated sparrows visit feeders, and bald eagles nest near big lakes."]]
    if month = 2 then return [["Late winter", "First blooms", "Red maples, daffodils and Japanese magnolias often bloom in February, ahead of spring."], ["In the garden", "Prune roses, plant peas", "Prune roses in mid to late February. Lettuce, peas and onions can go in now."], ["Outdoors", "Frogs are calling", "Spring peepers and chorus frogs call from wet ditches and ponds on mild nights."]]
    if month = 3 then return [["Spring color", "Azaleas and dogwoods", "Native azaleas and then dogwoods bloom from late March into April. Callaway's azalea trails are a highlight."], ["In the garden", "Last frost is near", "The last frost usually comes in late March or early April. Wait for April to plant tomatoes."], ["On the wing", "Hummingbirds return", "Ruby-throated hummingbirds arrive in late March. Put feeders out by mid-month."]]
    if month = 4 then return [["Spring", "Pine pollen season", "Yellow pine pollen coats cars and porches in early April. Keep windows closed on the worst days."], ["In the garden", "Warm-season planting", "Tomatoes, peppers and beans go in once nights stay above 50°, usually by mid-April."], ["On the lake", "Spring fishing", "Crappie and bass move shallow as the water warms. A good month for an early boat ride."]]
    if month = 5 then return [["Early summer", "Magnolias and gardenias", "Southern magnolias and gardenias bloom, and evenings are still comfortable."], ["In the garden", "Mulch before the heat", "Mulch beds now and water deeply once a week instead of a little every day."], ["Outdoors", "Fireflies", "Fireflies start blinking over lawns and fields on warm, still evenings."]]
    if month = 6 then return [["Summer", "The longest days", "Around the June solstice there are more than 14 hours of daylight."], ["In the garden", "First tomatoes", "Pick in the morning and water early, not at night, to keep leaf disease down."], ["Outdoors", "Pop-up storms", "Afternoon thunderstorms are common. When thunder roars, go indoors."]]
    if month = 7 then return [["Summer", "Peak heat", "July is usually the hottest month. Plan outdoor time for early morning or evening."], ["In the garden", "Keep it going", "Water deeply in the morning. Late July is the time to start fall vegetables from seed."], ["On the lake", "Early and late", "Boating and swimming are best before the heat and the afternoon storms build."]]
    if month = 8 then return [["Late summer", "Dog days", "Hot, humid days with pop-up storms, and the tropics get busier."], ["In the garden", "Start fall crops", "Sow collards, kale and broccoli for a fall harvest."], ["Night sky", "Perseid meteors", "The Perseids peak around August 12. The best viewing is after midnight."]]
    if month = 9 then return [["Early fall", "Goldenrod and asters", "Roadsides turn gold with goldenrod, and nights start to cool late in the month."], ["In the garden", "Fall planting begins", "Plant cool-season greens, and divide crowded perennials as the heat breaks."], ["On the wing", "Hummingbirds leave", "Most hummingbirds head south by early October. Leave feeders up until then."]]
    if month = 10 then return [["Fall color", "Starting to turn", "Usually peaks here in late October to early November. Callaway's trails are the closest showcase."], ["In the garden", "Plant pansies and shrubs", "Fall is Georgia's best season for trees and shrubs. Divide perennials; spring bulbs go in next month."], ["On the wing", "Monarchs passing through", "October is monarch migration month in Georgia. Late-blooming flowers help them refuel."]]
    if month = 11 then return [["Fall color", "Peak season", "Early November is usually peak color around LaGrange and Pine Mountain."], ["In the garden", "Plant spring bulbs", "Tulips, daffodils and hyacinths go in now through December. Mulch beds before the first hard freeze."], ["Outdoors", "Fantasy in Lights season", "Callaway Gardens' holiday light show opens in mid-November."]]
    if month = 12 then return [["Winter", "Bare branches, big skies", "Long nights and clear air make December great for stargazing; the Geminids peak mid-month."], ["In the garden", "Protect and plan", "Cover tender plants on frost nights and order seeds for spring."], ["On the wing", "Winter birds at feeders", "Juncos, white-throated sparrows and yellow-rumped warblers arrive for the winter."]]
    return invalid
end function

sub buildSeason(g as object, d as object)
    uiWallpaper(g, d, "season", "#0B1120", "pkg:/images/bg_season.jpg")
    header(g, "WHAT'S IN SEASON · " + UCase(tMonthNames()[tParts(d.now).m - 1]), "The season in " + d.place.seasonRegion, "#F4A259", false)
    cards = []
    cards.Append(seasonItems(tParts(d.now).m))
    frost = invalid
    for i = 1 to 3
        if frost = invalid and i < d.weather.days.Count()
            if d.weather.days[i].lo <= 34 then frost = d.weather.days[i]
        end if
    end for
    if frost <> invalid
        cards.Push(["Frost watch", "Frost " + tDayWord(frost.day, d.today), "Low of " + frost.lo.ToStr() + "° forecast. Cover tender plants."])
    else
        cards.Push(["Frost watch", "None this week", "No frost in the 3-day forecast. Daybreak warns two days ahead."])
    end if
    for i = 0 to 3
        x = gx(1 + i * 3)
        cw = gw(3)
        uiCard(g, x, 540, cw, 476, "#0B1120", "#2A3656", 28, 0.9)
        uiLabel(g, x + 36, 576, cards[i][0], 24, "#F4A259")
        uiText(g, x + 36, 620, cards[i][1], 40, 500, "Outfit", "#F4F1EA", cw - 72, "left", 2)
        uiText(g, x + 36, 740, cards[i][2], 26, 400, "Manrope", "#E1E4EC", cw - 72, "left", 7)
    end for
end sub

sub buildRadar(g as object, d as object)
    uiImage(g, "pkg:/images/radar_base.jpg", 0, 0, 1920, 1080)
    layer = radarLayer(d.radarTimes, radarView(d.home.lat, d.home.lon).bbox)
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
    ' town and water labels from the place, skipping any that would sit under a card
    view = radarView(d.home.lat, d.home.lon)
    cards = [[gx(1), 64, gx(1) + gw(4), 314], [gx(9), 64, 1808, 314], [gx(1), 876, gx(1) + gw(6), 1016], [gx(7), 876, 1808, 1016]]
    rp = d.place.radar
    if rp <> invalid
        for each pl in rp.places
            px = radarPx(view, pl.lat, pl.lon)
            w = Len(pl.name) * 15 + 20
            lx = px[0] + 14
            align = "left"
            if lx + w > 1880
                lx = px[0] - 14
                align = "right"
            end if
            hitBox = [lx, px[1] - 15, lx + w, px[1] + 15]
            if align = "right" then hitBox = [lx - w, px[1] - 15, lx, px[1] + 15]
            if onMap(px, hitBox, cards) and Abs(px[0] - 960) + Abs(px[1] - 540) > 60
                uiDot(g, px[0], px[1], 5, "#E1E4EC")
                if align = "right" then uiText(g, lx, px[1] - 15, pl.name, 24, 600, "Manrope", "#E1E4EC", w, "right") else uiText(g, lx, px[1] - 15, pl.name, 24, 600, "Manrope", "#E1E4EC")
            end if
        end for
        if rp.water <> invalid
            for each wl in rp.water
                px = radarPx(view, wl.lat, wl.lon)
                w = Len(wl.name) * 15 + 20
                if onMap(px, [px[0] - w, px[1] - 13, px[0], px[1] + 13], cards) then uiText(g, px[0], px[1] - 13, wl.name, 24, 600, "Manrope", "#A9C8EE", w, "right")
            end for
        end if
    end if
    uiText(g, 984, 516, d.place.town, 34, 600, "Outfit")
    uiText(g, 960, 244, "25 mi", 24, 600, "Manrope", "#C9CEDA", 120, "center")
    ' Say plainly whether the map is clear or the radar didn't load, so an
    ' empty map never looks like a broken one.
    ' (the TV can't read the frames' pixels, so "no rain" comes from the forecast)
    status = "No rain nearby"
    sub2 = "Radar is live · latest scan " + radarLatestText(d) + ". Rain shows in color."
    if d.radarTimes.Count() = 0
        status = "Radar unavailable"
        sub2 = "Couldn't reach NOAA's radar just now. The forecast shows no rain for " + d.place.town + " in the next 2 hours."
    end if
    if d.rainSoon
        status = "Rain likely soon"
        sub2 = "Forecast shows rain near " + d.place.town + " within 2 hours"
    end if
    if d.storms.Count() > 0
        st = d.storms[0]
        sub2 = "Tropics: " + st.kind + " " + st.name + ", " + st.miles.ToStr() + " mi away"
    end if
    ' a warning outranks the forecast: never say "no rain" while one is in effect
    for each al in d.alerts
        if al.level = "warning" and status <> "Warning in effect"
            status = "Warning in effect"
            sub2 = "Watch for storms moving toward " + d.place.town + ". Details are on the alert screen."
        end if
    end for
    uiCard(g, gx(1), 64, gw(4), 250, "#0B1120", "#1F2A44", 28, 0.92)
    dotColor = "#9EC79B"
    if d.rainSoon then dotColor = "#F4A259"
    uiDot(g, gx(1) + 38, 108, 7, dotColor)
    uiLabel(g, gx(1) + 58, 96, "Live radar · West Georgia")
    uiText(g, gx(1) + 40, 134, status, 46, 500, "Outfit", "#F4F1EA", gw(4) - 80)
    uiText(g, gx(1) + 40, 206, sub2, 24, 400, "Manrope", "#C9CEDA", gw(4) - 80, "left", 2)
    warn = d.alerts.Count() > 0
    fill = "#0B1120"
    if warn then fill = "#5C0A18"
    ax = gx(9)
    uiCard(g, ax, 64, gw(4), 250, fill, "#1F2A44", 28, 0.92)
    uiLabel(g, ax + 40, 96, "Alerts · " + d.place.area)
    if warn
        yy = 136
        for each a in d.alerts
            if yy < 280
                l = uiText(g, ax + 40, yy, a.event, 32, 600, "Manrope", "#F4F1EA", gw(4) - 80, "left", 2)
                yy = yy + uiHeight(l, 32) + 8
            end if
        end for
    else if d.alertsKnown = false
        uiText(g, ax + 40, 136, "Unavailable", 40, 500, "Outfit")
        uiText(g, ax + 40, 200, "Couldn't reach the National Weather Service. Check local news in severe weather.", 24, 400, "Manrope", "#F4A259", gw(4) - 80, "left", 3)
    else
        uiText(g, ax + 40, 136, "None in effect", 40, 500, "Outfit")
        uiText(g, ax + 40, 206, "National Weather Service, Peachtree City", 24, 400, "Manrope", "#A9B1C4", gw(4) - 80, "left", 2)
    end if
    uiCard(g, gx(1), 876, gw(6), 140, "#0B1120", "#1F2A44", 28, 0.92)
    uiText(g, gx(1) + 40, 898, "Past 2 hours", 24, 600)
    m.radarTimeLabel = uiText(g, gx(1) + gw(6) - 40, 898, "", 24, 700, "Manrope", "#F4A259", 300, "right")
    m.radarSegs = []
    n = frames.Count()
    if n > 0
        segw = (gw(6) - 80 - (n - 1) * 6) / n
        for j = 0 to n - 1
            m.radarSegs.Push(uiCard(g, gx(1) + 40 + j * (segw + 6), 960, segw, 12, "#2A3656", "", 10))
        end for
    end if
    lx0 = gx(7)
    uiCard(g, lx0, 876, gw(6), 140, "#0B1120", "#1F2A44", 28, 0.92)
    uiLabel(g, lx0 + 40, 898, "Precipitation")
    ' colors sampled from MRMS frames: blue for drizzle and very light rain up to magenta for hail
    legend = [["Very light", "#4660A0", "#5BA5CA"], ["Light", "#02FD02", "#01C501"], ["Moderate", "#FDF802", "#FD9500"], ["Heavy", "#FD0000", "#BC0000"], ["Hail", "#F800FD", "#9854C6"]]
    lw = (gw(6) - 80 - 4 * 16) / 5
    for j = 0 to 4
        lx = lx0 + 40 + j * (lw + 16)
        uiRect(g, lx, 944, lw / 2, 14, legend[j][1])
        uiRect(g, lx + lw / 2, 944, lw / 2, 14, legend[j][2])
        uiText(g, lx, 966, legend[j][0], 24, 400, "Manrope", "#C9CEDA", Int(lw))
    end for
    showRadarFrame(m.radarFrame)
end sub

' Radar frames as one group of posters, kept between builds of the radar
' screen while the frame times are unchanged, so rotating back to radar (or a
' data refresh) doesn't create and download a second set. Frames load at
' 960x540 (about 2 MB each decoded instead of 8 MB) and are scaled to fill
' the screen; low memory keeps only the latest 4.
function radarLayer(times as object, bbox as string) as object
    picks = times
    if m.lowMemory = true and times.Count() > 4
        picks = []
        for i = times.Count() - 4 to times.Count() - 1
            picks.Push(times[i])
        end for
    end if
    key = bbox + "|" + picks.Join(",")
    if m.radarCache <> invalid and m.radarCache.key = key then return m.radarCache
    group = CreateObject("roSGNode", "Group")
    frames = []
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

' True when a label's point is on screen and its hitBox clears every card.
function onMap(px as object, hitBox as object, cards as object) as boolean
    if px[0] < 20 or px[0] > 1900 or px[1] < 20 or px[1] > 1060 then return false
    for each c in cards
        if hitBox[0] < c[2] and hitBox[2] > c[0] and hitBox[1] < c[3] and hitBox[3] > c[1] then return false
    end for
    return true
end function

' Clock time of the newest radar frame ("1:08 PM"), or "—".
function radarLatestText(d as object) as string
    if d.radarTimes.Count() = 0 then return "—"
    return tClock(tUtcIsoToWall(Left(d.radarTimes[d.radarTimes.Count() - 1], 19) + "Z"))
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
