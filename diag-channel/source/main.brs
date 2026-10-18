' Read-only device diagnostics. Each result is printed to the dev console
' (port 8085) as a line "DIAG|<section>|<json>" for scripts/run_diag.py to collect.

sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("DiagScene")
    screen.Show()

    di = CreateObject("roDeviceInfo")

    scene.status = "Reading device and display info..."
    Emit("device", {
        model: di.GetModel()
        modelDisplayName: di.GetModelDisplayName()
        modelType: di.GetModelType()
        modelDetails: di.GetModelDetails()
        osVersion: di.GetOSVersion()
        uptimeMs: CreateObject("roAppManager").GetUptime().TotalMilliseconds()
        graphicsPlatform: di.GetGraphicsPlatform()
        generalMemoryLevel: di.GetGeneralMemoryLevel()
        captionsMode: di.GetCaptionsMode()
        audioGuideEnabled: di.IsAudioGuideEnabled()
    })
    Emit("display", {
        displayType: di.GetDisplayType()
        displayMode: di.GetDisplayMode()
        videoMode: di.GetVideoMode()
        aspectRatio: di.GetDisplayAspectRatio()
        displaySize: di.GetDisplaySize()
        uiResolution: di.GetUIResolution()
        displayProperties: di.GetDisplayProperties()
        graphicsResolutions: di.GetSupportedGraphicsResolutions()
    })

    scene.status = "Checking codec support..."
    Emit("video_codecs", {
        hevc_main10_4k: di.CanDecodeVideo({Codec: "hevc", Profile: "main 10", Level: "5.1", Container: "mp4"})
        hevc_main_4k: di.CanDecodeVideo({Codec: "hevc", Profile: "main", Level: "5.1", Container: "mp4"})
        vp9_profile2: di.CanDecodeVideo({Codec: "vp9", Profile: "profile 2", Container: "mkv"})
        av1: di.CanDecodeVideo({Codec: "av1", Container: "mp4"})
        h264_high_42: di.CanDecodeVideo({Codec: "h264", Profile: "high", Level: "4.2", Container: "mp4"})
        h264_bare: di.CanDecodeVideo({Codec: "h264"})
        mpeg2: di.CanDecodeVideo({Codec: "mpeg2", Container: "ts"})
        vp9_profile0: di.CanDecodeVideo({Codec: "vp9", Profile: "profile 0", Container: "mkv"})
        dolby_vision: di.CanDecodeVideo({Codec: "dvhe", Container: "mp4"})
    })
    Emit("audio", {
        outputChannel: di.GetAudioOutputChannel()
        decodeInfo: di.GetAudioDecodeInfo()
        soundEffectsVolume: di.GetSoundEffectsVolume()
        ac3: di.CanDecodeAudio({Codec: "ac3"}).result
        eac3: di.CanDecodeAudio({Codec: "eac3"}).result
        eac3_atmos: di.CanDecodeAudio({Codec: "eac3", ChCnt: 8}).result
        dts: di.CanDecodeAudio({Codec: "dts"}).result
        aac_51: di.CanDecodeAudio({Codec: "aac", ChCnt: 6}).result
        flac: di.CanDecodeAudio({Codec: "flac"}).result
        has_51_feature: di.HasFeature("5.1_surround_sound")
        can_output_51: di.HasFeature("can_output_5.1_surround_sound")
    })
    Emit("drm", di.GetDrmInfoEx())

    scene.status = "Reading network and memory info..."
    Emit("network", {
        connectionType: di.GetConnectionType()
        linkStatus: di.GetLinkStatus()
        connectionInfo: di.GetConnectionInfo()
    })
    mm = CreateObject("roAppMemoryMonitor")
    if mm <> invalid then
        Emit("memory", {
            channelAvailableMemoryKb: mm.GetChannelAvailableMemory()
            memoryLimitPercent: mm.GetMemoryLimitPercent()
            channelMemoryLimit: mm.GetChannelMemoryLimit()
        })
    end if

    scene.status = "Running CPU benchmark..."
    Emit("cpu_bench", CpuBench())

    scene.status = "Running internet speed test..."
    Emit("latency", Latency(5))
    for i = 1 to 3
        Emit("download", Download("https://speed.cloudflare.com/__down?bytes=25000000", "tmp:/diag_dl.bin"))
    end for

    scene.status = "Done. Press Home to exit."
    Emit("done", {ok: true})

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
    end while
end sub

sub Emit(section as string, data as object)
    print "DIAG|" + section + "|" + FormatJson(data)
end sub

function CpuBench() as object
    t = CreateObject("roTimespan")
    t.Mark()
    x = 0
    for i = 1 to 1000000
        x = x + (i mod 7)
    end for
    intMs = t.TotalMilliseconds()

    t.Mark()
    f = 0.0
    for i = 1 to 300000
        f = f + Sqr(i) * Sin(i)
    end for
    floatMs = t.TotalMilliseconds()

    t.Mark()
    s = ""
    arr = []
    for i = 1 to 50000
        arr.Push(Str(i).Trim())
    end for
    s = arr.Join(",")
    strMs = t.TotalMilliseconds()
    return {int_loop_1M_ms: intMs, float_300k_ms: floatMs, string_50k_ms: strMs, strLen: Len(s)}
end function

function NewTransfer(url as string) as object
    ut = CreateObject("roUrlTransfer")
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.SetUrl(url)
    return ut
end function

function Latency(n as integer) as object
    samples = []
    for i = 1 to n
        ut = NewTransfer("https://speed.cloudflare.com/__down?bytes=0")
        t = CreateObject("roTimespan")
        t.Mark()
        ut.GetToString()
        samples.Push(t.TotalMilliseconds())
    end for
    return {https_request_ms: samples}
end function

function Download(url as string, path as string) as object
    ut = NewTransfer(url)
    t = CreateObject("roTimespan")
    t.Mark()
    code = ut.GetToFile(path)
    ms = t.TotalMilliseconds()
    fs = CreateObject("roFileSystem")
    st = fs.Stat(path)
    size = 0
    if st <> invalid then size = st.size
    fs.Delete(path)
    mbps = 0.0
    if ms > 0 then mbps = size * 8.0 / (ms * 1000.0)
    return {code: code, bytes: size, ms: ms, mbps: mbps}
end function
