' Screens: Week ahead and Weekend.

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
