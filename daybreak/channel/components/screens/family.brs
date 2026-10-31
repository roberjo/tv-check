' Screens: School and Family board.

sub buildSchool(g as object, d as object)
    uiWallpaper(g, d, "school", "#0B1120")
    schools = {}
    for each mem in d.members
        if mem.school <> invalid then schools[UCase(mem.school)] = true
    end for
    eyebrow = "SCHOOL"
    if schools.Count() > 0 then eyebrow = schools.Keys().Join(" · ")
    header(g, eyebrow, "School this week", "#7FB7E8", false)
    top = 246
    items = []
    for each e in d.calendar
        if e.school and e.start >= d.today and items.Count() < 5 then items.Push(e)
    end for
    uiCard(g, gx(1), top, gw(6) + 40, 770, "#132235", "", 32)
    uiLabel(g, gx(1) + 52, top + 48, "Coming up · from the family calendar", 24, "#7FB7E8")
    yy = top + 116
    for each e in items
        uiText(g, gx(1) + 52, yy, tShortDate(e.start), 28, 700, "Manrope", "#7FB7E8")
        t = e.title
        if e.subtitle <> "" then t = t + " · " + e.subtitle
        uiText(g, gx(1) + 52, yy + 38, t, 32, 600, "Manrope", "#F4F1EA", gw(6) - 64)
        uiText(g, gx(1) + 52, yy + 82, tDayWord(e.start, d.today) + " · " + e.whoText, 24, 400, "Manrope", "#A9B1C4", gw(6) - 64)
        yy = yy + 128
    end for
    if items.Count() = 0 then uiText(g, gx(1) + 52, yy, "No school dates on the calendar this month.", 30, 400, "Manrope", "#A9B1C4", gw(6) - 64)
    kids = []
    for each mem in d.members
        if mem.school <> invalid then kids.Push(mem)
    end for
    if kids.Count() = 0 then return
    rx = gx(7) + 40
    rw = 1808 - rx
    kh = (770 - 28 * (kids.Count() - 1)) / kids.Count()
    for i = 0 to kids.Count() - 1
        k = kids[i]
        ky = top + i * (kh + 28)
        uiCard(g, rx, ky, rw, kh)
        uiRect(g, rx + 28, ky + 1, rw - 56, 6, k.color)
        uiText(g, rx + 40, ky + 36, k.name, 48, 600, "Outfit")
        info = k.school + " · " + k.grade.ToStr() + "th grade"
        if k.band = true then info = info + " · marching band"
        uiText(g, rx + 40, ky + 104, info, 24, 400, "Manrope", "#A9B1C4", rw - 80)
        nextShown = false
        for each e in items
            for each nm in e.who
                if nm = k.name and not nextShown
                    uiText(g, rx + 40, ky + 160, "Next: " + e.title + " (" + tDayWord(e.start, d.today) + ")", 26, 500, "Manrope", "#F4F1EA", rw - 80)
                    nextShown = true
                end if
            end for
        end for
        if k.band = true then uiText(g, rx + 40, ky + 208, "Friday nights: marching band at the game", 24, 500, "Manrope", k.color, rw - 80)
    end for
end sub

sub buildBoard(g as object, d as object)
    uiWallpaper(g, d, "board", "#0B1120")
    header(g, "FAMILY BOARD", "Notes for the " + d.household, "#F4A259", false)
    uiText(g, 1808, 140, "Add an event called ""TV: your note"" to the family calendar", 24, 400, "Manrope", "#A9B1C4", 900, "right")
    top = 246
    cw = gw(4)
    maxNotes = 4
    if d.chores.Count() > 0 then maxNotes = 2 ' chores take the bottom row
    for i = 0 to d.notes.Count() - 1
        if i < maxNotes
            n = d.notes[i]
            x = gx(1 + (i mod 2) * 4)
            y = top + (i \ 2) * 397
            uiCard(g, x, y, cw, 373, "#1B2433", "")
            uiRect(g, x + 28, y + 1, cw - 56, 6, n.color)
            uiText(g, x + 40, y + 46, n.text, 44, 500, "Outfit", "#F4F1EA", cw - 80, "left", 4)
            uiText(g, x + 40, y + 316, n.from, 24, 400, "Manrope", "#A9B1C4", cw - 80)
        end if
    end for
    if d.chores.Count() > 0
        cy0 = top + 397
        uiCard(g, gx(1), cy0, gw(8), 373)
        uiLabel(g, gx(1) + 40, cy0 + 36, "Whose turn")
        yy = cy0 + 88
        for each c in d.chores
            if yy < cy0 + 340
                uiDot(g, gx(1) + 52, yy + 18, 9, c.color)
                uiText(g, gx(1) + 76, yy, c.who, 30, 700, "Manrope", "#F4F1EA", 220)
                uiText(g, gx(1) + 310, yy + 2, c.task, 28, 500, "Manrope", "#F4F1EA", gw(8) - 600)
                when = "Tomorrow: "
                if c.every = "week" then when = "Next week: "
                uiText(g, gx(1) + gw(8) - 40, yy + 4, when + c.next, 24, 400, "Manrope", "#A9B1C4", 260, "right")
                yy = yy + 64
            end if
        end for
    end if
    gx0 = gx(9)
    gw0 = gw(4)
    gtop = top
    if d.countdowns.Count() > 0
        n = d.countdowns.Count()
        if n > 3 then n = 3
        ch = 84 + n * 70
        uiCard(g, gx0, top, gw0, ch, "#1B2433", "")
        uiRect(g, gx0 + 28, top + 1, gw0 - 56, 6, "#B3A6F2")
        uiLabel(g, gx0 + 40, top + 34, "Counting down", 24, "#B3A6F2")
        for i = 0 to n - 1
            c = d.countdowns[i]
            cy = top + 80 + i * 70
            days = c.days.ToStr()
            unit = "days"
            if c.days = 1 then unit = "day"
            if c.days = 0
                days = "Today"
                unit = ""
            end if
            uiText(g, gx0 + 40, cy, days, 44, 500, "Outfit", "#F4F1EA", 130)
            uiText(g, gx0 + 176, cy + 4, c.title, 26, 600, "Manrope", "#F4F1EA", gw0 - 216)
            uiText(g, gx0 + 176, cy + 36, unit + " · " + tShortDate(c.day), 24, 400, "Manrope", "#A9B1C4", gw0 - 216)
        end for
        gtop = top + ch + 24
    end if
    uiCard(g, gx0, gtop, gw0, top + 770 - gtop)
    uiLabel(g, gx0 + 40, gtop + 38, "Grocery list")
    yy = gtop + 98
    for i = 0 to d.groceries.Count() - 1
        if yy < top + 770 - 60
            uiCard(g, gx0 + 40, yy + 4, 28, 28, "#131B2E", "#A9B1C4", 10)
            uiText(g, gx0 + 88, yy, d.groceries[i], 28, 400, "Manrope", "#F4F1EA", gw0 - 128)
            yy = yy + 56
        end if
    end for
    if d.groceries.Count() = 0 then uiText(g, gx0 + 40, yy, "Add ""Buy: milk, eggs"" to the family calendar", 24, 400, "Manrope", "#A9B1C4", gw0 - 80, "left", 3)
end sub
