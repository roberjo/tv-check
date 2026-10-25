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
- **Before data:** the scene shows `buildLoading()`, with the real date and clock and placeholder cards. With no saved data and no connection, it says "Waiting for the internet connection...".
- **Offline:** when every source has failed twice in a row, the scene's status line says "Offline · showing saved data from 9:40 AM". It clears on the first success.
- **Night:** from 11 PM to 5 AM the screensaver plays only `buildNight()`, a dim clock that moves every 5 minutes. Radar is added in a warning.

## Memory budget
| Item | Before 1.2 | 1.2 |
|---|---|---|
| Radar frames (decoded RGBA) | 12 × 1920×1080 ≈ 100 MB, briefly ≈ 200 MB during a radar-to-radar crossfade | 8 × 960×540 ≈ 17 MB, built once per frame set |
| Raw ESPN schedules held by the task | up to ~1.5 MB of JSON as nested objects | compact events only |
| Photo backgrounds | 1 or 2 × 8 MB | same; skipped in low-memory mode |

**Low-memory mode:** the scene checks `roDeviceInfo.GetGeneralMemoryLevel()` and `roAppMemoryMonitor.GetMemoryLimitPercent()` every 10 seconds. When the level is `low` or `critical`, or the app is past 80% of its limit, radar keeps only the latest 4 frames and photo screens use a plain fill.

The decoded sizes are calculated (width × height × 4 bytes), not measured on the TV. To measure, run the read-only debug-console commands `loaded_textures` and `r2d2_bitmaps` while Daybreak is showing, and only when nobody is watching.

## Off-device testing
`@rokucommunity/brs` runs the library, `DataTask.brs` and the screen builders with the clock pinned and synthetic feeds. Tests ingest fixtures through the same `ingest()` the TV uses. See [`DEVELOPMENT.md`](DEVELOPMENT.md).
