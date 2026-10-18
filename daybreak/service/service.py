"""Daybreak service: renders screens on the Mac and serves them to the TV app.

Every minute it gathers data (cached per source), decides which screens matter
right now, renders them to daybreak/out/, and writes a manifest the TV polls.
Radar frames refresh every 10 minutes in a background thread.

Endpoints (all need ?token=DAYBREAK_TOKEN except /health):
  GET  /manifest.json          playlist for the TV
  GET  /img/<name>.jpg         rendered screens and radar frames
  GET  /action?id=<screen>     run that screen's OK-button action (only actions the service defined)
  GET  /board                  phone-friendly family board (notes + grocery list)
  POST /board                  add/toggle/clear board items
  GET  /health

Usage: .venv/bin/python daybreak/service/service.py
"""
import datetime as dt
import html
import json
import pathlib
import secrets
import sys
import threading
import time
import traceback
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "scripts"))
import screens  # noqa: E402
import sources as S  # noqa: E402

ENV_PATH = ROOT / ".env"
ENV = dict(l.split("=", 1) for l in ENV_PATH.read_text().splitlines() if "=" in l and not l.startswith("#"))
if "DAYBREAK_TOKEN" not in ENV:
    ENV["DAYBREAK_TOKEN"] = secrets.token_urlsafe(18)
    with ENV_PATH.open("a") as f:
        f.write(f"DAYBREAK_TOKEN={ENV['DAYBREAK_TOKEN']}\n")
TOKEN = ENV["DAYBREAK_TOKEN"]
PORT = int(ENV.get("DAYBREAK_PORT", "8770"))
ROKU = ENV["ROKU_IP"]
OUT = ROOT / "daybreak" / "out"
OUT.mkdir(parents=True, exist_ok=True)
(ROOT / "daybreak" / "data").mkdir(parents=True, exist_ok=True)
LOG = ROOT / "daybreak" / "logs" / "service.log"
LOG.parent.mkdir(parents=True, exist_ok=True)

state = {"manifest": None, "actions": {}, "radar_summary": None, "radar_frames": 0}
lock = threading.Lock()


def log(msg):
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}"
    print(line, flush=True)
    with LOG.open("a") as f:
        f.write(line + "\n")


# --- deciding what to show --------------------------------------------------------

def choose(data, available):
    """Ordered screen ids for the app; the screensaver uses ambient + the first three."""
    now = data["now"]
    h, wd = now.hour, now.weekday()
    warning = any(a["level"] == "warning" for a in data["alerts"])
    rain = state["radar_summary"] and state["radar_summary"]["near"]
    order = []
    if warning:
        order += ["radar"]
    if "gameday" in available:
        order += ["gameday"]
    if 4 <= h < 11:
        order += ["briefing"]
        if screens.finals(data):
            order += ["recap"]
        if wd < 5:
            order += ["school"]
    elif 11 <= h < 17:
        if screens.finals(data) and h < 14:
            order += ["recap"]
        order += ["ambient"]
        if wd >= 5 or data["weather"]["days"][0]["rain"] < 30:
            order += ["lake"]
        order += ["season"]
    else:
        order += ["tonight"]
        if screens.finals(data, hours=10):
            order += ["recap"]
        if wd in (5, 6):
            order += ["week"]
        if wd in (6, 0, 1, 2, 3):
            order += ["school"]
        tonight_clear = sum(x["cloud"] for x in data["weather"]["hours"][h:h + 6]) / 6 < 40
        if tonight_clear or data["shower"]:
            order += ["sky"]
    if rain or warning:
        order.insert(1 if order and order[0] == "gameday" else 0, "radar")
    order += ["board"]
    order += ["week", "radar", "lake", "sky", "recap", "season", "ambient", "briefing"]  # the rest, reachable with Left/Right
    seen, out = set(), []
    for s in order:
        if s in available and s not in seen:
            seen.add(s)
            out.append(s)
    return out


def render_all():
    data = screens.gather()
    stamp = int(time.time())
    available, metas, actions = {}, {}, {}
    for name, fn in screens.RENDERERS.items():
        try:
            sc, meta = fn(data)
        except Exception:
            log(f"render {name} failed:\n{traceback.format_exc()}")
            continue
        if sc is None:
            continue
        sc.save(OUT / f"{name}.jpg")
        available[name] = True
        metas[name] = meta or {}
        if meta and meta.get("action"):
            actions[name] = meta["action"]
    radar_urls = []
    try:
        if (screens.RADAR_DIR / "meta.json").exists():
            frames, summary = screens.render_radar(data)
            for i, (sc, _) in enumerate(frames):
                sc.save(OUT / f"radar_{i:02d}.jpg", quality=85)
                radar_urls.append(f"/img/radar_{i:02d}.jpg?v={stamp}")
            with lock:
                state["radar_summary"] = summary
            available["radar"] = True
            metas["radar"] = {"clock": None}
    except Exception:
        log(f"render radar failed:\n{traceback.format_exc()}")
    order = choose(data, available)
    items = []
    for name in order:
        item = {"id": name, "seconds": 30 if name in ("briefing", "week", "tonight") else 20,
                "clock": metas[name].get("clock"), "action": name in actions}
        if name == "radar":
            item.update(url=radar_urls[-1], frames=radar_urls, frame_ms=500, seconds=16)
        else:
            item["url"] = f"/img/{name}.jpg?v={stamp}"
        items.append(item)
    screensaver = ["ambient"] + [s for s in order if s not in ("ambient", "board", "gameday")][:3]
    manifest = {"version": stamp, "generated": data["now"].isoformat(), "screens": items,
                "screensaver": [s for s in screensaver if s in available],
                "alert": next((a["event"] for a in data["alerts"] if a["level"] == "warning"), None)}
    tmp = OUT / "manifest.tmp"
    tmp.write_text(json.dumps(manifest))
    tmp.replace(OUT / "manifest.json")
    with lock:
        state["manifest"], state["actions"] = manifest, actions
    return manifest


def render_loop():
    while True:
        t = time.time()
        try:
            m = render_all()
            log(f"rendered {len(m['screens'])} screens in {time.time() - t:.1f}s: {[s['id'] for s in m['screens']]}")
        except Exception:
            log(f"render loop error:\n{traceback.format_exc()}")
        time.sleep(max(5, 60 - (time.time() - t)))


def radar_loop():
    while True:
        t = time.time()
        try:
            screens.refresh_radar(12)
            log(f"radar refreshed in {time.time() - t:.0f}s")
        except Exception:
            log(f"radar refresh failed:\n{traceback.format_exc()}")
        time.sleep(600)


# --- actions and the family board ---------------------------------------------------------

def run_action(action):
    if action.get("type") == "launch" and str(action.get("app", "")).isdigit():
        req = urllib.request.Request(f"http://{ROKU}:8060/launch/{action['app']}", data=b"", method="POST")
        urllib.request.urlopen(req, timeout=5)
        return f"launched {action['app']}"
    raise ValueError("unsupported action")


def board_page():
    b = screens.board()
    member_opts = "".join(f'<option>{html.escape(m["name"])}</option>' for m in S.FAMILY["members"])
    notes = "".join(
        f'<li><b>{html.escape(n["text"])}</b><br><small>{html.escape(n.get("from", ""))}'
        f'{" · until " + html.escape(n["until"][5:16].replace("T", " ")) if n.get("until") else ""}</small>'
        f'<form method="post"><input type="hidden" name="op" value="del_note"><input type="hidden" name="i" value="{i}">'
        f'<button>Remove</button></form></li>' for i, n in enumerate(b["notes"]))
    groceries = "".join(
        f'<li><form method="post"><input type="hidden" name="op" value="toggle"><input type="hidden" name="i" value="{i}">'
        f'<button class="g">{"✓ " if g.get("done") else ""}{html.escape(g["item"])}</button></form></li>'
        for i, g in enumerate(b["groceries"]))
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Family board</title>
<style>
:root{{--bg:#0B1120;--card:#131B2E;--line:#1F2A44;--text:#F4F1EA;--muted:#A9B1C4;--accent:#F4A259}}
body{{margin:0;background:var(--bg);color:var(--text);font:17px/1.4 -apple-system,system-ui,sans-serif;padding:16px}}
h1{{font-size:26px;margin:4px 0 16px}} h2{{font-size:15px;letter-spacing:.12em;color:var(--muted);margin:24px 0 8px}}
section{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin-bottom:16px}}
input,select,textarea,button{{font:inherit;border-radius:10px;border:1px solid var(--line);background:#0B1120;color:var(--text);padding:10px}}
textarea{{width:100%;box-sizing:border-box;min-height:70px}} button{{background:var(--accent);color:#11142A;font-weight:700;border:0}}
ul{{list-style:none;padding:0;margin:0}} li{{padding:10px 0;border-top:1px solid var(--line)}} li:first-child{{border-top:0}}
li form{{display:inline}} li button{{background:transparent;color:var(--muted);border:1px solid var(--line);padding:4px 10px;margin-top:6px}}
button.g{{background:transparent;color:var(--text);border:0;padding:0;font-weight:400;text-align:left}}
.row{{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}}
</style></head><body>
<h1>Family board</h1>
<section><h2>NEW NOTE FOR THE TV</h2><form method="post"><input type="hidden" name="op" value="note">
<textarea name="text" maxlength="80" required placeholder="Dinner's at 6:30 tonight"></textarea>
<div class="row"><select name="from">{member_opts}</select>
<select name="hours"><option value="4">4 hours</option><option value="12" selected>Today</option><option value="48">2 days</option><option value="168">A week</option></select>
<button>Post</button></div></form></section>
<section><h2>NOTES</h2><ul>{notes or '<li><small>No notes</small></li>'}</ul></section>
<section><h2>GROCERY LIST</h2><form method="post" class="row"><input type="hidden" name="op" value="grocery">
<input name="item" maxlength="40" required placeholder="Milk"><button>Add</button></form>
<ul>{groceries or '<li><small>Empty</small></li>'}</ul>
<form method="post" class="row"><input type="hidden" name="op" value="clear_done"><button>Clear checked items</button></form></section>
</body></html>"""


def board_post(form):
    b = screens.board()
    op = form.get("op", "")
    if op == "note" and form.get("text", "").strip():
        until = S.now() + dt.timedelta(hours=min(168, int(form.get("hours", "12"))))
        name = form.get("from", "")
        b["notes"].insert(0, {"text": form["text"].strip()[:80], "from": name if S.member(name) else "",
                              "color": (S.member(name) or {}).get("color", "#7FB7E8"), "until": until.isoformat()})
        b["notes"] = b["notes"][:8]
    elif op == "del_note":
        i = int(form.get("i", -1))
        if 0 <= i < len(b["notes"]):
            b["notes"].pop(i)
    elif op == "grocery" and form.get("item", "").strip():
        b["groceries"].append({"item": form["item"].strip()[:40], "done": False})
    elif op == "toggle":
        i = int(form.get("i", -1))
        if 0 <= i < len(b["groceries"]):
            b["groceries"][i]["done"] = not b["groceries"][i].get("done")
    elif op == "clear_done":
        b["groceries"] = [g for g in b["groceries"] if not g.get("done")]
    screens.BOARD.write_text(json.dumps(b, indent=1))
    threading.Thread(target=render_all, daemon=True).start()  # show it on the TV right away


# --- HTTP -----------------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8", cache=None):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if cache:
            self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def _q(self):
        u = urllib.parse.urlparse(self.path)
        return u.path, urllib.parse.parse_qs(u.query)

    def _authed(self, q):
        return secrets.compare_digest(q.get("token", [""])[0], TOKEN)

    def do_GET(self):
        path, q = self._q()
        if path == "/health":
            return self._send(200, "ok")
        if not self._authed(q):
            return self._send(401, "unauthorized")
        if path == "/manifest.json":
            with lock:
                m = state["manifest"]
            return self._send(200, json.dumps(m), "application/json", "no-store") if m else self._send(503, "starting")
        if path.startswith("/img/"):
            name = pathlib.Path(path).name
            f = OUT / name
            if not name.endswith(".jpg") or not f.is_file():
                return self._send(404, "not found")
            return self._send(200, f.read_bytes(), "image/jpeg", "max-age=3600")
        if path == "/action":
            with lock:
                action = state["actions"].get(q.get("id", [""])[0])
            if not action:
                return self._send(404, "no action")
            try:
                return self._send(200, run_action(action))
            except Exception as e:
                return self._send(500, f"action failed: {e}")
        if path == "/board":
            return self._send(200, board_page(), "text/html; charset=utf-8", "no-store")
        return self._send(404, "not found")

    def do_POST(self):
        path, q = self._q()
        if not self._authed(q):
            return self._send(401, "unauthorized")
        if path != "/board":
            return self._send(404, "not found")
        length = min(int(self.headers.get("Content-Length", "0") or 0), 4096)
        form = {k: v[0] for k, v in urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", "replace")).items()}
        board_post(form)
        self.send_response(303)
        self.send_header("Location", f"/board?token={urllib.parse.quote(TOKEN)}")
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    log(f"Daybreak service starting on :{PORT}")
    threading.Thread(target=radar_loop, daemon=True).start()
    render_all()
    threading.Thread(target=render_loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
