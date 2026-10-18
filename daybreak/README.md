# Daybreak (standalone Roku app)

Everything runs on the TV. The app fetches its own data, draws native screens, and works as both an app and a screensaver. No Mac, no server, no Claude API.

```
daybreak/channel/
  source/main.brs            Main (app) + RunScreenSaver (screensaver)
  source/config.brs          generated: household, members, calendar URL (gitignored: private)
  source/lib/                time.brs, ics.brs (iCal + RRULE + EXDATE), rules.brs (curbside, moon, showers)
  components/DataTask.*      fetches all sources, derives games/finals/calendar/heads-up, publishes every minute
  components/ui.brs          9-patch cards, fonts, labels, icons
  components/screens.brs     12 screens + playlist rules
  components/DaybreakScene.* crossfades, exact clock, radar animation, Left/Right/Play
```

## Data (fetched by the TV)

| Source | What | Refresh |
|---|---|---|
| Open-Meteo | Weather, hourly, 8-day, sunrise and sunset | 10 min |
| NWS | Alerts for LaGrange (Troup County) | 2 min |
| USGS 02339400 (param 00062) | West Point Lake level | 30 min |
| ESPN (unofficial) | Braves, Falcons, Hawks, Georgia, Auburn | 15 min |
| lagrangepanthers.com iCal | LaGrange College schedule and finals | 30 min |
| Google News RSS | LaGrange and Troup County headlines (no obituaries or violent crime) | 30 min |
| Family Google Calendar (secret iCal) | Events, deadlines, board notes, groceries | 10 min |
| NOAA MRMS WMS | Radar frames, loaded straight into posters | 10 min |

**Family board through the calendar:**
- **Notes:** add an event called **"TV: Dinner at 6:30"**. It shows from 12 hours before the event until it ends.
- **Groceries:** add **"Buy: milk, eggs"**.
- **Privacy:** health appointments show as "Appointment".

## Build and test (Mac)
```
.venv/bin/python daybreak/build_channel.py      # assets + config + BrighterScript check + daybreak/dist/daybreak.zip
daybreak/tests/run.sh      <fixtures-dir>       # library unit tests
daybreak/tests/run_data.sh <fixtures-dir>       # derive() on saved live feeds
```
Fixtures (saved feeds plus a copy of `config/family.json`) stay outside the repo because the calendar is private.

## Install (only when nobody is watching)
1. Check: `curl -s http://192.168.1.176:8060/query/media-player` should show `state="close"`, with the Home screen active.
2. Upload `daybreak/dist/daybreak.zip` to the dev installer at `http://192.168.1.176` (user `rokudev`). This replaces any other dev app.
3. **Screensaver:** Settings → Theme → Screensaver → **Daybreak**.

## Remote
- **Left/Right:** previous or next screen.
- **Play:** pause or resume the rotation.
- **Back:** exit.
- **OK:** nothing. Launching other apps was removed on purpose.

## Reference renderer
`daybreak/service/` (Python and PIL) renders the same screens as images on the Mac. It's useful for design previews and isn't needed to run the TV app.
