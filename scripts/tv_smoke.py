"""Scripted on-TV check of every Daybreak screen.

1. Refuses unless nobody is watching (media player idle; Home or Daybreak in front).
2. Installs daybreak/dist/daybreak.zip with deploy.py (asks first unless --yes),
   or with --no-install launches the installed dev app.
3. Follows the dev console (port 8085) from the install on: waits for the first
   screen, reads the playlist that DaybreakScene logs.
4. Pauses the rotation, goes to the first screen through OK > Go to screen, then
   steps with Right, taking a screenshot of each into captures/screens/smoke-<time>/.
5. Opens diagnostics (*), screenshots the status and live-graph pages, closes it.
6. Presses Home, checks the console log for BrightScript errors, crashes and
   failed screens, writes summary.md next to the screenshots, and appends an
   ACTIVITY_LOG.md entry.

Keys sent (ECP keypress only): Select, Down, Play, Right, Info, Back, Home. No
settings are changed. Before every key it re-checks that Daybreak is still in
front, and stops if someone switched apps. Stdlib only.

Usage:
  python3 scripts/tv_smoke.py [--yes] [--no-install] [--zip path]
"""
import argparse
import datetime as dt
import pathlib
import re
import socket
import sys
import threading
import time
import urllib.request

from deploy import ROOT, ecp, install, load_env, package_version, watching_check
from screenshot import screenshot

ERROR_PATTERNS = [
    (re.compile(r"BRIGHTSCRIPT: ERROR"), "BrightScript runtime error"),
    (re.compile(r"Brightscript Debugger|STOP \(runtime error"), "stopped in the debugger (crash)"),
    (re.compile(r"Daybreak: screen '[^']+' failed"), "a screen failed to build"),
    (re.compile(r"Daybreak [\w-]+ error"), "data task error"),
    (re.compile(r"Daybreak: low memory mode true"), "low memory mode"),
]


class ConsoleLog:
    """Reads the dev console (8085) in the background. It replays its recent
    log on connect, so only lines after mark() count."""

    def __init__(self, ip):
        self.lines = []
        self.start = None
        self.sock = socket.create_connection((ip, 8085), timeout=5)
        self.sock.settimeout(1)
        self.stop = False
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        buf = b""
        while not self.stop:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            *done, buf = buf.split(b"\n")
            for raw in done:
                self.lines.append((time.time(), raw.decode(errors="replace").rstrip("\r")))

    def mark(self):
        self.start = time.time()

    def since(self):
        return [l for t, l in self.lines if self.start is not None and t >= self.start]

    def wait_for(self, pattern, timeout):
        rx = re.compile(pattern)
        end = time.time() + timeout
        while time.time() < end:
            for line in self.since():
                if rx.search(line):
                    return line
            time.sleep(0.5)
        return None

    def last(self, pattern):
        rx = re.compile(pattern)
        hits = [l for l in self.since() if rx.search(l)]
        return hits[-1] if hits else None

    def close(self):
        self.stop = True
        self.sock.close()


class Remote:
    def __init__(self, ip):
        self.ip = ip
        self.sent = []

    def still_ours(self):
        a = ecp(self.ip, "/query/active-app").find("app")
        return a is not None and a.get("id") == "dev"

    def press(self, key, pause=1.2):
        if key != "Home" and not self.still_ours():
            raise SystemExit(f"Daybreak is no longer in front (someone switched apps?); stopped before '{key}'.")
        req = urllib.request.Request(f"http://{self.ip}:8060/keypress/{key}", data=b"", method="POST")
        urllib.request.urlopen(req, timeout=5).close()
        self.sent.append(key)
        time.sleep(pause)

    def launch_dev(self):
        req = urllib.request.Request(f"http://{self.ip}:8060/launch/dev", data=b"", method="POST")
        urllib.request.urlopen(req, timeout=10).close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--yes", action="store_true", help="don't ask before installing")
    ap.add_argument("--no-install", action="store_true", help="test the installed dev app instead")
    ap.add_argument("--zip", type=pathlib.Path, default=ROOT / "daybreak" / "dist" / "daybreak.zip")
    ap.add_argument("--settle", type=float, default=4.0, help="seconds to let each screen load before its screenshot")
    args = ap.parse_args()
    env = load_env()
    ip = env.get("ROKU_IP", "").strip()
    user, password = env.get("ROKU_DEV_USER", "rokudev"), env.get("ROKU_DEV_PASS", "")

    ok, check = watching_check(ip)
    print(check)
    if not ok:
        sys.exit(1)
    version = "installed build"
    if not args.no_install:
        if not args.zip.exists():
            sys.exit(f"{args.zip} not found: run daybreak/build_channel.py first.")
        version = package_version(args.zip)
        if not args.yes and input(f"Install Daybreak {version} on {ip} and step through every screen? [y/N] ").lower() != "y":
            sys.exit("Not run.")

    started = dt.datetime.now()
    out = ROOT / "captures" / "screens" / f"smoke-{started:%Y%m%d-%H%M}"
    out.mkdir(parents=True, exist_ok=True)
    log = ConsoleLog(ip)
    time.sleep(2)  # let the replayed history arrive before the mark
    ok, check = watching_check(ip)  # re-check right before changing anything
    if not ok:
        sys.exit(check)
    log.mark()
    remote = Remote(ip)
    if args.no_install:
        remote.launch_dev()
        result = "launched the installed dev app"
    else:
        done, result = install(ip, user, password, args.zip)
        print(("Installed: " if done else "Install failed: ") + result)
        if not done:
            sys.exit(1)

    shots, problems, playlist = [], [], []
    try:
        first = log.wait_for(r"Daybreak: first screen after", 120)
        if not first:
            problems.append("no first screen within 2 minutes")
            raise SystemExit("Daybreak didn't show a screen within 2 minutes; see the console log.")
        print(first.strip())
        time.sleep(3)
        playlist_line = log.last(r"Daybreak: playlist ")
        playlist = playlist_line.split("playlist ", 1)[1].strip().split(",") if playlist_line else []
        print("playlist:", ", ".join(playlist) or "(not logged)")
        # pause (OK > Pause rotation), then OK > Go to screen > first entry
        remote.press("Select")
        remote.press("Select")
        remote.press("Select")
        remote.press("Down")
        remote.press("Select")
        remote.press("Select", pause=args.settle)
        for i in range(max(len(playlist), 1)):
            if i > 0:
                remote.press("Right", pause=args.settle)
            cur = log.last(r"Daybreak: screen \w+ \(")
            sid = re.search(r"screen (\w+) \(", cur).group(1) if cur else f"screen{i + 1}"
            data, ext = screenshot(ip, user, password)
            path = out / f"{i + 1:02d}-{sid}.{ext}"
            path.write_bytes(data)
            shots.append(path)
            print(f"  {path.relative_to(ROOT)}")
        remote.press("Info", pause=3)
        for page in ("diagnostics", "diagnostics-live"):
            data, ext = screenshot(ip, user, password)
            path = out / f"{page}.{ext}"
            path.write_bytes(data)
            shots.append(path)
            print(f"  {path.relative_to(ROOT)}")
            if page == "diagnostics":
                remote.press("Right", pause=3)
        remote.press("Back")
    finally:
        try:
            remote.press("Home")
        except OSError as e:
            problems.append(f"Home keypress failed: {e}")
        time.sleep(2)
        lines = log.since()
        log.close()
        for line in lines:
            for rx, what in ERROR_PATTERNS:
                if rx.search(line):
                    problems.append(f"{what}: {line.strip()[:160]}")
        (out / "console.log").write_text("\n".join(lines) + "\n")
        ended = dt.datetime.now()
        summary = [f"# Daybreak smoke test {started:%Y-%m-%d %H:%M}", "",
                   f"- Build: {version} ({result})", f"- Checks before: {check}",
                   f"- Screens: {len([s for s in shots if not s.name.startswith('diagnostics')])}"
                   f" of {len(playlist)} in the playlist",
                   f"- Keys: {' '.join(remote.sent)}", f"- Console lines after the install: {len(lines)}",
                   f"- Problems: {len(problems)}"] + [f"  - {p}" for p in problems]
        (out / "summary.md").write_text("\n".join(summary) + "\n")
        print("\n".join(summary))
        log_activity(started, ended, version, check, result, shots, problems, remote.sent, out)
    sys.exit(1 if problems else 0)


def log_activity(started, ended, version, check, result, shots, problems, keys, out):
    path = ROOT / "ACTIVITY_LOG.md"
    if not path.exists():
        return
    screens = [s.stem for s in shots]
    path.open("a").write(
        f"\n### ⚙️ Smoke test with scripts/tv_smoke.py ({started:%Y-%m-%d %H:%M}–{ended:%H:%M})\n"
        f"- **What:** {result} ({version}); stepped through every screen and diagnostics with screenshots.\n"
        f"- **Checks before:** {check}.\n"
        f"- **Result:** {len(shots)} screenshots ({', '.join(screens)}) in `{out.relative_to(ROOT)}/`; "
        f"{len(problems)} problem(s) in the console log" + ("." if not problems else ": " + "; ".join(problems[:5]) + ".") + "\n"
        f"- **Keypresses:** {' '.join(keys)}.\n"
        f"- **Impact on the TV:** the dev slot holds the tested build; the TV was left on Home; no settings changed.\n"
        f"- **Undo:** reinstall an earlier build, or delete the dev app at http://<tv>/plugin_install.\n")


if __name__ == "__main__":
    main()
