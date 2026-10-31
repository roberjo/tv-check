' Screens: Radar.

sub buildRadar(g as object, d as object)
    uiImage(g, "pkg:/images/radar_base.jpg", 0, 0, 1920, 1080)
    layer = radarLayer(d.radarTimes, radarView(d.home.lat, d.home.lon).bbox)
    parent = layer.group.getParent()
    if parent <> invalid then parent.removeChild(layer.group)
    g.appendChild(layer.group)
    frames = layer.frames
    for each f in frames
        f.poster.visible = false
    end for
    if frames.Count() > 0 then frames[frames.Count() - 1].poster.visible = true
    m.radarFrames = frames
    m.radarFrame = frames.Count() - 1
    uiImage(g, "pkg:/images/ring_radar.png", 703, 283, 514, 514, "#F4F1EA", 0.35)
    uiDot(g, 960, 540, 40, "#F4A259", 0.18)
    uiDot(g, 960, 540, 13, "#0B1120")
    uiDot(g, 960, 540, 9, "#F4A259")
    ' town and water labels from the place, skipping any that would sit under a card
    view = radarView(d.home.lat, d.home.lon)
    cards = [[gx(1), 64, gx(1) + gw(4), 314], [gx(9), 64, 1808, 314], [gx(1), 876, gx(1) + gw(6), 1016], [gx(7), 876, 1808, 1016]]
    rp = d.place.radar
    if rp <> invalid
        for each pl in rp.places
            px = radarPx(view, pl.lat, pl.lon)
            w = Len(pl.name) * 15 + 20
            lx = px[0] + 14
            align = "left"
            if lx + w > 1880
                lx = px[0] - 14
                align = "right"
            end if
            hitBox = [lx, px[1] - 15, lx + w, px[1] + 15]
            if align = "right" then hitBox = [lx - w, px[1] - 15, lx, px[1] + 15]
            if onMap(px, hitBox, cards) and Abs(px[0] - 960) + Abs(px[1] - 540) > 60
                uiDot(g, px[0], px[1], 5, "#E1E4EC")
                if align = "right" then uiText(g, lx, px[1] - 15, pl.name, 24, 600, "Manrope", "#E1E4EC", w, "right") else uiText(g, lx, px[1] - 15, pl.name, 24, 600, "Manrope", "#E1E4EC")
            end if
        end for
        if rp.water <> invalid
            for each wl in rp.water
                px = radarPx(view, wl.lat, wl.lon)
                w = Len(wl.name) * 15 + 20
                if onMap(px, [px[0] - w, px[1] - 13, px[0], px[1] + 13], cards) then uiText(g, px[0], px[1] - 13, wl.name, 24, 600, "Manrope", "#A9C8EE", w, "right")
            end for
        end if
    end if
    uiText(g, 984, 516, d.place.town, 34, 600, "Outfit")
    uiText(g, 960, 244, "25 mi", 24, 600, "Manrope", "#C9CEDA", 120, "center")
    ' Say plainly whether the map is clear or the radar didn't load, so an
    ' empty map never looks like a broken one.
    ' (the TV can't read the frames' pixels, so "no rain" comes from the forecast)
    status = "No rain nearby"
    sub2 = "Radar is live · latest scan " + radarLatestText(d) + ". Rain shows in color."
    if d.radarTimes.Count() = 0
        status = "Radar unavailable"
        sub2 = "Couldn't reach NOAA's radar just now. The forecast shows no rain for " + d.place.town + " in the next 2 hours."
    end if
    if d.rainSoon
        status = "Rain likely soon"
        sub2 = "Forecast shows rain near " + d.place.town + " within 2 hours"
    end if
    if d.storms.Count() > 0
        st = d.storms[0]
        sub2 = "Tropics: " + st.kind + " " + st.name + ", " + st.miles.ToStr() + " mi away"
    end if
    ' a warning outranks the forecast: never say "no rain" while one is in effect
    for each al in d.alerts
        if al.level = "warning" and status <> "Warning in effect"
            status = "Warning in effect"
            sub2 = "Watch for storms moving toward " + d.place.town + ". Details are on the alert screen."
        end if
    end for
    uiCard(g, gx(1), 64, gw(4), 250, "#0B1120", "#1F2A44", 28, 0.92)
    dotColor = "#9EC79B"
    if d.rainSoon then dotColor = "#F4A259"
    uiDot(g, gx(1) + 38, 108, 7, dotColor)
    uiLabel(g, gx(1) + 58, 96, "Live radar · West Georgia")
    uiText(g, gx(1) + 40, 134, status, 46, 500, "Outfit", "#F4F1EA", gw(4) - 80)
    uiText(g, gx(1) + 40, 206, sub2, 24, 400, "Manrope", "#C9CEDA", gw(4) - 80, "left", 2)
    warn = d.alerts.Count() > 0
    fill = "#0B1120"
    if warn then fill = "#5C0A18"
    ax = gx(9)
    uiCard(g, ax, 64, gw(4), 250, fill, "#1F2A44", 28, 0.92)
    uiLabel(g, ax + 40, 96, "Alerts · " + d.place.area)
    if warn
        yy = 136
        for each a in d.alerts
            if yy < 280
                l = uiText(g, ax + 40, yy, a.event, 32, 600, "Manrope", "#F4F1EA", gw(4) - 80, "left", 2)
                yy = yy + uiHeight(l, 32) + 8
            end if
        end for
    else if d.alertsKnown = false
        uiText(g, ax + 40, 136, "Unavailable", 40, 500, "Outfit")
        uiText(g, ax + 40, 200, "Couldn't reach the National Weather Service. Check local news in severe weather.", 24, 400, "Manrope", "#F4A259", gw(4) - 80, "left", 3)
    else
        uiText(g, ax + 40, 136, "None in effect", 40, 500, "Outfit")
        uiText(g, ax + 40, 206, "National Weather Service, Peachtree City", 24, 400, "Manrope", "#A9B1C4", gw(4) - 80, "left", 2)
    end if
    uiCard(g, gx(1), 876, gw(6), 140, "#0B1120", "#1F2A44", 28, 0.92)
    uiText(g, gx(1) + 40, 898, "Past 2 hours", 24, 600)
    m.radarTimeLabel = uiText(g, gx(1) + gw(6) - 40, 898, "", 24, 700, "Manrope", "#F4A259", 300, "right")
    m.radarSegs = []
    n = frames.Count()
    if n > 0
        segw = (gw(6) - 80 - (n - 1) * 6) / n
        for j = 0 to n - 1
            m.radarSegs.Push(uiCard(g, gx(1) + 40 + j * (segw + 6), 960, segw, 12, "#2A3656", "", 10))
        end for
    end if
    lx0 = gx(7)
    uiCard(g, lx0, 876, gw(6), 140, "#0B1120", "#1F2A44", 28, 0.92)
    uiLabel(g, lx0 + 40, 898, "Precipitation")
    ' colors sampled from MRMS frames: blue for drizzle and very light rain up to magenta for hail
    legend = [["Very light", "#4660A0", "#5BA5CA"], ["Light", "#02FD02", "#01C501"], ["Moderate", "#FDF802", "#FD9500"], ["Heavy", "#FD0000", "#BC0000"], ["Hail", "#F800FD", "#9854C6"]]
    lw = (gw(6) - 80 - 4 * 16) / 5
    for j = 0 to 4
        lx = lx0 + 40 + j * (lw + 16)
        uiRect(g, lx, 944, lw / 2, 14, legend[j][1])
        uiRect(g, lx + lw / 2, 944, lw / 2, 14, legend[j][2])
        uiText(g, lx, 966, legend[j][0], 24, 400, "Manrope", "#C9CEDA", Int(lw))
    end for
    showRadarFrame(m.radarFrame)
end sub

' Radar frames as one group of posters, kept between builds of the radar
' screen while the frame times are unchanged, so rotating back to radar (or a
' data refresh) doesn't create and download a second set. Frames load at
' 960x540 (about 2 MB each decoded instead of 8 MB) and are scaled to fill
' the screen; low memory keeps only the latest 4.
function radarLayer(times as object, bbox as string) as object
    picks = times
    if m.lowMemory = true and times.Count() > 4
        picks = []
        for i = times.Count() - 4 to times.Count() - 1
            picks.Push(times[i])
        end for
    end if
    key = bbox + "|" + picks.Join(",")
    if m.radarCache <> invalid and m.radarCache.key = key then return m.radarCache
    group = CreateObject("roSGNode", "Group")
    frames = []
    for each t in picks
        url = "https://opengeo.ncep.noaa.gov/geoserver/conus/conus_bref_qcd/ows?service=WMS&version=1.3.0&request=GetMap&layers=conus_bref_qcd&crs=EPSG:3857&bbox=" + bbox + "&width=960&height=540&format=image/png&transparent=true&time=" + t
        p = uiImage(group, url, 0, 0, 1920, 1080)
        p.loadWidth = 960
        p.loadHeight = 540
        p.visible = false
        frames.Push({poster: p, time: t})
    end for
    m.radarCache = {key: key, group: group, frames: frames}
    return m.radarCache
end function

' True when a label's point is on screen and its hitBox clears every card.
function onMap(px as object, hitBox as object, cards as object) as boolean
    if px[0] < 20 or px[0] > 1900 or px[1] < 20 or px[1] > 1060 then return false
    for each c in cards
        if hitBox[0] < c[2] and hitBox[2] > c[0] and hitBox[1] < c[3] and hitBox[3] > c[1] then return false
    end for
    return true
end function

' Clock time of the newest radar frame ("1:08 PM"), or "—".
function radarLatestText(d as object) as string
    if d.radarTimes.Count() = 0 then return "—"
    return tClock(tUtcIsoToWall(Left(d.radarTimes[d.radarTimes.Count() - 1], 19) + "Z"))
end function

sub showRadarFrame(i as integer)
    if m.radarFrames = invalid or m.radarFrames.Count() = 0 then return
    for j = 0 to m.radarFrames.Count() - 1
        m.radarFrames[j].poster.visible = (j = i)
        color = "0x2A3656FF"
        if j = i then color = "0xF4A259FF"
        m.radarSegs[j].blendColor = color
    end for
    m.radarTimeLabel.text = tClock(tUtcIsoToWall(Left(m.radarFrames[i].time, 19) + "Z"))
end sub
