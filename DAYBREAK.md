# Daybreak: design notes

Daybreak is a family dashboard and screensaver for a Roku TV. It's built for a household in LaGrange, Georgia, and everything personal lives in `config/family.json` (gitignored). Screenshots in `docs/images/` use the fictional family in `config/family.example.json`.

## One package, two entry points

| Entry | When |
|---|---|
| **Screensaver** (`RunScreenSaver`) | After the TV's idle timeout, once it's selected in Settings → Theme → Screensaver. Shows Ambient plus the three most relevant screens |
| **App** (`Main`) | On demand. Every screen, in priority order. Left/Right browse, Play pauses |

## Screens and when they appear

| Screen | Shows when | Data |
|---|---|---|
| Briefing | 4–11 AM | Weather, family calendar, game watch, local headlines, heads-up |
| Ambient | Midday; first in the screensaver | Big clock, weather, sun arc, "next up" chip, Callaway Gardens photo |
| Tonight | After 5 PM | Tonight's game or a quiet night, weather, curbside, evening apps |
| Week ("Sunday Reset") | Weekend evenings | 7-day forecast, calendar, games, curbside, heads-up |
| Recap | Mornings or evenings after games | Finals (pro, SEC, LaGrange College), a house-divided hero card, records |
| Game day | A tracked team plays within 6 hours | Team panels with a countdown; Georgia vs Auburn splits the screen |
| Radar | Rain likely within 2 hours, or any NWS warning | NOAA MRMS frames over a USGS base map, Troup County alerts |
| Lake | Weekends or dry days | West Point Lake level vs summer and winter pool, best lake day, sunset, moon |
| Sky | Clear nights or a meteor shower within 2 weeks | Moon phase, shower, viewing conditions |
| School | School mornings and evenings | School-related calendar items, a card per student |
| Board | When there are notes | "TV: …" calendar events as notes, "Buy: …" as groceries |
| Season | Midday | Monthly nature and garden notes for West Georgia, frost watch |

## Rule-based insights (no AI at runtime)
"Heads up" items, most important first:
1. NWS warnings and watches.
2. Curbside pickup tomorrow or today.
3. Calendar deadlines within 7 days.
4. Overlapping evening events.
5. Rain of 60% or more, or a low of 34°F or below.
6. Birthdays within 2 weeks.
7. A meteor shower peaking within 4 days.
8. West Point Lake well below winter pool.

## City of LaGrange curbside rules
- **Every week:** household garbage on your day.
- **Alternating weeks** (Sunday–Saturday): **yard waste** (leaves, brush, limbs; no grass clippings) or **bulky trash** (furniture, mattresses and other large items).
- **Verified against the flyer:** yard weeks start the week of 2025-12-28, which matches all 53 weeks of the city's 2026 schedule flyer.
- **Holidays:** a city holiday moves that day's pickup to the next day. A shift onto a weekend is flagged to confirm with the city.
- **Code:** `scripts/sanitation.py` (reference) and `daybreak/channel/source/lib/rules.brs` (on the TV).

## Visual system
- **Colors:** ink navy `#0B1120`, cards `#131B2E` with a `#1F2A44` border, text `#F4F1EA` with `#A9B1C4` secondary. Accents: amber `#F4A259` (day) and violet `#B3A6F2` (night).
- **Type:** Outfit (display) and Manrope (UI), both under the SIL Open Font License. The build creates static weights because Roku can't select weights from a variable font.
- **Layout:** 1080p with 112 px side margins and 64 px vertical margins. The smallest text is 20 px.
- **Readability over photos:** every photo background is dimmed until all text clears WCAG contrast against the brightest 2% of pixels behind it: 4.5:1 for small text, 3:1 for large. `scripts/contrast_check.py` measures it. Results: Ambient 0.55 dim, Briefing 0.78, Season 0.70.

## Imagery and licensing
- Callaway Gardens photos: CC0 (Wikimedia Commons, D. Dugan).
- Map layers: USGS National Map (public domain). Radar: NOAA/NCEP MRMS (public domain).
- Callaway Gardens' and tourism boards' own marketing media isn't used; it's copyrighted.

## Privacy choices
- **Health appointments** in the calendar show only as "Appointment".
- **"Gentle news" (default on)** hides violent-crime headlines on the living-room screen.
- **The calendar's secret iCal URL** lives in `.env`. The build bakes it into the sideloaded package (`source/config.brs`, gitignored), so the package itself is private.

## Constraints
- **Developer mode:** a sideloaded app needs it on, and only one dev app can be installed at a time.
- **Memory:** about 325 MB is free during 4K playback; Daybreak only runs when nothing else is playing.
- **No overlays:** a Roku app can't draw over other apps, and launching other apps from the app was deliberately left out.
