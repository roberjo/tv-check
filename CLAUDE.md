# tv-check

This project explores the network interfaces of a TCL 65R625 Roku TV at 192.168.1.176 (Ethernet; formerly .127 on Wi-Fi). Record results in `FINDINGS.md`.

- Only use the Python stdlib. The scripts live in `scripts/`.
- Roku ECP runs on port 8060. Read-only `GET /query/*` calls are always fine.
- Ask the user before any state-changing call (`POST /keypress`, `/launch`, `/input`, `/search`, power) because it changes what's on the TV in the living room.
- Don't touch the other Roku (Hisense, 192.168.1.130) unless asked.
- `captures/` holds raw device responses with serials, MACs and the SSID. It's gitignored, so keep it that way.
- The TV's IP comes from DHCP. If it doesn't respond, re-run `scripts/ssdp_discover.py`.
- Developer mode is on. Dev installer credentials are in `.env`: digest auth against `http://$ROKU_IP/`. Don't copy them into any other file.
- Debug console on port 8080: `help`, `free`, `chanperf`, `plugins`, `sgnodes`, `sgperf`, `loaded_textures`, `r2d2_bitmaps` and `showkey` are read-only and fine to run. Ask the user before `press`, `type`, `fps_display`, `genkey`, `remove_plugin`, `clear_launch_caches` or any sideload/package upload.
- `scripts/run_diag.py` takes over the TV screen. Ask before running it, and check `/query/media-player` first so you don't interrupt someone watching.
- Dev console 8085 replays its recent log when you connect, so only trust DIAG lines that arrive after the install.
- `scripts/console.py <ip> "<cmd>" ...` runs debug-console commands. `remove_plugin <id>` uninstalls an app from the device **and the Roku account**, so only use it with explicit approval for each app.

## Activity log (required)
After every action that touches the TV or changes project files, append an entry to `ACTIVITY_LOG.md`, including read-only probes. Cover what was done, why, the result (with numbers), the impact on the TV, and how to undo it. If the TV's state changed, also update the "Current state of the TV" table at the top. The user asked for this explicitly.
- `attic/concierge/` (shelved, unmaintained): voice concierge (Siri Shortcut → `server.py` → Claude → ECP). Keep all TV safety limits in `attic/concierge/roku.py`. Restart the server after editing it or `.env`. Don't send test commands that change the TV while someone is watching (check `media-player` first).
- Family profile: `config/family.json` (gitignored), with names, colors, birthdays, team allegiance and school. The family calendar's secret iCal URL is only in `.env` as `FAMILY_CALENDAR_ICS`. Never copy it into docs, logs, the design canvas or chat. Read the calendar with `scripts/family_calendar.py`.
- Calendar privacy: keep medical and health appointments off the design canvas and show them on the TV only as "Appointment" unless the family says otherwise.
- Daybreak (`daybreak/channel/`) is a **standalone** Roku app: the TV fetches all data itself (DataTask) and draws native screens. `daybreak/preview/` renders the TV's own screen code off-device for design review (`--audit` checks the 24 px minimum and contrast). The user chose no Claude API, no family photos and no launching other apps. **Install or test on the TV only when nobody is watching** (check `media-player` and `active-app` first). Build with `daybreak/build_channel.py`, which runs BrighterScript. Test off-device with `daybreak/tests/run.sh` and `run_data.sh` (synthetic feeds and calendar in `daybreak/tests/fixtures/`, clock pinned; live feeds via `fetch_fixtures.sh` and `run_live.sh`). Install with `scripts/deploy.py`, which refuses while someone is watching and asks first. `scripts/screenshot.py` captures Daybreak's screen through the dev installer (read-only; saves to `captures/screens/`). `scripts/tv_monitor.py` graphs the TV's real CPU and memory from the read-only `chanperf` and `free`. See `docs/DEVELOPMENT.md`. `ACTIVITY_LOG.md` is local-only (gitignored): it holds household details.
