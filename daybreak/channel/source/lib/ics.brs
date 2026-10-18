' Minimal iCalendar reader: all-day and timed events (UTC, TZID treated as
' local), RRULE (DAILY / WEEKLY with BYDAY and INTERVAL / MONTHLY / YEARLY,
' COUNT, UNTIL) and EXDATE. Times are wall seconds (see time.brs).

function icsTime(prop as string, value as string) as integer
    v = value.Trim()
    if Len(v) = 8 or Instr(1, prop, "VALUE=DATE") > 0
        return tYmd(Val(Mid(v, 1, 4)), Val(Mid(v, 5, 2)), Val(Mid(v, 7, 2)))
    end if
    iso = Mid(v, 1, 4) + "-" + Mid(v, 5, 2) + "-" + Mid(v, 7, 2) + "T" + Mid(v, 10, 2) + ":" + Mid(v, 12, 2) + ":" + Mid(v, 14, 2)
    if Right(v, 1) = "Z" then return tUtcIsoToWall(iso + "Z")
    return tLocalIsoToWall(iso)
end function

function icsUnescape(s as string) as string
    return s.Replace("\,", ",").Replace("\;", ";").Replace("\n", " ").Replace("\N", " ")
end function

function icsParse(text as string) as object
    lines = text.Replace(Chr(13), "").Split(Chr(10))
    unfolded = []
    for each line in lines
        if Len(line) > 0 and (Left(line, 1) = " " or Left(line, 1) = Chr(9)) and unfolded.Count() > 0
            unfolded[unfolded.Count() - 1] = unfolded[unfolded.Count() - 1] + Mid(line, 2)
        else
            unfolded.Push(line)
        end if
    end for
    events = []
    ev = invalid
    for each line in unfolded
        if line = "BEGIN:VEVENT"
            ev = {start: invalid, finish: invalid, allDay: false, summary: "", location: "", description: "", rrule: "", exdates: {}, cancelled: false}
        else if line = "END:VEVENT"
            if ev <> invalid and ev.start <> invalid then events.Push(ev)
            ev = invalid
        else if ev <> invalid
            c = Instr(1, line, ":")
            if c > 0
                prop = Left(line, c - 1)
                value = Mid(line, c + 1)
                name = prop
                semi = Instr(1, prop, ";")
                if semi > 0 then name = Left(prop, semi - 1)
                if name = "DTSTART"
                    ev.start = icsTime(prop, value)
                    ev.allDay = (Len(value.Trim()) = 8 or Instr(1, prop, "VALUE=DATE") > 0)
                else if name = "DTEND"
                    ev.finish = icsTime(prop, value)
                else if name = "SUMMARY"
                    ev.summary = icsUnescape(value)
                else if name = "LOCATION"
                    ev.location = icsUnescape(value)
                else if name = "DESCRIPTION"
                    ev.description = value
                else if name = "RRULE"
                    ev.rrule = value
                else if name = "EXDATE"
                    for each part in value.Split(",")
                        ev.exdates[tKey(icsTime(prop, part))] = true
                    end for
                else if name = "STATUS"
                    ev.cancelled = (value.Trim() = "CANCELLED")
                end if
            end if
        end if
    end for
    return events
end function

' Start times (wall seconds) of ev's occurrences whose day falls in [lo, hi].
function icsOccurrences(ev as object, lo as integer, hi as integer) as object
    out = []
    startDay = tDay(ev.start)
    timeOfDay = ev.start - startDay
    if ev.rrule = ""
        if startDay >= tDay(lo) and startDay <= hi then out.Push(ev.start)
        return out
    end if
    r = {}
    for each part in ev.rrule.Split(";")
        kv = part.Split("=")
        if kv.Count() = 2 then r["rr_" + UCase(kv[0])] = kv[1] ' prefixed: RRULE's COUNT would shadow the AA's Count() method
    end for
    freq = r["rr_FREQ"]
    interval = 1
    if r["rr_INTERVAL"] <> invalid then interval = Val(r["rr_INTERVAL"])
    lastDay = hi
    if r["rr_UNTIL"] <> invalid
        u = tDay(icsTime("", r["rr_UNTIL"]))
        if u < lastDay then lastDay = u
    end if
    count = 1000000
    if r["rr_COUNT"] <> invalid then count = Val(r["rr_COUNT"])
    byday = {}
    if freq = "WEEKLY" and r["rr_BYDAY"] <> invalid
        names = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        for each code in r["rr_BYDAY"].Split(",")
            for i = 0 to 6
                if Right(code, 2) = names[i] then byday[i.ToStr()] = true
            end for
        end for
    end if
    startParts = tParts(startDay)
    weekStart0 = startDay - tWeekday(startDay) * 86400
    n = 0
    d = startDay
    while d <= lastDay and n < count
        hit = false
        if freq = "WEEKLY" and byday.Count() > 0
            weeks = (d - weekStart0) \ (7 * 86400)
            hit = (weeks mod interval = 0) and byday.DoesExist(tWeekday(d).ToStr())
        else if freq = "WEEKLY"
            hit = (((d - startDay) \ 86400) mod (7 * interval) = 0)
        else if freq = "DAILY"
            hit = (((d - startDay) \ 86400) mod interval = 0)
        else if freq = "MONTHLY"
            hit = (tParts(d).d = startParts.d)
        else if freq = "YEARLY"
            p = tParts(d)
            hit = (p.d = startParts.d and p.m = startParts.m)
        else
            hit = (d = startDay)
        end if
        if hit
            n = n + 1
            if d >= tDay(lo) and not ev.exdates.DoesExist(tKey(d)) then out.Push(d + timeOfDay)
        end if
        d = d + 86400
    end while
    return out
end function
