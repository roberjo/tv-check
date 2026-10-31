' (DaybreakScene.xml loads every file in components/screens/.)
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
