"""Package + sideload diag-channel/, launch it, collect its DIAG output from the
dev console (8085) and chanperf samples from the debug console (8080), then
press Home to return the TV to the home screen.

Reads ROKU_IP / ROKU_DEV_USER / ROKU_DEV_PASS from .env.
Usage: python3 -u scripts/run_diag.py [outdir]
"""
import json
import pathlib
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
env = dict(l.split("=", 1) for l in (ROOT / ".env").read_text().split() if "=" in l)
ip, user, pw = env["ROKU_IP"], env["ROKU_DEV_USER"], env["ROKU_DEV_PASS"]
outdir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "captures" / ip / "diag").resolve()
outdir.mkdir(parents=True, exist_ok=True)
TIMEOUT = 180


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


def ecp_post(path):
    urllib.request.urlopen(urllib.request.Request(f"http://{ip}:8060/{path}", method="POST"), timeout=5)


def package():
    zpath = outdir / "diag-channel.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in (ROOT / "diag-channel").rglob("*"):
            if p.is_file():
                z.write(p, p.relative_to(ROOT / "diag-channel"))
    return zpath


def read_console(sink, stop):
    # 8085 drops the connection when the dev channel is replaced; reconnect until stopped.
    while not stop.is_set():
        try:
            s = socket.create_connection((ip, 8085), timeout=3)
        except OSError:
            time.sleep(1)
            continue
        s.settimeout(1)
        with s:
            while not stop.is_set():
                try:
                    c = s.recv(65536)
                except socket.timeout:
                    continue
                except OSError:
                    break
                if not c:
                    break
                sink.append(c.decode(errors="replace"))


def chanperf_sampler(samples, stop):
    with socket.create_connection((ip, 8080), timeout=3) as s:
        s.settimeout(2)
        while not stop.is_set():
            s.sendall(b"chanperf\r\n")
            try:
                out = s.recv(65536).decode(errors="replace")
            except socket.timeout:
                out = ""
            for line in out.splitlines():
                if "cpu=" in line:
                    samples.append(f"{time.strftime('%H:%M:%S')} {line.strip(' >')}")
            stop.wait(2)


console, perf, stop = [], [], threading.Event()
threads = [threading.Thread(target=read_console, args=(console, stop), daemon=True),
           threading.Thread(target=chanperf_sampler, args=(perf, stop), daemon=True)]
for t in threads:
    t.start()

# 8085 replays its recent log on connect; only parse what arrives after this point.
time.sleep(3)
mark = len("".join(console))

r = subprocess.run(["curl", "-s", "-m", "60", "--digest", "-u", f"{user}:{pw}",
                    "-F", "mysubmit=Install", "-F", f"archive=@{package()}",
                    f"http://{ip}/plugin_install"], capture_output=True, text=True)
msgs = re.findall(r'"text":"([^"]*)"', r.stdout)
log(f"install: {msgs or ('curl exit ' + str(r.returncode))}")
if not any("Received" in m or "Identical" in m for m in msgs):
    sys.exit("install failed")
# An identical package is accepted without relaunching, so always launch explicitly.
ecp_post("launch/dev")
log("launched dev channel; waiting for results")

deadline = time.time() + TIMEOUT
while time.time() < deadline and "DIAG|done|" not in "".join(console)[mark:]:
    time.sleep(2)
stop.set()
for t in threads:
    t.join(timeout=5)

raw = "".join(console)[mark:]
(outdir / "dev_console.txt").write_text(raw)
(outdir / "chanperf.txt").write_text("\n".join(perf))
results = {}
for sec, js in re.findall(r"DIAG\|(\w+)\|(.*)", raw):
    try:
        data = json.loads(js.strip())
    except json.JSONDecodeError:
        continue
    if sec in results:
        results[sec] = results[sec] if isinstance(results[sec], list) else [results[sec]]
        results[sec].append(data)
    else:
        results[sec] = data
(outdir / "diag.json").write_text(json.dumps(results, indent=2))
log(f"sections collected: {list(results)}" + ("" if "done" in results else "  (TIMED OUT)"))
log(f"chanperf samples: {len(perf)}")

ecp_post("keypress/Home")
log("returned TV to Home")
