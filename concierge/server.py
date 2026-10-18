"""TV concierge: an HTTP endpoint that takes a spoken/typed request, lets Claude
decide what to do, and drives the TCL Roku TV over ECP.

POST /command   body: {"text": "..."} or plain text.   Auth: "Authorization: Bearer <CONCIERGE_TOKEN>"
GET  /command?text=...&token=...                       (handy for testing from a browser)
GET  /health

Replies are short plain text, meant to be spoken back by Siri.
Config comes from ../.env: ROKU_IP, CONCIERGE_TOKEN, ANTHROPIC_API_KEY, and optional
CONCIERGE_PORT, CONCIERGE_MAX_VOLUME, CONCIERGE_NIGHT_MAX_VOLUME.
"""
import json
import os
import pathlib
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from roku import ALLOWED_KEYS, Roku  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
for line in (ROOT / ".env").read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())

MODEL = os.environ.get("CONCIERGE_MODEL", "claude-opus-5-5")
PORT = int(os.environ.get("CONCIERGE_PORT", "8765"))
TOKEN = os.environ["CONCIERGE_TOKEN"]
CONVERSATION_IDLE_RESET_S = 600
MAX_HISTORY_MESSAGES = 40
MAX_TOOL_ROUNDS = 8
LOG_PATH = ROOT / "concierge" / "logs" / "commands.jsonl"

tv = Roku(os.environ["ROKU_IP"],
          max_volume=int(os.environ.get("CONCIERGE_MAX_VOLUME", "40")),
          night_max_volume=int(os.environ.get("CONCIERGE_NIGHT_MAX_VOLUME", "15")))
client = anthropic.Anthropic()

TOOLS = [
    {
        "name": "get_tv_state",
        "description": "Read the TV's current state: power mode, foreground app, player state/position, volume, mute, and the current volume cap.",
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "launch_app",
        "description": (
            "Open an installed app by its numeric Roku app id (see the installed apps list), optionally deep-linking "
            "to specific content. Deep links: YouTube (837) takes the 11-character video id as content_id. "
            "Netflix (12) takes the Netflix title id (from netflix.com/title/<id>) with media_type 'movie' or 'series'. "
            "Other apps accept their own content ids if known. Without content_id the app just opens."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "app_id": {"type": "string", "description": "Roku app id, e.g. '12' for Netflix."},
                "content_id": {"type": "string", "description": "Optional app-specific content id for a deep link."},
                "media_type": {"type": "string", "enum": ["movie", "series", "season", "episode", "live", "short-form", "special"]},
            },
            "required": ["app_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "roku_search",
        "description": (
            "Use Roku's built-in universal search, which covers every streaming app. With launch=true and a provider_id "
            "(an installed app id), Roku tries to start the best match directly in that app. Good for 'play <title> on <app>' "
            "when you don't know the app's content id. Without launch it just shows the search results on screen."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "keyword": {"type": "string", "description": "Title, person, or topic to search for."},
                "type": {"type": "string", "enum": ["movie", "tv-show", "person", "channel", "game"]},
                "provider_id": {"type": "string", "description": "Installed app id to prefer, e.g. '12' for Netflix."},
                "launch": {"type": "boolean", "description": "Start playback of the best match if possible."},
                "season": {"type": "integer"},
            },
            "required": ["keyword"],
            "additionalProperties": False,
        },
    },
    {
        "name": "press_keys",
        "description": (
            "Press remote-control buttons in order (max 25). Allowed keys: " + ", ".join(sorted(ALLOWED_KEYS)) + ". "
            "Use for navigation, play/pause (Play toggles), rewind/fast-forward, power, inputs, and channel up/down."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"keys": {"type": "array", "items": {"type": "string", "enum": sorted(ALLOWED_KEYS)}, "maxItems": 25}},
            "required": ["keys"],
            "additionalProperties": False,
        },
    },
    {
        "name": "type_text",
        "description": "Type text into the on-screen keyboard or search box that currently has focus.",
        "input_schema": {
            "type": "object",
            "properties": {"text": {"type": "string", "maxLength": 100}},
            "required": ["text"],
            "additionalProperties": False,
        },
    },
    {
        "name": "set_volume",
        "description": "Set the TV volume to an absolute level 0-100. The household cap is enforced automatically.",
        "input_schema": {
            "type": "object",
            "properties": {"level": {"type": "integer", "minimum": 0, "maximum": 100}},
            "required": ["level"],
            "additionalProperties": False,
        },
    },
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 3},
]


def build_system_prompt():
    apps = "\n".join(f"- {a['name']} (id {a['id']}, {a['type']})" for a in tv.apps())
    return f"""You are the voice concierge for the living-room TV, a 65" TCL Roku TV. People speak a request into their phone; you act on the TV with your tools, then reply with ONE short sentence that Siri will read aloud.

How to act:
- Do the thing rather than asking, unless the request is genuinely ambiguous in a way that matters. Prefer the app the household actually uses: Netflix, Spectrum TV, YouTube, Paramount Plus, HBO Max, Peacock, Hulu, Disney Plus, Prime Video.
- For "play <title>": if you know or can find the app's content id (web_search for a YouTube video id or a netflix.com/title id), use launch_app with a deep link. Otherwise use roku_search with launch=true and the right provider_id.
- For live TV channels and sports on cable networks, the household uses Spectrum TV (id 23048). Open it and tell the user which channel to pick if you can't tune directly.
- For "what's on / when is the game": use web_search, then answer and offer to put it on.
- Follow-ups like "something else", "louder", "go back", "pause" refer to the conversation so far and the current TV state.
- Check get_tv_state after acting when it matters (e.g. confirm something launched).

Rules:
- Never buy, rent, or subscribe to anything, and never press Select on a screen that might confirm a purchase. If something needs payment, say so instead.
- Respect the volume cap reported in the TV state; never try to work around it.
- Keep every reply to one sentence, plain words, no markdown, no lists, no URLs.

Installed apps and inputs:
{apps}
"""


def run_tool(name, args):
    if name == "get_tv_state":
        return json.dumps(tv.state())
    if name == "launch_app":
        return tv.launch(args["app_id"], args.get("content_id"), args.get("media_type"))
    if name == "roku_search":
        return tv.search(args["keyword"], args.get("type"), args.get("provider_id"), args.get("launch", False), args.get("season"))
    if name == "press_keys":
        return tv.press(args["keys"])
    if name == "type_text":
        return tv.type_text(args["text"])
    if name == "set_volume":
        return tv.set_volume(args["level"])
    raise ValueError(f"unknown tool {name}")


class Conversation:
    """One shared household conversation. History is append-only so the prompt
    cache and thinking blocks stay valid; it resets after 10 idle minutes."""

    def __init__(self):
        self.lock = threading.Lock()
        self.system = build_system_prompt()
        self.messages = []
        self.last_used = 0.0

    def handle(self, text):
        with self.lock:
            if time.time() - self.last_used > CONVERSATION_IDLE_RESET_S or len(self.messages) > MAX_HISTORY_MESSAGES:
                self.system = build_system_prompt()  # refresh the installed-app list between conversations
                self.messages = []
            self.last_used = time.time()
            try:
                state = json.dumps(tv.state())
            except OSError as e:
                return "I can't reach the TV right now.", [{"error": str(e)}]
            now = time.strftime("%A %B %-d, %-I:%M %p")
            self.messages.append({"role": "user", "content": f"[{now}] TV state: {state}\n\nRequest: {text}"})
            actions = []
            for _ in range(MAX_TOOL_ROUNDS):
                response = client.beta.messages.create(
                    model=MODEL,
                    max_tokens=16000,
                    system=[{"type": "text", "text": self.system, "cache_control": {"type": "ephemeral"}}],
                    tools=TOOLS,
                    messages=self.messages,
                    output_config={"effort": "low"},
                    betas=["server-side-fallback-2026-07-01"],
                    fallbacks="default",
                )
                self.messages.append({"role": "assistant", "content": response.content})
                if response.stop_reason == "refusal":
                    return "Sorry, I can't help with that one.", actions
                if response.stop_reason == "pause_turn":
                    continue
                tool_uses = [b for b in response.content if b.type == "tool_use"]
                if not tool_uses:
                    reply = " ".join(b.text for b in response.content if b.type == "text").strip()
                    return reply or "Done.", actions
                results = []
                for tu in tool_uses:
                    try:
                        out = run_tool(tu.name, tu.input)
                        results.append({"type": "tool_result", "tool_use_id": tu.id, "content": out})
                    except Exception as e:  # report tool failures back to Claude instead of crashing
                        out = f"Error: {e}"
                        results.append({"type": "tool_result", "tool_use_id": tu.id, "content": out, "is_error": True})
                    actions.append({"tool": tu.name, "input": tu.input, "result": out})
                self.messages.append({"role": "user", "content": results})
            return "That took too many steps, so I stopped.", actions


conversation = Conversation()


def log(entry):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a") as f:
        f.write(json.dumps(entry) + "\n")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, text):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self, query):
        auth = self.headers.get("Authorization", "")
        return auth == f"Bearer {TOKEN}" or query.get("token", [""])[0] == TOKEN

    def _command(self, text):
        text = (text or "").strip()
        if not text:
            return self._send(400, "I didn't catch that.")
        t0 = time.time()
        try:
            reply, actions = conversation.handle(text)
        except anthropic.APIConnectionError:
            reply, actions = "I can't reach Claude right now.", []
        except anthropic.RateLimitError:
            reply, actions = "I'm being rate limited, try again in a minute.", []
        except anthropic.APIStatusError as e:
            reply, actions = "Something went wrong talking to Claude.", [{"error": f"{e.status_code} {e.message}"}]
        except Exception as e:  # e.g. missing credentials; Siri should still hear an answer
            reply, actions = "The TV concierge hit an error, check the server log.", [{"error": repr(e)}]
        log({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "client": self.client_address[0], "text": text,
             "reply": reply, "actions": actions, "seconds": round(time.time() - t0, 2)})
        self._send(200, reply)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/health":
            return self._send(200, "ok")
        if url.path != "/command":
            return self._send(404, "not found")
        if not self._authorized(query):
            return self._send(401, "unauthorized")
        self._command(query.get("text", [""])[0])

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path != "/command":
            return self._send(404, "not found")
        if not self._authorized(query):
            return self._send(401, "unauthorized")
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0") or 0)).decode(errors="replace")
        try:
            text = json.loads(raw).get("text", "")
        except (json.JSONDecodeError, AttributeError):
            text = raw
        self._command(text)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"{time.strftime('%H:%M:%S')} {self.client_address[0]} {fmt % args}\n")


if __name__ == "__main__":
    print(f"concierge on :{PORT}, model {MODEL}, TV {os.environ['ROKU_IP']}", flush=True)
    if not (os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")):
        print("WARNING: no ANTHROPIC_API_KEY in .env or the environment; commands will fail", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
