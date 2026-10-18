' Daybreak scene: owns the data task, picks screens, crossfades between them,
' keeps the clock exact and animates radar. Left/Right browse, Play pauses.

sub init()
    m.stage = m.top.findNode("stage")
    m.status = m.top.findNode("status")
    m.fade = m.top.findNode("fade")
    m.fadeIn = m.top.findNode("fadeIn")
    m.fadeOut = m.top.findNode("fadeOut")
    m.rotateTimer = m.top.findNode("rotateTimer")
    m.clockTimer = m.top.findNode("clockTimer")
    m.frameTimer = m.top.findNode("frameTimer")
    m.dataTask = m.top.findNode("dataTask")
    m.items = []
    m.index = 0
    m.data = invalid
    m.current = invalid
    m.serial = 0
    m.paused = false
    m.rotateTimer.observeField("fire", "onRotate")
    m.clockTimer.observeField("fire", "updateClock")
    m.frameTimer.observeField("fire", "onFrame")
    m.fade.observeField("state", "onFadeState")
    m.status.text = "Loading Daybreak..."
    m.top.setFocus(true)
end sub

sub onStart()
    m.dataTask.config = DaybreakConfig()
    m.dataTask.observeField("data", "onData")
    m.dataTask.control = "RUN"
    m.clockTimer.control = "start"
end sub

sub onData()
    m.data = m.dataTask.data
    if m.data = invalid then return
    if m.data.weather = invalid and m.data.calendar.Count() = 0
        m.status.text = "Waiting for the internet connection..."
        return
    end if
    m.status.text = ""
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
            m.status.text = "Paused. Press Play to resume."
        else
            m.status.text = ""
            m.rotateTimer.control = "start"
        end if
        return true
    end if
    return false
end function
