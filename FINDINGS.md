# Findings: TCL 65R625 (192.168.1.127)

Last probed: 2026-10-17

## Open ports

| Port | Service | Notes |
|---|---|---|
| 8060 | Roku ECP (HTTP) | Main control and query API |
| 8061 | Roku ECP (TLS?) | `ecp-tls-enabled=true` in device-info |
| 7000 | AirPlay (AirTunes/377.40) | `/info` returns a binary plist without auth |
| 7250 | Miracast | |
| 1900/udp | SSDP | Answers `roku:ecp`, `upnp:rootdevice`, DIAL |

These ports are closed: 22, 23, 80 (dev installer, only open in dev mode), 5555 (adb), 8008/8009 (Cast), 8085 (BrightScript debug).

## ECP access level: **Limited**

`ecp-setting-mode=limited`. Any other endpoint returns `403 ECP command not allowed in Limited mode.`

| Endpoint | Status |
|---|---|
| `/query/device-info` | 200 |
| `/query/active-app` | 200 |
| `/` and `/dial/dd.xml` | 200 |
| `/query/apps`, `/query/media-player`, `/query/tv-channels`, `/query/tv-active-channel`, `/query/sgnodes/*`, `/query/chanperf`, `/query/registry/*`, `/query/app-ui`, `/query/audio-device` | 403 |

To unlock more, set **Settings → System → Advanced system settings → Control by mobile apps → Network access** to **Enabled** (it's currently Limited). This lets anyone on the LAN query and control the TV.

## What can be learned right now, with no auth

**Identity and hardware**
- TCL 65R625 / A108X, US region, ATSC tuner, panel id 15
- Serial, device-id, UDN, advertising-id, Wi-Fi MAC and Ethernet MAC are all exposed (see `captures/`)
- UI renders at 1080p. The panel supports 4K60, Dolby Vision (dvhe.05.09), HDR10 and SDR (from AirPlay `/info`)
- Wi-Fi uses a Realtek driver and supports 5 GHz

**Household context**
- User-assigned name and the room the TV is in
- Wi-Fi network SSID (the home network's name)
- Time zone America/New_York, en_US locale, 12-hour clock
- User profile type: `adult`
- Closed captions: "When mute"

**Live state**
- `power-mode`: PowerOn
- `uptime`: seconds since boot
- **Currently active app**
- Headphones (private listening) connected: yes/no

**Feature flags**
- Developer mode off; voice search on; AirPlay supported; wake-on-WLAN supported; find-remote supported

## Ideas to explore next

1. **Activity logging.** Poll `/query/active-app` and `power-mode` on an interval to build a viewing timeline. This works in Limited mode.
2. **Enable full ECP.** This exposes the installed app list, media-player state (position, duration, stream format), live-TV channel info and app icons.
3. **Control (state-changing).** `POST /keypress/<Key>`, `/launch/<appId>`, and `/input` for deep links. Ask before sending any of these, since they change what's on screen.
4. **ECP over WebSocket / TLS on 8061.** Newer Roku OS versions move ECP to an authenticated channel. Check what 8061 negotiates.
5. **Developer mode** (Home ×3, Up ×2, Right, Left, Right, Left, Right on the remote). This opens port 80 for sideloading and 8085 for the BrightScript debug console.

---

# Update 2026-10-17: ECP Enabled + Developer Mode on

The TV moved to **Ethernet at 192.168.1.176** (`network-type=ethernet`). `ecp-setting-mode=enabled` and `developer-enabled=true`.

## Newly open ports

| Port | What it is |
|---|---|
| 80 | Dev installer web UI (digest auth, user `rokudev`). Nothing is sideloaded yet; no dev key is set |
| 8080 | **Debug telnet console**. Greets with serial, name and OS build. Commands include `free`, `chanperf`, `plugins`, `sgnodes`, `sgperf`, `loaded_textures`, `r2d2_bitmaps`, `press`, `type`, `genkey`, `remove_plugin` |
| 8085 | BrightScript console for the sideloaded dev channel (silent until one runs) |
| 8086, 8087, 8089 | SceneGraph and profiler debug ports (silent until a dev channel runs) |
| 9080 | Unknown and silent; possibly the remote debug protocol |

## ECP endpoints now returning 200

| Endpoint | What it reveals |
|---|---|
| `/query/apps` | **~70 user-visible apps and inputs**: streaming services, live-TV apps and HDMI inputs |
| `/query/active-app` | Current foreground app (Home screen at probe time) |
| `/query/media-player` | Player state (`close`/`play`/`pause`/`buffer`), and when playing: position, duration, stream format, bitrate |
| `/query/tv-channels`, `/query/tv-active-channel` | Antenna channel list (only analog ch 3 has been scanned) and program title, rating, CC, signal |
| `/query/audio-device` | **Volume (20) and mute state**, active outputs (speakers, S/PDIF, line-out), headphone/ARC options |
| `/query/graphics-frame-rate` | Live UI frame rate |
| `/query/icon/<id>` | App icon PNGs |

`/query/chanperf`, `/sgnodes/*`, `/r2d2-bitmaps`, `/registry/dev` and `/app-ui` return **202** with an empty body. These apply to a sideloaded dev channel, so they need one running.

## Debug console (8080) findings

- **`free`**: about 1.1 GB RAM, about 640 MB available, 360 MB swap unused.
- **`chanperf`**: "not available" with no dev channel running.
- **`plugins`**: the full list of ~130 installed packages, including hidden system ones. Each line has a `usg` counter that looks like a per-app launch count, enough to build a rough viewing-habit profile.
- The hidden system packages include **`ACR Lib Channel` and `AcrAddon`**. ACR (automatic content recognition) is the Roku/TCL feature that fingerprints what's on screen, including HDMI inputs, for ad targeting. You can turn it off in Settings → Privacy → Smart TV experience → "Use info from TV inputs".
- Ad and analytics libraries are also present: BrightLine, Innovid, DFP Ad Service, Roku Ads/Analytics, and Interactive Ads.
- TCL and Roku factory apps are present: TCL Manufacturing App, Roku Manufacturing Library, Roku Tuning App.
- Flash: 36.4 MB free; 389.9 MB allowed for plugins.

## What's possible from here

1. **Viewing logger.** Poll `active-app` + `media-player` + `audio-device` to log what's watched, when, for how long, and at what volume. Read-only.
2. **Sideload a probe channel.** A small BrightScript app pushed via port 80 could read data ECP doesn't expose, such as `roDeviceInfo` (connection info, display mode, model details) and `roAppManager`, and would activate `chanperf`/`sgnodes`. **This needs your OK.**
3. **Screenshots.** The dev installer can capture the screen, but only while the sideloaded dev channel is in the foreground, not other apps. `scripts/screenshot.py` does this (`POST /plugin_inspect` with `mysubmit=Screenshot`, then `GET /pkgs/dev.jpg`, both with digest auth).
4. **Remote control** via ECP `keypress`/`launch` or console `press`/`type`. **Ask before each use.**

## Roku OS 16 notes (2026-10-25, Daybreak 1.7.2 on the TV)
- **The Home screen is an app now.** `/query/active-app` on the Home screen returns `<app id="562859" type="home" ui-location="home">Roku Dynamic Menu</app>`, not the old `<app>Roku</app>`. Tools that look for "Roku" or id `home` must also accept `type="home"`.
- **The dev installer closes the connection on an unauthorized upload.** It answers a 2 MB `POST /plugin_install` without credentials with 401 and drops the socket mid-body, so urllib's digest handler (which only authenticates after a 401) fails with "Broken pipe". Fetch the digest challenge with a bodiless `GET` first and send the `Authorization` header with the upload (`scripts/deploy.py`). A full upload and install takes about 3 s.
- **Display modes:** `roDeviceInfo.GetDisplayMode()` returns `1080p` and the UI resolution is FHD (1920×1080), while `GetVideoMode()` returns `2160p60`. Roku OS draws apps at 1080p and scales them up to the 4K panel; only video plays at 2160p.
- **Launch beacons** on the dev console (8085): `AppCompileComplete` ≈ 140–260 ms, and `AppLaunchComplete` once the app signals it (Daybreak: 2.7 s cold, 0.64–0.70 s warm).
- **`loaded_textures`** answers "only works when a Scene Graph screen is displayed" even with a SceneGraph app in front; `r2d2_bitmaps` lists every decoded bitmap on the device, the Home screen's included.
- **`free`** with Daybreak running: about 255 MB available of 1.1 GB, down from 299 MB on the Home screen.

