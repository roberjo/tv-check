' Time helpers. Daybreak keeps every time as "wall seconds": the local
' (America/New_York) wall-clock time encoded as if it were UTC seconds since
' 1970. Day math is then plain integer math, and DST never shifts a date.

function tNowWall() as integer
    d = CreateObject("roDateTime")
    d.ToLocalTime()
    return d.AsSeconds()
end function

function tNowUtc() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

' "2026-10-17T22:15:00Z" or "2026-10-18T17:00Z" -> wall seconds
function tUtcIsoToWall(s as string) as integer
    s = tNormIso(s)
    d = CreateObject("roDateTime")
    d.FromISO8601String(s)
    d.ToLocalTime()
    return d.AsSeconds()
end function

' Local wall time without zone ("2026-10-17T07:46") or with a local offset
' ("2026-10-17T22:15:00.000-04:00"): keep the clock reading as-is.
function tLocalIsoToWall(s as string) as integer
    base = Left(s, 19)
    if Len(base) = 16 then base = base + ":00"
    if Len(base) = 10 then base = base + "T00:00:00"
    d = CreateObject("roDateTime")
    d.FromISO8601String(base + "Z")
    return d.AsSeconds()
end function

function tNormIso(s as string) as string
    ' ESPN sends "2026-10-18T17:00Z" without seconds
    if Len(s) = 17 and Right(s, 1) = "Z" then return Left(s, 16) + ":00Z"
    return s
end function

function tYmd(yr as integer, mo as integer, dy as integer) as integer
    d2 = CreateObject("roDateTime")
    d2.FromISO8601String(tPad(yr, 4) + "-" + tPad(mo, 2) + "-" + tPad(dy, 2) + "T00:00:00Z")
    return d2.AsSeconds()
end function

function tPad(n as integer, width as integer) as string
    s = n.ToStr()
    while Len(s) < width
        s = "0" + s
    end while
    return s
end function

function tDay(w as integer) as integer
    return w - (w mod 86400)
end function

' 0 = Sunday ... 6 = Saturday (1970-01-01 was a Thursday)
function tWeekday(w as integer) as integer
    return ((w \ 86400) + 4) mod 7
end function

function tHour(w as integer) as integer
    return (w mod 86400) \ 3600
end function

function tParts(w as integer) as object
    d = CreateObject("roDateTime")
    d.FromSeconds(w)
    return {y: d.GetYear(), m: d.GetMonth(), d: d.GetDayOfMonth()}
end function

function tKey(w as integer) as string
    p = tParts(w)
    return tPad(p.y, 4) + "-" + tPad(p.m, 2) + "-" + tPad(p.d, 2)
end function

function tWeekdayNames() as object
    return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
end function

function tMonthNames() as object
    return ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
end function

function tClock(w as integer) as string
    h = tHour(w)
    mins = (w mod 3600) \ 60
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    return h12.ToStr() + ":" + tPad(mins, 2) + " " + suffix
end function

' "Saturday, October 17"
function tLongDate(w as integer) as string
    p = tParts(w)
    return tWeekdayNames()[tWeekday(w)] + ", " + tMonthNames()[p.m - 1] + " " + p.d.ToStr()
end function

' "Oct 23"
function tShortDate(w as integer) as string
    p = tParts(w)
    return Left(tMonthNames()[p.m - 1], 3) + " " + p.d.ToStr()
end function

' Today / Tomorrow / Yesterday / weekday name within 6 days / "Sat Oct 31"
function tDayWord(w as integer, today as integer) as string
    n = (tDay(w) - today) \ 86400
    if n = 0 then return "Today"
    if n = 1 then return "Tomorrow"
    if n = -1 then return "Yesterday"
    if n > 1 and n < 7 then return tWeekdayNames()[tWeekday(w)]
    return Left(tWeekdayNames()[tWeekday(w)], 3) + " " + tShortDate(w)
end function

' 625.21 -> "625.2"
function fmt1(x as dynamic) as string
    whole = Int(x)
    tenth = Int((x - whole) * 10 + 0.5)
    if tenth = 10
        whole = whole + 1
        tenth = 0
    end if
    return whole.ToStr() + "." + tenth.ToStr()
end function
