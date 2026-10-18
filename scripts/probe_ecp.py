"""Probe read-only Roku ECP endpoints and report status + size of each response.

Usage: python3 scripts/probe_ecp.py <tv-ip> [outdir]
Saves each successful response to outdir (default: captures/<ip>/).
"""
import os
import sys
import urllib.error
import urllib.request

# Read-only GET endpoints only; nothing here changes TV state.
ENDPOINTS = [
    "/",
    "/query/device-info",
    "/query/apps",
    "/query/active-app",
    "/query/media-player",
    "/query/tv-channels",
    "/query/tv-active-channel",
    "/query/icon/tvinput.dtv",
    "/query/chanperf",
    "/query/sgnodes/all",
    "/query/sgnodes/roots",
    "/query/r2d2-bitmaps",
    "/query/graphics-frame-rate",
    "/query/registry/dev",
    "/query/app-ui",
    "/query/audio-device",
    "/dial/dd.xml",
]


def probe(ip, outdir):
    os.makedirs(outdir, exist_ok=True)
    for path in ENDPOINTS:
        url = f"http://{ip}:8060{path}"
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                body = r.read()
                status = r.status
        except urllib.error.HTTPError as e:
            body, status = e.read(), e.code
        except Exception as e:  # timeouts, resets
            print(f"ERR  {path:32} {e}")
            continue
        print(f"{status}  {path:32} {len(body):>7} bytes")
        if status == 200:
            name = path.strip("/").replace("/", "_") or "root"
            with open(os.path.join(outdir, name if name.endswith(".xml") else name + (".png" if "icon" in path else ".xml")), "wb") as f:
                f.write(body)


if __name__ == "__main__":
    ip = sys.argv[1]
    probe(ip, sys.argv[2] if len(sys.argv) > 2 else os.path.join("captures", ip))
