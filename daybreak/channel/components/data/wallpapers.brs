' Data task: the wallpaper catalog, daily picks and background downloads.

' --- wallpapers ------------------------------------------------------------------------
' Photo backgrounds come from a catalog (daybreak/wallpapers, served from the
' repo): the TV fetches it daily, picks a photo per screen per day, and
' downloads today's and tomorrow's picks into cachefs: in the background.

' Catalog -> [{id, file, place, credit, tags, screens, seasons}]. Ids become file names
' on the TV, so only lowercase letters, digits and dashes pass.
function normWallpapers(j as dynamic) as dynamic
    if j = invalid or type(j.photos) <> "roArray" then return invalid
    safeId = CreateObject("roRegex", "^[a-z0-9-]{1,40}$", "")
    safeFile = CreateObject("roRegex", "^img/[a-z0-9-]{1,40}\.jpg$", "")
    out = []
    for each p in j.photos
        if out.Count() < 100 and type(p) = "roAssociativeArray" and isText(p.id) and isText(p.file)
            if safeId.IsMatch(p.id) and safeFile.IsMatch(p.file) and type(p.screens) = "roArray"
                out.Push({id: p.id, file: p.file, place: Left(strOrEmpty(p.place), 60), credit: Left(strOrEmpty(p.credit), 80),
                          tags: textList(p.tags), screens: textList(p.screens), seasons: textList(p.seasons)})
            end if
        end if
    end for
    return out
end function

function textList(v as dynamic) as object
    out = []
    if type(v) = "roArray"
        for each x in v
            if isText(x) then out.Push(x)
        end for
    end if
    return out
end function

function hasItem(list as dynamic, v as string) as boolean
    for each x in arrOf(list)
        if x = v then return true
    end for
    return false
end function

' Screens that can show a wallpaper, in pick order.
function wallpaperScreens() as object
    return ["ambient", "briefing", "season", "tonight", "week", "weekend", "recap", "lake", "school", "board"]
end function

' A photo for each screen on this day: different photos on different screens
' where there are enough, changing daily, and never yesterday's photo on the
' same screen. That last needs no history: even days pick from the even
' positions of a screen's candidate list and odd days from the odd ones, so
' consecutive days draw from different photos.
'
' Candidates for a screen passed the contrast audit there (screens); lake
' photos alone go on the Lake screen, night photos only on Tonight (which
' prefers them), and photos suited to the season (seasons; none = any) come
' first. Photos in hidden (ids the family hid) are never picked.
function wallpaperPicks(photos as dynamic, day as integer, hidden = {} as object) as object
    picks = {}
    if photos = invalid then return picks
    season = seasonOf(tParts(day).m)
    used = {}
    n = day \ 86400
    screens = wallpaperScreens()
    for si = 0 to screens.Count() - 1
        sc = screens[si]
        all = []
        fit = []
        night = []
        for each p in photos
            ok = hasItem(p.screens, sc) and (sc <> "lake" or hasItem(p.tags, "lake"))
            if hasItem(p.tags, "night") and sc <> "tonight" then ok = false
            if hidden.DoesExist(p.id) then ok = false
            if ok
                all.Push(p)
                if arrOf(p.seasons).Count() = 0 or hasItem(p.seasons, season) then fit.Push(p) ' saved catalogs before 1.10 have no seasons
                if hasItem(p.tags, "night") then night.Push(p)
            end if
        end for
        cands = fit
        if night.Count() > 0 then cands = night
        if cands.Count() = 0 then cands = all
        half = []
        for k = 0 to cands.Count() - 1
            if k mod 2 = n mod 2 or cands.Count() = 1 then half.Push(cands[k])
        end for
        if half.Count() > 0
            start = ((n \ 2) * 7 + si * 5) mod half.Count()
            pick = invalid
            for k = 0 to half.Count() - 1
                c = half[(start + k) mod half.Count()]
                if pick = invalid and not used.DoesExist(c.id) then pick = c
            end for
            if pick = invalid then pick = half[start] ' all taken today: share one rather than repeat yesterday's
            used[pick.id] = true
            picks[sc] = pick
        end if
    end for
    return picks
end function

function seasonOf(month as integer) as string
    if month >= 3 and month <= 5 then return "spring"
    if month >= 6 and month <= 8 then return "summer"
    if month >= 9 and month <= 11 then return "fall"
    return "winter"
end function

function wallpaperPath(id as string) as string
    return "cachefs:/wp-" + id + ".jpg"
end function

function haveWallpaper(id as string) as boolean
    if m.offDevice = true then return m.testWallpapers <> invalid and m.testWallpapers.DoesExist(id)
    return CreateObject("roFileSystem").Exists(wallpaperPath(id))
end function

' Downloads today's and tomorrow's photos, at most 3 per refresh so a slow
' connection never holds up the data, and deletes any other saved photos.
sub syncWallpapers()
    photos = fresh("wallpapers")
    base = currentPlace().wallpapers
    if photos = invalid or base = invalid or m.offDevice = true then return
    today = tDay(tNowWall())
    keep = {}
    for each day in [today, today + 86400]
        picks = wallpaperPicks(photos, day, hiddenPhotos())
        for each sc in picks
            keep[picks[sc].id] = picks[sc]
        end for
    end for
    fs = CreateObject("roFileSystem")
    for each f in fs.GetDirectoryListing("cachefs:/")
        if Left(f, 3) = "wp-" and (Right(f, 4) <> ".jpg" or not keep.DoesExist(Mid(f, 4, Len(f) - 7))) then fs.Delete("cachefs:/" + f)
    end for
    budget = 3
    have = 0
    for each id in keep
        if budget > 0 and not fs.Exists(wallpaperPath(id))
            budget = budget - 1
            err = downloadWallpaper(base + keep[id].file, wallpaperPath(id))
            if err <> "" then m.wallpaperError = err
        end if
        if fs.Exists(wallpaperPath(id)) then have = have + 1
    end for
    m.wallpaperFiles = {have: have, want: keep.Count(), error: m.wallpaperError}
end sub

' Saves under a temporary name and keeps the file only if it arrived whole.
' Returns "" or what went wrong.
function downloadWallpaper(url as string, path as string) as string
    tmp = path + ".part"
    ut = CreateObject("roUrlTransfer")
    ut.SetUrl(url)
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.SetMinimumTransferRate(4096, 20) ' give up on a stalled transfer
    code = ut.GetToFile(tmp)
    fs = CreateObject("roFileSystem")
    st = fs.Stat(tmp)
    if st <> invalid then m.bytesTotal = m.bytesTotal + st.size
    if code = 200 and st <> invalid and st.size > 20000 and fs.Rename(tmp, path) then return ""
    fs.Delete(tmp)
    err = "HTTP " + code.ToStr()
    if code = 200 then err = "incomplete photo"
    print "Daybreak wallpaper download failed: "; err; " "; url
    return err
end function
