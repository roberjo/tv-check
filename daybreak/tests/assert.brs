' Shared test helpers. Every test file ends with testSummary(); the runner
' scripts fail when any line starts with "  FAIL" or the summary is missing.

sub check(name as string, got as dynamic, want as dynamic)
    if m.fails = invalid then m.fails = 0
    g = asText(got)
    w = asText(want)
    if g = w
        print "  ok   "; name
    else
        print "  FAIL "; name; ": got '"; g; "' want '"; w; "'"
        m.fails = m.fails + 1
    end if
end sub

function asText(v as dynamic) as string
    if v = invalid then return "invalid"
    t = type(v)
    if t = "roArray" or t = "roAssociativeArray" then return FormatJson(v)
    if t = "roString" or t = "String" then return v
    return v.ToStr()
end function

sub testSummary(suite as string)
    if m.fails = invalid then m.fails = 0
    print ""
    if m.fails = 0 then print "ALL TESTS PASSED ("; suite; ")" else print m.fails; " FAILED ("; suite; ")"
end sub
