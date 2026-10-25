' Builds every screen off-device from the synthetic feeds (clock pinned to
' Sunday 2026-10-18 10:00 AM) and checks the playlists and key content.
sub Main()
    cfg = fixtureConfig()
    d = derive(cfg)
    check("app playlist", chooseScreens(d, "app").Join(", "), "gameday, briefing, recap, board, week, radar, lake, sky, season, ambient")
    check("screensaver playlist", chooseScreens(d, "screensaver").Join(", "), "ambient, gameday, briefing, recap")
    for each id in ["ambient", "briefing", "tonight", "week", "lake", "sky", "recap", "gameday", "school", "board", "season", "radar", "night"]
        g = buildScreen(id, d)
        check("builds " + id, g.getChildCount() > 4, true)
        check(id + ": no text under 24 px", smallest(g, 999) >= 24, true)
    end for
    ' Game watch: next game per tracked team, at most one college game, in time order
    names = []
    for each gm in briefingGames(d)
        names.Push(gm.name)
    end for
    check("game watch picks", names.Join(", "), "Falcons, Panthers women's volleyball, Hawks, Auburn, Georgia")
    ' night mode: the screensaver is just the clock from 11 PM to 5 AM
    late = {}
    late.Append(d)
    late.now = d.today + 23 * 3600 + 30 * 60
    check("late-night screensaver", chooseScreens(late, "screensaver").Join(","), "night")
    check("late-night app is unchanged", chooseScreens(late, "app")[0] <> "night", true)
    late.now = d.today + 86400 + 2 * 3600
    late.today = d.today + 86400
    texts = labelTexts(buildScreen("night", late))
    check("after midnight, the coming day's forecast", texts.DoesExist("Today 70° / 48°, partly cloudy"), true)
    ' loading skeleton
    check("loading screen", labelTexts(buildLoading(d.now, "Getting ready...")).DoesExist("Getting ready..."), true)
    ' Briefing: calendar rows in time order, heads-up skips what the calendar shows
    rows = briefingRows(d)
    whens = []
    for i = 0 to 3
        whens.Push(rows[i].when + " " + rows[i].title)
    end for
    check("briefing rows in time order", whens.Join(" | "), "Today 6 PM Family photo with Grandma | Tomorrow Garbage + yard waste | Tuesday 4 PM Casey band rehearsal | Friday Science fair registration deadline")
    texts = labelTexts(buildScreen("briefing", d))
    check("briefing heads-up has no repeats", texts.DoesExist("Rain likely Tuesday (65%).") and not texts.DoesExist("Tomorrow: garbage plus yard waste (no grass clippings). Curb by 7 AM."), true)
    ' warning + rain reorders the app playlist
    feed("alerts", ["alerts_warning.json"])
    d = derive(cfg)
    check("warning puts radar first", chooseScreens(d, "app")[0], "radar")
    texts = labelTexts(buildScreen("radar", d))
    check("radar lists the warning", texts.DoesExist("Tornado Warning"), true)
    ' stale and missing data
    m.fetched.weather = m.testNowUtc - 30 * 60
    m.fetched.alerts = m.testNowUtc - 2 * 3600
    d = derive(cfg)
    texts = labelTexts(buildScreen("briefing", d))
    check("weather card says as of", texts.DoesExist("as of 9:30 AM"), true)
    texts = labelTexts(buildScreen("radar", d))
    check("expired alerts say unavailable", texts.DoesExist("Unavailable") and not texts.DoesExist("None in effect"), true)
    ' radar frames are reused between builds and trimmed on low memory
    a = buildScreen("radar", d)
    framesA = m.radarFrames[0].poster
    b = buildScreen("radar", d)
    check("radar frames reused", framesA.isSameNode(m.radarFrames[0].poster) and m.radarFrames.Count() = 8, true)
    check("frames moved to the new screen", a.getChildCount() < b.getChildCount(), true)
    m.lowMemory = true
    m.radarCache = invalid
    g = buildScreen("radar", d)
    check("low memory: 4 frames, no photos", m.radarFrames.Count().ToStr() + " " + buildScreen("ambient", d).getChild(0).subtype(), "4 Rectangle")
    m.lowMemory = false
    ' settings: hidden screens leave the playlist (never all of them), speed scales time
    d = derive(cfg)
    check("hidden screens", chooseScreens(d, "app", {gameday: true, recap: true}).Join(", "), "briefing, board, week, radar, lake, sky, season, ambient")
    everything = {}
    for each k in availableScreens(d)
        everything[k] = true
    end for
    check("hiding everything keeps the defaults", chooseScreens(d, "app", everything).Count() > 3, true)
    check("rotation speed", rotationSeconds("briefing", "normal").ToStr() + " " + rotationSeconds("briefing", "slow").ToStr() + " " + rotationSeconds("briefing", "fast").ToStr(), "30 60 18")
    ' gentle news: violent headlines are kept at ingest and hidden by the setting
    store("news", [{headline: "Council approves park", source: "Local", violent: false}, {headline: "Two charged with assault", source: "Local", violent: true}, {headline: "Old cache item", source: "Local"}])
    check("gentle news on", derive(cfg).news.Count(), 2)
    m.testSettings = {gentleNews: false}
    check("gentle news off", derive(cfg).news.Count(), 3)
    m.testSettings = invalid
    ' overlays
    nav = buildNav(["briefing", "radar", "week"], 1, false)
    check("nav names the screen", labelTexts(nav).DoesExist("Radar"), true)
    check("nav dots", nav.getChildCount(), 6)
    menu = {page: "main", index: 0, settings: defaultSettings(cfg), paused: false, items: ["briefing", "radar"], all: ["briefing", "radar", "week"]}
    labels = []
    for each e in menuEntries(menu)
        labels.Push(e.label)
    end for
    check("main menu", labels.Join(", "), "Pause rotation, Go to screen, Settings, Diagnostics, Close")
    menu.page = "settings"
    menu.settings.hidden = {week: true}
    vals = []
    for each e in menuEntries(menu)
        vals.Push(e.label + "=" + e.value)
    end for
    check("settings page", vals.Join(", "), "Gentle news=On, Rotation speed=Normal, Briefing=On, Radar=On, Week ahead=Off")
    check("menu text >= 24 px", smallest(buildMenu(menu), 999) >= 24, true)
    info = sampleDiagnostics()
    g = buildDiagnostics(info)
    texts = labelTexts(g)
    check("diagnostics: source rows", texts.DoesExist("Family calendar") and texts.DoesExist("timed out (3x)"), true)
    check("diagnostics: memory", texts.DoesExist("142 MB") and texts.DoesExist("38%"), true)
    check("diagnostics: speed", texts.DoesExist("87.4 Mbps down · 23 ms"), true)
    check("diagnostics: no text under 24 px", smallest(g, 999) >= 24, true)
    check("source colors", sourceColor(info.health.sources.weather, info.limits, "weather", info.nowUtc) + " " + sourceColor(info.health.sources.lake, info.limits, "lake", info.nowUtc) + " " + sourceColor(info.health.sources.news, info.limits, "news", info.nowUtc), "#9EC79B #E5484D #F4A259")
    check("diagnostics with nothing known", buildDiagnostics({nowUtc: 0}).getChildCount() > 10, true)
    check("hint", labelTexts(buildHint()).DoesExist("diagnostics"), true)
    testSummary("screens")
end sub

' The smallest label font size in a built screen.
function smallest(node as object, least as integer) as integer
    if node.subtype() = "Label" and node.text <> "" and node.font <> invalid
        if node.font.size < least then least = node.font.size
    end if
    for i = 0 to node.getChildCount() - 1
        least = smallest(node.getChild(i), least)
    end for
    return least
end function

' Every label's text in a built screen, as a set.
function labelTexts(node as object) as object
    out = {}
    collectTexts(node, out)
    return out
end function

sub collectTexts(node as object, out as object)
    if node.subtype() = "Label" then out[node.text] = true
    for i = 0 to node.getChildCount() - 1
        collectTexts(node.getChild(i), out)
    end for
end sub
