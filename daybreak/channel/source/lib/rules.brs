' City of LaGrange curbside schedule, moon phase, meteor showers, heads-up tips.
' Ported from scripts/sanitation.py and daybreak/service/sources.py.

' Garbage every week on your day; yard waste and bulky trash alternate
' Sunday-Saturday weeks (yard weeks start the week of 2025-12-28; verified
' against all 53 weeks of the 2026 flyer). A city holiday moves pickup to the
' next day; landing on a weekend is flagged to confirm with the city.
' 2026 is from the city's flyer. 2027 is provisional (the usual city holidays
' with federal observance rules) until the 2027 flyer is published.
function curbHolidays() as object
    return {
        "2026-01-01": "New Year's Day", "2026-01-19": "Martin Luther King Jr. Day", "2026-05-25": "Memorial Day",
        "2026-06-19": "Juneteenth", "2026-07-03": "Independence Day (observed)", "2026-09-07": "Labor Day",
        "2026-11-26": "Thanksgiving", "2026-11-27": "Day after Thanksgiving", "2026-12-24": "Christmas Eve",
        "2026-12-25": "Christmas Day",
        "2027-01-01": "New Year's Day", "2027-01-18": "Martin Luther King Jr. Day", "2027-05-31": "Memorial Day",
        "2027-06-18": "Juneteenth (observed)", "2027-07-05": "Independence Day (observed)", "2027-09-06": "Labor Day",
        "2027-11-25": "Thanksgiving", "2027-11-26": "Day after Thanksgiving", "2027-12-23": "Christmas Eve (observed)",
        "2027-12-24": "Christmas Day (observed)", "2027-12-31": "New Year's Day (observed)"
    }
end function

' Years whose schedule has been checked against the city's flyer.
function curbVerifiedYears() as object
    return {"2026": true}
end function

' pickupWeekday: 0 = Sunday ... 6 = Saturday (Monday = 1)
function curbNext(today as integer, pickupWeekday as integer) as object
    holidays = curbHolidays()
    scheduled = today + ((pickupWeekday - tWeekday(today) + 7) mod 7) * 86400
    pickup = scheduled
    while holidays.DoesExist(tKey(pickup))
        pickup = pickup + 86400
    end while
    if pickup < today then return curbNext(scheduled + 86400, pickupWeekday)
    anchor = tYmd(2025, 12, 28)
    weekStart = scheduled - tWeekday(scheduled) * 86400
    weeks = (weekStart - anchor) \ (7 * 86400)
    yard = (weeks mod 2 = 0)
    holiday = invalid
    if holidays.DoesExist(tKey(scheduled)) then holiday = holidays[tKey(scheduled)]
    extra = "bulky trash"
    curb = "Furniture, mattresses, bikes and other large items"
    if yard
        extra = "yard waste"
        curb = "Leaves, brush and limbs (no grass clippings)"
    end if
    return {pickup: pickup, scheduled: scheduled, yard: yard, extra: extra, curb: curb, holiday: holiday,
            confirm: (tWeekday(pickup) = 0 or tWeekday(pickup) = 6),
            known: curbVerifiedYears().DoesExist(tParts(scheduled).y.ToStr())}
end function

' A short caveat for screens: weekend shifts and holiday shifts in a year the
' city hasn't published yet should be checked before relying on them.
function curbCaveat(c as object) as string
    if c.confirm then return "Weekend pickup: confirm with the city"
    if not c.known and c.holiday <> invalid then return "Holiday shift not yet confirmed by the city"
    if not c.known then return "Schedule not yet confirmed by the city"
    return ""
end function

function moonPhase(utcNow as integer) as object
    synodic = 29.530588853
    ref = 947182440 ' 2000-01-06 18:14 UTC, a new moon
    days = (utcNow - ref) / 86400.0
    age = days - Int(days / synodic) * synodic
    illum = (1 - Cos(2 * 3.14159265 * age / synodic)) / 2
    waxing = age < synodic / 2
    name = "Waning "
    if waxing then name = "Waxing "
    if illum < 0.5 then name = name + "crescent" else name = name + "gibbous"
    if age < 1 or age > synodic - 1 then name = "New moon"
    if Abs(age - synodic / 2) < 1 then name = "Full moon"
    if Abs(age - synodic / 4) < 1 then name = "First quarter"
    if Abs(age - 3 * synodic / 4) < 1 then name = "Last quarter"
    fullIn = synodic / 2 - age
    if fullIn < 0 then fullIn = fullIn + synodic
    return {illum: illum, waxing: waxing, name: name, age: age, nextFull: utcNow + Int(fullIn * 86400)}
end function

function meteorShowers() as object
    return [["Quadrantids", 1, 3], ["Lyrids", 4, 22], ["Eta Aquariids", 5, 5], ["Perseids", 8, 12],
            ["Orionids", 10, 21], ["Leonids", 11, 17], ["Geminids", 12, 13]]
end function

function nextShower(today as integer, withinDays as integer) as object
    y = tParts(today).y
    for each yr in [y, y + 1]
        for each s in meteorShowers()
            peak = tYmd(yr, s[1], s[2])
            n = (peak - today) \ 86400
            if n >= 0 and n <= withinDays then return {name: s[0], peak: peak}
        end for
    end for
    return invalid
end function

' Boolean checks that treat a missing (invalid) value as neither true nor
' false; comparing invalid to a boolean is a type mismatch in BrightScript.
function isTrue(v as dynamic) as boolean
    t = type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

function isFalse(v as dynamic) as boolean
    t = type(v)
    if t = "Boolean" or t = "roBoolean" then return not v
    return false
end function

' Up to max tip texts, skipping tips whose ref is in shown (refs already on screen).
function tipTexts(tips as object, shown as object, max as integer) as object
    out = []
    for each tip in tips
        if out.Count() < max and not shown.DoesExist(tip.ref) then out.Push(tip.t)
    end for
    return out
end function

' --- chores ---------------------------------------------------------------------------
' Whose turn: weekly chores rotate each Sunday-to-Saturday week (counted from
' Sunday 2026-01-04), daily ones each day (from 2026-01-01). Returns
' [{task, who, next, every, color}] where next is the following turn.
function choreTurns(chores as dynamic, members as object, today as integer) as object
    out = []
    if chores = invalid then return out
    colors = {}
    for each mem in members
        colors[mem.name] = mem.color
    end for
    for each c in chores
        n = c.rotate.Count()
        if n > 0
            if c.every = "day"
                k = (today - tYmd(2026, 1, 1)) \ 86400
            else
                k = ((today - tWeekday(today) * 86400) - tYmd(2026, 1, 4)) \ (7 * 86400)
            end if
            i = ((k mod n) + n) mod n
            who = c.rotate[i]
            color = colors[who]
            if color = invalid then color = "#F4F1EA"
            out.Push({task: c.task, who: who, next: c.rotate[(i + 1) mod n], every: c.every, color: color})
        end if
    end for
    return out
end function

' --- place --------------------------------------------------------------------------
' Everything town- and household-specific beyond family members. These are
' the LaGrange, Georgia defaults; config/family.json "place" overrides any
' top-level key (see config/family.example.json). Set lake, college or
' curbside to null to turn that part off.
function placeDefaults() as object
    return {
        town: "LaGrange", region: "GA", area: "Troup County", seasonRegion: "West Georgia",
        timezone: "America/New_York",
        teams: [
            {key: "georgia", name: "Georgia", short: "UGA", color: "#BA0C2F", id: "61", path: "football/college-football/teams/61"},
            {key: "auburn", name: "Auburn", short: "AU", color: "#0C2340", accent: "#E87722", id: "2", path: "football/college-football/teams/2"},
            {key: "falcons", name: "Falcons", short: "ATL", color: "#A71930", id: "1", path: "football/nfl/teams/1"},
            {key: "hawks", name: "Hawks", short: "HWK", color: "#C8102E", id: "1", path: "basketball/nba/teams/1"},
            {key: "braves", name: "Braves", short: "ATL", color: "#13274F", accent: "#CE1141", id: "15", path: "baseball/mlb/teams/15"}
        ],
        rivalry: ["Georgia", "Auburn"],
        lake: {name: "West Point Lake", site: "02339400", summerPool: 635, winterPool: 628, lowAlert: 626},
        college: {name: "LaGrange College", short: "LC", team: "Panthers", color: "#8E1B24",
                  ics: "https://lagrangepanthers.com/calendar.ashx/calendar.ics"},
        news: {queries: ["%22LaGrange%22+GA+when%3A2d", "%22Troup+County%22+when%3A3d", "%22LaGrange+Daily+News%22+when%3A2d"],
               local: "lagrange|troup|west point|hogansville|callaway|pine mountain", ownSource: "LaGrange"},
        curbside: "lagrange",
        ' radar map: towns labeled around home (lat/lon; projected on the TV), and
        ' water labels drawn to the left of their point in blue
        radar: {places: [{name: "West Point", lat: 32.878, lon: -85.183}, {name: "Hogansville", lat: 33.173, lon: -84.915},
                         {name: "Pine Mountain", lat: 32.865, lon: -84.854}, {name: "Newnan", lat: 33.381, lon: -84.800},
                         {name: "Carrollton", lat: 33.580, lon: -85.077}, {name: "Auburn", lat: 32.610, lon: -85.481},
                         {name: "Atlanta", lat: 33.749, lon: -84.388}],
                water: [{name: "West Point Lake", lat: 33.032, lon: -85.232}]}
    }
end function

' --- radar map geometry ----------------------------------------------------------------
' The radar window: Web Mercator (EPSG:3857), 1920x1080, centered on home and
' 300 km across on the ground, the same window scripts/radar_map.py renders
' the base map for. 25 miles is 257 px.
function radarView(lat as float, lon as float) as object
    r = 6378137.0
    k = 3.14159265358979 / 180
    x = lon * k * r
    y = Log(Tan(3.14159265358979 / 4 + lat * k / 2)) * r
    hw = 150000.0 / Cos(lat * k)
    hh = hw * 1080 / 1920
    v = {x0: x - hw, y0: y - hh, x1: x + hw, y1: y + hh}
    v.bbox = Int(v.x0).ToStr() + "," + Int(v.y0).ToStr() + "," + Int(v.x1).ToStr() + "," + Int(v.y1).ToStr()
    return v
end function

' Screen pixel [x, y] of a lat/lon in the radar window.
function radarPx(v as object, lat as float, lon as float) as object
    r = 6378137.0
    k = 3.14159265358979 / 180
    x = lon * k * r
    y = Log(Tan(3.14159265358979 / 4 + lat * k / 2)) * r
    return [Int((x - v.x0) / (v.x1 - v.x0) * 1920 + 0.5), Int((v.y1 - y) / (v.y1 - v.y0) * 1080 + 0.5)]
end function

' cfg.place over the defaults, key by key. An explicit null (invalid) in
' family.json arrives as the string "none" from the build.
function placeOf(cfg as dynamic) as object
    p = placeDefaults()
    if cfg = invalid or cfg.place = invalid then return p
    for each k in cfg.place
        v = cfg.place[k]
        if type(v) = "roString" or type(v) = "String"
            if v = "none" then p[k] = invalid else p[k] = v
        else
            p[k] = v
        end if
    end for
    return p
end function

' The place for this thread: set by the data task and the harness, defaults otherwise.
function currentPlace() as object
    if m.place = invalid then m.place = placeDefaults()
    return m.place
end function
