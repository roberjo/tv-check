' Builds every screen a wallpaper could sit behind, once for each photo in the
' real catalog (daybreak/wallpapers/catalog.json), and prints the scene trees
' for render.py's contrast audit. Run via preview.sh --wallpapers; the
' wallpapers' build.py --audit records which screens each photo passed.
sub Main()
    cfg = fixtureConfig()
    m.fontMetrics = ParseJson(ReadAsciiFile("pkg:/font_metrics.json"))
    catalog = ParseJson(ReadAsciiFile("pkg:/wallpaper_catalog.json"))
    ' the screens at the times of day they show: evening ones at 7 PM
    evening = {tonight: true, week: true}
    morningData = derive(cfg)
    m.testNowUtc = m.testNowUtc + 9 * 3600
    m.testNowWall = m.testNowWall + 9 * 3600
    for each k in m.cache
        m.fetched[k] = m.testNowUtc ' the synthetic feeds count as fresh at 7 PM too
    end for
    eveningData = derive(cfg)
    for each d in [morningData, eveningData]
        if d.notes.Count() = 0 then d.notes = [{text: "Dinner at 6:30 tonight", from: "Jordan", color: "#9EC79B"}]
    end for
    for each p in catalog.photos
        for each id in wallpaperScreens()
            if id <> "lake" or hasItem(p.tags, "lake")
                d = morningData
                if evening.DoesExist(id) then d = eveningData
                d.wallpapers = {}
                d.wallpapers[id] = {uri: "cachefs:/wp-" + p.id + ".jpg", place: p.place, credit: p.credit}
                print "SCENE|wp:"; p.id; "|"; id; "|"; FormatJson(dumpNode(buildScreen(id, d)))
            end if
        end for
    end for
    print "LIVE SMOKE OK" ' brs.sh's end-of-run marker
end sub
