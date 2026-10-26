# Daybreak (standalone Roku app)

Everything runs on the TV. The app fetches its own data, draws native screens, and works as both an app and a screensaver. No Mac, no server, no Claude API.

```
daybreak/channel/
  source/main.brs            Main (app) + RunScreenSaver (screensaver)
  source/config.brs          generated: household, members, calendar URL (gitignored: private)
  source/lib/                time.brs, ics.brs (iCal + RRULE + EXDATE), rules.brs (curbside, moon, showers)
  components/DataTask.*      fetches due sources in parallel, keeps compact data, derives, publishes on change, saves a warm-start cache
  components/ui.brs          9-patch cards, fonts, labels, icons
  components/screens.brs     12 screens + playlist rules
  components/DaybreakScene.* crossfades, exact clock, radar animation, Left/Right/Play
```

## Data (fetched by the TV)

| Source | What | Refresh | Dropped after |
|---|---|---|---|
| Open-Meteo | Weather, hourly, 8-day, sunrise and sunset | 10 min | 3 h |
| NWS | Alerts for LaGrange (Troup County) | 2 min | 30 min (then shown as "Unavailable") |
| USGS 02339400 (param 00062) | West Point Lake level | 30 min | 12 h |
| ESPN (unofficial) | Braves, Falcons, Hawks, Georgia, Auburn | 15 min | 6 h |
| lagrangepanthers.com iCal | LaGrange College schedule and finals | 30 min | 24 h |
| Google News RSS | LaGrange and Troup County headlines (no obituaries or violent crime) | 30 min | 12 h |
| Family Google Calendar (secret iCal) | Events, deadlines, board notes, groceries | 10 min | 24 h |
| NOAA MRMS WMS | Radar: 8 frames over about 2 hours, at 960×540 | 10 min | 30 min |
| Open-Meteo air quality | US AQI now and for the next day | 30 min | 6 h |
| National Hurricane Center | Active Atlantic storms (June to November only) | 30 min | 6 h |
| This repo (`daybreak/wallpapers/catalog.json`) | Wallpaper catalog; the photos themselves download in the background, a few per refresh | 1 day | 30 days |

Team schedules refresh every 2 minutes while a tracked game is in progress, for live scores. Open-Meteo's pollen data only covers Europe, so Daybreak shows air quality but not pollen.

All due sources are fetched in parallel. Screens show "as of" when a source is older than twice its refresh interval. The last good data is saved on the TV (`cachefs:`), so the screensaver starts with it immediately. How it all fits together is in [`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

**Family board through the calendar:**
- **Notes:** add an event called **"TV: Dinner at 6:30"**. It shows from 12 hours before the event until it ends.
- **Groceries:** add **"Buy: milk, eggs"**.
- **School closings:** when the district announces one, add an event like **"No school"**, **"Early release 12:30"** or **"Delayed opening"**. It becomes the top heads-up on the day and the day before, and shows on the School screen. Troup County Schools publishes no feed the TV could read; announcements come by SchoolStatus, media and Facebook.
- **Countdowns:** add an event called **"Countdown: Beach trip"** on the day. The Board counts down to it (up to a year out), and Heads up mentions it in the last two weeks.
- **Privacy:** health appointments show as "Appointment".

## Build and test (Mac)
```
.venv/bin/python daybreak/build_channel.py          # assets + config + BrighterScript + daybreak/dist/daybreak.zip
.venv/bin/python daybreak/build_channel.py --check  # BrighterScript only, with the example config (what CI runs)
daybreak/tests/run.sh                               # library unit tests
daybreak/tests/run_data.sh                          # derive() + every screen on synthetic feeds, clock pinned
daybreak/tests/run_live.sh                          # optional smoke run on live feeds (fetch_fixtures.sh first)
```
The synthetic feeds in `tests/fixtures/feeds/` come from `tests/make_fixtures.py` and are committed. Live feeds and the copy of `family.example.json` stay out of git. See [`docs/DEVELOPMENT.md`](../docs/DEVELOPMENT.md).

## Install (only when nobody is watching)
```
python3 scripts/deploy.py --check   # read-only: media player idle and Home or Daybreak in front?
python3 scripts/deploy.py           # asks, re-checks, uploads to the dev installer, logs the install
```
The install replaces any other dev app. Then choose **Settings → Theme → Screensaver → Daybreak**.

## Remote (app)
| Button | Does |
|---|---|
| Left / Right | Previous or next screen |
| Play | Pause or resume the rotation |
| OK | Menu: pause, go to a screen, hide this photo, settings, diagnostics |
| * (Options) | Diagnostics; Left/Right switch to live graphs |
| Back | Close the menu or diagnostics, or exit |

Page dots at the bottom show where you are in the playlist, and a thin line along the bottom edge fills up until the next screen. A remote hint shows on the first three launches. In the screensaver, any button ends it, as on every Roku screensaver. Launching other apps was left out on purpose.

**Settings** (OK → Settings) are saved on the TV, in the app's registry section:
- **Gentle news:** on hides violent-crime headlines. The default comes from `GENTLE_NEWS` in `.env`.
- **Rotation speed:** Normal, Slow (twice as long) or Fast (60%).
- **Screens:** turn any screen off. At least one stays on.

**Diagnostics** (the * key) shows:
- every data source: last update, response time, size and status, colored green, amber or red
- memory: free to the app, % of its limit, the TV's memory level, low-memory mode, screen element count
- the device, display and network
- the warm-start cache
- a speed test, run only when you press OK (a 25 MB download)
- **Live graphs** (press Right): the last 6 minutes of app memory, memory-limit use, Daybreak's network traffic with the TV's measured network speed, and timer delay, a stand-in for CPU load, which Roku doesn't let apps read

## Previews and the design audit
`daybreak/preview/` renders every screen **from the TV's own code**. The BrightScript builders run off-device against the synthetic feeds and dump the SceneGraph tree. `render.py` then draws it with the package's fonts and 9-patch images.
```
.venv/bin/python daybreak/build_channel.py              # once, to generate fonts and images
daybreak/preview/preview.sh daybreak/out/preview         # PNG per screen
daybreak/preview/preview.sh daybreak/out/preview --audit # also: text under 24 px, WCAG contrast per label
daybreak/preview/preview.sh daybreak/out/preview --docs docs/images   # README screenshots
```
CI runs the audit and attaches the PNGs to every run as `screen-previews`. The off-device runner can't measure text, so `preview.sh` first writes the bundled fonts' real character widths (`font_metrics.py`) and layout uses those. Kerning isn't applied, so spacing can still differ by a few pixels from the TV.

`daybreak/art/` holds the sources the build turns into bundled images: the photos, the variable fonts and `draw.py`.
