' Screens: Game recap and Game day.

sub buildRecap(g as object, d as object)
    uiWallpaper(g, d, "recap", "#0B1120")
    header(g, "GAME RECAP · " + UCase(tLongDate(d.now)), "How your teams did", "#F4A259", false)
    top = 246
    r = d.rivalry
    hero = invalid
    if r = invalid
        for each f in d.finals
            if hero = invalid and f.pro then hero = f
        end for
        if hero = invalid and d.finals.Count() > 0 then hero = d.finals[0]
    end if
    if r <> invalid
        fans = {}
        fans[r.winner] = fansOf(d, r.winner)
        fans[r.loser] = fansOf(d, r.loser)
        win = teamNamed(d, r.winner)
        color = "#5C0A18"
        accent = "#F4F1EA"
        if win <> invalid
            color = win.color
            if win.accent <> invalid then accent = win.accent
        end if
        uiCard(g, gx(1), top, gw(6) + 40, 770, color, "", 32)
        teamLogo(g, logoOf(d, r.winner), gx(1) + gw(6) + 40 - 500, top + 230, 460, 0.12)
        uiLabel(g, gx(1) + 56, top + 54, "House divided · final", 24, accent)
        uiText(g, gx(1) + 56, top + 120, r.winner + " " + r.hi.ToStr(), 120, 600, "Outfit")
        uiText(g, gx(1) + 56, top + 280, r.loser + " " + r.lo.ToStr(), 80, 400, "Outfit", "#C9CEDA")
        brag = r.winner + " fans have bragging rights."
        if fans[r.winner] <> "" then brag = fans[r.winner] + " have bragging rights."
        if fans[r.loser] <> "" then brag = brag + " " + fans[r.loser] + ", there's always next year."
        uiText(g, gx(1) + 56, top + 460, brag, 34, 500, "Manrope", "#F4F1EA", gw(6) - 72, "left", 3)
        uiText(g, gx(1) + 56, top + 690, r.host + " hosted · " + r.network, 26, 400, "Manrope", "#C9CEDA", gw(6) - 72)
    else if hero <> invalid
        uiCard(g, gx(1), top, gw(6) + 40, 770, hero.color, "", 32)
        teamLogo(g, hero.logo, gx(1) + gw(6) + 40 - 500, top + 270, 460, 0.12)
        res = "Loss · "
        if hero.won then res = "Win · "
        uiLabel(g, gx(1) + 56, top + 54, res + hero.team, 24, "#F4F1EA")
        uiText(g, gx(1) + 56, top + 140, hero.score, 190, 600, "Outfit")
        uiText(g, gx(1) + 56, top + 400, hero.detail, 36, 600, "Manrope", "#F4F1EA", gw(6) - 72)
    end if
    rx = gx(7) + 40
    rw = 1808 - rx
    uiCard(g, rx, top, rw, 520)
    uiLabel(g, rx + 40, top + 38, "More results")
    yy = top + 90
    n = 0
    for each f in d.finals
        skip = (f.rivalry and r <> invalid) or (hero <> invalid and f.start = hero.start and f.team = hero.team)
        if not skip and n < 6
            bg = "#3A2024"
            fg = "#F2A7B0"
            wl = "L"
            if f.won
                bg = "#1F3A2A"
                fg = "#9EC79B"
                wl = "W"
            end if
            uiCard(g, rx + 40, yy, 60, 42, bg, "", 10)
            uiText(g, rx + 70, yy + 5, wl, 24, 800, "Manrope", fg, 60, "center")
            label = f.team + " " + f.detail
            if not f.pro then label = f.team + " " + sportCase(f.detail)
            uiText(g, rx + 124, yy + 4, label, 26, 600, "Manrope", "#F4F1EA", rw - 300)
            uiText(g, rx + rw - 40, yy, f.score, 32, 400, "Outfit", "#F4F1EA", 150, "right")
            yy = yy + 64
            n = n + 1
        end if
    end for
    if n = 0 then uiText(g, rx + 40, yy, "No other finals in the last day and a half.", 26, 400, "Manrope", "#A9B1C4", rw - 80)
    uiCard(g, rx, top + 552, rw, 218)
    uiLabel(g, rx + 40, top + 588, "Season records")
    i = 0
    for each t in recordTeams(d)
        label = t.name
        if fansOf(d, t.name) <> "" then label = label + " (" + fansOf(d, t.name) + ")"
        uiText(g, rx + 40, top + 636 + i * 56, label, 26, 600, "Manrope", "#F4F1EA", rw - 280)
        rec = d.records[t.key]
        if rec = invalid then rec = "—"
        uiText(g, rx + rw - 40, top + 636 + i * 56, rec, 30, 400, "Outfit", "#F4F1EA", 200, "right")
        i = i + 1
    end for
end sub

' "Men's Soccer vs Covenant" -> "men's soccer vs Covenant"
function sportCase(detail as string) as string
    for each sep in [" vs ", " at "]
        k = Instr(1, detail, sep)
        if k > 0 then return LCase(Left(detail, k - 1)) + Mid(detail, k)
    end for
    return LCase(detail)
end function

function teamNamed(d as object, name as string) as dynamic
    for each t in d.place.teams
        if t.name = name then return t
    end for
    return invalid
end function

' Season records to show: the rivalry pair, or else the first two teams.
function recordTeams(d as object) as object
    out = []
    if d.place.rivalry <> invalid
        for each n in d.place.rivalry
            t = teamNamed(d, n)
            if t <> invalid then out.Push(t)
        end for
    end if
    if out.Count() = 0
        for i = 0 to d.place.teams.Count() - 1
            if i < 2 then out.Push(d.place.teams[i])
        end for
    end if
    return out
end function

function fansOf(d as object, team as string) as string
    names = []
    for each mem in d.members
        if mem.allegiance = team then names.Push(mem.name)
    end for
    return names.Join(" & ")
end function

sub buildGameday(g as object, d as object)
    games = soonGames(d)
    uiRect(g, 0, 0, 1920, 1080, "#0B1120")
    panels = []
    for each gm in games
        if panels.Count() < 2 then panels.Push(gm)
    end for
    pw = 1920 / panels.Count()
    divided = false
    pair = d.place.rivalry
    if panels.Count() = 2 and pair <> invalid and pair.Count() = 2
        divided = (panels[0].name = pair[0] and panels[1].name = pair[1]) or (panels[0].name = pair[1] and panels[1].name = pair[0])
    end if
    for i = 0 to panels.Count() - 1
        gm = panels[i]
        x = i * pw
        uiRect(g, x, 0, pw, 790, gm.color)
        align = "left"
        tx = x + 112
        ls = 640
        if panels.Count() = 2 then ls = 460
        lx = x + pw - ls - 80 ' the logo sits on the side away from the text
        if i = 1
            align = "right"
            tx = x + pw - 112
            lx = x + 80
        end if
        teamLogo(g, gm.logo, lx, (790 - ls) / 2, ls)
        lbl = "GAME DAY"
        if gm.state = "in" then lbl = "ON NOW"
        if divided then lbl = lbl + " · HOUSE DIVIDED"
        uiText(g, tx, 72, lbl, 24, 700, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        size = 160
        if panels.Count() = 2 then size = 132
        uiText(g, tx, 110, gm.name, size, 600, "Outfit", "#F4F1EA", Int(pw) - 224, align)
        uiText(g, tx, 130 + size + 20, gm.detail, 34, 500, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        if gm.state = "in"
            uiText(g, tx, 520, gm.my + "–" + gm.their, 120, 500, "Outfit", "#F4F1EA", Int(pw) - 224, align)
            if gm.status <> invalid and gm.status <> "" then uiText(g, tx, 400, gm.status, 34, 600, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        else
            uiText(g, tx, 540, tClock(gm.start), 100, 300, "Outfit", "#F4F1EA", Int(pw) - 224, align)
        end if
        if gm.network <> "" then uiText(g, tx, 680, "on " + gm.network, 30, 600, "Manrope", "#F4F1EA", Int(pw) - 224, align)
        if gm.wx <> invalid then uiText(g, tx, 728, "Game time: " + gameWxText(gm.wx), 30, 500, "Manrope", "#F4F1EA", Int(pw) - 224, align)
    end for
    if panels.Count() = 1
        delta = panels[0].start - d.now
        if delta > 0 then uiText(g, 1808, 580, "Kickoff in " + (delta \ 3600).ToStr() + " h " + ((delta mod 3600) \ 60).ToStr() + " m", 40, 500, "Outfit", "#F4F1EA", 700, "right")
    end if
    others = []
    for each gm in d.games
        isPanel = false
        for each p in panels
            if p.start = gm.start and p.name = gm.name then isPanel = true
        end for
        if not isPanel and others.Count() < 4 then others.Push(gm)
    end for
    for i = 0 to others.Count() - 1
        gm = others[i]
        x = gx(1 + i * 3)
        cw = gw(3)
        uiCard(g, x, 830, cw, 190)
        teamLogo(g, gm.logo, x + cw - 140, 856, 120, 0.18)
        uiCard(g, x + 36, 866, 18, 18, gm.color, "", 10)
        uiText(g, x + 66, 856, gm.name, 26, 700, "Manrope", "#F4F1EA", cw - 100)
        uiText(g, x + 36, 900, gameWhenShort(gm, d.today), 34, 400, "Outfit", "#F4F1EA", cw - 72)
        uiText(g, x + 36, 958, gm.detail, 24, 400, "Manrope", "#A9B1C4", cw - 72)
    end for
end sub
