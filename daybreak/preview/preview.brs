' Builds every screen from the synthetic feeds for a few moments in time and
' prints each scene tree as JSON for preview/render.py. Run via preview.sh.
sub Main()
    cfg = fixtureConfig()
    base = {utc: m.testNowUtc, wall: m.testNowWall}
    scenarios = [
        {name: "morning", hours: 0, screens: ["briefing", "ambient", "gameday", "recap", "lake", "season", "board", "school"]},
        {name: "evening", hours: 9, screens: ["tonight", "week", "sky"]},
        {name: "night", hours: 14, screens: ["night"]},
        {name: "warning", hours: 0, alerts: "alerts_warning.json", screens: ["radar"]}
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
    m.testNowWall = base.wall
    loading = buildLoading(base.wall, "Getting today's weather, calendar and games...")
    updateClock()
    print "SCENE|startup|loading|"; FormatJson(dumpNode(loading))
    print "LIVE SMOKE OK"
end sub

function dumpNode(n as object) as object
    o = {t: n.subtype()}
    tr = n.translation
    if tr <> invalid and tr.Count() = 2
        o.x = tr[0]
        o.y = tr[1]
    end if
    for each f in ["width", "height", "color", "uri", "blendColor", "opacity", "visible", "text", "horizAlign", "wrap", "maxLines", "lineSpacing"]
        v = n[f]
        if f = "text" and v <> invalid then v = v.Replace(Chr(34), "{Q}") ' brs FormatJson doesn't escape quotes
        if v <> invalid then o[f] = v
    end for
    if o.t = "Label" and n.font <> invalid
        o.font = n.font.uri
        o.size = n.font.size
    end if
    kids = []
    for i = 0 to n.getChildCount() - 1
        kids.Push(dumpNode(n.getChild(i)))
    end for
    if kids.Count() > 0 then o.kids = kids
    return o
end function
