' SceneGraph drawing helpers mirroring daybreak/service/draw.py: tinted
' 9-patch cards, labels in the bundled Outfit/Manrope weights, dots, images.

function hexc(h as string, alpha = "FF" as string) as string
    return "0x" + Mid(h, 2) + alpha
end function

function uiFont(fam as string, weight as integer, size as integer) as object
    if m.fontCache = invalid then m.fontCache = {}
    weights = [400, 500, 600, 700, 800]
    if fam = "Outfit" then weights = [200, 300, 400, 500, 600]
    best = weights[0]
    for each w in weights
        if Abs(w - weight) < Abs(best - weight) then best = w
    end for
    key = fam + best.ToStr() + "_" + size.ToStr()
    if not m.fontCache.DoesExist(key)
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/" + fam + "-" + best.ToStr() + ".ttf"
        f.size = size
        m.fontCache[key] = f
    end if
    return m.fontCache[key]
end function

' Text at (x, y) = top-left. align "left" | "right" | "center": for right and
' center, x is the right edge / center and width is required.
function uiText(p as object, x as float, y as float, text as dynamic, size as integer, weight = 400 as integer, fam = "Manrope" as string, color = "#F4F1EA" as string, width = 0 as integer, align = "left" as string, lines = 1 as integer) as object
    l = p.createChild("Label")
    l.font = uiFont(fam, weight, size)
    l.color = hexc(color)
    if text = invalid then text = ""
    l.text = text.ToStr()
    if width > 0 then l.width = width
    l.horizAlign = align
    if lines > 1
        l.wrap = true
        l.maxLines = lines
        l.lineSpacing = Int(size * 0.18)
    end if
    tx = x
    if align = "right" then tx = x - width
    if align = "center" then tx = x - width / 2
    l.translation = [tx, y]
    return l
end function

function uiLabel(p as object, x as float, y as float, text as string, size = 22 as integer, color = "#A9B1C4" as string) as object
    return uiText(p, x, y, UCase(text), size, 700, "Manrope", color)
end function

function uiTextWidth(p as object, text as string, size as integer, weight = 400 as integer, fam = "Manrope" as string) as float
    l = uiText(p, -4000, -4000, text, size, weight, fam)
    w = uiWidth(l, size)
    p.removeChild(l)
    return w
end function

' Rendered size of a label. Off-device runners report 0, so fall back to an
' estimate there (0.56 em per character, wrapped to the label width).
function uiWidth(l as object, size as integer) as float
    w = l.boundingRect().width
    if w = 0 and l.text <> "" then w = Len(l.text) * size * 0.56
    return w
end function

function uiHeight(l as object, size as integer) as float
    h = l.boundingRect().height
    if h = 0 and l.text <> ""
        lines = 1
        if l.wrap and l.width > 0 then lines = Int(Len(l.text) * size * 0.56 / l.width) + 1
        if l.maxLines > 0 and lines > l.maxLines then lines = l.maxLines
        h = lines * size * 1.3
    end if
    return h
end function

function uiCard(p as object, x as float, y as float, w as float, h as float, fill = "#131B2E" as string, border = "#1F2A44" as string, r = 28 as integer, opacity = 1.0 as float) as object
    radii = [10, 14, 18, 22, 28, 32]
    rr = radii[0]
    for each v in radii
        if Abs(v - r) < Abs(rr - r) then rr = v
    end for
    c = p.createChild("Poster")
    c.uri = "pkg:/images/card" + rr.ToStr() + ".9.png"
    c.translation = [x, y]
    c.width = w
    c.height = h
    c.blendColor = hexc(fill)
    c.opacity = opacity
    if border <> ""
        b = p.createChild("Poster")
        b.uri = "pkg:/images/ring" + rr.ToStr() + ".9.png"
        b.translation = [x, y]
        b.width = w
        b.height = h
        b.blendColor = hexc(border)
    end if
    return c
end function

function uiRect(p as object, x as float, y as float, w as float, h as float, color as string, opacity = 1.0 as float) as object
    r = p.createChild("Rectangle")
    r.translation = [x, y]
    r.width = w
    r.height = h
    r.color = hexc(color)
    r.opacity = opacity
    return r
end function

function uiDot(p as object, cx as float, cy as float, radius as float, color as string, opacity = 1.0 as float) as object
    return uiImage(p, "pkg:/images/dot.png", cx - radius, cy - radius, radius * 2, radius * 2, color, opacity)
end function

function uiImage(p as object, uri as string, x as float, y as float, w as float, h as float, blend = "" as string, opacity = 1.0 as float) as object
    i = p.createChild("Poster")
    i.uri = uri
    i.translation = [x, y]
    i.width = w
    i.height = h
    if blend <> "" then i.blendColor = hexc(blend)
    i.opacity = opacity
    return i
end function

function wxKind(code as integer) as string
    if code <= 1 then return "sun"
    if code = 2 then return "partly"
    if code = 3 or code = 45 or code = 48 then return "cloud"
    if code >= 95 then return "storm"
    if (code >= 71 and code <= 77) or code = 85 or code = 86 then return "snow"
    return "rain"
end function

function wxLabel(code as integer) as string
    names = {"0": "Clear", "1": "Mostly clear", "2": "Partly cloudy", "3": "Cloudy", "45": "Fog", "48": "Fog",
             "51": "Drizzle", "53": "Drizzle", "55": "Drizzle", "56": "Freezing drizzle", "57": "Freezing drizzle",
             "61": "Light rain", "63": "Rain", "65": "Heavy rain", "66": "Freezing rain", "67": "Freezing rain",
             "71": "Light snow", "73": "Snow", "75": "Heavy snow", "77": "Snow", "80": "Showers", "81": "Showers",
             "82": "Heavy showers", "85": "Snow showers", "86": "Snow showers", "95": "Thunderstorms",
             "96": "Thunderstorms", "99": "Thunderstorms"}
    k = code.ToStr()
    if names.DoesExist(k) then return names[k]
    return "—"
end function

function teamChip(p as object, x as float, y as float, size as float, short as string, color as string, accent as dynamic) as object
    border = ""
    if accent <> invalid then border = accent
    uiCard(p, x, y, size, size, color, border, 14)
    fs = Int(size * 0.34)
    if Len(short) >= 3 then fs = Int(size * 0.3)
    return uiText(p, x + size / 2, y + size / 2 - fs * 0.62, short, fs, 600, "Outfit", "#F4F1EA", Int(size), "center")
end function
