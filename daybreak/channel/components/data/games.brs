' Data task: sports schedules, game venues and weather at outdoor games.

' True while a tracked game is in progress (or should have started in the
' last 4 hours and hasn't finished).
function liveGame() as boolean
    all = m.cache.sports
    if all = invalid then return false
    now = tNowWall()
    for each entry in all
        for each ev in entry.events
            if ev.state = "in" then return true
            if ev.state = "pre" and not ev.tbd and ev.start <= now and ev.start >= now - 4 * 3600 then return true
        end for
    end for
    return false
end function

' rivalry: the place's pair of tracked team names ([a, b]); a final between
' them becomes the "house divided" result.
function deriveSports(all as dynamic, now as integer) as object
    out = {games: [], finals: [], rivalry: invalid, records: {}}
    if all = invalid then return out
    pair = currentPlace().rivalry
    rivA = ""
    rivB = ""
    if pair <> invalid and pair.Count() = 2
        rivA = pair[0]
        rivB = pair[1]
    end if
    for each entry in all
        team = entry.team
        w = 0
        l = 0
        for each ev in entry.events
            detail = "at " + ev.opp
            if ev.home then detail = "vs " + ev.opp
            if ev.state = "post"
                if ev.won then w = w + 1 else l = l + 1
                if ev.start >= now - 36 * 3600
                    rivalry = rivA <> "" and (ev.opp = rivA or ev.opp = rivB) and (team.name = rivA or team.name = rivB)
                    out.finals.Push({team: team.name, color: team.color, won: ev.won, score: ev.my + "–" + ev.their, detail: detail,
                                     start: ev.start, pro: true, rivalry: rivalry, logo: strOrEmpty(entry.logo)})
                    if rivalry and team.name = rivB
                        hi = Val(ev.my)
                        lo = Val(ev.their)
                        winner = rivA
                        loser = rivB
                        if ev.won
                            winner = rivB
                            loser = rivA
                        end if
                        if lo > hi
                            t = hi
                            hi = lo
                            lo = t
                        end if
                        host = ev.opp
                        if ev.home then host = rivB
                        out.rivalry = {winner: winner, loser: loser, hi: hi, lo: lo, network: ev.network, host: host}
                    end if
                end if
            else if ev.start >= now - 4 * 3600 and ev.start <= now + 14 * 86400
                out.games.Push({name: team.name, short: team.short, color: team.color, accent: team.accent, logo: strOrEmpty(entry.logo),
                                start: ev.start, state: ev.state, detail: detail, network: ev.network, tbd: ev.tbd,
                                my: ev.my, their: ev.their, status: ev.status, venue: strOrEmpty(ev.venue),
                                zip: strOrEmpty(ev.zip), outdoor: outdoorVenue(team.path, strOrEmpty(ev.venue))})
            end if
        end for
        out.records[team.key] = w.ToStr() + "–" + l.ToStr()
    end for
    return out
end function

function scoreOf(c as object) as string
    s = c.score
    if type(s) = "roAssociativeArray" then s = s.displayValue
    if s = invalid then return "0"
    return s.ToStr()
end function

' --- weather at outdoor games -----------------------------------------------------------
' ESPN schedules give each venue's name and ZIP code but no coordinates and no
' roof. Football, baseball and soccer venues count as outdoors unless the
' stadium has a roof (outdoorVenue). Each new ZIP is geocoded once with
' Open-Meteo (kept for a year), then each venue with a game in the next week
' gets an hourly forecast, read at the kickoff hour.

' ZIP -> {lat, lon} (or {none: true} when the geocoder had no match).
function venueMap() as object
    v = fresh("venues")
    if type(v) <> "roAssociativeArray" then return {}
    return v
end function

' Distinct ZIPs of outdoor games with a set time in the next 7 days (at most 6).
function gameWxZips(all as dynamic, now as integer) as object
    out = []
    seen = {}
    if type(all) <> "roArray" then return out
    for each entry in all
        for each ev in arrOf(aaOf(entry).events)
            zip = strOrEmpty(ev.zip)
            ok = zip <> "" and ev.state = "pre" and not isTrue(ev.tbd) and ev.start >= now and ev.start <= now + 7 * 86400
            if ok and outdoorVenue(strOrEmpty(aaOf(entry.team).path), strOrEmpty(ev.venue)) and not seen.DoesExist(zip) and out.Count() < 6
                seen[zip] = true
                out.Push(zip)
            end if
        end for
    end for
    return out
end function

' Whether a geocoded venue with a game this week has no forecast yet.
function gameWxMissing() as boolean
    wx = fresh("gamewx")
    known = venueMap()
    for each zip in gameWxZips(fresh("sports"), tNowWall())
        v = known[zip]
        if v <> invalid and not isTrue(v.none) and (type(wx) <> "roAssociativeArray" or not wx.DoesExist(zip)) then return true
    end for
    return false
end function

function gameWxUrl(v as object) as string
    u = "https://api.open-meteo.com/v1/forecast?latitude=" + v.lat.ToStr() + "&longitude=" + v.lon.ToStr()
    u = u + "&hourly=temperature_2m,precipitation_probability,weather_code&temperature_unit=fahrenheit"
    return u + "&timezone=" + currentPlace().timezone.Replace("/", "%2F") + "&forecast_days=8"
end function

' Geocoder answers (one per ZIP in urls) merged into the saved venues.
function normVenues(bodies as object, urls as object) as dynamic
    out = {}
    old = venueMap()
    if old.Count() < 80 then out.Append(old) ' a long-running TV starts over now and then
    zipRe = CreateObject("roRegex", "name=(\d{5})&", "")
    for i = 0 to bodies.Count() - 1
        mt = zipRe.Match(strOrEmpty(arrAt(urls, i)))
        if mt.Count() > 1 and bodies[i] <> ""
            r = aaOf(arrAt(aaOf(parseJsonSafe(bodies[i])).results, 0))
            lat = numOf(r.latitude, invalid)
            lon = numOf(r.longitude, invalid)
            if lat <> invalid and lon <> invalid and r.country_code = "US" and Abs(lat) <= 90 and Abs(lon) <= 180
                out[mt[1]] = {lat: lat, lon: lon}
            else if parseJsonSafe(bodies[i]) <> invalid
                out[mt[1]] = {none: true} ' a real answer with no match: don't ask again
            end if
        end if
    end for
    if out.Count() = 0 then return invalid
    return out
end function

' Forecasts (one per venue URL) -> ZIP -> {start (wall time of the first
' hour), temp[], rain[], code[]}; missing hours are -999.
function normGameWx(bodies as object, urls as object) as dynamic
    byUrl = {}
    known = venueMap()
    for each zip in known
        if not isTrue(known[zip].none) then byUrl[gameWxUrl(known[zip])] = zip
    end for
    out = {}
    for i = 0 to bodies.Count() - 1
        zip = byUrl[strOrEmpty(arrAt(urls, i))]
        h = aaOf(aaOf(parseJsonSafe(bodies[i])).hourly)
        times = arrOf(h.time)
        if zip <> invalid and times.Count() > 0 and isText(times[0])
            f = {start: tLocalIsoToWall(times[0]), temp: [], rain: [], code: []}
            for k = 0 to times.Count() - 1
                t = numAt(h.temperature_2m, k, invalid)
                if t = invalid then f.temp.Push(-999) else f.temp.Push(Int(t + 0.5))
                f.rain.Push(Int(numAt(h.precipitation_probability, k, 0)))
                f.code.Push(Int(numAt(h.weather_code, k, 0)))
            end for
            out[zip] = f
        end if
    end for
    if out.Count() = 0 then return invalid
    return out
end function

' {temp, rain, code} at kickoff for an outdoor game with a set time, or invalid.
function kickoffWeather(gm as object, wx as dynamic) as dynamic
    if type(wx) <> "roAssociativeArray" or not isTrue(gm.outdoor) or isTrue(gm.tbd) or gm.state <> "pre" then return invalid
    f = wx[strOrEmpty(gm.zip)]
    if f = invalid then return invalid
    k = (gm.start - f.start + 1800) \ 3600
    if k < 0 or k >= f.temp.Count() then return invalid
    if f.temp[k] = -999 then return invalid
    return {temp: f.temp[k], rain: f.rain[k], code: f.code[k]}
end function
