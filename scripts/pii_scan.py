"""Privacy scan: block household details from reaching the public repo.

The private values come only from gitignored files, so none of them is ever
written into the repo:
  config/family.json   household name, member names, birthdays, schools, calendar id
  .env                 dev password, tokens, the family calendar's iCal URL and id
  captures/*/query_device-info.xml   TV serial, device id, MACs, Wi-Fi network name
Public patterns (a private Google Calendar iCal URL, a real calendar id, a
labeled Roku serial, a MAC address) are checked everywhere, including CI where
the private files don't exist.

A finding prints the file, line and kind ("member name 2"), never the value,
so the scan's own output can't leak what it protects.

Usage:
  python3 scripts/pii_scan.py              # staged changes (the pre-commit hook)
  python3 scripts/pii_scan.py --all        # every tracked file
  python3 scripts/pii_scan.py --self-test  # proves the rules fire (CI)
Exits 1 on a finding. Install the hook with scripts/install_hooks.sh.
Stdlib only.
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".ttf", ".otf", ".woff", ".woff2", ".zip", ".pdf"}
SKIP_FILES = {"package-lock.json"}
# .env keys whose values are secret or household-specific (ROKU_IP and the user name are not)
ENV_KEYS = ["ROKU_DEV_PASS", "CONCIERGE_TOKEN", "DAYBREAK_TOKEN", "FAMILY_CALENDAR_ICS", "FAMILY_CALENDAR_ID"]
ALLOW = ROOT / ".pii-allow"  # tracked: "<path glob> <kind>", for known public coincidences
DEVICE_TAGS = ["serial-number", "device-id", "wifi-mac", "ethernet-mac", "network-name"]

PUBLIC = [
    ("private calendar URL", re.compile(r"calendar\.google\.com/calendar/ical/[^/\s]+/private-[0-9a-f]{8,}", re.I)),
    ("calendar id", re.compile(r"\b[0-9a-z]{20,}@group\.calendar\.google\.com", re.I)),
    ("TV serial", re.compile(r"serial[-_ ]?(?:number)?\W{1,4}[A-Z0-9]{12}\b", re.I)),
    ("MAC address", re.compile(r"\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b", re.I)),
]


def private_values(family_path=ROOT / "config" / "family.json", env_path=ROOT / ".env", captures=ROOT / "captures"):
    """[(kind, value, needs)] where needs is a word that must share the line (or None)."""
    vals = []
    if family_path.exists():
        fam = json.loads(family_path.read_text())
        hh = str(fam.get("household", ""))
        surname = hh.replace(" family", "").replace(" Family", "").strip()
        if len(surname) >= 3:
            vals.append(("household name", surname, None))
        for i, mem in enumerate(fam.get("members", []), 1):
            if len(str(mem.get("name", ""))) >= 3:
                vals.append((f"member name {i}", mem["name"], None))
            if mem.get("birthday"):
                vals.append((f"birthday {i}", mem["birthday"], "birth"))  # MM-DD alone is any date
            if mem.get("school"):
                vals.append((f"school {i}", mem["school"], None))
        for name, cal in (fam.get("calendars") or {}).items():
            cid = str(cal.get("id", ""))
            if cid and not cid.startswith("<"):
                vals.append((f"calendar id ({name})", cid, None))
    if env_path.exists():
        env = dict(l.split("=", 1) for l in env_path.read_text().splitlines() if "=" in l and not l.startswith("#"))
        for k in ENV_KEYS:
            v = env.get(k, "").strip().strip('"')
            if len(v) >= 6:
                vals.append((f".env {k}", v, None))
    if captures.exists():
        for f in captures.glob("*/query_device-info.xml"):
            text = f.read_text(errors="replace")
            for tag in DEVICE_TAGS:
                m = re.search(rf"<{tag}>([^<]+)</{tag}>", text)
                if m and len(m.group(1).strip()) >= 4:
                    vals.append((f"TV {tag}", m.group(1).strip(), None))
    seen, out = set(), []
    for kind, v, needs in vals:
        if (v, needs) not in seen:
            seen.add((v, needs))
            out.append((kind, v, needs))
    return out


def compile_private(vals):
    rules = []
    for kind, v, needs in vals:
        # whole words, case-sensitive for names (so "Will" doesn't match "will")
        rules.append((kind, re.compile(r"(?<![\w])" + re.escape(v) + r"(?![\w])"), needs))
    return rules


def scan_lines(lines, private_rules):
    """lines: [(file, lineno, text)] -> [(file, lineno, kind)]"""
    hits = []
    for f, n, text in lines:
        for kind, rx, needs in private_rules:
            if rx.search(text) and (needs is None or needs in text.lower()):
                hits.append((f, n, kind))
        for kind, rx in PUBLIC:
            if rx.search(text) and "<your" not in text and "XXXX" not in text.upper():
                hits.append((f, n, kind))
    return hits


def allowed():
    rules = []
    if ALLOW.exists():
        for line in ALLOW.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                glob, kind = line.split(None, 1)
                rules.append((glob, kind.strip()))
    return rules


def drop_allowed(hits, rules):
    return [h for h in hits if not any(pathlib.PurePosixPath(h[0]).match(g) and h[2] == k for g, k in rules)]


def scannable(path):
    p = pathlib.PurePosixPath(path)
    return p.suffix.lower() not in SKIP_SUFFIXES and p.name not in SKIP_FILES


def staged_lines():
    diff = subprocess.run(["git", "diff", "--cached", "-U0", "--no-color", "--diff-filter=ACMR"],
                          cwd=ROOT, capture_output=True, text=True, check=True).stdout
    out, f, n = [], None, 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            f = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@"):
            n = int(re.search(r"\+(\d+)", line).group(1))
        elif line.startswith("+") and f and scannable(f):
            out.append((f, n, line[1:]))
            n += 1
    return out


def tracked_lines():
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
    out = []
    for f in filter(None, files):
        p = ROOT / f
        if not scannable(f) or not p.is_file():
            continue
        try:
            text = p.read_text()
        except UnicodeDecodeError:
            continue
        out.extend((f, i, line) for i, line in enumerate(text.splitlines(), 1))
    return out


def self_test():
    """The rules must fire on the fictional family and the public patterns."""
    example = ROOT / "config" / "family.example.json"
    fam = json.loads(example.read_text())
    m1 = fam["members"][0]
    rules = compile_private(private_values(example, pathlib.Path("/nonexistent"), pathlib.Path("/nonexistent")))
    cases = {
        "member name 1": f"Dinner at Grandma's with {m1['name']}.",
        "birthday 1": f'  "birthday": "{m1["birthday"]}",',
        "private calendar URL": "https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/private-0123456789abcdef/basic.ics",
        "TV serial": "<serial-number>X000000ABCDE</serial-number>",
        "MAC address": "ethernet 0a:1b:2c:3d:4e:5f",
    }
    failed = []
    for kind, text in cases.items():
        kinds = {k for _, _, k in scan_lines([("case", 1, text)], rules)}
        if kind not in kinds:
            failed.append(kind)
    clean = scan_lines([("case", 1, "Pickup moves to 03-14 this week; Alexander St. is closed.")], rules)
    if clean:
        failed.append("false positive: " + ", ".join(k for _, _, k in clean))
    for f in failed:
        print("self-test FAILED:", f)
    print(f"pii self-test: {len(cases) - len(failed)}/{len(cases)} rules fire")
    return 1 if failed else 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    vals = private_values()
    rules = compile_private(vals)
    lines = tracked_lines() if "--all" in argv else staged_lines()
    hits = drop_allowed(scan_lines(lines, rules), allowed())
    for f, n, kind in hits:
        print(f"{f}:{n}: {kind}")
    where = "tracked files" if "--all" in argv else "staged changes"
    print(f"pii scan ({where}, {len(vals)} private values + {len(PUBLIC)} public patterns): {len(hits)} finding(s)")
    if hits and "--all" not in argv:
        print("Commit blocked. Move the value to a gitignored file, or use the fictional family.")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
