' A built screen as plain data, for render.py (shared by preview.brs and wallpapers.brs).
function dumpNode(n as object) as object
    o = {t: n.subtype()}
    tr = n.translation
    if tr <> invalid and tr.Count() = 2
        o.x = tr[0]
        o.y = tr[1]
    end if
    for each f in ["width", "height", "color", "uri", "blendColor", "opacity", "visible", "text", "horizAlign", "wrap", "maxLines", "lineSpacing"]
        v = n[f]
        if f = "text" and v <> invalid then v = v.Replace(Chr(34), "{Q}") ' brs FormatJson doesn't escape quotes
        if v <> invalid then o[f] = v
    end for
    if o.t = "Label" and n.font <> invalid
        o.font = n.font.uri
        o.size = n.font.size
    end if
    kids = []
    for i = 0 to n.getChildCount() - 1
        kids.Push(dumpNode(n.getChild(i)))
    end for
    if kids.Count() > 0 then o.kids = kids
    return o
end function
