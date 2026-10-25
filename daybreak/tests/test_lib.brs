' Off-device tests for source/lib (run with @rokucommunity/brs; see daybreak/tests/run.sh).
sub Main()
    m.fails = 0
    ' --- curbside (expected values from scripts/sanitation.py, verified against the city flyer)
    c = curbNext(tYmd(2026, 10, 18), 1)
    check("curb next from Sun Oct 18", tKey(c.pickup) + " " + c.extra, "2026-10-19 yard waste")
    c = curbNext(tYmd(2026, 10, 20), 1)
    check("curb next from Tue Oct 20", tKey(c.pickup) + " " + c.extra, "2026-10-26 bulky trash")
    c = curbNext(tYmd(2026, 9, 6), 1)
    check("Labor Day shift", tKey(c.pickup) + " " + c.extra + " " + c.holiday, "2026-09-08 yard waste Labor Day")
    c = curbNext(tYmd(2026, 1, 18), 1)
    check("MLK shift", tKey(c.pickup) + " " + c.extra, "2026-01-20 bulky trash")
    c = curbNext(tYmd(2026, 5, 24), 1)
    check("Memorial Day shift", tKey(c.pickup), "2026-05-26")
    c = curbNext(tYmd(2026, 11, 25), 4)
    check("Thanksgiving Thursday route", tKey(c.pickup) + " confirm=" + c.confirm.ToStr(), "2026-11-28 confirm=true")
    check("weekend shift caveat", curbCaveat(c), "Weekend pickup: confirm with the city")
    c = curbNext(tYmd(2026, 10, 18), 1)
    check("2026 is verified", c.known.ToStr() + " '" + curbCaveat(c) + "'", "true ''")
    ' --- 2027 (provisional until the city's 2027 flyer)
    c = curbNext(tYmd(2027, 1, 17), 1)
    check("MLK 2027 shift", tKey(c.pickup) + " " + c.holiday, "2027-01-19 Martin Luther King Jr. Day")
    check("2027 holiday caveat", curbCaveat(c), "Holiday shift not yet confirmed by the city")
    c = curbNext(tYmd(2027, 7, 4), 1)
    check("July 4 2027 observed Monday", tKey(c.pickup) + " " + c.holiday, "2027-07-06 Independence Day (observed)")
    c = curbNext(tYmd(2027, 2, 7), 1)
    check("2027 ordinary week caveat", c.known.ToStr() + " " + curbCaveat(c), "false Schedule not yet confirmed by the city")
    c = curbNext(tYmd(2027, 11, 24), 4)
    check("Thanksgiving 2027 Thursday route", tKey(c.pickup) + " confirm=" + c.confirm.ToStr(), "2027-11-27 confirm=true")
    ' --- dates
    check("weekday Oct 17 2026", tWeekday(tYmd(2026, 10, 17)).ToStr(), "6")
    check("day word", tDayWord(tYmd(2026, 10, 23) + 3600, tYmd(2026, 10, 17)), "Friday")
    check("clock", tClock(tYmd(2026, 10, 17) + 19 * 3600 + 4 * 60), "7:04 PM")
    check("long date", tLongDate(tYmd(2026, 10, 17)), "Saturday, October 17")
    check("utc->wall (EDT)", tKey(tUtcIsoToWall("2026-10-18T02:30:00Z")) + " " + tClock(tUtcIsoToWall("2026-10-18T02:30:00Z")), "2026-10-17 10:30 PM")
    check("espn iso", tClock(tUtcIsoToWall("2026-10-18T17:00Z")), "1:00 PM")
    ' --- sky
    s = nextShower(tYmd(2026, 10, 17), 14)
    check("next shower", s.name + " " + tKey(s.peak), "Orionids 2026-10-21")
    mp = moonPhase(1792290000)
    check("moon illum ~43%", Int(mp.illum * 100 + 0.5).ToStr(), "43")
    ' --- iCal: synthetic calendar (tests/fixtures/sample.ics) for Oct 17 + 21 days
    events = icsParse(ReadAsciiFile("pkg:/sample.ics"))
    check("sample events parsed", events.Count().ToStr(), "11")
    lo = tYmd(2026, 10, 17)
    hi = lo + 21 * 86400
    found = []
    for each ev in events
        if not ev.cancelled
            for each w in icsOccurrences(ev, lo, hi)
                found.Push(tKey(w) + " " + ev.summary)
            end for
        end if
    end for
    found.Sort()
    check("occurrences (series ended, COUNT=2, all-day, UTC, TZID)", found.Join(" | "), "2026-10-17 Buy: milk, eggs, coffee | 2026-10-17 TV: Dinner at 6:30 tonight | 2026-10-18 Family photo with Grandma | 2026-10-20 Casey band rehearsal | 2026-10-23 Science fair registration deadline — Nov 7 fair | 2026-10-27 Casey band rehearsal | 2026-10-30 Countdown: Beach trip | 2026-11-06 Dentist checkup for Riley | 2026-11-07 Science fair — both kids")
    for each ev in events
        if ev.summary = "Family photo with Grandma" then check("UTC -> local 6 PM", tClock(ev.start), "6:00 PM")
        if ev.summary = "Jordan Piano Lesson"
            keys = []
            for each w in icsOccurrences(ev, tYmd(2025, 6, 9), tYmd(2025, 6, 20))
                keys.Push(tKey(w))
            end for
            check("EXDATE skips Tue 2025-06-10", keys.Join(","), "2025-06-12,2025-06-17,2025-06-19")
        end if
    end for
    lc = icsParse(ReadAsciiFile("pkg:/feeds/lc.ics"))
    check("college feed parses", lc.Count().ToStr() + " " + lc[0].summary, "4 [W] LaGrange College Men's Soccer vs Covenant College")
    testSummary("lib")
end sub
