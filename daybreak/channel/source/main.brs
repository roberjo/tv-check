' Daybreak: a standalone family dashboard. One package, two entry points:
' Main for the app, RunScreenSaver for the screensaver. All data is fetched
' on the TV by DataTask; no other computer is involved.

sub Main()
    RunDaybreak("app")
end sub

sub RunScreenSaver()
    RunDaybreak("screensaver")
end sub

sub RunDaybreak(mode as string)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("DaybreakScene")
    screen.Show()
    ' Roku measures the TV's network throughput once a minute; diagnostics graphs it
    syslog = CreateObject("roSystemLog")
    if syslog <> invalid
        syslog.SetMessagePort(port)
        syslog.EnableType("bandwidth.minute")
    end if
    scene.mode = mode ' set last: starts the data task
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
        if type(msg) = "roSystemLogEvent"
            info = msg.GetInfo()
            if info.LogType = "bandwidth.minute" then scene.bandwidthKbps = info.bandwidth
        end if
    end while
end sub
