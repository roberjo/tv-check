' Screens: Ambient, Briefing and Tonight.

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
