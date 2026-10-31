' Data task: the heads-up tips and rain timing.

' When rain is likely on a day, from the hourly forecast: the first run of
' hours at 60% or more between 6 AM (or now, today) and midnight ->
' {from, until, peak}, or invalid. A dry hour ends the run, so "until about"
' never spans a break in the rain.
function rainWindow(w as object, day as integer, now as integer) as dynamic
    start = day + 6 * 3600
    if day = tDay(now) and now - now mod 3600 > start then start = now - now mod 3600
    out = invalid
    for each h in w.hours
        if h.t >= start and h.t < day + 86400
            if h.rain >= 60
                if out = invalid then out = {from: h.t, until: h.t + 3600, peak: h.rain, open: true}
                if out.open
                    out.until = h.t + 3600
                    if h.rain > out.peak then out.peak = h.rain
                end if
            else if out <> invalid
                out.open = false
            end if
        end if
    end for
    return out
end function

' "Rain likely Tuesday from about noon (65%)." Today, when it's already raining:
' "Rain likely until about 8 PM (80%)." Without hourly data, the daily chance.
function rainTip(w as object, day as object, now as integer, today as integer) as string
    word = tDayWord(day.day, today)
    if word = "Today" or word = "Tomorrow" then word = LCase(word)
    win = rainWindow(w, tDay(day.day), now)
    if win = invalid then return "Rain likely " + word + " (" + day.rain.ToStr() + "%)."
    pct = " (" + win.peak.ToStr() + "%)."
    if tDay(day.day) = today
        if win.from <= now then return "Rain likely until about " + hourWord(win.until) + pct
        return "Rain likely from about " + hourWord(win.from) + pct
    end if
    return "Rain likely " + word + " from about " + hourWord(win.from) + pct
end function

' 3 PM, noon, midnight
function hourWord(t as integer) as string
    h = tHour(t)
    if h = 12 then return "noon"
    if h = 0 then return "midnight"
    return tClock(t).Replace(":00", "")
end function

function rainSoon(w as dynamic, now as integer) as boolean
    if w = invalid then return false
    for each h in w.hours
        if h.t > now - 3600 and h.t <= now + 2 * 3600 and h.rain >= 50 then return true
    end for
    return false
end function

' Rule-based insights, most important first. Each tip has a priority p, a
' kind (alert, curb, deadline, clocks, overlap, rain, frost, birthday, shower, lake, ...)
' and a ref naming what it's about, so a screen can skip tips it already shows.
function headsUp(d as object) as object
    tips = []
    today = d.today
    for each a in d.alerts
        p = 1
        if a.level = "warning" then p = 0
        tips.Push({p: p, kind: "alert", ref: a.event, t: a.event + " for " + d.place.area + "."})
    end for
    c = d.curb
    n = 99
    if c <> invalid then n = (c.pickup - today) \ 86400
    if n <= 1 or (tWeekday(d.now) = 0 and n <= 2)
        moved = ""
        if c.holiday <> invalid then moved = " (moved for " + c.holiday + ")"
        extra = "bulky trash"
        if c.yard then extra = "yard waste (no grass clippings)"
        t = tDayWord(c.pickup, today) + moved + ": garbage plus " + extra + ". Curb by 7 AM."
        caveat = curbCaveat(c)
        if caveat <> "" then t = t + " " + caveat + "."
        tips.Push({p: 2, kind: "curb", ref: "curb", t: t})
    end if
    ' school closings and early releases today or tomorrow come right after warnings
    for each e in d.calendar
        dn = (tDay(e.start) - today) \ 86400
        if isTrue(e.closing) and dn >= 0 and dn <= 1
            t = tDayWord(e.start, today) + ": " + e.title
            if not e.allDay then t = t + " at " + tClock(e.start)
            if e.subtitle <> "" then t = t + " (" + e.subtitle + ")"
            tips.Push({p: 1, kind: "school", ref: e.title, t: t + "."})
        end if
    end for
    for each e in d.calendar
        dn = (tDay(e.start) - today) \ 86400
        if e.deadline and dn >= 0 and dn <= 7
            t = e.title + " is " + LCase(tDayWord(e.start, today))
            if dn >= 2 then t = e.title + " is " + tDayWord(e.start, today)
            if e.subtitle <> "" then t = t + " (" + e.subtitle + ")"
            if e.who.Count() > 0 then t = t + " for " + e.who.Join(" and ")
            tips.Push({p: 3, kind: "deadline", ref: e.title, t: t + "."})
        end if
    end for
    for i = 0 to d.calendar.Count() - 1
        a = d.calendar[i]
        for j = i + 1 to d.calendar.Count() - 1
            b = d.calendar[j]
            if not a.allDay and not b.allDay and tDay(a.start) = tDay(b.start) and Abs(a.start - b.start) < 5400 and (tDay(a.start) - today) \ 86400 <= 7
                tips.Push({p: 4, kind: "overlap", ref: a.title, t: tDayWord(a.start, today) + ": " + a.title + " and " + b.title + " overlap."})
            end if
        end for
    end for
    if d.weather <> invalid
        for i = 0 to 3
            day = d.weather.days[i]
            if day.rain >= 60 then tips.Push({p: 5, kind: "rain", ref: tKey(day.day), t: rainTip(d.weather, day, d.now, today)})
            if i > 0 and day.lo <= 34 then tips.Push({p: 5, kind: "frost", ref: tKey(day.day), t: "Frost possible " + tDayWord(day.day, today) + " morning (" + day.lo.ToStr() + "°). Cover tender plants."})
        end for
    end if
    for each gm in d.games
        if gm.wx <> invalid and gm.wx.rain >= 60 and tDay(gm.start) - today <= 2 * 86400
            tips.Push({p: 5, kind: "gamerain", ref: gm.name + tKey(gm.start), t: tDayWord(gm.start, today) + ": " + gm.wx.rain.ToStr() + "% chance of rain at game time for " + gm.name + " " + gm.detail + " (" + tClock(gm.start) + ")."})
        end if
    end for
    for each b in d.birthdays
        if b.days <= 14 then tips.Push({p: 6, kind: "birthday", ref: b.name + "'s birthday", t: b.name + "'s birthday is " + tDayWord(b.day, today) + "."})
    end for
    if d.dst <> invalid
        sunset = 0
        if d.weather <> invalid
            for each wd in d.weather.days
                if tDay(wd.day) = tDay(d.dst.day) then sunset = wd.sunset
            end for
        end if
        tips.Push({p: 3, kind: "clocks", ref: "clocks", t: dstTip(d.dst, today, sunset)})
    end if
    if d.shower <> invalid and (d.shower.peak - today) \ 86400 <= 4
        tips.Push({p: 7, kind: "shower", ref: d.shower.name, t: "The " + d.shower.name + " meteor shower peaks " + tDayWord(d.shower.peak, today) + " night. Best before dawn."})
    end if
    if d.air <> invalid and d.air.peak >= 101
        tips.Push({p: 5, kind: "air", ref: "air", t: "Air quality " + LCase(aqiLabel(d.air.peak)) + " " + tDayWord(d.air.peakAt, today) + " (AQI " + d.air.peak.ToStr() + "). Limit time outdoors if sensitive."})
    end if
    for each c in d.countdowns
        if c.days > 0 and c.days <= 14 then tips.Push({p: 6, kind: "countdown", ref: c.title, t: c.title + " is in " + c.days.ToStr() + " days."})
        if c.days = 0 then tips.Push({p: 6, kind: "countdown", ref: c.title, t: c.title + " is today!"})
    end for
    for each st in d.storms
        p = 7
        if st.miles <= 500 then p = 3
        tips.Push({p: p, kind: "tropics", ref: st.name, t: st.kind + " " + st.name + " (" + st.mph.ToStr() + " mph) is " + st.miles.ToStr() + " mi from " + d.place.town + "."})
    end for
    if d.lake <> invalid and d.place.lake <> invalid and d.lake.level < d.place.lake.lowAlert
        tips.Push({p: 8, kind: "lake", ref: "lake", t: d.place.lake.name + " is low at " + fmt1(d.lake.level) + " ft. Check ramps before launching."})
    end if
    ' SortBy doesn't promise a stable order; sort on priority, then insertion order.
    for i = 0 to tips.Count() - 1
        tips[i].order = tips[i].p * 1000 + i
    end for
    tips.SortBy("order")
    return tips
end function
