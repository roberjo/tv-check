# Daybreak: design notes

Daybreak is a family dashboard and screensaver for a Roku TV. It's built for a household in LaGrange, Georgia, and everything personal lives in `config/family.json` (gitignored). Screenshots in `docs/images/` use the fictional family in `config/family.example.json`.

## One package, two entry points

| Entry | When |
|---|---|
| **Screensaver** (`RunScreenSaver`) | After the TV's idle timeout, once it's selected in Settings → Theme → Screensaver. Shows Ambient plus the three most relevant screens, and only the night clock from 11 PM to 5 AM |
| **App** (`Main`) | On demand. Every screen, in priority order. Left/Right browse, Play pauses |

## Screens and when they appear

| Screen | Shows when | Data |
|---|---|---|
| Briefing | 4–11 AM | Weather, family calendar, game watch, local headlines, heads-up |
| Ambient | Midday; first in the screensaver | Big clock, weather, sun arc, "next up" chip, Callaway Gardens photo |
| Tonight | After 5 PM | Tonight's game or a quiet night, weather, curbside, evening apps |
| Week ("Sunday Reset") | Weekend evenings | 7-day forecast, calendar, games, curbside, heads-up |
| Weekend | Friday midday and evening, Saturday until 5 PM | Saturday and Sunday side by side: forecast, sunrise and sunset, calendar and games. The better day outside is marked (rain chance, distance from 72°, wind over 15 mph), and the lake level is shown |
| Recap | Mornings or evenings after games | Finals (pro, SEC, LaGrange College), a house-divided hero card with the winner's logo watermark, records |
| Game day | A tracked team plays within 6 hours, or is playing now | Team panels with the team's logo as a faint watermark, a countdown and, for outdoor games, the stadium's forecast at game time. The live score and period during the game. The rivalry pair splits the screen |
| Radar | Rain likely within 2 hours, or any NWS warning | NOAA MRMS frames over a USGS base map, Troup County alerts |
| Lake | Weekends or dry days | West Point Lake level vs summer and winter pool, best lake day, sunset, moon |
| Sky | Clear nights or a meteor shower within 2 weeks | Moon phase, shower, viewing conditions |
| School | School mornings and evenings | School-related calendar items, a card per student |
| Board | When there are notes, groceries, countdowns or chores | "TV: …" calendar events as notes, "Buy: …" as groceries, "Countdown: …" as days to go, and whose turn it is for each chore |
| Season | Midday, all year | Three nature and garden notes for each month in West Georgia, frost watch |
| Weather warning | A tornado, severe thunderstorm, flash flood, extreme wind or hurricane warning | Takes over the app and the screensaver, alternating with radar until the warning expires. Shows the NWS headline, expiry and what to do |
| Night | Screensaver, 11 PM to 5 AM | A dim clock that drifts every 5 minutes, plus the coming day's forecast and first event. Radar joins it during a warning |
| Loading | Before the first data arrives | The real date and clock with placeholder cards. If the TV is offline, a note says when the saved data is from |

## Rule-based insights (no AI at runtime)
"Heads up" items, most important first:
1. NWS warnings and watches, and school closings, early releases or delayed openings (from the calendar) today or tomorrow.
2. Curbside pickup tomorrow or today.
3. Calendar deadlines within 7 days, and clock changes for daylight saving ("Clocks fall back 1 hour Sunday at 2 AM. Sunset moves to 5:44 PM.") from 3 days ahead.
4. Overlapping evening events.
5. Rain of 60% or more, timed from the hourly forecast ("Rain likely from about 3 PM (70%)", "Rain likely Tuesday from about noon (65%)"), or a low of 34°F or below.
6. Birthdays within 2 weeks.
7. A meteor shower peaking within 4 days, and Atlantic storms (within 500 miles is raised to priority 3).
8. West Point Lake well below winter pool.

Also at priority 5, air quality reaching "unhealthy for sensitive groups" (US AQI 101 or higher) in the next 24 hours. At priority 6, countdowns within 2 weeks.

## City of LaGrange curbside rules
- **Every week:** household garbage on your day.
- **Alternating weeks** (Sunday–Saturday): **yard waste** (leaves, brush, limbs; no grass clippings) or **bulky trash** (furniture, mattresses and other large items).
- **Verified against the flyer:** yard weeks start the week of 2025-12-28, which matches all 53 weeks of the city's 2026 schedule flyer.
- **Holidays:** a city holiday moves that day's pickup to the next day. A shift onto a weekend is flagged to confirm with the city.
- **Code:** `scripts/sanitation.py` (reference) and `daybreak/channel/source/lib/rules.brs` (on the TV).

## Visual system
- **Colors:** ink navy `#0B1120`, cards `#131B2E` with a `#1F2A44` border, text `#F4F1EA` with `#A9B1C4` secondary. Accents: amber `#F4A259` (day) and violet `#B3A6F2` (night).
- **Type:** Outfit (display) and Manrope (UI), both under the SIL Open Font License. The build creates static weights because Roku can't select weights from a variable font.
- **Layout:** 1080p with 112 px side margins and 64 px vertical margins, on a 12-column grid with 32 px gutters (`gx()` and `gw()` in `ui.brs`). Cards in a row share column edges.
- **Type scale:** 24 (captions and labels), 26 (body), 30, 36, 44, 56, 76 (titles), plus display sizes for clocks and temperatures. **Nothing is smaller than 24 px**, the comfortable minimum at living-room distance. Tests and CI enforce it.
- **Readability:** every label must clear WCAG contrast against the brightest 2% of what's drawn behind it: 4.5:1 for small text, 3:1 for large (24 px and up, or 19 px bold). Photo backgrounds are pre-dimmed (Ambient 0.55, Briefing 0.78, Season 0.70). `daybreak/preview/preview.sh --audit` checks every label on every screen, and CI runs it on each PR.
- **Accents:** a thin amber rule marks Heads up. Member colors mark notes and students. An amber "as of" note marks data that's getting old.

## Imagery and licensing
- **Wallpapers:** 36 photos from Wikimedia Commons (CC0, public domain, CC BY, CC BY-SA), credited on screen and in `daybreak/wallpapers/CREDITS.md`. The packaged Callaway Gardens fallbacks are CC0 (D. Dugan).
- **Not covered yet:** Commons has no usable free photos of Fayetteville; add one to `sources.json` when there is.
- Map layers: USGS National Map (public domain). Radar: NOAA/NCEP MRMS (public domain).
- Callaway Gardens' and tourism boards' own marketing media isn't used; it's copyrighted.

## Privacy choices
- **Health appointments** in the calendar show only as "Appointment".
- **"Gentle news" (default on)** hides violent-crime headlines on the living-room screen.
- **Warm-start cache:** the last good data, including parsed calendar events (without descriptions), is saved in the app's cache on the TV (`cachefs:`). It never leaves the TV, and removing the app removes it.
- **The calendar's secret iCal URL** lives in `.env`. The build bakes it into the sideloaded package (`source/config.brs`, gitignored), so the package itself is private.

## Constraints
- **Developer mode:** a sideloaded app needs it on, and only one dev app can be installed at a time.
- **Memory:** about 325 MB is free during 4K playback; Daybreak only runs when nothing else is playing. Measured on the TV, Daybreak's images take 25 MB (radar frames 17 MB, the base map 8 MB) and it starts in 0.2 s with saved data (2.3 s cold). A low-memory mode drops to 4 frames and skips photo backgrounds (see `docs/ARCHITECTURE.md`).
- **No overlays:** a Roku app can't draw over other apps, and launching other apps from the app was deliberately left out.
