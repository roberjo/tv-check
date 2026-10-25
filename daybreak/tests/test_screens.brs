' Builds every screen off-device from the synthetic feeds (clock pinned to
' Sunday 2026-10-18 10:00 AM) and checks the playlists and key content.
sub Main()
    cfg = fixtureConfig()
    d = derive(cfg)
    check("app playlist", chooseScreens(d, "app").Join(", "), "gameday, briefing, recap, board, week, radar, lake, sky, season, ambient")
    check("screensaver playlist", chooseScreens(d, "screensaver").Join(", "), "ambient, gameday, briefing, recap")
    for each id in ["ambient", "briefing", "tonight", "week", "lake", "sky", "recap", "gameday", "school", "board", "season", "radar"]
        g = buildScreen(id, d)
        check("builds " + id, g.getChildCount() > 10, true)
    end for
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
    m.cache.alerts = ParseJson(ReadAsciiFile("pkg:/feeds/alerts_warning.json"))
    d = derive(cfg)
    check("warning puts radar first", chooseScreens(d, "app")[0], "radar")
    texts = labelTexts(buildScreen("radar", d))
    check("radar lists the warning", texts.DoesExist("Tornado Warning"), true)
    testSummary("screens")
end sub

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
