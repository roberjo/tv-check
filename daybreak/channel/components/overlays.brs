' Overlays drawn above the screens: page dots and rotation progress, the
' first-run remote hint, the OK menu (with settings) and the diagnostics
' screen. Builders take plain data so they also run off-device (tests and
' daybreak/preview); DaybreakScene gathers the device values.

' --- settings ----------------------------------------------------------------------

' Defaults come from family.json via the generated config; the menu saves
' changes to the registry (see DaybreakScene).
function defaultSettings(cfg as dynamic) as object
    s = {gentleNews: true, speed: "normal", hidden: {}}
    if cfg <> invalid and cfg.gentleNews <> invalid then s.gentleNews = cfg.gentleNews
    return s
end function

' Seconds a screen stays up at the chosen rotation speed.
function rotationSeconds(id as string, speed as string) as integer
    s = screenSeconds(id)
    if speed = "slow" then return s * 2
    if speed = "fast" then return Int(s * 0.6)
    return s
end function

function speedLabel(speed as string) as string
    if speed = "slow" then return "Slow"
    if speed = "fast" then return "Fast"
    return "Normal"
end function

function nextSpeed(speed as string) as string
    if speed = "normal" then return "slow"
    if speed = "slow" then return "fast"
    return "normal"
end function

' --- page dots and progress --------------------------------------------------------

' One dot per screen in the playlist (the current one wide and amber) centered
' at the bottom, the screen's name beside it, and a thin progress line along
' the bottom edge that DaybreakScene animates over the screen's time.
function buildNav(items as object, index as integer, paused as boolean) as object
    g = CreateObject("roSGNode", "Group")
    n = items.Count()
    total = 0
    for i = 0 to n - 1
        total = total + 12
        if i = index then total = total + 28
        if i < n - 1 then total = total + 10
    end for
    x = 960 - total / 2
    for i = 0 to n - 1
        w = 12
        color = "#5A6380"
        if i = index
            w = 40
            color = "#F4A259"
        end if
        uiCard(g, x, 1040, w, 12, color, "", 10)
        x = x + w + 10
    end for
    name = screenTitles()[items[index]]
    if name = invalid then name = items[index]
    if paused then name = name + " · paused"
    uiText(g, 960 - total / 2 - 24, 1030, name, 24, 600, "Manrope", "#C9CEDA", 500, "right")
    track = uiRect(g, 0, 1076, 1920, 4, "#1F2A44", 0.8)
    track.id = "navTrack"
    bar = uiRect(g, 0, 1076, 0, 4, "#F4A259", 0.9)
    bar.id = "navProgress"
    return g
end function

' --- first-run hint ----------------------------------------------------------------

function buildHint() as object
    g = CreateObject("roSGNode", "Group")
    uiCard(g, 460, 860, 1000, 150, "#070B14", "#F4A259", 28, 0.94)
    uiLabel(g, 500, 884, "Remote", 24, "#F4A259")
    keys = [["Left / Right", "browse"], ["Play", "pause"], ["OK", "menu"], ["*", "diagnostics"]]
    for i = 0 to 3
        x = 500 + i * 236
        uiText(g, x, 926, keys[i][0], 26, 700, "Manrope", "#F4F1EA", 220)
        uiText(g, x, 962, keys[i][1], 24, 400, "Manrope", "#A9B1C4", 220)
    end for
    return g
end function

' --- OK menu -----------------------------------------------------------------------

' Menu pages as lists of {label, value, action}. state = {page, index, settings,
' paused, items (playlist), all (every screen id)}.
function menuEntries(state as object) as object
    st = state.settings
    if state.page = "screens"
        out = []
        for each id in state.items
            out.Push({label: screenTitles()[id], value: "", action: "goto:" + id})
        end for
        return out
    end if
    if state.page = "settings"
        out = [{label: "Gentle news", value: onOff(st.gentleNews), action: "toggle:gentleNews"},
               {label: "Rotation speed", value: speedLabel(st.speed), action: "speed"}]
        for each id in state.all
            shown = not st.hidden.DoesExist(id)
            out.Push({label: screenTitles()[id], value: onOff(shown), action: "screen:" + id})
        end for
        return out
    end if
    pause = "Pause rotation"
    if state.paused then pause = "Resume rotation"
    return [{label: pause, value: "", action: "pause"}, {label: "Go to screen", value: "", action: "page:screens"},
            {label: "Settings", value: "", action: "page:settings"}, {label: "Diagnostics", value: "", action: "diagnostics"},
            {label: "Close", value: "", action: "close"}]
end function

function onOff(v as boolean) as string
    if v then return "On"
    return "Off"
end function

' A panel on the right with the page's entries; the focused one is highlighted.
' Long pages scroll so the focused entry stays visible.
function buildMenu(state as object) as object
    g = CreateObject("roSGNode", "Group")
    uiRect(g, 0, 0, 1920, 1080, "#000000", 0.45)
    px = 1184
    uiRect(g, px, 0, 736, 1080, "#0B1120", 0.97)
    uiRect(g, px, 0, 2, 1080, "#1F2A44")
    titles = {main: "Daybreak", screens: "Go to screen", settings: "Settings"}
    uiLabel(g, px + 64, 72, "Menu", 24, "#F4A259")
    uiText(g, px + 64, 108, titles[state.page], 56, 500, "Outfit", "#F4F1EA", 600)
    entries = menuEntries(state)
    rowH = 76
    visible = 10
    first = 0
    if state.index >= visible then first = state.index - visible + 1
    y = 220
    for i = first to entries.Count() - 1
        if i < first + visible
            e = entries[i]
            if i = state.index then uiCard(g, px + 40, y, 656, rowH - 8, "#1A2440", "#F4A259", 18)
            uiText(g, px + 72, y + 18, e.label, 30, 600, "Manrope", "#F4F1EA", 420)
            if e.value <> ""
                vc = "#A9B1C4"
                if e.value = "On" then vc = "#9EC79B"
                uiText(g, px + 664, y + 20, e.value, 28, 600, "Manrope", vc, 200, "right")
            end if
            y = y + rowH
        end if
    end for
    hint = "Up / Down to move, OK to choose, Back to close"
    if state.page <> "main" then hint = "OK to change, Back for the menu"
    uiText(g, px + 64, 1000, hint, 24, 400, "Manrope", "#A9B1C4", 640)
    return g
end function

' --- diagnostics -------------------------------------------------------------------

' info = {now, version, health: {sources, savedAt, warm, cacheBytes}, limits,
' memory: {availableKb, limitPercent, level, lowMode, nodes}, device: {model,
' os, display, ui, uptimeMin, appUptimeMin}, network: {type, ip, link},
' speed: {state, mbps, latencyMs, error}}. Missing parts show as "—".
function buildDiagnostics(info as object) as object
    g = CreateObject("roSGNode", "Group")
    uiRect(g, 0, 0, 1920, 1080, "#070B14", 0.98)
    uiLabel(g, 112, 62, "Diagnostics · Daybreak " + strOr(info.version), 24, "#F4A259")
    uiText(g, 112, 100, "How Daybreak is doing", 76, 500, "Outfit", "#F4F1EA", 1300)
    uiText(g, 1808, 140, "Back to close", 24, 400, "Manrope", "#A9B1C4", 400, "right")
    ' data sources
    top = 246
    uiCard(g, gx(1), top, gw(8), 770)
    uiLabel(g, gx(1) + 40, top + 36, "Data sources")
    cols = [["Source", 0], ["Updated", 280], ["Time", 470], ["Size", 600], ["Status", 730]]
    for each c in cols
        uiText(g, gx(1) + 40 + c[1], top + 88, c[0], 24, 700, "Manrope", "#A9B1C4")
    end for
    yy = top + 132
    names = ["weather", "alerts", "air", "lake", "sports", "lc", "news", "calendar", "radar", "tropics"]
    labels = {weather: "Weather", alerts: "NWS alerts", air: "Air quality", lake: "Lake gauge", sports: "Team schedules",
              lc: "College iCal", news: "Headlines", calendar: "Family calendar", radar: "Radar times", tropics: "Tropics (NHC)"}
    sources = {}
    if info.health <> invalid and info.health.sources <> invalid then sources = info.health.sources
    for each name in names
        s = sources[name]
        dot = "#5A6380"
        updated = "not yet"
        ms = "—"
        size = "—"
        status = "waiting"
        if s <> invalid
            dot = sourceColor(s, info.limits, name, info.nowUtc)
            if s.lastOk <> invalid then updated = agoText(info.nowUtc - s.lastOk)
            ms = s.ms.ToStr() + " ms"
            size = kbText(s.bytes)
            status = "OK"
            if not s.ok
                status = s.error
                if status = "" then status = "HTTP " + s.code.ToStr()
                if s.fails > 1 then status = status + " (" + s.fails.ToStr() + "x)"
            else if s.parts > 1 and s.okParts < s.parts
                status = s.okParts.ToStr() + " of " + s.parts.ToStr() + " answered"
            end if
        end if
        uiDot(g, gx(1) + 48, yy + 16, 8, dot)
        uiText(g, gx(1) + 68, yy, labels[name], 26, 600, "Manrope", "#F4F1EA", 250)
        uiText(g, gx(1) + 320, yy, updated, 24, 400, "Manrope", "#C9CEDA", 180)
        uiText(g, gx(1) + 510, yy, ms, 24, 400, "Manrope", "#C9CEDA", 120)
        uiText(g, gx(1) + 640, yy, size, 24, 400, "Manrope", "#C9CEDA", 120)
        uiText(g, gx(1) + 770, yy, status, 24, 400, "Manrope", "#C9CEDA", gw(8) - 810)
        yy = yy + 54
    end for
    warm = "No saved data yet"
    if info.health <> invalid and info.health.savedAt <> invalid and info.health.savedAt > 0
        warm = "Saved " + agoText(info.nowUtc - info.health.savedAt) + " · " + kbText(info.health.cacheBytes)
        if isTrue(info.health.warm) then warm = warm + " · started warm"
    end if
    uiText(g, gx(1) + 40, top + 700, "Warm-start cache: " + warm, 24, 400, "Manrope", "#A9B1C4", gw(8) - 80)
    ' memory, device, network, speed
    rx = gx(9)
    rw = gw(4)
    mem = info.memory
    if mem = invalid then mem = {}
    lines = [["App memory free", kbMb(mem.availableKb)], ["App limit used", pctText(mem.limitPercent)],
             ["Memory level", strOr(mem.level)], ["Low-memory mode", onOffDash(mem.lowMode)], ["Screen elements", strOr(mem.nodes)]]
    diagCard(g, rx, top, rw, 288, "Memory", lines)
    dev = info.device
    if dev = invalid then dev = {}
    net = info.network
    if net = invalid then net = {}
    lines = [["Model", strOr(dev.model)], ["Roku OS", strOr(dev.os)], ["Display", strOr(dev.display)],
             ["Network", strOr(net.type)], ["IP address", strOr(net.ip)], ["Daybreak up", minutesText(dev.appUptimeMin)]]
    diagCard(g, rx, top + 312, rw, 340, "Device", lines)
    sp = info.speed
    uiCard(g, rx, top + 676, rw, 94)
    uiLabel(g, rx + 36, top + 690, "Speed test")
    t = "Press OK to run (downloads 25 MB)"
    if sp <> invalid
        if sp.state = "running" then t = "Running..."
        if sp.state = "done" then t = fmt1(sp.mbps) + " Mbps down · " + sp.latencyMs.ToStr() + " ms"
        if sp.state = "error" then t = "Failed: " + strOr(sp.error)
    end if
    uiText(g, rx + 36, top + 724, t, 26, 600, "Manrope", "#F4F1EA", rw - 72)
    return g
end function

sub diagCard(g as object, x as integer, y as integer, w as integer, h as integer, title as string, lines as object)
    uiCard(g, x, y, w, h)
    uiLabel(g, x + 36, y + 30, title)
    for i = 0 to lines.Count() - 1
        uiText(g, x + 36, y + 76 + i * 42, lines[i][0], 24, 400, "Manrope", "#A9B1C4", 236)
        uiText(g, x + w - 36, y + 76 + i * 42, lines[i][1], 24, 600, "Manrope", "#F4F1EA", w - 296, "right")
    end for
end sub

' Green when fresh, amber when failing once or past twice the refresh
' interval, red when failing repeatedly or past its maximum age.
function sourceColor(s as object, limits as dynamic, name as string, nowUtc as integer) as string
    age = 0
    if s.lastOk <> invalid then age = nowUtc - s.lastOk
    lim = invalid
    if limits <> invalid then lim = limits[name]
    if s.lastOk = invalid or s.fails >= 3 then return "#E5484D"
    if lim <> invalid and age > lim.maxAge then return "#E5484D"
    if s.fails > 0 or (lim <> invalid and age > 2 * lim.ttl) then return "#F4A259"
    return "#9EC79B"
end function

function agoText(sec as integer) as string
    if sec < 60 then return "just now"
    if sec < 3600 then return (sec \ 60).ToStr() + " min ago"
    if sec < 86400 then return (sec \ 3600).ToStr() + " h ago"
    return (sec \ 86400).ToStr() + " d ago"
end function

function kbText(bytes as dynamic) as string
    if bytes = invalid then return "—"
    if bytes < 1024 then return bytes.ToStr() + " B"
    return Int(bytes / 1024 + 0.5).ToStr() + " KB"
end function

function kbMb(kb as dynamic) as string
    if kb = invalid then return "—"
    return Int(kb / 1024 + 0.5).ToStr() + " MB"
end function

function pctText(v as dynamic) as string
    if v = invalid then return "—"
    return v.ToStr() + "%"
end function

function minutesText(v as dynamic) as string
    if v = invalid then return "—"
    if v < 60 then return v.ToStr() + " min"
    return (v \ 60).ToStr() + " h " + (v mod 60).ToStr() + " min"
end function

function onOffDash(v as dynamic) as string
    if v = invalid then return "—"
    return onOff(v)
end function

function strOr(v as dynamic) as string
    if v = invalid then return "—"
    if type(v) = "roString" or type(v) = "String" then
        if v = "" then return "—"
        return v
    end if
    return v.ToStr()
end function
