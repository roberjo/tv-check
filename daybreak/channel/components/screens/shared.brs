' Screens: pieces shared by several screens.

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
