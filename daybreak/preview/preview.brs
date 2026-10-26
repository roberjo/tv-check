' Builds every screen from the synthetic feeds for a few moments in time and
' prints each scene tree as JSON for preview/render.py. Run via preview.sh.
sub Main()
    cfg = fixtureConfig()
    m.fontMetrics = ParseJson(ReadAsciiFile("pkg:/font_metrics.json")) ' real advance widths (preview.sh)
    base = {utc: m.testNowUtc, wall: m.testNowWall}
    ' the real wallpaper catalog (preview.sh copies it), every photo as if downloaded
    store("wallpapers", normWallpapers(ParseJson(ReadAsciiFile("pkg:/wallpaper_catalog.json"))))
    m.testWallpapers = {}
    for each p in fresh("wallpapers")
        m.testWallpapers[p.id] = true
    end for
    scenarios = [
        {name: "morning", hours: 0, screens: ["briefing", "ambient", "gameday", "recap", "lake", "season", "board", "school"]},
        {name: "evening", hours: 9, screens: ["tonight", "week", "sky"]},
        {name: "night", hours: 14, screens: ["night"]},
        {name: "warning", hours: 0, alerts: "alerts_warning.json", screens: ["alert", "radar"]}
    ]
    for each sc in scenarios
        m.testNowUtc = base.utc + sc.hours * 3600
        m.testNowWall = base.wall + sc.hours * 3600
        if sc.alerts <> invalid then feed("alerts", [sc.alerts]) else feed("alerts", ["alerts.json"])
        m.fetched = {}
        for each k in m.cache
            m.fetched[k] = m.testNowUtc
        end for
        d = derive(cfg)
        if d.notes.Count() = 0 then d.notes = [{text: "Dinner at 6:30 tonight", from: "Jordan", color: "#9EC79B"}]
        for each id in sc.screens
            g = buildScreen(id, d)
            updateClock()
            print "SCENE|"; sc.name; "|"; id; "|"; FormatJson(dumpNode(g))
        end for
    end for
    ' a game in progress
    m.testNowUtc = base.utc
    m.testNowWall = base.wall
    feed("alerts", ["alerts.json"])
    store("sports", ingest("sports", ["", "", "", "", ReadAsciiFile("pkg:/feeds/espn_live.json")]))
    d = derive(cfg)
    print "SCENE|live|gameday|"; FormatJson(dumpNode(buildScreen("gameday", d)))
    feed("sports", ["espn_georgia.json", "espn_auburn.json", "espn_falcons.json", "espn_hawks.json", "espn_braves.json"])
    d = derive(cfg)
    ' overlays: menu, settings, diagnostics, remote hint
    menu = {page: "main", index: 1, settings: defaultSettings(cfg), paused: false, items: chooseScreens(d, "app"),
            all: ["briefing", "ambient", "tonight", "week", "recap", "gameday", "radar", "lake", "sky", "school", "board", "season"]}
    print "SCENE|overlay|menu|"; FormatJson(dumpNode(buildMenu(menu)))
    menu.page = "settings"
    menu.index = 1
    menu.settings.hidden = {school: true}
    print "SCENE|overlay|settings|"; FormatJson(dumpNode(buildMenu(menu)))
    print "SCENE|overlay|diagnostics|"; FormatJson(dumpNode(buildDiagnostics(sampleDiagnostics())))
    print "SCENE|overlay|hint|"; FormatJson(dumpNode(buildHint()))
    m.testNowWall = base.wall
    loading = buildLoading(base.wall, "Getting today's weather, calendar and games...")
    updateClock()
    print "SCENE|startup|loading|"; FormatJson(dumpNode(loading))
    print "LIVE SMOKE OK"
end sub
