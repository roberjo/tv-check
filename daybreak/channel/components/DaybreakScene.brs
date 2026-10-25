' Daybreak scene: owns the data task, picks screens, crossfades between them,
' keeps the clock exact and animates radar. Screens rebuild only when they
' rotate in or their data changes; the data task publishes only on content
' changes. Memory is checked every 10 s and low memory trims radar frames and
' photo backgrounds.
'
' Remote (app only; any key ends the screensaver): Left/Right browse, Play
' pauses, OK opens the menu (pause, go to a screen, settings, diagnostics),
' * (Options) opens diagnostics, Back closes an overlay or exits.

sub init()
    m.stage = m.top.findNode("stage")
    m.navLayer = m.top.findNode("navLayer")
    m.overlay = m.top.findNode("overlay")
    m.status = m.top.findNode("status")
    m.fade = m.top.findNode("fade")
    m.fadeIn = m.top.findNode("fadeIn")
    m.fadeOut = m.top.findNode("fadeOut")
    m.progress = m.top.findNode("progress")
    m.progressWidth = m.top.findNode("progressWidth")
    m.rotateTimer = m.top.findNode("rotateTimer")
    m.clockTimer = m.top.findNode("clockTimer")
    m.frameTimer = m.top.findNode("frameTimer")
    m.pausedTimer = m.top.findNode("pausedTimer")
    m.hintTimer = m.top.findNode("hintTimer")
    m.dataTask = m.top.findNode("dataTask")
    m.items = []
    m.index = 0
    m.data = invalid
    m.current = invalid
    m.serial = 0
    m.paused = false
    m.lowMemory = false
    m.overlayKind = ""
    m.memMonitor = CreateObject("roAppMemoryMonitor")
    m.deviceInfo = CreateObject("roDeviceInfo")
    m.startedAt = CreateObject("roTimespan")
    m.registry = CreateObject("roRegistrySection", "daybreak")
    m.rotateTimer.observeField("fire", "onRotate")
    m.clockTimer.observeField("fire", "onClockTick")
    m.frameTimer.observeField("fire", "onFrame")
    m.pausedTimer.observeField("fire", "onPausedRefresh")
    m.hintTimer.observeField("fire", "hideHint")
    m.fade.observeField("state", "onFadeState")
    m.top.setFocus(true)
end sub

sub onStart()
    cfg = DaybreakConfig()
    m.settings = loadSettings(cfg)
    showLoading("Getting today's weather, calendar and games...")
    m.dataTask.config = cfg
    m.dataTask.settings = m.settings
    m.dataTask.observeField("data", "onData")
    m.dataTask.observeField("health", "onHealth")
    m.dataTask.control = "RUN"
    m.clockTimer.control = "start"
    if m.top.mode = "app" then maybeShowHint()
end sub

sub onData()
    m.data = m.dataTask.data
    if m.data = invalid then return
    if m.data.weather = invalid and m.data.calendar.Count() = 0
        showLoading("Waiting for the internet connection...")
        return
    end if
    replan(false)
end sub

' Re-picks the playlist (new data, a setting changed) and keeps the current
' screen if it's still in it.
sub replan(forceRebuild as boolean)
    if m.data = invalid then return
    currentId = invalid
    if m.items.Count() > 0 and m.index < m.items.Count() then currentId = m.items[m.index]
    m.items = chooseScreens(m.data, m.top.mode, m.settings.hidden)
    found = -1
    for i = 0 to m.items.Count() - 1
        if m.items[i] = currentId then found = i
    end for
    if found >= 0
        m.index = found
        show(found, forceRebuild) ' rebuild in place with fresh data
    else
        show(0, true)
    end if
end sub

sub show(i as integer, restartTimer as boolean)
    if m.items.Count() = 0 then return
    m.index = i
    id = m.items[i]
    ' relative times ("in 2 h 10 m", the sun's position) use the time of building
    m.data.now = tNowWall()
    m.data.today = tDay(m.data.now)
    grp = invalid
    try
        grp = buildScreen(id, m.data)
    catch e
        ' A screen that fails to build is skipped rather than freezing the screensaver.
        print "Daybreak: screen '"; id; "' failed: "; e.message
        if m.items.Count() > 1 and restartTimer
            m.items.Delete(i)
            show(i mod m.items.Count(), true)
        end if
        return
    end try
    m.serial = m.serial + 1
    grp.id = "screen" + m.serial.ToStr()
    grp.opacity = 0
    m.stage.appendChild(grp)
    m.fadeIn.fieldToInterp = grp.id + ".opacity"
    if m.current <> invalid
        m.fadeOut.fieldToInterp = m.current.id + ".opacity"
    else
        m.fadeOut.fieldToInterp = ""
    end if
    m.previous = m.current
    m.current = grp
    m.fade.control = "start"
    updateClock()
    m.frameTimer.control = "stop"
    if m.radarFrames <> invalid and m.radarFrames.Count() > 1 then m.frameTimer.control = "start"
    if restartTimer
        m.rotateTimer.control = "stop"
        m.rotateTimer.duration = rotationSeconds(id, m.settings.speed)
        if not isHeld() then m.rotateTimer.control = "start"
    end if
    updateNav(restartTimer)
end sub

' Rotation stops while paused or while the menu or diagnostics are open.
function isHeld() as boolean
    return m.paused or m.overlayKind = "menu" or m.overlayKind = "diagnostics"
end function

sub onFadeState()
    if m.fade.state = "stopped"
        ' drop everything but the screen now showing
        while m.stage.getChildCount() > 1
            child = m.stage.getChild(0)
            if child.isSameNode(m.current) then exit while
            m.stage.removeChild(child)
        end while
    end if
end sub

' The skeleton screen (date, clock, placeholder cards) until real data arrives.
sub showLoading(message as string)
    if m.loading <> invalid and m.current <> invalid and m.current.isSameNode(m.loading) then m.stage.removeChild(m.loading)
    m.loading = buildLoading(tNowWall(), message)
    m.serial = m.serial + 1
    m.loading.id = "screen" + m.serial.ToStr()
    m.stage.appendChild(m.loading)
    if m.current <> invalid and not m.current.isSameNode(m.loading) then m.stage.removeChild(m.current)
    m.current = m.loading
    updateClock()
end sub

' --- page dots and progress -----------------------------------------------------

sub updateNav(restartProgress as boolean)
    m.navLayer.removeChildrenIndex(m.navLayer.getChildCount(), 0)
    if m.top.mode <> "app" or m.items.Count() = 0 then return
    nav = buildNav(m.items, m.index, m.paused)
    m.navLayer.appendChild(nav)
    bar = nav.findNode("navProgress")
    m.progressWidth.fieldToInterp = "navProgress.width"
    if restartProgress
        m.progress.control = "stop"
        m.progress.duration = rotationSeconds(m.items[m.index], m.settings.speed)
        bar.width = 0
        if not isHeld() then m.progress.control = "start"
    else
        bar.width = 1920 * 0.5
    end if
end sub

' --- clock, memory, refresh -----------------------------------------------------

' Every source failing for two tries in a row means the TV is offline: say so,
' and when the saved data is from.
sub onHealth()
    h = m.dataTask.health
    if h = invalid or h.sources = invalid then return
    tried = 0
    failing = 0
    lastOk = 0
    for each name in h.sources
        s = h.sources[name]
        tried = tried + 1
        if not s.ok and s.fails >= 2 then failing = failing + 1
        if s.lastOk <> invalid and s.lastOk > lastOk then lastOk = s.lastOk
    end for
    offline = tried > 0 and failing = tried
    if offline and lastOk > 0
        m.status.text = "Offline · showing saved data from " + tClock(lastOk + (tNowWall() - tNowUtc()))
    else if offline
        m.status.text = "Offline · waiting for the internet connection"
    else
        m.status.text = ""
    end if
    if m.overlayKind = "diagnostics" then refreshDiagnostics()
end sub

sub onClockTick()
    updateClock()
    checkMemory()
end sub

' "low" or "critical" general memory, or the app past 80% of its limit, turns
' on the light mode: fewer radar frames and no photo backgrounds.
sub checkMemory()
    low = false
    if m.deviceInfo <> invalid
        level = m.deviceInfo.GetGeneralMemoryLevel()
        if level = "low" or level = "critical" then low = true
    end if
    if m.memMonitor <> invalid
        if m.memMonitor.GetMemoryLimitPercent() >= 80 then low = true
    end if
    if low <> m.lowMemory
        m.lowMemory = low
        print "Daybreak: low memory mode "; low
        if low then m.radarCache = invalid
    end if
end sub

' While paused, rebuild the screen every 5 minutes so relative times stay right.
sub onPausedRefresh()
    if m.paused and m.items.Count() > 0 then show(m.index, false)
end sub

sub onRotate()
    if m.items.Count() = 0 then return
    show((m.index + 1) mod m.items.Count(), true)
end sub

sub onFrame()
    if m.radarFrames = invalid or m.radarFrames.Count() < 2 then return
    m.radarFrame = (m.radarFrame + 1) mod m.radarFrames.Count()
    showRadarFrame(m.radarFrame)
end sub

' --- settings -----------------------------------------------------------------------

function loadSettings(cfg as object) as object
    s = defaultSettings(cfg)
    if m.registry <> invalid and m.registry.Exists("settings")
        saved = ParseJson(m.registry.Read("settings"))
        if saved <> invalid
            if saved.gentleNews <> invalid then s.gentleNews = saved.gentleNews
            if saved.speed <> invalid then s.speed = saved.speed
            if saved.hidden <> invalid then s.hidden = saved.hidden
        end if
    end if
    return s
end function

sub saveSettings()
    if m.registry = invalid then return
    m.registry.Write("settings", FormatJson(m.settings))
    m.registry.Flush()
    m.dataTask.settings = m.settings
end sub

' --- first-run hint -------------------------------------------------------------------

' The remote hint shows on the first three app launches, for 8 seconds.
sub maybeShowHint()
    if m.registry = invalid then return
    n = 0
    if m.registry.Exists("hints") then n = Val(m.registry.Read("hints"))
    if n >= 3 then return
    m.registry.Write("hints", (n + 1).ToStr())
    m.registry.Flush()
    setOverlay("hint", buildHint())
    m.hintTimer.control = "start"
end sub

sub hideHint()
    if m.overlayKind = "hint" then setOverlay("", invalid)
end sub

' --- overlays (menu, diagnostics) -----------------------------------------------------

sub setOverlay(kind as string, node as dynamic)
    wasHeld = isHeld()
    m.overlay.removeChildrenIndex(m.overlay.getChildCount(), 0)
    m.overlayKind = kind
    if node <> invalid then m.overlay.appendChild(node)
    held = isHeld()
    if held and not wasHeld
        m.rotateTimer.control = "stop"
        m.progress.control = "pause"
    else if wasHeld and not held and m.items.Count() > 0
        show(m.index, true) ' restart this screen's time
    end if
end sub

sub openMenu(page as string)
    if m.menu = invalid or page = "main" then m.menu = {page: "main", index: 0}
    m.menu.page = page
    if page <> "main" then m.menu.index = 0
    drawMenu()
end sub

sub drawMenu()
    all = []
    for each id in ["briefing", "ambient", "tonight", "week", "recap", "gameday", "radar", "lake", "sky", "school", "board", "season"]
        all.Push(id)
    end for
    m.menu.settings = m.settings
    m.menu.paused = m.paused
    m.menu.items = m.items
    m.menu.all = all
    setOverlay("menu", buildMenu(m.menu))
end sub

sub menuSelect()
    entries = menuEntries(m.menu)
    if entries.Count() = 0 then return
    action = entries[m.menu.index].action
    if action = "close"
        setOverlay("", invalid)
    else if action = "pause"
        setOverlay("", invalid)
        togglePause()
    else if action = "diagnostics"
        openDiagnostics()
    else if Left(action, 5) = "page:"
        openMenu(Mid(action, 6))
    else if Left(action, 5) = "goto:"
        id = Mid(action, 6)
        setOverlay("", invalid)
        for i = 0 to m.items.Count() - 1
            if m.items[i] = id then show(i, true)
        end for
    else if action = "toggle:gentleNews"
        m.settings.gentleNews = not m.settings.gentleNews
        saveSettings()
        drawMenu()
    else if action = "speed"
        m.settings.speed = nextSpeed(m.settings.speed)
        saveSettings()
        drawMenu()
    else if Left(action, 7) = "screen:"
        id = Mid(action, 8)
        if m.settings.hidden.DoesExist(id) then m.settings.hidden.Delete(id) else m.settings.hidden[id] = true
        saveSettings()
        replan(false)
        drawMenu()
    end if
end sub

sub openDiagnostics()
    setOverlay("diagnostics", invalid)
    refreshDiagnostics()
end sub

sub refreshDiagnostics()
    m.overlay.removeChildrenIndex(m.overlay.getChildCount(), 0)
    m.overlay.appendChild(buildDiagnostics(gatherDiagnostics()))
end sub

' Device-side values for the diagnostics screen (buildDiagnostics draws them).
function gatherDiagnostics() as object
    di = m.deviceInfo
    info = {nowUtc: tNowUtc(), health: m.dataTask.health, limits: sourceLimitsForDiag(), speed: m.speed}
    info.version = CreateObject("roAppInfo").GetVersion()
    mem = {lowMode: m.lowMemory, nodes: countNodes(m.top)}
    if m.memMonitor <> invalid
        mem.availableKb = m.memMonitor.GetChannelAvailableMemory()
        mem.limitPercent = m.memMonitor.GetMemoryLimitPercent()
    end if
    if di <> invalid then mem.level = di.GetGeneralMemoryLevel()
    info.memory = mem
    if di <> invalid
        os = di.GetOSVersion()
        osText = ""
        if os <> invalid then osText = os.major + "." + os.minor + " build " + os.build
        ui = di.GetUIResolution()
        info.device = {model: di.GetModelDisplayName() + " (" + di.GetModel() + ")", os: osText,
                       display: di.GetDisplayMode() + " · UI " + ui.name, appUptimeMin: m.startedAt.TotalSeconds() \ 60}
        ips = di.GetIPAddrs()
        ip = ""
        for each k in ips
            if ip = "" then ip = ips[k]
        end for
        kind = di.GetConnectionType()
        if kind = "WiredConnection" then kind = "Ethernet"
        if kind = "WiFiConnection" then kind = "Wi-Fi"
        info.network = {type: kind, ip: ip, link: di.GetLinkStatus()}
    end if
    return info
end function

' Same numbers as DataTask's sourceLimits(), for coloring the diagnostics rows.
function sourceLimitsForDiag() as object
    return {
        weather: {ttl: 600, maxAge: 3 * 3600}, alerts: {ttl: 120, maxAge: 1800}, lake: {ttl: 1800, maxAge: 12 * 3600},
        sports: {ttl: 900, maxAge: 6 * 3600}, lc: {ttl: 1800, maxAge: 24 * 3600}, news: {ttl: 1800, maxAge: 12 * 3600},
        calendar: {ttl: 600, maxAge: 24 * 3600}, radar: {ttl: 600, maxAge: 1800}
    }
end function

function countNodes(n as object) as integer
    c = 1
    for i = 0 to n.getChildCount() - 1
        c = c + countNodes(n.getChild(i))
    end for
    return c
end function

sub startSpeedTest()
    if m.speed <> invalid and m.speed.state = "running" then return
    m.speedTask = CreateObject("roSGNode", "SpeedTask")
    m.speedTask.observeField("result", "onSpeed")
    m.speed = {state: "running"}
    m.speedTask.control = "RUN"
    refreshDiagnostics()
end sub

sub onSpeed()
    m.speed = m.speedTask.result
    if m.overlayKind = "diagnostics" then refreshDiagnostics()
end sub

sub togglePause()
    m.paused = not m.paused
    if m.paused
        m.rotateTimer.control = "stop"
        m.progress.control = "pause"
        m.pausedTimer.control = "start"
    else
        m.pausedTimer.control = "stop"
    end if
    if m.items.Count() > 0 then show(m.index, not m.paused)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.overlayKind = "hint" then hideHint()
    if m.overlayKind = "menu"
        n = menuEntries(m.menu).Count()
        if key = "up" then m.menu.index = (m.menu.index - 1 + n) mod n
        if key = "down" then m.menu.index = (m.menu.index + 1) mod n
        if key = "up" or key = "down" then drawMenu()
        if key = "OK" then menuSelect()
        if key = "back" or key = "left"
            if m.menu.page = "main" then setOverlay("", invalid) else openMenu("main")
        end if
        return true
    end if
    if m.overlayKind = "diagnostics"
        if key = "OK" then startSpeedTest()
        if key = "back" or key = "options" then setOverlay("", invalid)
        return true
    end if
    if key = "OK"
        openMenu("main")
        return true
    end if
    if key = "options"
        openDiagnostics()
        return true
    end if
    if m.items.Count() = 0 then return false
    if key = "right"
        show((m.index + 1) mod m.items.Count(), true)
        return true
    else if key = "left"
        show((m.index - 1 + m.items.Count()) mod m.items.Count(), true)
        return true
    else if key = "play"
        togglePause()
        return true
    end if
    return false
end function
