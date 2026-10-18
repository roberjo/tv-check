' City of LaGrange curbside schedule, moon phase, meteor showers.
' Ported from scripts/sanitation.py and daybreak/service/sources.py.

' Garbage every week on your day; yard waste and bulky trash alternate
' Sunday-Saturday weeks (yard weeks start the week of 2025-12-28; verified
' against all 53 weeks of the 2026 flyer). A city holiday moves pickup to the
' next day; landing on a weekend is flagged to confirm with the city.
function curbHolidays() as object
    return {
        "2026-01-01": "New Year's Day", "2026-01-19": "Martin Luther King Jr. Day", "2026-05-25": "Memorial Day",
        "2026-06-19": "Juneteenth", "2026-07-03": "Independence Day (observed)", "2026-09-07": "Labor Day",
        "2026-11-26": "Thanksgiving", "2026-11-27": "Day after Thanksgiving", "2026-12-24": "Christmas Eve",
        "2026-12-25": "Christmas Day"
    }
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
            confirm: (tWeekday(pickup) = 0 or tWeekday(pickup) = 6), known: (tParts(scheduled).y = 2026)}
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
