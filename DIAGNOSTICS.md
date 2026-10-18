# Diagnostic evaluation: TCL 65R625 Roku TV

Date: 2026-10-17. Device at 192.168.1.176 (Ethernet), Roku OS 16.0.4 build 834 (firmware dated Sep 7 2026).

The data comes from four sources:
- ECP queries
- The debug console on port 8080 (`free`, `plugins`, `r2d2_bitmaps`, `chanperf`)
- The sideloaded `diag-channel` (roDeviceInfo, roAppMemoryMonitor, CPU benchmark, speed test)
- Two sampling runs: 3 minutes idle and 2 minutes of 4K YouTube playback

Raw data is in `captures/192.168.1.176/diag/`.

## Summary

| Area | Status | Notes |
|---|---|---|
| Software | ✅ Current | 16.0.4, firmware built Sep 2026 |
| RAM | ⚠️ Adequate, tight under 4K | 1.1 GB total. 600 MB free idle, **325 MB free during 4K YouTube**, swap starting to be used |
| CPU | ⚪ No system-wide metric | Roku exposes CPU only for sideloaded apps. The benchmark gives a baseline for future comparison |
| Graphics | ✅ Healthy | 28 MB of the 120 MB texture budget used. UI renders up to 60 fps |
| Storage | ⚠️ **Low** | **36.4 MB flash free.** 46 apps already evicted. 28 never-used apps still occupy flash |
| Network | ✅ Good | Ethernet, **82–88 Mbps** down, ~50 ms HTTPS round-trip. Plenty for 4K (needs ~25 Mbps) |
| Video | ✅ | 4K60 output. Dolby Vision, HDR10, HLG. HEVC Main10, VP9 Profile 2 (HDR). No AV1, HDR10+, VRR or ALLM |
| Audio | ⚠️ TV speakers only | No HDMI ARC device active. Output is set to 5.1. Supports DD+, Atmos (DD+ JOC) and AC-4. No DTS |
| DRM | ✅ | Widevine L1 and PlayReady SL3000 with TEE, so services allow full 4K/HDR |
| Security | ⚠️ | Dev mode on with a 4-digit password. ECP fully enabled on the LAN |

## Measurements

### Memory (console `free`, sampled every 5 s)

| State | Used | Available | Buff/cache | Swap used |
|---|---|---|---|
| Idle, Home screen | 433–545 MB (mean 464) | 523–635 MB (mean 603) | ~290 MB | 0 |
| 4K YouTube (VP9/Opus) | 708–738 MB (mean 726) | 313–345 MB (mean 326) | ~355 MB | 0.2–0.7 MB |

Per-app limits from roAppMemoryMonitor: 580 MB foreground, 354 MB background, and 445 MB Roku-managed heap. `generalMemoryLevel` was `normal` throughout.

**Assessment:** there's enough headroom for one app. Swap starts to be used during 4K playback, and roughly 30% of RAM is left. Expect slower app switches and occasional app reloads when moving between heavy apps like YouTube, Netflix and Spectrum. This is a fixed hardware limit.

### CPU

Roku OS doesn't expose system-wide CPU. `chanperf` works only for the sideloaded diagnostic app:
- 13–26% CPU while running an 85 Mbps HTTPS download
- 0% at rest
- ~23 MB RSS

BrightScript benchmark (single thread, interpreted), for comparison after future firmware updates:

| Test | Run 1 | Run 2 |
|---|---|---|
| 1M integer loop | 441 ms | 438 ms |
| 300k sqrt × sin | 386 ms | 382 ms |
| 50k string build + join | 330 ms | 313 ms |

### Graphics

- `r2d2_bitmaps`: 135 surfaces, 27.9 MB of 120 MB texture memory in use. The largest single item is the 1920×1080 theme background (8.4 MB).
- UI frame rate reaches 60 fps during navigation and drops to ~0 when the screen is static (normal). The UI renders at 1080p; video plays at 2160p60.

### Storage

- Flash available: **36.4 MB**. Allowed plugin space: 389.9 MB.
- 129 packages: 83 on flash, **46 evicted**. Evicted apps re-download every time they launch, which slows startup.
- Launch counters (`usg`): Netflix 175, Spectrum TV 25, Backdrops 10, YouTube 7, Paramount+ 6, HBO Max 4, Peacock 4. About 10 others have 1.
- **These 28 apps sit on flash with zero launches:** ABC News, adult swim, AMC+, Cartoon Network, CBS, CBS Sports, ESPN, Fandango, FanDuel Sports, FOX One, Frndly TV, HappyKids, Lifetime, NBC, NFL, Pandora, PBS, PBS KIDS, Plex, Pluto TV, Tennis Channel, The CW. The rest are seasonal themes and sound packs (Fall is Fantastical, Winter in the Park, Winter is Whimsical, Nautical/Space/Western Sounds).
- 35 more never-used apps are installed but already evicted, including Apple TV, YouTube TV, Sling, DIRECTV, TBS/TNT and several screensavers.

### Network

- Wired (`eth0`). Gateway and DNS are 192.168.1.1, with 8.8.8.8 and 8.8.4.4 as fallbacks. IPv6 is active.
- Download from Cloudflare, 3 × 25 MB per run, 2 runs: **81.9–87.8 Mbps**. This plateau is consistent with a 10/100 Ethernet port. 4K streaming needs 15–25 Mbps, so there's 3× headroom.
- HTTPS request time: 530 ms for the first request (cold DNS + TLS), then 45–61 ms.
- LAN ping from this Mac (on Wi-Fi): 4–5 ms idle. During 4K playback it averaged 12 ms and peaked at 36 ms.

### Display and video

- Panel: 3840×2160, 60 Hz, LED, 143×80 cm. Supports HDR: Dolby Vision, HDR10, HLG. **No HDR10+, no VRR, no ALLM, no seamless HDR switching.**
- Video output mode: `2160p60`. UI resolution: 1080p.
- Decoders: HEVC Main and Main 10 at 4K60, VP9 Profile 0 and 2, H.264 High (up to 4K60), MPEG-2. **AV1 isn't supported**, so YouTube falls back to VP9 (seen during playback: `video=vp9 audio=opus`).

### Audio

- Active outputs: TV speakers, S/PDIF and line-out. The ARC/eARC, headphone and Bluetooth paths are capable but **inactive**.
- Volume 20 out of 100 (someone changed it to 18 during the test). Not muted. Menu sound effects at 40.
- Output channel setting: "5.1 surround". Decoders: AC3 6ch, DD+ 8ch (Atmos via `eac3` ChCnt 8 = true), AC-4 12ch, AAC 6ch, FLAC, Opus, ALAC, LPCM. **DTS isn't supported.**

## Recommendations

Settings the API can read are marked **measured**. Picture and sound modes aren't readable over the network, so those are **general advice for this model**. Check the current values on the TV before changing anything.

### Performance and responsiveness

1. **Remove unused apps (measured: highest impact).** Flash is down to 36 MB, so Roku is evicting apps. Remove the never-launched apps listed above (Home → highlight → `*` → Remove channel). That frees flash so Netflix, Spectrum, YouTube, Paramount+, HBO Max and Peacock stay installed and launch faster. Each app can be reinstalled for free from the Roku Channel Store later.
2. **Drop extra seasonal themes and sound packs (measured).** Six theme and sound packages occupy flash. Keep the current theme and remove the rest.
3. **Restart the TV occasionally (measured: low RAM headroom).** Settings → System → Power → System restart clears memory fragmentation. Once a week is plenty if apps feel sluggish.
4. **Keep Ethernet (measured).** It gives a stable 85 Mbps with low jitter. Wi-Fi 5 GHz might be faster on paper but less consistent. Speed isn't a bottleneck at the current rate.
5. **Reserve the IP on the router (measured).** The address changed from .127 to .176 when the TV switched to Ethernet. A DHCP reservation for the TV's Ethernet MAC keeps tools pointed at the right device.

### Picture (general advice for the 6-Series R625)

6. **Pick the right picture mode per content.** Use **Movie** for SDR film/TV and **Dark HDR** or **Bright HDR** for HDR depending on room light. Avoid **Vivid**, which oversaturates and crushes detail. Roku applies settings separately for SDR, HDR10 and Dolby Vision, so set each while that type of content is playing (`*` button during playback).
7. **Turn off motion smoothing for films** (`*` → Picture settings → Advanced → Action smoothing = Off). Use Low only for sports if you like it.
8. **Keep local dimming on** (Contrast control zones / Local contrast = High). It's the main reason this panel's HDR looks good.
9. **Nintendo Switch on HDMI: enable Game mode for that input (measured: no ALLM).** The panel doesn't support ALLM, so the TV won't switch automatically. Go to the HDMI input → `*` → Game mode = On to cut input lag.
10. **Confirm you're getting 4K on YouTube.** YouTube doesn't report resolution over ECP. During playback, open the video's settings → **Stats for nerds** to confirm 2160p and check dropped frames. With 85 Mbps it should run 4K steadily. If it doesn't, check the resolution setting in YouTube's settings.
11. **Settings → Display type** should be **4K HDR TV** (auto-detected on Roku TVs; the measured output was already 2160p60).

### Sound

12. **The biggest audio upgrade is a soundbar on HDMI ARC (measured: TV speakers only).** The TV decodes DD+ and Atmos (via DD+), so an ARC soundbar with Dolby Atmos gets full surround from Netflix, Disney+ and others. Enable Settings → System → Control other devices (CEC) → ARC so the TV remote controls soundbar volume.
13. **If nothing is connected to optical/S/PDIF:** "5.1 surround" output does nothing for the built-in speakers. Leaving it is harmless, but if you add an optical soundbar, use **Auto** or **Dolby Digital Plus** passthrough.
14. **Speaker settings to try:** use Audio mode **Movie** for films and **Speech clarity** for dialogue-heavy shows, and turn **Volume mode = Leveling** on if commercial loudness jumps bother you (`*` → Sound settings).
15. **Turn off menu sounds if you like:** Settings → Audio → Menu volume (currently 40) → Off.

### Privacy and security

16. **Turn off ACR (measured: ACR packages installed).** Settings → Privacy → Smart TV experience → uncheck **Use info from TV inputs**. This stops the TV fingerprinting what's on screen, including the Switch and the Stream Box input, for ad targeting.
17. **Settings → Privacy → Advertising → Limit ad tracking** = On, and reset the advertising ID.
18. **When you're done exploring:** turn developer mode off (same remote sequence → Disable installer). Its 4-digit password and open debug consoles (8080, 8085) are reachable by anything on your LAN. Optionally set "Control by mobile apps" back to **Limited**, but that also turns off the extra data this project relies on.

## Not measurable over the network

- **System-wide CPU and temperature:** Roku doesn't expose them.
- **Picture settings** (mode, backlight, color temperature, motion) and **sound settings** (mode, leveling): there's no read-only ECP endpoint, so check them on screen.
- **Stream bitrate and resolution for YouTube:** YouTube's player doesn't report them to ECP. Netflix, Spectrum and Roku's own player do report them.
- **Panel health** (dead pixels, uniformity, backlight bleed): needs test patterns and a visual check.

## Follow-up 2026-10-17: unused apps removed

With the user's approval, I removed the 28 never-launched apps from recommendations 1–2 using the debug console's `remove_plugin <id>`. This also removes them from the Roku account. Each was confirmed with "Removed plugin id: …" (log in `captures/192.168.1.176/removal_log.json`).

| | Before | After |
|---|---|---|
| Flash available | 35.4 MB | **107.4 MB** |
| Installed packages | 129 | 102 |
| Apps and inputs (`/query/apps`) | 73 | 52 (themes and sound packs aren't in this list; the dev app is now included) |

The active theme (Disney Hocus Pocus) and screensaver (Roku City) weren't touched. Netflix, Spectrum TV, YouTube, Paramount+, HBO Max and Peacock remain installed.
