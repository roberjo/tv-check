"""Install daybreak/dist/daybreak.zip on the Roku through the dev installer.

Refuses unless nobody is watching: the media player must be idle and the
active app must be the Home screen or the dev app (Daybreak itself). Asks
before installing unless --yes is given. Reads ROKU_IP, ROKU_DEV_USER and
ROKU_DEV_PASS from .env and never prints the password. Appends an entry to
ACTIVITY_LOG.md (local, gitignored) when it installs.

Usage:
  python3 scripts/deploy.py --check        # only run the nobody-watching checks
  python3 scripts/deploy.py [--yes] [--zip path/to/daybreak.zip]
"""
import argparse
import datetime as dt
import hashlib
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
IDLE_STATES = {"close", "stop", "none", "startup"}


def load_env():
    path = ROOT / ".env"
    if not path.exists():
        sys.exit("No .env: copy .env.example and fill in ROKU_IP, ROKU_DEV_USER and ROKU_DEV_PASS.")
    return dict(l.split("=", 1) for l in path.read_text().splitlines() if "=" in l and not l.startswith("#"))


def ecp(ip, path):
    with urllib.request.urlopen(f"http://{ip}:8060{path}", timeout=5) as r:
        return ET.fromstring(r.read())


def watching_check(ip):
    """Returns (ok, summary). Read-only ECP queries."""
    try:
        player = ecp(ip, "/query/media-player")
        app = ecp(ip, "/query/active-app")
    except (OSError, ET.ParseError) as e:
        return False, f"TV at {ip} didn't answer ECP ({e}). If its address changed, run scripts/ssdp_discover.py."
    state = player.get("state", "?")
    a = app.find("app")
    app_id = a.get("id", "home") if a is not None else "home"
    app_name = (a.text or "").strip() if a is not None else "Home"
    # Roku OS 16 reports the Home screen as an app ("Roku Dynamic Menu", type="home")
    is_home = app_id == "home" or app_name == "Roku" or (a is not None and a.get("type") == "home")
    saver = app.find("screensaver")
    summary = f"media-player state={state}, active app={app_name or app_id} ({app_id})"
    if saver is not None:
        summary += f", screensaver={(saver.text or '').strip()}"
    if state not in IDLE_STATES:
        return False, summary + ": something is playing, not installing."
    if not is_home and app_id != "dev":
        return False, summary + ": another app is open, not installing."
    return True, summary


def package_version(zip_path):
    with zipfile.ZipFile(zip_path) as z:
        m = dict(l.split("=", 1) for l in z.read("manifest").decode().splitlines() if "=" in l)
    return f'{m.get("major_version")}.{m.get("minor_version")}.{m.get("build_version")}'


def multipart(fields, file_field, file_path):
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; '
                  f'filename="{file_path.name}"\r\nContent-Type: application/zip\r\n\r\n').encode())
    parts.append(file_path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def digest_header(url, method, user, password):
    """Fetch the digest challenge with a bodiless GET, then answer it. urllib's
    digest handler only answers after a 401, and the dev installer closes the
    connection mid-upload, so the 2 MB POST must carry the answer up front."""
    try:
        urllib.request.urlopen(url, timeout=10).close()
        return None
    except urllib.error.HTTPError as e:
        if e.code != 401:
            raise
        challenge = e.headers.get("WWW-Authenticate", "")
    if not challenge.lower().startswith("digest "):
        sys.exit("The dev installer didn't ask for digest auth; is developer mode on?")
    c = dict(re.findall(r'(\w+)="?([^",]*)"?', challenge[7:]))
    # MD5 is what HTTP Digest (RFC 2617) and the Roku dev installer require; the
    # password is only used in the challenge-response, never stored.
    md5 = lambda t: hashlib.md5(t.encode(), usedforsecurity=False).hexdigest()
    path = urllib.parse.urlsplit(url).path
    ha1, ha2 = md5(f"{user}:{c['realm']}:{password}"), md5(f"{method}:{path}")
    cnonce, nc = uuid.uuid4().hex[:16], "00000001"
    if "auth" in c.get("qop", "").split(","):
        resp = md5(f"{ha1}:{c['nonce']}:{nc}:{cnonce}:auth:{ha2}")
        extra = f', qop=auth, nc={nc}, cnonce="{cnonce}"'
    else:
        resp, extra = md5(f"{ha1}:{c['nonce']}:{ha2}"), ""
    opaque = f', opaque="{c["opaque"]}"' if "opaque" in c else ""
    return (f'Digest username="{user}", realm="{c["realm"]}", nonce="{c["nonce"]}", uri="{path}", '
            f'response="{resp}"{opaque}{extra}')


def install(ip, user, password, zip_path):
    url = f"http://{ip}/plugin_install"
    body, ctype = multipart({"mysubmit": "Install"}, "archive", zip_path)
    headers = {"Content-Type": ctype}
    auth = digest_header(url, "POST", user, password)
    if auth:
        headers["Authorization"] = auth
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=120) as r:
        html = r.read().decode(errors="replace")
    for pattern in (r"Install Success", r"Identical to previous version", r"Application Received"):
        if re.search(pattern, html):
            return True, pattern
    msg = re.findall(r"<font color=\"red\">(.*?)</font>", html, re.S)
    return False, " ".join(m.strip() for m in msg) or "unexpected installer response"


def log_activity(version, summary, result):
    log = ROOT / "ACTIVITY_LOG.md"
    if not log.exists():
        return
    stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    log.open("a").write(
        f"\n### ⚙️ Daybreak {version} installed with scripts/deploy.py ({stamp})\n"
        f"- **What:** sideloaded `daybreak/dist/daybreak.zip` through the dev installer.\n"
        f"- **Checks before installing:** {summary}.\n"
        f"- **Result:** {result}.\n"
        f"- **Impact on the TV:** the dev app slot now holds Daybreak {version}; the screensaver setting is unchanged.\n"
        f"- **Undo:** reinstall the previous build, or delete it at http://<tv>/plugin_install.\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="only run the nobody-watching checks")
    ap.add_argument("--yes", action="store_true", help="don't ask before installing")
    ap.add_argument("--zip", type=pathlib.Path, default=ROOT / "daybreak" / "dist" / "daybreak.zip")
    args = ap.parse_args()
    env = load_env()
    ip = env.get("ROKU_IP", "").strip()
    ok, summary = watching_check(ip)
    print(summary)
    if args.check or not ok:
        sys.exit(0 if ok else 1)
    if not args.zip.exists():
        sys.exit(f"{args.zip} not found: run daybreak/build_channel.py first.")
    version = package_version(args.zip)
    if not args.yes and input(f"Install Daybreak {version} on {ip}? This replaces the dev app. [y/N] ").lower() != "y":
        sys.exit("Not installed.")
    ok, summary = watching_check(ip)  # re-check right before the upload
    if not ok:
        sys.exit(summary)
    try:
        done, result = install(ip, env.get("ROKU_DEV_USER", "rokudev"), env.get("ROKU_DEV_PASS", ""), args.zip)
    except urllib.error.HTTPError as e:
        sys.exit(f"Dev installer returned HTTP {e.code}. Check ROKU_DEV_USER and ROKU_DEV_PASS in .env.")
    print(("Installed: " if done else "Install failed: ") + result)
    if done:
        log_activity(version, summary, result)
    sys.exit(0 if done else 1)


if __name__ == "__main__":
    main()
