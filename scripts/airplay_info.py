"""Fetch and decode the AirPlay receiver /info binary plist."""
import plistlib
import pprint
import sys
import urllib.request

ip = sys.argv[1]
with urllib.request.urlopen(f"http://{ip}:7000/info", timeout=5) as r:
    info = plistlib.loads(r.read())
pprint.pprint(info, width=110, sort_dicts=True)
