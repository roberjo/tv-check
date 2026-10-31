' Screens: weather warning, loading and the night clock.

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
