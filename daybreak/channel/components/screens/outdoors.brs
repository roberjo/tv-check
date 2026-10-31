' Screens: Lake, Sky and Season.

sub buildLake(g as object, d as object)
    lk = d.lake
    uiWallpaper(g, d, "lake", "#081420")
    pl = d.place.lake
    header(g, "OUTDOORS · " + UCase(pl.name), "Lake conditions", "#7FB7E8", false)
    uiText(g, 1808, 140, "USGS gauge " + pl.site + " · " + tClock(lk.time), 24, 400, "Manrope", "#9FB3C8", 600, "right")
    top = 246
    uiCard(g, gx(1), top, gw(4), 770, "#0E2033", "#1B3550", 32)
    gx0 = gx(1) + 60
    gy0 = top + 60
    gh = 640
    uiCard(g, gx0, gy0, 64, gh, "#132A42", "", 32)
    lvl = lk.level
    ' the gauge shows 20 ft, from 5 ft above summer pool down
    gTop = pl.summerPool + 5
    ly = gy0 + (gTop - lvl) / 20 * gh
    if ly < gy0 then ly = gy0
    if ly > gy0 + gh - 40 then ly = gy0 + gh - 40
    uiCard(g, gx0, ly, 64, gy0 + gh - ly, "#7FB7E8", "", 32)
    for each pool in [[pl.summerPool, "Summer full pool"], [pl.winterPool, "Winter pool"]]
        py = gy0 + (gTop - pool[0]) / 20 * gh
        uiRect(g, gx0 - 16, py - 1, 96, 3, "#F4F1EA")
        uiText(g, gx0 + 120, py - 38, pool[0].ToStr() + " ft", 26, 700)
        uiText(g, gx0 + 120, py - 6, pool[1], 24, 400, "Manrope", "#9FB3C8")
    end for
    uiText(g, gx0 + 120, ly - 24, fmt1(lvl), 84, 400, "Outfit")
    uiText(g, gx0 + 120, ly + 76, "feet now", 24, 600, "Manrope", "#7FB7E8")
    rx = gx(5)
    rw = gw(8)
    if lvl < pl.winterPool
        uiCard(g, rx, top, rw, 170, "#2A2418", "#5A4520")
        uiText(g, rx + 44, top + 30, fmt1(pl.summerPool - lvl) + " ft below summer pool, " + fmt1(pl.winterPool - lvl) + " ft below winter pool", 38, 500, "Outfit", "#F4F1EA", rw - 88)
        uiText(g, rx + 44, top + 98, "Low water. Check Corps ramp and beach status before you launch.", 26, 400, "Manrope", "#E1D3BE", rw - 88)
    else
        uiCard(g, rx, top, rw, 170, "#0E2033", "#1B3550")
        uiText(g, rx + 44, top + 54, "Lake is at normal levels", 40, 500, "Outfit")
    end if
    best = d.weather.days[0]
    bestScore = -1
    for i = 0 to 5
        if i < d.weather.days.Count()
            dd = d.weather.days[i]
            sc = 0
            if dd.rain < 30 then sc = sc + 3
            if dd.hi >= 65 and dd.hi <= 88 then sc = sc + 2
            if dd.wind <= 10 then sc = sc + 2
            if tWeekday(dd.day) = 0 or tWeekday(dd.day) = 6 then sc = sc + 1
            if sc > bestScore
                bestScore = sc
                best = dd
            end if
        end if
    end for
    sunset = d.weather.days[0].sunset
    cards = [["Best lake day", tDayWord(best.day, d.today), "High " + best.hi.ToStr() + "°, " + LCase(wxLabel(best.code)) + ", wind up to " + best.wind.ToStr() + " mph"],
             ["Sunset on the water", tClock(sunset), "Golden hour starts " + tClock(sunset - 2400)],
             ["Fishing moon", Int(d.moon.illum * 100 + 0.5).ToStr() + "% lit", d.moon.name + " · full " + tShortDate(tUtcToWallApprox(d.moon.nextFull))]]
    cw = (rw - 64) / 3
    for i = 0 to 2
        cx = rx + i * (cw + 32)
        uiCard(g, cx, top + 202, cw, 568, "#0E2033", "#1B3550")
        uiLabel(g, cx + 36, top + 238, cards[i][0], 24, "#9FB3C8")
        uiText(g, cx + 36, top + 290, cards[i][1], 60, 500, "Outfit", "#F4F1EA", Int(cw) - 72)
        uiText(g, cx + 36, top + 400, cards[i][2], 26, 400, "Manrope", "#C9D6E3", Int(cw) - 72, "left", 4)
    end for
end sub

function tUtcToWallApprox(utc as integer) as integer
    return utc + (tNowWall() - tNowUtc())
end function

sub buildSky(g as object, d as object)
    uiBackdrop(g, "pkg:/images/bg_sky.jpg", "#05070F")
    cloud = 0
    n = 0
    for each hr in d.weather.hours
        if hr.t >= d.today + 21 * 3600 and hr.t <= d.today + 27 * 3600
            cloud = cloud + hr.cloud
            n = n + 1
        end if
    end for
    if n > 0 then cloud = cloud / n else cloud = 50
    title = "Cloudy tonight."
    if cloud < 70 then title = "Some clouds tonight."
    if cloud < 30 then title = "Clear skies. Look up."
    header(g, "TONIGHT'S SKY OVER " + UCase(d.place.town), title, "#B3A6F2", false)
    mp = d.moon
    idx = Int(mp.age / 29.530588853 * 30)
    if idx > 29 then idx = 29
    uiImage(g, "pkg:/images/moon_" + tPad(idx, 2) + ".png", 112, 330, 300, 300)
    uiText(g, 452, 370, Int(mp.illum * 100 + 0.5).ToStr() + "%", 72, 300, "Outfit")
    uiText(g, 452, 462, mp.name, 28, 600, "Manrope", "#F4F1EA", 240, "left", 2)
    uiText(g, 452, 540, "Full moon " + tShortDate(tUtcToWallApprox(mp.nextFull)), 24, 400, "Manrope", "#B8BED0", 240)
    uiCard(g, gx(5) + 16, 300, 1808 - gx(5) - 16, 380, "#131729", "#2A3050", 32)
    s = d.shower
    tx = gx(5) + 64
    tw = 1808 - tx - 48
    if s <> invalid
        lbl = "Coming up"
        if (s.peak - d.today) \ 86400 <= 7 then lbl = "This week's show"
        uiLabel(g, tx, 340, lbl, 24, "#B3A6F2")
        uiText(g, tx, 384, s.name + " meteor shower peaks " + tDayWord(s.peak, d.today) + " night", 54, 500, "Outfit", "#F4F1EA", tw, "left", 2)
        tip = "Best in the dark hours before dawn. Face away from town lights."
        if d.place.lake <> invalid then tip = tip + " The " + d.place.lake.name + " shoreline is darker than downtown."
        uiText(g, tx, 540, tip, 26, 400, "Manrope", "#C9CEDA", tw, "left", 3)
    else
        uiLabel(g, tx, 340, "Tonight", 24, "#B3A6F2")
        m2 = moonWords(mp.name)
        uiText(g, tx, 384, m2.line, 54, 500, "Outfit", "#F4F1EA", tw, "left", 2)
        uiText(g, tx, 540, m2.tip, 26, 400, "Manrope", "#C9CEDA", tw, "left", 3)
    end if
    lo = 99
    for each hr in d.weather.hours
        if hr.t >= d.today + 21 * 3600 and hr.t <= d.today + 30 * 3600 and hr.temp < lo then lo = hr.temp
    end for
    viewing = "Cloudy"
    if cloud < 70 then viewing = "Partly cloudy"
    if cloud < 30 then viewing = "Clear"
    dark = "Moon up late"
    if mp.illum < 0.3 then dark = "Dark all evening"
    if mp.waxing and mp.illum >= 0.3 then dark = "After midnight"
    cards = [["Viewing tonight", viewing, Int(cloud).ToStr() + "% cloud cover · low " + lo.ToStr() + "°"],
             ["Moonset and dark sky", dark, "Darkest skies come after the moon sets"],
             ["Sunrise tomorrow", tClock(d.weather.days[1].sunrise), "Meteor watching ends at first light"]]
    for i = 0 to 2
        x = gx(1 + i * 4)
        w3 = gw(4)
        uiCard(g, x, 760, w3, 256, "#131729", "#2A3050")
        uiLabel(g, x + 36, 794, cards[i][0], 24, "#A3A9C2")
        uiText(g, x + 36, 836, cards[i][1], 40, 500, "Outfit", "#F4F1EA", w3 - 72)
        uiText(g, x + 36, 910, cards[i][2], 24, 400, "Manrope", "#C9CEDA", w3 - 72, "left", 2)
    end for
end sub

' Three notes per month for West Georgia (USDA zone 8a), shown on the Season screen.
function seasonItems(month as integer) as dynamic
    if month = 1 then return [["Winter", "Long nights", "Early sunsets and cold, clear air make January good for stargazing. Orion is high in the evening sky."], ["In the garden", "Plan and prune", "Order seeds and prune fruit trees and summer-blooming shrubs while they're dormant."], ["On the wing", "Winter visitors", "Juncos and white-throated sparrows visit feeders, and bald eagles nest near big lakes."]]
    if month = 2 then return [["Late winter", "First blooms", "Red maples, daffodils and Japanese magnolias often bloom in February, ahead of spring."], ["In the garden", "Prune roses, plant peas", "Prune roses in mid to late February. Lettuce, peas and onions can go in now."], ["Outdoors", "Frogs are calling", "Spring peepers and chorus frogs call from wet ditches and ponds on mild nights."]]
    if month = 3 then return [["Spring color", "Azaleas and dogwoods", "Native azaleas and then dogwoods bloom from late March into April. Callaway's azalea trails are a highlight."], ["In the garden", "Last frost is near", "The last frost usually comes in late March or early April. Wait for April to plant tomatoes."], ["On the wing", "Hummingbirds return", "Ruby-throated hummingbirds arrive in late March. Put feeders out by mid-month."]]
    if month = 4 then return [["Spring", "Pine pollen season", "Yellow pine pollen coats cars and porches in early April. Keep windows closed on the worst days."], ["In the garden", "Warm-season planting", "Tomatoes, peppers and beans go in once nights stay above 50°, usually by mid-April."], ["On the lake", "Spring fishing", "Crappie and bass move shallow as the water warms. A good month for an early boat ride."]]
    if month = 5 then return [["Early summer", "Magnolias and gardenias", "Southern magnolias and gardenias bloom, and evenings are still comfortable."], ["In the garden", "Mulch before the heat", "Mulch beds now and water deeply once a week instead of a little every day."], ["Outdoors", "Fireflies", "Fireflies start blinking over lawns and fields on warm, still evenings."]]
    if month = 6 then return [["Summer", "The longest days", "Around the June solstice there are more than 14 hours of daylight."], ["In the garden", "First tomatoes", "Pick in the morning and water early, not at night, to keep leaf disease down."], ["Outdoors", "Pop-up storms", "Afternoon thunderstorms are common. When thunder roars, go indoors."]]
    if month = 7 then return [["Summer", "Peak heat", "July is usually the hottest month. Plan outdoor time for early morning or evening."], ["In the garden", "Keep it going", "Water deeply in the morning. Late July is the time to start fall vegetables from seed."], ["On the lake", "Early and late", "Boating and swimming are best before the heat and the afternoon storms build."]]
    if month = 8 then return [["Late summer", "Dog days", "Hot, humid days with pop-up storms, and the tropics get busier."], ["In the garden", "Start fall crops", "Sow collards, kale and broccoli for a fall harvest."], ["Night sky", "Perseid meteors", "The Perseids peak around August 12. The best viewing is after midnight."]]
    if month = 9 then return [["Early fall", "Goldenrod and asters", "Roadsides turn gold with goldenrod, and nights start to cool late in the month."], ["In the garden", "Fall planting begins", "Plant cool-season greens, and divide crowded perennials as the heat breaks."], ["On the wing", "Hummingbirds leave", "Most hummingbirds head south by early October. Leave feeders up until then."]]
    if month = 10 then return [["Fall color", "Starting to turn", "Usually peaks here in late October to early November. Callaway's trails are the closest showcase."], ["In the garden", "Plant pansies and shrubs", "Fall is Georgia's best season for trees and shrubs. Divide perennials; spring bulbs go in next month."], ["On the wing", "Monarchs passing through", "October is monarch migration month in Georgia. Late-blooming flowers help them refuel."]]
    if month = 11 then return [["Fall color", "Peak season", "Early November is usually peak color around LaGrange and Pine Mountain."], ["In the garden", "Plant spring bulbs", "Tulips, daffodils and hyacinths go in now through December. Mulch beds before the first hard freeze."], ["Outdoors", "Fantasy in Lights season", "Callaway Gardens' holiday light show opens in mid-November."]]
    if month = 12 then return [["Winter", "Bare branches, big skies", "Long nights and clear air make December great for stargazing; the Geminids peak mid-month."], ["In the garden", "Protect and plan", "Cover tender plants on frost nights and order seeds for spring."], ["On the wing", "Winter birds at feeders", "Juncos, white-throated sparrows and yellow-rumped warblers arrive for the winter."]]
    return invalid
end function

sub buildSeason(g as object, d as object)
    uiWallpaper(g, d, "season", "#0B1120", "pkg:/images/bg_season.jpg")
    header(g, "WHAT'S IN SEASON · " + UCase(tMonthNames()[tParts(d.now).m - 1]), "The season in " + d.place.seasonRegion, "#F4A259", false)
    cards = []
    cards.Append(seasonItems(tParts(d.now).m))
    frost = invalid
    for i = 1 to 3
        if frost = invalid and i < d.weather.days.Count()
            if d.weather.days[i].lo <= 34 then frost = d.weather.days[i]
        end if
    end for
    if frost <> invalid
        cards.Push(["Frost watch", "Frost " + tDayWord(frost.day, d.today), "Low of " + frost.lo.ToStr() + "° forecast. Cover tender plants."])
    else
        cards.Push(["Frost watch", "None this week", "No frost in the 3-day forecast. Daybreak warns two days ahead."])
    end if
    for i = 0 to 3
        x = gx(1 + i * 3)
        cw = gw(3)
        uiCard(g, x, 540, cw, 476, "#0B1120", "#2A3656", 28, 0.9)
        uiLabel(g, x + 36, 576, cards[i][0], 24, "#F4A259")
        uiText(g, x + 36, 620, cards[i][1], 40, 500, "Outfit", "#F4F1EA", cw - 72, "left", 2)
        uiText(g, x + 36, 740, cards[i][2], 26, 400, "Manrope", "#E1E4EC", cw - 72, "left", 7)
    end for
end sub
