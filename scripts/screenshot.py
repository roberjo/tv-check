"""Save a screenshot of the dev app (Daybreak) through the dev installer.

Read-only for the TV: the installer copies the current frame and nothing on
screen changes. Only works while the dev app is in front. Screens show family
details, so images go to captures/ (gitignored) by default.

Usage: python3 scripts/screenshot.py [name]   # -> captures/screens/<name or time>.jpg
"""
import datetime as dt
import sys
import urllib.request

from deploy import ROOT, digest_header, load_env, multipart


def screenshot(ip, user, password):
    url = f"http://{ip}/plugin_inspect"
    blank = ROOT / "captures" / ".empty"
    blank.parent.mkdir(exist_ok=True)
    blank.write_bytes(b"")
    body, ctype = multipart({"mysubmit": "Screenshot", "passwd": ""}, "archive", blank)
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": ctype, "Authorization": digest_header(url, "POST", user, password)})
    html = urllib.request.urlopen(req, timeout=30).read().decode(errors="replace")
    if "dev.jpg" not in html and "dev.png" not in html:
        sys.exit("No screenshot: is Daybreak (the dev app) in front?")
    ext = "png" if "dev.png" in html else "jpg"
    img = f"http://{ip}/pkgs/dev.{ext}"
    req = urllib.request.Request(img, headers={"Authorization": digest_header(img, "GET", user, password)})
    return urllib.request.urlopen(req, timeout=30).read(), ext


if __name__ == "__main__":
    env = load_env()
    data, ext = screenshot(env["ROKU_IP"], env.get("ROKU_DEV_USER", "rokudev"), env.get("ROKU_DEV_PASS", ""))
    name = sys.argv[1] if len(sys.argv) > 1 else dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = ROOT / "captures" / "screens" / f"{name}.{ext}"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"saved {out.relative_to(ROOT)} ({len(data) // 1024} KB)")
