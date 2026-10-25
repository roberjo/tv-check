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
    ' a tornado warning takes over the app and the screensaver (even at night) until it expires
    check("takeover in the app", chooseScreens(d, "app").Join(","), "alert,radar")
    check("takeover in the screensaver", chooseScreens(d, "screensaver").Join(","), "alert,radar")
    texts = labelTexts(buildScreen("alert", d))
    check("alert screen", texts.DoesExist("Tornado Warning") and texts.DoesExist("Until 10:45 AM"), true)
    check("alert instructions", texts.DoesExist("TAKE COVER NOW! Move to a basement or an interior room on the lowest floor of a sturdy building. Avoid windows."), true)
    check("alert text >= 24 px", smallest(buildScreen("alert", d), 999) >= 24, true)
    m.testNowUtc = m.testNowUtc + 50 * 60
    m.testNowWall = m.testNowWall + 50 * 60
    feed("alerts", ["alerts_warning.json"]) ' the TV re-fetches alerts every 2 minutes
    after = derive(cfg)
    check("takeover ends at expiry", after.takeover = invalid and chooseScreens(after, "app")[0] <> "alert", true)
    check("expired alerts drop out", after.alerts.Count().ToStr() + " " + after.alerts[0].event, "1 Flood Watch")
    m.testNowUtc = m.testNowUtc - 50 * 60
    m.testNowWall = m.testNowWall - 50 * 60
    ' radar geometry: the same window and label pixels as scripts/radar_map.py
    v = radarView(33.0393, -85.0313)
    want = [-9644575, 3799871, -9286707, 4001172]
    got = v.bbox.Split(",")
    close = true
    for i = 0 to 3
        if Abs(Val(got[i]) - want[i]) > 10 then close = false ' within 10 m (0.06 px): single-precision math
    end for
    check("radar bbox matches radar_map.py", close, true)
    wp = radarPx(v, 32.878, -85.183)
    check("West Point label pixel", wp[0].ToStr() + "," + wp[1].ToStr(), "869,655")
    at = radarPx(v, 33.749, -84.388)
    check("Atlanta label pixel", at[0].ToStr() + "," + at[1].ToStr(), "1344,32")
    texts = labelTexts(buildScreen("radar", d))
    check("radar lists the warning", texts.DoesExist("Tornado Warning"), true)
    check("a warning outranks no-rain wording", texts.DoesExist("Warning in effect") and not texts.DoesExist("No rain nearby"), true)
    check("legend explains very light echoes", texts.DoesExist("Very light"), true)
    d.radarTimes = []
    d.alerts = []
    texts = labelTexts(buildScreen("radar", d))
    check("no frames says unavailable", texts.DoesExist("Radar unavailable") and not texts.DoesExist("No rain nearby"), true)
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
    check("diagnostics: wallpaper downloads", texts.DoesExist("12 of 16 photos · HTTP 404"), true)
    check("diagnostics: start-up time", texts.DoesExist("2 h 15 min · 2.4 s"), true)
    check("up text before the first screen", upText(3, 0) + " / " + upText(invalid, 900), "3 min / —")
    check("diagnostics: no text under 24 px", smallest(g, 999) >= 24, true)
    check("source colors", sourceColor(info.health.sources.weather, info.limits, "weather", info.nowUtc) + " " + sourceColor(info.health.sources.lake, info.limits, "lake", info.nowUtc) + " " + sourceColor(info.health.sources.news, info.limits, "news", info.nowUtc), "#9EC79B #E5484D #F4A259")
    check("diagnostics with nothing known", buildDiagnostics({nowUtc: 0}).getChildCount() > 10, true)
    check("hint", labelTexts(buildHint()).DoesExist("diagnostics"), true)
    ' season notes exist for every month, and each fits its card (3 notes, body under 140 characters)
    full = true
    for mo = 1 to 12
        items = seasonItems(mo)
        if items = invalid or items.Count() <> 3 then full = false
        if items <> invalid
            for each it in items
                if Len(it[2]) > 140 or Len(it[1]) > 28 then full = false
            end for
        end if
    end for
    check("season notes for all 12 months", full, true)
    ' 1.5: countdowns on the board, air on the weather card, storms on radar, live scores
    d = derive(cfg)
    texts = labelTexts(buildScreen("board", d))
    check("board countdown", texts.DoesExist("Beach trip") and texts.DoesExist("12"), true)
    check("board chores", texts.DoesExist("Whose turn") and texts.DoesExist("Feed the dog") and texts.DoesExist("Next week: Riley"), true)
    check("weather card air", labelTexts(buildScreen("briefing", d)).DoesExist("Air moderate · 58"), true)
    check("radar tropics line", labelTexts(buildScreen("radar", d)).DoesExist("Tropics: Hurricane Nadine, " + d.storms[0].miles.ToStr() + " mi away"), true)
    store("sports", ingest("sports", ["", "", "", "", ReadAsciiFile("pkg:/feeds/espn_live.json")]))
    d = derive(cfg)
    texts = labelTexts(buildScreen("gameday", d))
    check("game day live score", texts.DoesExist("4–2") and texts.DoesExist("Bot 6th") and texts.DoesExist("ON NOW"), true)
    check("tonight live", labelTexts(buildScreen("tonight", d)).DoesExist("vs Mets · Live · 4–2 · Bot 6th on TBS"), true)
    ' every screen still builds for a town with no lake, college or curbside
    m.place = placeOf({place: {town: "Athens", lake: "none", college: "none", curbside: "none"}})
    d = derive(cfg)
    for each id in ["ambient", "briefing", "tonight", "week", "sky", "recap", "school", "board", "season", "radar", "night"]
        check("Athens builds " + id, buildScreen(id, d).getChildCount() > 4, true)
    end for
    check("no lake screen", availableScreens(d).DoesExist("lake"), false)
    m.place = invalid
    check("moon sentences", moonWords("Full moon").line + " / " + moonWords("New moon").line + " / " + moonWords("First quarter").line + " / " + moonWords("Waxing crescent").line, "The moon is full / It's a new moon / The moon is at first quarter / The moon is a waxing crescent")
    ' wallpapers: the photo, a dimming fill in the screen's color, and the credit
    d = derive(cfg)
    d.wallpapers = {week: {uri: "cachefs:/wp-park-one.jpg", place: "Test Park", credit: "Test Photographer · CC0"}}
    g = buildScreen("week", d)
    credit = g.findNode("photoCredit")
    check("week wallpaper", g.getChild(0).uri + " " + g.getChild(1).subtype() + " " + fmt1(g.getChild(1).opacity), "cachefs:/wp-park-one.jpg Rectangle 0.8")
    check("photo credit", labelTexts(credit).DoesExist("Photo: Test Park · Test Photographer · CC0"), true)
    d.wallpapers.week.place = "Dowdell's Knob at dawn"
    check("label drops before the place", labelTexts(buildScreen("week", d).findNode("photoCredit")).DoesExist("Dowdell's Knob at dawn · Test Photographer · CC0"), true)
    d.wallpapers.week.place = "Test Park"
    d.wallpapers.week.place = "A Very Long Place Name, Somewhere Far Away In Georgia"
    check("long place drops first, license stays", labelTexts(buildScreen("week", d).findNode("photoCredit")).DoesExist("Photo: Test Photographer · CC0"), true)
    d.wallpapers = {ambient: {uri: "cachefs:/wp-park-one.jpg", place: "Test Park", credit: "Test Photographer · CC0"}}
    texts = labelTexts(buildScreen("ambient", d))
    check("ambient caption names the photo", texts.DoesExist("Test Park") and texts.DoesExist("Photo: Test Photographer · CC0"), true)
    d.wallpapers = {week: {uri: "cachefs:/wp-park-one.jpg", place: "Test Park", credit: "Test Photographer · CC0"}}
    check("no photo, no credit", buildScreen("board", d).findNode("photoCredit") = invalid and buildScreen("ambient", d).getChild(0).uri = "pkg:/images/bg_ambient.jpg", true)
    m.lowMemory = true
    g = buildScreen("week", d)
    check("low memory: no wallpaper", g.getChild(0).subtype() + " " + (g.findNode("photoCredit") = invalid).ToStr(), "Rectangle true")
    m.lowMemory = false
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
