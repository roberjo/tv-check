# Daybreak architecture

Daybreak is one sideloaded Roku package with two entry points: `Main` (the app) and `RunScreenSaver`. Both create a `DaybreakScene`, which owns a `DataTask`.

```
               every minute                                on content change
 Internet ──▶ DataTask (Task thread) ───────────────────────▶ DaybreakScene (render thread)
   8 sources   fetchAll: due requests in parallel            chooseScreens → buildScreen
               ingest:   raw response → compact form         crossfade, clock, radar frames
               store:    cache + fetch time                  memory check every 10 s
               derive:   compact cache → one data object
               publish:  only if the signature changed  ──▶ data field
                         health every minute           ──▶ health field (diagnostics)
               saveCache: cachefs:, at most every 10 min
```

## Data task (`components/DataTask.brs`)
- **Sources:** `sourceUrls()` lists each source's URLs, and `sourceLimits()` gives each one a refresh interval (`ttl`) and a maximum age (`maxAge`).

| Source | ttl | maxAge | Compact form |
|---|---|---|---|
| weather (Open-Meteo) | 10 min | 3 h | days and hours with wall-clock times |
| alerts (NWS) | 2 min | 30 min | `[{event, level}]` |
| lake (USGS) | 30 min | 12 h | `{level, time}` |
| sports (ESPN, 5 teams) | 15 min | 6 h | per team: `[{start, state, home, opp, network, tbd, won, my, their}]` |
| lc (college iCal) | 30 min | 24 h | `[{title, start, allDay, result, us, them}]` |
| news (3 Google News RSS queries) | 30 min | 12 h | `[{headline, source}]`, already filtered |
| calendar (family iCal) | 10 min | 24 h | parsed events without descriptions |
| radar (MRMS capabilities) | 10 min | 30 min | the latest 8 frame times, about 16 min apart |
| air (Open-Meteo air quality) | 30 min | 6 h | `{aqi, pm25, hours: [{t, aqi}]}` |
| tropics (NHC CurrentStorms, June to November) | 30 min | 6 h | Atlantic storms `[{name, kind, mph, lat, lon}]` |

During a game (an event `in` progress, or one that should have started in the last 4 hours), `sports` refreshes every 2 minutes instead of 15.

**Place:** `placeOf(cfg)` merges `family.json`'s `place` over `placeDefaults()` (`rules.brs`). The data task keeps it in `m.place`, and derived data carries it as `d.place`, so screens use `d.place.town`, `d.place.lake` and so on. Sources a town doesn't have (lake, college) get no URLs.

- **Fetching:** `fetchAll` starts every due request at once on one message port with a shared 25-second deadline. One slow source no longer delays the others.
- **Ingest:** `ingest` turns raw bodies into the compact form above, so raw documents (up to ~360 KB of ESPN JSON per team) never stay in memory. Empty bodies, error pages and unparseable data give `invalid`, and the previous good value is kept.
- **Freshness:** `fresh(name)` returns cached data younger than `maxAge`, or `invalid`. `asOfTimes()` reports sources older than twice their `ttl`, and screens show "as of 9:40 AM" for them. Expired alerts show as **Unavailable**, not "None in effect".
- **Publishing:** `derive` runs every minute. Data is published only when `dataSignature()` (everything except the clock fields) changes. The moon is computed hourly so it doesn't change the signature every minute.
- **Health:** each source records its last attempt and last success, HTTP status, latency, bytes, consecutive failures and last error. This goes to the `health` field every minute.
- **Warm start:** after a refresh that stored new data (at most every 10 minutes), the compact cache and fetch times are written to `cachefs:/daybreak-cache.json`. On launch they're loaded and published before any network request. Off-device runs use `tmp:`.

## Scene (`components/DaybreakScene.brs`, `screens.brs`, `ui.brs`)
- **Building:** a screen is built when it rotates in, or when new data arrives while it's showing. `show()` stamps the current time into the data first, so relative times ("Falcons in 2 h 10 m") are right without republishing. While paused, a 5-minute timer rebuilds the screen.
- **Crossfade:** the new screen fades in over the old one, then everything but the current screen is removed.
- **Radar:** `radarLayer()` builds one group of frame posters per set of frame times and moves it into each new radar screen, so nothing is downloaded or decoded twice. Frames load at 960×540 and are scaled to fill the screen.

## Startup and offline
- **Launch time:** the scene sends Roku's `AppLaunchComplete` beacon when the first real screen shows, and logs `Daybreak: first screen after N ms` on the dev console (port 8085). Diagnostics shows it under "Up · ready in". Measured on the TV: **cold start (no saved data) 2.3 s** to the first screen, 2.7 s by Roku's beacon; **warm start 0.17–0.21 s**, 0.64–0.70 s by the beacon. Compiling takes about 180 ms of that.
- **Warm start:** the saved data (`cachefs:`) is shown at once. Diagnostics lists each saved source as "saved data" with its age until the next fetch replaces the row.
- **Before data:** the scene shows `buildLoading()`, with the real date and clock and placeholder cards. With no saved data and no connection, it says "Waiting for the internet connection...".
- **Offline:** when every source has failed twice in a row, the scene's status line says "Offline · showing saved data from 9:40 AM". It clears on the first success.
- **Night:** from 11 PM to 5 AM the screensaver plays only `buildNight()`, a dim clock that moves every 5 minutes. Radar is added in a warning.

## Overlays (`components/overlays.brs`)
- **Layers:** the scene stacks `stage` (screens), then `navLayer` (page dots and the progress line, app only), then `overlay` (hint, menu, diagnostics).
- **Rotation:** the menu and diagnostics hold the rotation while they're open.
- **Builders take plain data.** `buildMenu(state)` and `buildDiagnostics(info)` don't call device APIs. The scene's `gatherDiagnostics()` collects `roDeviceInfo`, `roAppMemoryMonitor`, `roAppInfo` and the data task's `health` field. That lets tests and previews render the overlays with sample values.
- **Settings** live in the `daybreak` registry section as JSON. The data task gets them through its `settings` field. Gentle news is applied in `derive()`, so a change takes effect within a minute, without refetching.
- **Speed test:** `SpeedTask` runs only on request: three empty requests for latency, then a 25 MB download to `tmp:`, deleted afterwards.

## Parsing untrusted feeds
- **Return invalid, don't throw:** every parser in DataTask reads JSON through type-checked accessors (`aaOf`, `arrOf`, `arrAt`, `numOf`, `numAt`, `textTime`, `strOrEmpty`) and returns `invalid` when a response isn't usable. The previous good value is then kept.
- **Rejected before parsing:** `parseJsonSafe` turns away error pages and cut-off downloads.
- **Weather needs a full week:** a forecast with fewer than 7 complete days is rejected, because screens show a week ahead.
- **Tests:** `tests/test_robust.brs` feeds every source junk, partial and wrongly typed bodies. RSS is the exception, because the emulator lacks the XML-list methods it needs.
- **Belt and braces:** `refresh()` also wraps `ingest()` in try/catch.

## Live graphs (diagnostics page 2)
- **Samples:** every 10 seconds (the clock timer), `sampleStats()` in the scene records four values, and keeps 36 samples (6 minutes):
  - the app's free memory and % of its limit (`roAppMemoryMonitor`)
  - Daybreak's bytes downloaded (the data task's `bytesTotal`, published once a minute)
  - how late the timer fired
- **Why timer delay:** Roku gives apps no CPU reading, so timer delay stands in for load. On the TV, `chanperf` on the debug console has the real CPU figure.
- **TV throughput:** the main thread listens for Roku's `bandwidth.minute` system-log events and sets the scene's `bandwidthKbps`. On this TV they didn't arrive while idle or during a 25 MB speed test (Roku measures during video playback), so the card shows the last speed test result until one arrives.
- **Drawing:** `buildLiveGraphs()` draws the four bar graphs and redraws every 10 s while open.

## Wallpapers
- **Catalog:** `daybreak/wallpapers/catalog.json`, served from this repo (`place.wallpapers`). Each photo has an id, a file, a place, a credit, tags and `screens`: the screens where every label passed the contrast audit, recorded by `build.py --audit`.
- **Fetching:** DataTask fetches the catalog daily (`normWallpapers` keeps only safe ids and `img/<id>.jpg` paths, at most 100 entries).
- **Picks:** `wallpaperPicks(photos, day)` chooses a photo for each of the nine photo screens: different photos on different screens, changing daily, only on audited screens, and lake photos on the Lake screen.
- **Downloads:** `syncWallpapers()` downloads today's and tomorrow's picks into `cachefs:/wp-<id>.jpg`, three per refresh. A download goes to a `.part` file and is kept only if it arrived whole (HTTP 200, over 20 KB; stalled transfers are dropped). Every other `wp-*` file is deleted, so the TV holds at most about 18 photos (about 7 MB).
- **Screens:** `derive` puts only downloaded picks in `d.wallpapers`. `uiWallpaper` draws the photo under the screen's own fill color at `wallpaperDim()`: 0.55 on Ambient, 0.70 on Season, 0.78 on Briefing, 0.82 on card screens.
- **Credit:** `buildScreen` adds the credit at bottom right, on a translucent pill so it reads on any photo. The scene hides it while its status line uses the corner.
- **Fallbacks:** with no download yet, screens use the packaged pre-dimmed photos or plain fills. Low-memory mode uses plain fills.
- **Memory:** a wallpaper decodes to 8.3 MB, the same as the packaged photos, and at most two are decoded during a crossfade.

## Radar geometry
- **The window:** `radarView(lat, lon)` (`rules.brs`) computes the Web Mercator window around home, 300 km across on the ground and 1920×1080. It's the same window `scripts/radar_map.py` uses for the base map, so the radar frames, the base map and the labels line up. `radarPx()` places labels.
- **Precision:** the math is single precision, as BrightScript floats are. Tests check it against the Python projection: the bounding box agrees to within 10 m (under 0.1 px), and the label pixels match exactly.

## Severe-weather takeover
`takeoverAlert()` finds an unexpired tornado, severe thunderstorm, flash flood, extreme wind or hurricane warning, or a tornado or flash-flood emergency. While there is one:
- `chooseScreens()` returns only `alert` and `radar`, in the app and the screensaver alike, at any hour.
- Expired alerts drop out at derive time, so the takeover ends on its own, even if a refresh is late.

## Memory budget
| Item | Before 1.2 | 1.2 |
|---|---|---|
| Radar frames (decoded RGBA) | 12 × 1920×1080 ≈ 100 MB, briefly ≈ 200 MB during a radar-to-radar crossfade | 8 × 960×540 ≈ 17 MB, built once per frame set |
| Raw ESPN schedules held by the task | up to ~1.5 MB of JSON as nested objects | compact events only |
| Photo backgrounds | 1 or 2 × 8 MB | same; skipped in low-memory mode |

**Low-memory mode:** the scene checks `roDeviceInfo.GetGeneralMemoryLevel()` and `roAppMemoryMonitor.GetMemoryLimitPercent()` every 10 seconds. When the level is `low` or `critical`, or the app is past 80% of its limit, radar keeps only the latest 4 frames and photo screens use a plain fill.

**Measured on the TV** (TCL 65R625, Roku OS 16.0, Daybreak 1.7.2, 2026-10-25, #44):

| Measure | Value | Source |
|---|---|---|
| Daybreak's decoded bitmaps | **25.0 MB**: radar base map 8.4 MB (1920×1080), 8 radar frames 16.7 MB (2.1 MB each), ring art 1.2 MB | `r2d2_bitmaps` |
| Channel memory | 23–29 MiB, 0–4% CPU | `chanperf` |
| Memory free to the app | 247–256 MB, 1–2% of its limit, level "normal" | diagnostics overlay |
| SceneGraph nodes | 245 in the whole scene, 78 on screen | `sgnodes all`, diagnostics |
| System memory available | 299 MB on the Home screen, 255 MB with Daybreak running | `free` |

The radar frames stay decoded while other screens show, so radar can come back without a reload. That's 17 MB the app could release, but with 250 MB free it isn't worth the reload.

To measure again, run the read-only debug-console commands `chanperf`, `r2d2_bitmaps` and `sgnodes all` while Daybreak is showing, and only when nobody is watching. `loaded_textures` reports nothing on Roku OS 16 ("only works when a Scene Graph screen is displayed", even with Daybreak in front).

## Off-device testing
`@rokucommunity/brs` runs the library, `DataTask.brs` and the screen builders with the clock pinned and synthetic feeds. Tests ingest fixtures through the same `ingest()` the TV uses. See [`DEVELOPMENT.md`](DEVELOPMENT.md).
