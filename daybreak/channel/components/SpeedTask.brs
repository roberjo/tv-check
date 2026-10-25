' Speed test, run only when asked from the diagnostics screen: three empty
' requests for latency, then a 25 MB download to tmp: (deleted afterwards).
' Same method as diag-channel.

sub init()
    m.top.functionName = "runTest"
end sub

sub runTest()
    m.top.result = {state: "running"}
    best = 0
    for i = 1 to 3
        ut = speedTransfer("https://speed.cloudflare.com/__down?bytes=0")
        t = CreateObject("roTimespan")
        ut.GetToString()
        ms = t.TotalMilliseconds()
        if best = 0 or ms < best then best = ms
    end for
    path = "tmp:/daybreak_speed.bin"
    ut = speedTransfer("https://speed.cloudflare.com/__down?bytes=25000000")
    t = CreateObject("roTimespan")
    code = ut.GetToFile(path)
    ms = t.TotalMilliseconds()
    fs = CreateObject("roFileSystem")
    st = fs.Stat(path)
    size = 0
    if st <> invalid then size = st.size
    fs.Delete(path)
    if code <> 200 or size = 0 or ms = 0
        m.top.result = {state: "error", error: "HTTP " + code.ToStr()}
        return
    end if
    m.top.result = {state: "done", mbps: size * 8.0 / (ms * 1000.0), latencyMs: best, bytes: size, ms: ms}
end sub

function speedTransfer(url as string) as object
    ut = CreateObject("roUrlTransfer")
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.SetUrl(url)
    return ut
end function
