# TV concierge (voice control) · unmaintained

> **Shelved.** This experiment uses the Claude API, which Daybreak deliberately doesn't. It's kept for reference and isn't tested or maintained. See [`../README.md`](../README.md).

Say **"Hey Siri, TV Pilot"**, then speak a request like "put on something funny on Netflix", "turn it down", "pause" or "when's the Braves game?". Siri sends the words to this server on the Mac. Claude decides what to do and drives the TCL Roku TV, then Siri speaks a one-sentence reply.

```
iPhone / Watch / HomePod ──Siri Shortcut "TV Pilot"──▶ attic/concierge/server.py (Mac :8765) ──Claude API──▶ tools ──ECP──▶ TV :8060
```

## Files

| File | Purpose |
|---|---|
| `server.py` | HTTP server plus the Claude tool loop (model `claude-opus-5-5`, effort `low` for speed) |
| `roku.py` | ECP client. **All safety limits live here:** key allowlist, 25 keys per call, volume cap of 40 (15 from 22:00 to 07:00) |
| `make_shortcut.py` | Builds and signs `shortcut/TV Pilot.shortcut` with the server URL and token baked in |
| `logs/commands.jsonl` | Every request: text, actions taken, reply, latency (gitignored) |

## Setup

1. **API key.** Add `ANTHROPIC_API_KEY=sk-ant-...` to `../.env` (gitignored). Get one at console.anthropic.com → API Keys.
2. **Start the server.**
   ```
   cd ~/Documents/GitHub/tv-check
   .venv/bin/python attic/concierge/server.py
   ```
   It listens on port 8765. To keep it running across logins, install the LaunchAgent (see below).
3. **Install the shortcut.** Run `open "attic/concierge/shortcut/TV Pilot.shortcut"` on the Mac and click **Add Shortcut**. It syncs to your iPhone, Watch and HomePod through iCloud. You can also AirDrop the file to the phone.
4. **First run on the iPhone.** Run it once by tapping it. iOS asks for permission to use dictation and to connect to `<your-mac>.local`; allow both. From then on, "Hey Siri, TV Pilot" works hands-free.

**If the shortcut import fails,** build it by hand in the Shortcuts app (2 minutes) with three actions:
1. **Dictate Text**
2. **Get Contents of URL**: `http://<your-mac>.local:8765/command`, Method **POST**, Header `Authorization` = `Bearer <CONCIERGE_TOKEN from .env>`, Request Body **JSON** with key `text` = *Dictated Text*
3. **Speak Text**: *Contents of URL*

Name it **TV Pilot**.

## Testing without Siri
```
source .env
curl -X POST http://localhost:8765/command -H "Authorization: Bearer $CONCIERGE_TOKEN" -d "what's playing?"
```

## Tools Claude can use
`get_tv_state`, `launch_app` (deep links: YouTube video ids, Netflix title ids), `roku_search` (Roku universal search, optionally auto-launching in a chosen app), `press_keys` (allowlisted remote buttons), `type_text`, `set_volume` (capped), and Anthropic's `web_search` (max 3 per request) for "what's on" questions and finding content ids.

## Behavior and limits
- **Follow-ups:** one shared household conversation, so "something else" and "louder" refer to the last request. It resets after 10 idle minutes.
- **Safety:** Claude is told never to buy, rent or subscribe. The volume cap and key allowlist are enforced in code regardless of what the model asks for.
- **Speed:** about 2–3 seconds for simple commands and longer when a web search is needed. To trade quality for speed, set `CONCIERGE_MODEL=claude-sonnet-5-5` or `claude-haiku-5-5` in `.env`.
- **The Mac has to be awake and on the home network.** The hostname `<your-mac>.local` follows the Mac when its IP changes.
- **Spectrum:** Claude opens the Spectrum TV app and navigates; direct channel deep links are still untested. The app itself does the playback, because the streams are DRM-protected and tied to Spectrum's sign-in.

## LaunchAgent (optional: start automatically at login)
Save as `~/Library/LaunchAgents/com.tvcheck.concierge.plist`, then run `launchctl load ~/Library/LaunchAgents/com.tvcheck.concierge.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.tvcheck.concierge</string>
  <key>ProgramArguments</key><array>
    <string>/Users/johnroberts/Documents/GitHub/tv-check/.venv/bin/python</string>
    <string>/Users/johnroberts/Documents/GitHub/tv-check/attic/concierge/server.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/Users/johnroberts/Documents/GitHub/tv-check/attic/concierge/logs/server.log</string>
</dict></plist>
```
