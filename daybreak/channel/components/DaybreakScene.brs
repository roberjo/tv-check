' Daybreak scene: owns the data task, picks screens, crossfades between them,
' keeps the clock exact and animates radar. Left/Right browse, Play pauses.
' Screens rebuild only when they rotate in or their data changes; the data
' task publishes only on content changes. Memory is checked every 10 s and
' low memory trims radar frames and photo backgrounds.

sub init()
    m.stage = m.top.findNode("stage")
    m.status = m.top.findNode("status")
    m.fade = m.top.findNode("fade")
    m.fadeIn = m.top.findNode("fadeIn")
    m.fadeOut = m.top.findNode("fadeOut")
    m.rotateTimer = m.top.findNode("rotateTimer")
    m.clockTimer = m.top.findNode("clockTimer")
    m.frameTimer = m.top.findNode("frameTimer")
    m.pausedTimer = m.top.findNode("pausedTimer")
    m.dataTask = m.top.findNode("dataTask")
    m.items = []
    m.index = 0
    m.data = invalid
    m.current = invalid
    m.serial = 0
    m.paused = false
    m.lowMemory = false
    m.memMonitor = CreateObject("roAppMemoryMonitor")
    m.deviceInfo = CreateObject("roDeviceInfo")
    m.rotateTimer.observeField("fire", "onRotate")
    m.clockTimer.observeField("fire", "onClockTick")
    m.frameTimer.observeField("fire", "onFrame")
    m.pausedTimer.observeField("fire", "onPausedRefresh")
    m.fade.observeField("state", "onFadeState")
    m.top.setFocus(true)
end sub

sub onStart()
    showLoading("Getting today's weather, calendar and games...")
    m.dataTask.config = DaybreakConfig()
    m.dataTask.observeField("data", "onData")
    m.dataTask.observeField("health", "onHealth")
    m.dataTask.control = "RUN"
    m.clockTimer.control = "start"
end sub

sub onData()
    m.data = m.dataTask.data
    if m.data = invalid then return
    if m.data.weather = invalid and m.data.calendar.Count() = 0
        showLoading("Waiting for the internet connection...")
        return
    end if
    currentId = invalid
    if m.items.Count() > 0 then currentId = m.items[m.index]
    m.items = chooseScreens(m.data, m.top.mode)
    found = -1
    for i = 0 to m.items.Count() - 1
        if m.items[i] = currentId then found = i
    end for
    if found >= 0
        m.index = found
        show(found, false) ' rebuild in place with fresh data; keep the rotation timer running
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
        m.rotateTimer.duration = screenSeconds(id)
        if not m.paused then m.rotateTimer.control = "start"
    end if
end sub

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
    else if not m.paused
        m.status.text = ""
    end if
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

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or m.items.Count() = 0 then return false
    if key = "right"
        show((m.index + 1) mod m.items.Count(), true)
        return true
    else if key = "left"
        show((m.index - 1 + m.items.Count()) mod m.items.Count(), true)
        return true
    else if key = "play"
        m.paused = not m.paused
        if m.paused
            m.rotateTimer.control = "stop"
            m.pausedTimer.control = "start"
            m.status.text = "Paused. Press Play to resume."
        else
            m.status.text = ""
            m.pausedTimer.control = "stop"
            m.rotateTimer.control = "start"
        end if
        return true
    end if
    return false
end function
